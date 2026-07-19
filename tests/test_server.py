"""Ingestion server: request handling end-to-end with mocked pipeline."""

import json
import threading
import urllib.request
from http.server import HTTPServer

import pytest

from ingestion import server as srv
from ingestion.extract import Extraction
from ingestion.merchant import MerchantOffer, MerchantResult
from ingestion.models import Card, Offer, RewardRule


@pytest.fixture
def running_server(monkeypatch, tmp_path):
    def fake_run_auto(card_name, db_path, provider=None, url=None, client=None,
                      country=""):
        if card_name == "Broken Card":
            raise RuntimeError("pipeline blew up")  # -> 500
        if card_name == "Nonexistent Card":
            raise LookupError("no search results")  # -> 404 card_not_found
        card = Card(id="test_card", name=card_name, issuer="Test Bank", network="visa")
        return [Extraction(
            card=card,
            rules=[RewardRule(card_id="test_card", category="general",
                              rate=1.0, unit="cashback_pct")],
            valuation=None,
            offers=[Offer(card_id="test_card", title="Welcome bonus")],
            warnings=["something skipped"],
        )]

    # Count how many times the (expensive) merchant pipeline runs.
    calls = {"n": 0}

    def fake_find(merchant, client, url=None, cards=None, country=""):
        calls["n"] += 1
        return MerchantResult(
            merchant=merchant, category="beauty",
            offers=[MerchantOffer(title="20% off", card_hint="Emirates NBD")],
            source_ref="https://x.ae")

    monkeypatch.setattr(srv, "run_auto", fake_run_auto)
    monkeypatch.setattr(srv, "find_merchant_offers", fake_find)
    monkeypatch.setattr(srv, "get_client", lambda *a, **k: object())
    srv._search_cache.clear()
    srv._merchant_calls = calls  # expose to tests
    # Fresh, generous limiter so unrelated tests don't trip the rate limit.
    monkeypatch.setattr(srv, "_rate", srv.RateLimiter(1000, window_seconds=60))
    httpd = HTTPServer(("127.0.0.1", 0), srv.Handler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    yield f"http://127.0.0.1:{httpd.server_address[1]}"
    httpd.shutdown()


def _post(url: str, body: dict) -> tuple[int, dict]:
    req = urllib.request.Request(
        url, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"}, method="POST",
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())


def test_ingest_returns_extraction(running_server):
    status, body = _post(f"{running_server}/ingest", {"card": "My Card"})
    assert status == 200
    card = body["cards"][0]
    assert card["card"]["id"] == "test_card"
    assert card["rules"][0]["category"] == "general"
    assert card["offers"][0]["title"] == "Welcome bonus"
    assert card["warnings"] == ["something skipped"]


def test_ingest_missing_card_400(running_server):
    status, body = _post(f"{running_server}/ingest", {})
    assert status == 400


def test_ingest_pipeline_failure_500(running_server):
    status, body = _post(f"{running_server}/ingest", {"card": "Broken Card"})
    assert status == 500
    assert body["error"] == "server_error"
    assert "RuntimeError" in body["detail"]  # detail kept for support/logs


def test_ingest_card_not_found_404(running_server):
    status, body = _post(f"{running_server}/ingest", {"card": "Nonexistent Card"})
    assert status == 404
    assert body["error"] == "card_not_found"


def test_search_returns_category_and_offers(running_server):
    status, body = _post(f"{running_server}/search", {"merchant": "Glossy Salon"})
    assert status == 200
    assert body["category"] == "beauty"
    assert body["offers"][0]["title"] == "20% off"
    assert body["cached"] is False


def test_search_missing_merchant_400(running_server):
    status, _ = _post(f"{running_server}/search", {})
    assert status == 400


def test_search_second_call_is_cached_no_pipeline(running_server):
    _post(f"{running_server}/search", {"merchant": "Cache Me"})
    status, body = _post(f"{running_server}/search", {"merchant": "cache me"})
    assert status == 200
    assert body["cached"] is True             # case-insensitive key hit
    assert srv._merchant_calls["n"] == 1      # pipeline ran only once


def test_search_rejects_injection_400(running_server):
    status, body = _post(f"{running_server}/search",
                         {"merchant": "'; DROP TABLE cards;--"})
    assert status == 400
    assert srv._merchant_calls["n"] == 0      # pipeline never ran


def test_ingest_rejects_script_400(running_server):
    status, _ = _post(f"{running_server}/ingest",
                      {"card": "<script>alert(1)</script>"})
    assert status == 400


def test_rate_limit_returns_429(running_server):
    srv._rate = srv.RateLimiter(2, window_seconds=60)  # tiny limit for this test
    a, _ = _post(f"{running_server}/search", {"merchant": "One"})
    b, _ = _post(f"{running_server}/search", {"merchant": "Two"})
    c, body = _post(f"{running_server}/search", {"merchant": "Three"})
    assert (a, b) == (200, 200)
    assert c == 429
