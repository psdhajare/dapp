"""SQLite layer (B1): create schema, upsert cards/rules/valuations, read back."""

from __future__ import annotations

import sqlite3
from pathlib import Path

from .models import Card, Offer, PointsValuation, RewardRule

SCHEMA_PATH = Path(__file__).resolve().parent.parent / "db" / "schema.sql"
SEED_PATH = Path(__file__).resolve().parent.parent / "db" / "seed.sql"


class Database:
    def __init__(self, path: str = ":memory:") -> None:
        self.conn = sqlite3.connect(path)
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA foreign_keys = ON")

    def init_schema(self) -> None:
        self.conn.executescript(SCHEMA_PATH.read_text())
        self.conn.commit()

    def init_schema_if_needed(self) -> None:
        exists = self.conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='cards'"
        ).fetchone()
        if not exists:
            self.init_schema()

    def load_seed(self) -> None:
        self.conn.executescript(SEED_PATH.read_text())
        self.conn.commit()

    def close(self) -> None:
        self.conn.close()

    # --- writes (idempotent upserts) ---

    def upsert_card(self, card: Card) -> None:
        card.validate()
        self.conn.execute(
            """INSERT INTO cards
                 (id, name, issuer, network, currency, annual_fee,
                  apr, foreign_tx_fee, min_salary, interest_free_days,
                  color_primary, color_secondary)
               VALUES
                 (:id, :name, :issuer, :network, :currency, :annual_fee,
                  :apr, :foreign_tx_fee, :min_salary, :interest_free_days,
                  :color_primary, :color_secondary)
               ON CONFLICT(id) DO UPDATE SET
                 name=excluded.name, issuer=excluded.issuer, network=excluded.network,
                 currency=excluded.currency, annual_fee=excluded.annual_fee,
                 apr=excluded.apr, foreign_tx_fee=excluded.foreign_tx_fee,
                 min_salary=excluded.min_salary,
                 interest_free_days=excluded.interest_free_days,
                 color_primary=excluded.color_primary,
                 color_secondary=excluded.color_secondary""",
            card.__dict__,
        )
        self.conn.commit()

    def upsert_rule(self, rule: RewardRule) -> None:
        rule.validate()
        params = dict(rule.__dict__, verified=int(rule.verified))
        self.conn.execute(
            """INSERT INTO reward_rules
                 (card_id, category, rate, unit, cap_amount, cap_period,
                  min_spend, conditions, source_ref, verified)
               VALUES
                 (:card_id, :category, :rate, :unit, :cap_amount, :cap_period,
                  :min_spend, :conditions, :source_ref, :verified)
               ON CONFLICT(card_id, category) DO UPDATE SET
                 rate=excluded.rate, unit=excluded.unit, cap_amount=excluded.cap_amount,
                 cap_period=excluded.cap_period, min_spend=excluded.min_spend,
                 conditions=excluded.conditions, source_ref=excluded.source_ref,
                 verified=excluded.verified""",
            params,
        )
        self.conn.commit()

    def upsert_valuation(self, val: PointsValuation) -> None:
        val.validate()
        self.conn.execute(
            """INSERT INTO points_valuation (card_id, points_currency, value_per_point)
               VALUES (:card_id, :points_currency, :value_per_point)
               ON CONFLICT(card_id) DO UPDATE SET
                 points_currency=excluded.points_currency,
                 value_per_point=excluded.value_per_point""",
            val.__dict__,
        )
        self.conn.commit()

    def upsert_offer(self, offer: Offer) -> None:
        offer.validate()
        params = dict(offer.__dict__, verified=int(offer.verified))
        self.conn.execute(
            """INSERT INTO card_offers
                 (card_id, category, title, description, source_ref, verified)
               VALUES (:card_id, :category, :title, :description, :source_ref, :verified)
               ON CONFLICT(card_id, title) DO UPDATE SET
                 category=excluded.category, description=excluded.description,
                 source_ref=excluded.source_ref, verified=excluded.verified""",
            params,
        )
        self.conn.commit()

    def mark_held(self, card_id: str) -> None:
        self.conn.execute(
            "INSERT OR IGNORE INTO user_cards (card_id) VALUES (?)", (card_id,)
        )
        self.conn.commit()

    # --- reads ---

    def get_card(self, card_id: str) -> Card | None:
        row = self.conn.execute("SELECT * FROM cards WHERE id = ?", (card_id,)).fetchone()
        return Card(**row) if row else None

    def get_rules(self, card_id: str) -> list[RewardRule]:
        rows = self.conn.execute(
            """SELECT card_id, category, rate, unit, cap_amount, cap_period,
                      min_spend, conditions, source_ref, verified
               FROM reward_rules WHERE card_id = ? ORDER BY category""",
            (card_id,),
        ).fetchall()
        return [RewardRule(**dict(r, verified=bool(r["verified"]))) for r in rows]

    def get_offers(self, card_id: str) -> list[Offer]:
        rows = self.conn.execute(
            """SELECT card_id, category, title, description, source_ref, verified
               FROM card_offers WHERE card_id = ? ORDER BY title""",
            (card_id,),
        ).fetchall()
        return [Offer(**dict(r, verified=bool(r["verified"]))) for r in rows]

    def get_valuation(self, card_id: str) -> PointsValuation | None:
        row = self.conn.execute(
            "SELECT * FROM points_valuation WHERE card_id = ?", (card_id,)
        ).fetchone()
        return PointsValuation(**row) if row else None
