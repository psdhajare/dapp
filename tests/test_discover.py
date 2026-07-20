"""Auto-discovery: search parsing, domain ranking, html-to-text."""

from ingestion import discover

DDG_HTML = '''
<div class="result">
  <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.smartsaver.ae%2Fbest-cards&rut=x">Best cards UAE</a>
</div>
<div class="result">
  <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.emiratesnbd.com%2Fen%2Fcards%2Fduo&rut=y">Duo Card</a>
</div>
'''


def test_parse_search_results():
    urls = discover.parse_search_results(DDG_HTML)
    assert urls == [
        "https://www.smartsaver.ae/best-cards",
        "https://www.emiratesnbd.com/en/cards/duo",
    ]


def test_rank_prefers_bank_domain():
    urls = [
        "https://www.smartsaver.ae/best-cards",
        "https://www.emiratesnbd.com/en/cards/duo",
    ]
    ranked = discover.rank_urls(urls, "Emirates NBD Duo")
    assert ranked[0] == "https://www.emiratesnbd.com/en/cards/duo"

    ranked = discover.rank_urls(
        ["https://aggregator.ae/x", "https://www.mashreq.com/cards/cashback"],
        "Mashreq Cashback",
    )
    assert ranked[0] == "https://www.mashreq.com/cards/cashback"


def test_html_to_text_strips_scripts():
    html = """<html><head><title>t</title><script>var x=1;</script></head>
    <body><h1>Duo Card</h1><style>.a{}</style><p>4% dining cashback</p></body></html>"""
    text = discover.html_to_text(html)
    assert "Duo Card" in text
    assert "4% dining cashback" in text
    assert "var x" not in text
    assert ".a{}" not in text


def test_find_doc_url_uses_search_and_ranking(monkeypatch):
    monkeypatch.setattr(
        discover, "search",
        lambda q, country="": ["https://blog.ae/cards", "https://www.mashreq.com/cashback"],
    )
    assert discover.find_doc_url("Mashreq Cashback") == "https://www.mashreq.com/cashback"


class _FakeResp:
    def __init__(self, payload):
        self._payload = payload

    def raise_for_status(self):
        pass

    def json(self):
        return self._payload


def test_brave_is_default_and_receives_country(monkeypatch):
    calls = {}

    def fake_brave(q, country=""):
        calls["brave"] = country
        return ["https://x.ae/offer"]

    def fake_searxng(q, country=""):
        calls["searxng"] = True  # must NOT run: Brave answered first
        return ["https://should-not-be-used"]

    monkeypatch.setattr(discover, "_brave", fake_brave)
    monkeypatch.setattr(discover, "_searxng", fake_searxng)
    monkeypatch.setattr(discover, "_ENGINES", (discover._brave, discover._searxng))

    assert discover.search("salt offer", country="AE") == ["https://x.ae/offer"]
    assert calls["brave"] == "AE"          # country threaded to the engine
    assert "searxng" not in calls          # Brave is the default, ran first


def test_falls_back_to_free_engine_when_brave_skips(monkeypatch):
    # Brave returns None when unconfigured -> the free SearXNG answers.
    monkeypatch.setattr(discover, "_brave", lambda q, country="": None)
    monkeypatch.setattr(discover, "_searxng",
                        lambda q, country="": ["https://free.ae"])
    monkeypatch.setattr(discover, "_ENGINES", (discover._brave, discover._searxng))
    assert discover.search("q", country="AE") == ["https://free.ae"]


def test_brave_sends_country_param(monkeypatch):
    monkeypatch.setenv("BRAVE_API_KEY", "test-key")
    captured = {}

    def fake_get(url, params=None, headers=None, timeout=None):
        captured["params"] = params
        captured["headers"] = headers
        return _FakeResp({"web": {"results": [{"url": "https://x.ae"}]}})

    monkeypatch.setattr(discover.requests, "get", fake_get)
    out = discover._brave("salt cafe offer", country="ae")
    assert out == ["https://x.ae"]
    assert captured["params"]["country"] == "AE"           # normalized upper
    assert captured["headers"]["X-Subscription-Token"] == "test-key"


def test_brave_skips_without_key(monkeypatch):
    monkeypatch.delenv("BRAVE_API_KEY", raising=False)
    assert discover._brave("q", country="AE") is None
