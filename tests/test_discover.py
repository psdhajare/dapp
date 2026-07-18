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
        lambda q: ["https://blog.ae/cards", "https://www.mashreq.com/cashback"],
    )
    assert discover.find_doc_url("Mashreq Cashback") == "https://www.mashreq.com/cashback"
