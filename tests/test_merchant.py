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
    monkeypatch.setattr(discover, "search", lambda q, country="": [
        "https://wallethub.com/best-baby-cards",
        "https://lifestyle.emiratesnbd.com/en/deals/glossy-salon-offer",
    ])
    monkeypatch.setattr(discover, "fetch_text", lambda u, timeout=0: "Glossy Salon offers ...")

    r = find_merchant_offers("Glossy Hair Salon", FakeLLM(OFFERS_JSON))
    assert r.category == "beauty"
    assert len(r.offers) == 1               # blank-title offer dropped
    assert r.offers[0].card_hint == "Emirates NBD"
    assert r.offers[0].valid_until == "31 Dec 2026"
    assert "emiratesnbd.com" in r.source_ref  # deal page ranked first


def test_category_from_keyword_even_if_search_fails(monkeypatch):
    def boom(_, country=""):
        raise LookupError("no results")
    monkeypatch.setattr(discover, "search", boom)

    # Salon keyword still yields a category; offers empty on search failure.
    r = find_merchant_offers("Downtown Salon", FakeLLM("{}"))
    assert r.category == "beauty"
    assert r.offers == []


def test_irrelevant_pages_are_dropped(monkeypatch):
    # A generic bonus/aggregator page that never names the merchant must not be
    # used as a source or fed to the LLM (the sushi-library / mypointslife bug).
    monkeypatch.setattr(discover, "search", lambda q, country="": [
        "https://www.mypointslife.com/bank-account-bonus-promotions-and-offers/",
    ])
    monkeypatch.setattr(
        discover, "fetch_text",
        lambda u, timeout=0: "Best US bank account bonuses and credit card promotions")

    r = find_merchant_offers("Sushi Library", FakeLLM(OFFERS_JSON))
    assert r.offers == []          # nothing extracted from an irrelevant page
    assert r.source_ref is None    # do NOT surface the junk page as the source


def test_result_to_dict_shape(monkeypatch):
    monkeypatch.setattr(discover, "search", lambda q, country="": ["https://x.ae/offer"])
    monkeypatch.setattr(
        discover, "fetch_text", lambda u, timeout=0: "Some Cafe card offer")
    d = result_to_dict(find_merchant_offers("Some Cafe", FakeLLM(OFFERS_JSON)))
    assert set(d) == {"merchant", "category", "offers", "source_ref"}
    assert d["offers"][0]["title"] == "20% off"


def test_bank_phrase_reduces_card_to_issuer():
    assert merchant._bank_phrase("Emirates NBD Platinum") == "Emirates NBD"
    assert merchant._bank_phrase("Mashreq Cashback Credit Card") == "Mashreq"
    assert merchant._bank_phrase("Wio Credit Card") == "Wio"
    assert merchant._bank_phrase("Apple Card") == "Apple"
    assert merchant._bank_phrase("Diners Club") == "Diners Club"


def test_gather_urls_adds_bank_targeted_queries(monkeypatch):
    queries: list[str] = []
    monkeypatch.setattr(merchant.discover, "search",
                        lambda q, country="": (queries.append(q) or []))
    merchant._gather_urls("Khau Galli", country="AE",
                          cards=["Emirates NBD Platinum", "Wio Credit Card"])
    # A per-bank query is issued for each held card's issuer.
    assert any('"Khau Galli" Emirates NBD offer' in q for q in queries)
    assert any('"Khau Galli" Wio offer' in q for q in queries)
