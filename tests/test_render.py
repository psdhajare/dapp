"""JS-render fetch fallback (hosted API, mocked)."""

from ingestion import render


class _Resp:
    def __init__(self, payload):
        self._p = payload

    def raise_for_status(self):
        pass

    def json(self):
        return self._p


def test_disabled_without_key(monkeypatch):
    monkeypatch.setattr(render, "_KEY", "")
    assert render.render_text("https://x") == ""
    assert render.is_configured() is False


def test_firecrawl_returns_markdown(monkeypatch):
    monkeypatch.setattr(render, "_KEY", "k")
    monkeypatch.setattr(render, "_PROVIDER", "firecrawl")
    captured = {}

    def fake_post(url, json=None, headers=None, timeout=None):
        captured["url"] = url
        captured["headers"] = headers
        return _Resp({"data": {"markdown": "20% off at Babies Basic with Emirates NBD"}})

    monkeypatch.setattr(render.requests, "post", fake_post)
    out = render.render_text("https://lifestyle.emiratesnbd.com/deals/babies-basic")
    assert "20% off" in out
    assert captured["headers"]["Authorization"] == "Bearer k"


def test_failure_degrades_to_empty(monkeypatch):
    monkeypatch.setattr(render, "_KEY", "k")

    def boom(*a, **k):
        raise RuntimeError("render timeout")

    monkeypatch.setattr(render.requests, "post", boom)
    assert render.render_text("https://x") == ""  # never raises
