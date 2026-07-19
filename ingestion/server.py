"""Ingestion service: the app posts a card name, gets extracted data back.

Holds the DeepSeek key; the app stays offline except when adding a card.

    python3 -m ingestion.server        # listens on 0.0.0.0:8765
    POST /ingest {"card": "Card Name", "url": "optional doc url"}
    POST /search {"merchant": "Name"}  # category + live card offers (cached ~24h)
    GET  /health                       # readiness probe

Config via env: INGEST_HOST (default 0.0.0.0), INGEST_PORT (default 8765),
INGEST_DB (default db/cards.db), INGEST_CACHE_TTL seconds (default 86400).
"""

from __future__ import annotations

import json
import os
import threading
import time
import traceback
from dataclasses import asdict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from .cli import run_auto
from .extract import Extraction
from .llm import get_client
from .merchant import find_merchant_offers, result_to_dict
from .programs import programs_for_cards
from .security import InputError, RateLimiter, sanitize_query

DB_PATH = os.environ.get("INGEST_DB", "db/cards.db")
HOST = os.environ.get("INGEST_HOST", "0.0.0.0")
PORT = int(os.environ.get("INGEST_PORT", "8765"))
CACHE_TTL = int(os.environ.get("INGEST_CACHE_TTL", "86400"))  # 24h for hits
# Misses (no offers found) expire fast so a real offer isn't hidden for a day.
MISS_CACHE_TTL = int(os.environ.get("INGEST_MISS_CACHE_TTL", "1800"))  # 30 min
# Server-side defense-in-depth limit per client IP (client also limits itself).
RATE_LIMIT = int(os.environ.get("INGEST_RATE_LIMIT", "30"))  # requests / minute
_rate = RateLimiter(RATE_LIMIT, window_seconds=60)

# merchant key -> (expires_at_epoch, payload). Shared across handler threads.
_search_cache: dict[str, tuple[float, dict]] = {}
_cache_lock = threading.Lock()


def _cache_get(key: str) -> dict | None:
    with _cache_lock:
        entry = _search_cache.get(key)
        if entry and entry[0] > time.time():
            return entry[1]
        if entry:
            del _search_cache[key]
    return None


def _cache_put(key: str, payload: dict, ttl: int = CACHE_TTL) -> None:
    with _cache_lock:
        _search_cache[key] = (time.time() + ttl, payload)


def extraction_to_dict(e: Extraction) -> dict:
    return {
        "card": asdict(e.card),
        "rules": [asdict(r) for r in e.rules],
        "valuation": asdict(e.valuation) if e.valuation else None,
        "offers": [asdict(o) for o in e.offers],
        "warnings": e.warnings,
    }


class Handler(BaseHTTPRequestHandler):
    def _send(self, status: int, body: dict) -> None:
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.end_headers()
        self.wfile.write(payload)

    def do_OPTIONS(self):  # CORS preflight
        self._send(204, {})

    def do_GET(self):
        if self.path == "/health":
            self._send(200, {"status": "ok"})
        else:
            self._send(404, {"error": "not found"})

    def _read_json(self) -> dict:
        return json.loads(self._body or b"{}")

    def _client_ip(self) -> str:
        # Behind NPM: trust X-Forwarded-For's first hop if present.
        fwd = self.headers.get("X-Forwarded-For")
        if fwd:
            return fwd.split(",")[0].strip()
        return self.client_address[0]

    def do_POST(self):
        try:
            # Drain the request body first so early responses (429/404) don't
            # leave unread bytes on the socket (which causes client resets).
            length = int(self.headers.get("Content-Length", 0) or 0)
            self._body = self.rfile.read(length)
            if not _rate.allow(self._client_ip()):
                self._send(429, {"error": "rate limit exceeded, slow down"})
                return
            if self.path == "/ingest":
                self._handle_ingest()
            elif self.path == "/search":
                self._handle_search()
            else:
                self._send(404, {"error": "not found"})
        except InputError as e:
            self._send(400, {"error": str(e)})
        except Exception as e:  # log full detail server-side; app shows a
            # friendly message. Keep a short code in the body for support.
            traceback.print_exc()
            self._send(500, {"error": "server_error", "detail": f"{type(e).__name__}: {e}"})

    def _optional_country(self, req: dict) -> str:
        """Sanitized country hint for search context; '' if absent/invalid."""
        raw = req.get("country")
        if not raw:
            return ""
        try:
            return sanitize_query(raw)
        except InputError:
            return ""

    def _handle_ingest(self):
        req = self._read_json()
        # sanitize_query raises InputError (-> 400) on empty/oversized/malicious.
        # NOTE: client-supplied 'url' is intentionally ignored here (SSRF guard);
        # the server always discovers the doc URL itself.
        card_name = sanitize_query(req.get("card"))
        results = run_auto(card_name, DB_PATH, provider=None,
                           country=self._optional_country(req))
        # A product can be a bundle of >1 physical card (e.g. a dual-card set).
        self._send(200, {"cards": [extraction_to_dict(e) for e in results]})

    def _handle_search(self):
        req = self._read_json()
        merchant = sanitize_query(req.get("merchant"))  # InputError -> 400
        # The user's held card names, used to target loyalty-program checks and
        # scope offers. Sanitized; NOT logged or persisted beyond the cache key.
        raw_cards = req.get("cards")
        cards: list[str] = []
        if isinstance(raw_cards, list):
            for c in raw_cards[:20]:
                try:
                    cards.append(sanitize_query(c))
                except InputError:
                    continue
        country = self._optional_country(req)
        # Cache depends on the market + which programs the cards grant.
        progs = programs_for_cards(cards)
        key = merchant.lower() + "|" + country.lower() + "|" + ",".join(sorted(progs))
        cached = _cache_get(key)
        if cached is not None:
            self._send(200, dict(cached, cached=True))
            return
        # No client 'url' override (SSRF guard) — pipeline finds it itself.
        result = find_merchant_offers(merchant, get_client(), cards=cards,
                                      country=country)
        payload = result_to_dict(result)
        # Cache a real hit for a day; a miss only briefly so it retries soon.
        ttl = CACHE_TTL if payload.get("offers") else MISS_CACHE_TTL
        _cache_put(key, payload, ttl)
        self._send(200, dict(payload, cached=False))


def main() -> None:
    # Threaded so concurrent card-adds don't serialize behind a slow LLM call.
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"ingestion server on http://{HOST}:{PORT}/ingest -> {DB_PATH}")
    server.serve_forever()


if __name__ == "__main__":
    main()
