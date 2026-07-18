"""Ingestion service: the app posts a card name, gets extracted data back.

Holds the DeepSeek key; the app stays offline except when adding a card.

    python3 -m ingestion.server        # listens on 0.0.0.0:8765
    POST /ingest {"card": "Card Name", "url": "optional doc url"}
    GET  /health                       # readiness probe

Config via env: INGEST_HOST (default 0.0.0.0), INGEST_PORT (default 8765),
INGEST_DB (default db/cards.db).
"""

from __future__ import annotations

import json
import os
from dataclasses import asdict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from .cli import run_auto
from .extract import Extraction

DB_PATH = os.environ.get("INGEST_DB", "db/cards.db")
HOST = os.environ.get("INGEST_HOST", "0.0.0.0")
PORT = int(os.environ.get("INGEST_PORT", "8765"))


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

    def do_POST(self):
        if self.path != "/ingest":
            self._send(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            req = json.loads(self.rfile.read(length) or b"{}")
            card_name = (req.get("card") or "").strip()
            if not card_name:
                self._send(400, {"error": "missing 'card'"})
                return
            result = run_auto(card_name, DB_PATH, provider=None,
                              url=req.get("url"))
            self._send(200, extraction_to_dict(result))
        except Exception as e:  # surface any pipeline failure to the app
            self._send(500, {"error": f"{type(e).__name__}: {e}"})


def main() -> None:
    # Threaded so concurrent card-adds don't serialize behind a slow LLM call.
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"ingestion server on http://{HOST}:{PORT}/ingest -> {DB_PATH}")
    server.serve_forever()


if __name__ == "__main__":
    main()
