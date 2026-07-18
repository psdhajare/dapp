"""B1: SQLite writer/reader — upsert, read back, idempotent, validation."""

import pytest

from ingestion.db import Database
from ingestion.models import Card, PointsValuation, RewardRule


def db_with_categories():
    db = Database()
    db.init_schema()
    return db


def test_upsert_and_read_card():
    db = db_with_categories()
    card = Card(id="amex", name="Amex", issuer="AmEx", network="amex")
    db.upsert_card(card)
    assert db.get_card("amex") == card


def test_upsert_card_is_idempotent():
    db = db_with_categories()
    db.upsert_card(Card(id="amex", name="Old", issuer="AmEx", network="amex"))
    db.upsert_card(Card(id="amex", name="New", issuer="AmEx", network="amex"))
    count = db.conn.execute("SELECT COUNT(*) c FROM cards").fetchone()["c"]
    assert count == 1
    assert db.get_card("amex").name == "New"


def test_upsert_and_read_rules():
    db = db_with_categories()
    db.upsert_card(Card(id="amex", name="Amex", issuer="AmEx", network="amex"))
    rule = RewardRule(
        card_id="amex", category="dining", rate=4, unit="points_per_unit",
        cap_amount=500, cap_period="monthly", source_ref="seed", verified=True,
    )
    db.upsert_rule(rule)
    got = db.get_rules("amex")
    assert got == [rule]


def test_rule_upsert_updates_on_conflict():
    db = db_with_categories()
    db.upsert_card(Card(id="amex", name="Amex", issuer="AmEx", network="amex"))
    db.upsert_rule(RewardRule(card_id="amex", category="dining", rate=2, unit="points_per_unit"))
    db.upsert_rule(RewardRule(card_id="amex", category="dining", rate=4, unit="points_per_unit"))
    rules = db.get_rules("amex")
    assert len(rules) == 1 and rules[0].rate == 4


def test_valuation_roundtrip():
    db = db_with_categories()
    db.upsert_card(Card(id="amex", name="Amex", issuer="AmEx", network="amex"))
    val = PointsValuation(card_id="amex", points_currency="MR", value_per_point=0.009)
    db.upsert_valuation(val)
    assert db.get_valuation("amex") == val


def test_offer_roundtrip_and_idempotent_upsert():
    from ingestion.models import Offer

    db = db_with_categories()
    db.upsert_card(Card(id="duo", name="Duo", issuer="ENBD", network="visa"))
    offer = Offer(card_id="duo", title="BOGO movies", category="dining",
                  description="old", source_ref="x")
    db.upsert_offer(offer)
    db.upsert_offer(Offer(card_id="duo", title="BOGO movies", category="dining",
                          description="new", source_ref="x"))
    offers = db.get_offers("duo")
    assert len(offers) == 1
    assert offers[0].description == "new"


def test_invalid_rule_rejected_before_write():
    db = db_with_categories()
    db.upsert_card(Card(id="amex", name="Amex", issuer="AmEx", network="amex"))
    with pytest.raises(ValueError):
        db.upsert_rule(RewardRule(card_id="amex", category="bogus", rate=1, unit="cashback_pct"))
