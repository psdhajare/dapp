"""Plain data holders shared across ingestion. Mirror the DB schema columns."""

from __future__ import annotations

import re
from dataclasses import dataclass

VALID_CATEGORIES = {
    "dining", "grocery", "fuel", "travel", "transit",
    "online", "utilities", "entertainment", "general",
}
VALID_UNITS = {"cashback_pct", "points_per_unit"}
VALID_CAP_PERIODS = {"none", "monthly", "quarterly", "yearly"}
VALID_NETWORKS = {"visa", "mastercard", "amex", "other"}


_HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")


@dataclass
class Card:
    id: str
    name: str
    issuer: str
    network: str
    currency: str = "GBP"
    annual_fee: float = 0.0
    color_primary: str | None = None
    color_secondary: str | None = None

    def validate(self) -> None:
        if not self.id or not self.name or not self.issuer:
            raise ValueError("card id, name, issuer are required")
        if self.network not in VALID_NETWORKS:
            raise ValueError(f"invalid network: {self.network}")
        for c in (self.color_primary, self.color_secondary):
            if c is not None and not _HEX_RE.match(c):
                raise ValueError(f"invalid color hex: {c}")


@dataclass
class RewardRule:
    card_id: str
    category: str
    rate: float
    unit: str
    cap_amount: float | None = None
    cap_period: str = "none"
    min_spend: float | None = None
    conditions: str | None = None
    source_ref: str | None = None
    verified: bool = False

    def validate(self) -> None:
        if self.category not in VALID_CATEGORIES:
            raise ValueError(f"invalid category: {self.category}")
        if self.unit not in VALID_UNITS:
            raise ValueError(f"invalid unit: {self.unit}")
        if self.cap_period not in VALID_CAP_PERIODS:
            raise ValueError(f"invalid cap_period: {self.cap_period}")
        if self.rate < 0:
            raise ValueError("rate must be non-negative")
        if self.cap_amount is not None and self.cap_period == "none":
            raise ValueError("cap_amount set but cap_period is 'none'")


@dataclass
class Offer:
    card_id: str
    title: str
    category: str | None = None
    description: str | None = None
    source_ref: str | None = None
    verified: bool = False

    def validate(self) -> None:
        if not self.title:
            raise ValueError("offer title is required")
        if self.category is not None and self.category not in VALID_CATEGORIES:
            raise ValueError(f"invalid offer category: {self.category}")


@dataclass
class PointsValuation:
    card_id: str
    points_currency: str
    value_per_point: float

    def validate(self) -> None:
        if self.value_per_point <= 0:
            raise ValueError("value_per_point must be positive")
