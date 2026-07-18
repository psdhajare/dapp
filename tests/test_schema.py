"""T0: schema loads, constraints hold, seed inserts and reads back."""

import sqlite3

import pytest

from ingestion.db import Database


def fresh_db():
    db = Database()
    db.init_schema()
    return db


def test_schema_creates_all_tables():
    db = fresh_db()
    names = {
        r["name"]
        for r in db.conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        ).fetchall()
    }
    assert {
        "categories", "cards", "reward_rules", "points_valuation",
        "poi_category_map", "user_cards", "spend_log",
    } <= names


def test_foreign_key_enforced():
    db = fresh_db()
    with pytest.raises(sqlite3.IntegrityError):
        db.conn.execute(
            "INSERT INTO reward_rules (card_id, category, rate, unit) "
            "VALUES ('nope', 'dining', 1, 'cashback_pct')"
        )


def test_categories_seeded_by_schema():
    db = fresh_db()
    count = db.conn.execute("SELECT COUNT(*) c FROM categories").fetchone()["c"]
    assert count == 9


def test_network_check_constraint():
    db = fresh_db()
    with pytest.raises(sqlite3.IntegrityError):
        db.conn.execute(
            "INSERT INTO cards (id, name, issuer, network) "
            "VALUES ('x', 'X', 'Y', 'discover')"
        )


def test_seed_loads_and_reads():
    db = fresh_db()
    db.load_seed()
    rows = db.conn.execute("SELECT COUNT(*) c FROM cards").fetchone()
    assert rows["c"] == 2
    held = db.conn.execute("SELECT COUNT(*) c FROM user_cards").fetchone()
    assert held["c"] == 2
