"""Ingestion server: request handling end-to-end with mocked pipeline."""

import json
import threading
import urllib.request
from http.server import HTTPServer

import pytest

from ingestion import server as srv
from ingestion.extract import Extraction
from ingestion.models import Card, Offer, RewardRule


@pytest.fixture
def running_server(monkeypatch, tmp_path):
    def fake_run_auto(card_name, db_path, provider=None, url=None, client=None):
        if card_name == "Broken Card":
            raise LookupError("no search results")
        card = Card(id="test_card", name=card_name, issuer="Test Bank", network="visa")
        return Extraction(
            card=card,
            rules=[RewardRule(card_id="test_card", category="general",
                              rate=1.0, unit="cashback_pct")],
            valuation=None,
            offers=[Offer(card_id="test_card", title="Welcome bonus")],
            warnings=["something skipped"],
        )

    monkeypatch.setattr(srv, "run_auto", fake_run_auto)
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
    assert body["card"]["id"] == "test_card"
    assert body["rules"][0]["category"] == "general"
    assert body["offers"][0]["title"] == "Welcome bonus"
    assert body["warnings"] == ["something skipped"]


def test_ingest_missing_card_400(running_server):
    status, body = _post(f"{running_server}/ingest", {})
    assert status == 400


def test_ingest_pipeline_failure_500(running_server):
    status, body = _post(f"{running_server}/ingest", {"card": "Broken Card"})
    assert status == 500
    assert "LookupError" in body["error"]
