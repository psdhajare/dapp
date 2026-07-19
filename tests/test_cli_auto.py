"""Auto flow end-to-end: name -> (mocked) discover -> (mocked) LLM -> DB + held."""

import json

import pytest

from ingestion import discover
from ingestion.cli import run_auto
from ingestion.db import Database
from tests.test_extract import FakeLLM

DUO = json.dumps({
    "card": {"id": "enbd_duo", "name": "Emirates NBD Duo", "issuer": "Emirates NBD",
             "network": "mastercard", "currency": "AED", "annual_fee": 0},
    "rules": [
        {"category": "dining", "rate": 2, "unit": "cashback_pct",
         "cap_amount": 2000, "cap_period": "monthly", "min_spend": None, "conditions": None},
        {"category": "general", "rate": 0.5, "unit": "cashback_pct",
         "cap_amount": None, "cap_period": "none", "min_spend": None, "conditions": None},
    ],
    "points_valuation": None,
})


def test_run_auto_whole_flow(tmp_path, monkeypatch):
    monkeypatch.setattr(discover, "find_doc_url",
                        lambda name: "https://www.emiratesnbd.com/duo")
    monkeypatch.setattr(discover, "fetch_text",
                        lambda url: "Duo card 2% dining cashback capped AED 2000/month")

    db_path = tmp_path / "cards.db"
    results = run_auto("Emirates NBD Duo", str(db_path), provider=None,
                       client=FakeLLM(DUO))

    assert len(results) == 1
    assert results[0].card.currency == "AED"

    db = Database(str(db_path))
    assert db.get_card("enbd_duo").issuer == "Emirates NBD"
    assert db.get_rules("enbd_duo")[0].source_ref == "https://www.emiratesnbd.com/duo"
    held = db.conn.execute("SELECT card_id FROM user_cards").fetchall()
    assert [r["card_id"] for r in held] == ["enbd_duo"]


DUO_MULTI = json.dumps({
    "cards": [
        {"card": {"id": "enbd_duo_dining", "name": "Emirates NBD Duo Dining",
                  "issuer": "Emirates NBD", "network": "mastercard",
                  "currency": "AED", "annual_fee": 0},
         "rules": [{"category": "dining", "rate": 5, "unit": "cashback_pct",
                    "cap_amount": None, "cap_period": "none",
                    "min_spend": None, "conditions": None}],
         "points_valuation": None},
        {"card": {"id": "enbd_duo_everyday", "name": "Emirates NBD Duo Everyday",
                  "issuer": "Emirates NBD", "network": "mastercard",
                  "currency": "AED", "annual_fee": 0},
         "rules": [{"category": "general", "rate": 1, "unit": "cashback_pct",
                    "cap_amount": None, "cap_period": "none",
                    "min_spend": None, "conditions": None}],
         "points_valuation": None},
    ]
})


def test_run_auto_multi_card_bundle(tmp_path, monkeypatch):
    monkeypatch.setattr(discover, "find_doc_url", lambda name: "https://enbd/duo")
    monkeypatch.setattr(discover, "fetch_text", lambda url: "Duo dual-card set")

    db_path = tmp_path / "cards.db"
    results = run_auto("Emirates NBD Duo", str(db_path), provider=None,
                       client=FakeLLM(DUO_MULTI))

    assert [r.card.id for r in results] == ["enbd_duo_dining", "enbd_duo_everyday"]

    db = Database(str(db_path))
    held = {r["card_id"] for r in
            db.conn.execute("SELECT card_id FROM user_cards").fetchall()}
    assert held == {"enbd_duo_dining", "enbd_duo_everyday"}


def test_run_auto_rejects_empty_doc(tmp_path, monkeypatch):
    monkeypatch.setattr(discover, "find_doc_url", lambda name: "https://x.com")
    monkeypatch.setattr(discover, "fetch_text", lambda url: "   ")
    with pytest.raises(ValueError):
        run_auto("X", str(tmp_path / "c.db"), provider=None, client=FakeLLM("{}"))


def test_run_auto_explicit_url_skips_search(tmp_path, monkeypatch):
    calls = []
    monkeypatch.setattr(discover, "find_doc_url",
                        lambda name: calls.append(name) or "should-not-happen")
    monkeypatch.setattr(discover, "fetch_text", lambda url: f"doc from {url}")

    run_auto("Emirates NBD Duo", str(tmp_path / "c.db"), provider=None,
             client=FakeLLM(DUO), url="https://www.emiratesnbd.com/duo-direct")
    assert calls == []
