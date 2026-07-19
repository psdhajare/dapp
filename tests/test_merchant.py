"""Live merchant offer discovery (mocked network + LLM)."""

import json

from ingestion import discover, merchant
from ingestion.merchant import find_merchant_offers, result_to_dict
from tests.test_extract import FakeLLM

OFFERS_JSON = json.dumps({
    "category": "beauty",
    "offers": [
        {"title": "20% off", "description": "On hair services",
         "card_hint": "Emirates NBD", "valid_until": "31 Dec 2026"},
        {"title": "", "description": "blank title dropped"},
    ],
})


def test_find_offers_happy_path(monkeypatch):
    # Offer/deal URL should outrank a generic article and be the source.
    monkeypatch.setattr(discover, "search", lambda q: [
        "https://wallethub.com/best-baby-cards",
        "https://lifestyle.emiratesnbd.com/en/deals/glossy-salon-offer",
    ])
    monkeypatch.setattr(discover, "fetch_text", lambda u: "Glossy Salon offers ...")

    r = find_merchant_offers("Glossy Hair Salon", FakeLLM(OFFERS_JSON))
    assert r.category == "beauty"
    assert len(r.offers) == 1               # blank-title offer dropped
    assert r.offers[0].card_hint == "Emirates NBD"
    assert r.offers[0].valid_until == "31 Dec 2026"
    assert "emiratesnbd.com" in r.source_ref  # deal page ranked first


def test_category_from_keyword_even_if_search_fails(monkeypatch):
    def boom(_):
        raise LookupError("no results")
    monkeypatch.setattr(discover, "search", boom)

    # Salon keyword still yields a category; offers empty on search failure.
    r = find_merchant_offers("Downtown Salon", FakeLLM("{}"))
    assert r.category == "beauty"
    assert r.offers == []


def test_result_to_dict_shape(monkeypatch):
    monkeypatch.setattr(discover, "search", lambda q: ["https://x.ae/offer"])
    monkeypatch.setattr(discover, "fetch_text", lambda u: "text")
    d = result_to_dict(find_merchant_offers("Some Cafe", FakeLLM(OFFERS_JSON)))
    assert set(d) == {"merchant", "category", "offers", "source_ref"}
    assert d["offers"][0]["title"] == "20% off"
