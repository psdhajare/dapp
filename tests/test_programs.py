"""Loyalty-program mapping + merchant membership (mocked network)."""

from ingestion import discover, programs
from ingestion.merchant import find_merchant_offers
from tests.test_extract import FakeLLM


def test_programs_for_cards_maps_wio_to_entertainer():
    assert programs.programs_for_cards(["Wio", "Emirates NBD Duo"]) == ["entertainer"]


def test_programs_for_cards_none_for_unmapped():
    assert programs.programs_for_cards(["Mashreq Cashback", "ADCB"]) == []


def test_granting_cards_attributes_to_wio():
    got = programs.granting_cards("entertainer", ["Wio Personal", "Mashreq"])
    assert got == ["Wio Personal"]


def test_merchant_on_program_true_when_listed(monkeypatch):
    monkeypatch.setattr(discover, "search",
                        lambda q: ["https://www.theentertainerme.com/outlets/sushi-library"])
    monkeypatch.setattr(discover, "fetch_text",
                        lambda u, timeout=0: "Sushi Library — Buy one get one on The Entertainer")
    assert programs.merchant_on_program("Sushi Library", "entertainer") is True


def test_merchant_on_program_false_when_page_omits_merchant(monkeypatch):
    monkeypatch.setattr(discover, "search",
                        lambda q: ["https://www.theentertainerme.com/outlets/other"])
    monkeypatch.setattr(discover, "fetch_text",
                        lambda u, timeout=0: "Some other restaurant entirely")
    assert programs.merchant_on_program("Sushi Library", "entertainer") is False


def test_non_member_restaurant_not_falsely_matched(monkeypatch):
    # The bug: a restaurant NOT on Entertainer must not match. Its outlet page
    # doesn't exist; search returns another outlet + a query-echo search URL.
    # Generic word "restaurant" must not cause a match.
    monkeypatch.setattr(discover, "search", lambda q: [
        "https://www.theentertainerme.com/outlets/some-other-place",
        "https://www.theentertainerme.com/search?q=royal+gulf+restaurant",
    ])
    monkeypatch.setattr(discover, "fetch_text",
                        lambda u, timeout=0: "Browse hundreds of restaurants")
    assert programs.merchant_on_program("Royal Gulf Restaurant", "entertainer") is False


def test_merchant_on_program_ignores_non_member_domains(monkeypatch):
    # A page that names the merchant but isn't the program's site doesn't count.
    monkeypatch.setattr(discover, "search",
                        lambda q: ["https://random.blog/sushi-library-review"])
    monkeypatch.setattr(discover, "fetch_text",
                        lambda u, timeout=0: "Sushi Library is great")
    assert programs.merchant_on_program("Sushi Library", "entertainer") is False


def test_program_offer_surfaced_for_wio_holder(monkeypatch):
    # No direct offers (empty LLM), but Wio grants Entertainer and the merchant
    # is listed -> a program offer must appear. This is the sushi-library case.
    monkeypatch.setattr(discover, "search",
                        lambda q: ["https://www.theentertainerme.com/outlets/sushi-library"])
    monkeypatch.setattr(discover, "fetch_text",
                        lambda u, timeout=0: "Sushi Library on The Entertainer")

    r = find_merchant_offers("Sushi Library", FakeLLM("{}"), cards=["Wio"])
    assert len(r.offers) == 1
    o = r.offers[0]
    assert o.via == "The Entertainer"
    assert o.title == "Buy 1 Get 1 free"
    assert o.card_hint == "Wio"


def test_no_program_offer_without_granting_card(monkeypatch):
    monkeypatch.setattr(discover, "search",
                        lambda q: ["https://www.theentertainerme.com/outlets/sushi-library"])
    monkeypatch.setattr(discover, "fetch_text",
                        lambda u, timeout=0: "Sushi Library on The Entertainer")
    # User holds only Mashreq -> no Entertainer -> no program offer.
    r = find_merchant_offers("Sushi Library", FakeLLM("{}"), cards=["Mashreq Cashback"])
    assert r.offers == []
