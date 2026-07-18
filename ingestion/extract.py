"""Extraction (B2): document text + LLMClient -> validated Card/RewardRules.

Provider-agnostic: depends only on the LLMClient interface.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field

from .llm import LLMClient
from .models import (
    VALID_CATEGORIES,
    Card,
    Offer,
    PointsValuation,
    RewardRule,
)

SYSTEM_PROMPT = (
    "You extract credit-card reward rules from documents into strict JSON. "
    "Only output JSON matching the requested schema. Do not invent data; if a "
    "field is unknown, use null. Categories must be one of: "
    + ", ".join(sorted(VALID_CATEGORIES))
    + ". unit is 'cashback_pct' or 'points_per_unit'. When a document expresses "
    "points earning as a percentage of spend (e.g. '5% Plus Points'), use "
    "cashback_pct with that percentage — reserve points_per_unit for 'N points "
    "per unit spent' schemes. cap_period is one of none, monthly, quarterly, "
    "yearly. Also collect non-rate benefits (e.g. buy-1-get-1 cinema tickets, "
    "free airport lounge, valet parking) as offers with the closest matching "
    "category or null. For color_primary/color_secondary give the physical "
    "card's design colors as hex — from the document or from your knowledge "
    "of this specific card's look; null if you don't know it."
)

USER_TEMPLATE = """Extract the card and its reward rules from this document.

Return JSON with this shape:
{{
  "card": {{"id": str, "name": str, "issuer": str,
            "network": "visa|mastercard|amex|other",
            "currency": str, "annual_fee": number,
            "color_primary": "#RRGGBB"|null, "color_secondary": "#RRGGBB"|null}},
  "rules": [{{"category": str, "rate": number, "unit": str,
              "cap_amount": number|null, "cap_period": str,
              "min_spend": number|null, "conditions": str|null}}],
  "offers": [{{"title": str, "category": str|null, "description": str|null}}],
  "points_valuation": {{"points_currency": str, "value_per_point": number}} | null
}}

Document:
---
{text}
---"""


@dataclass
class Extraction:
    card: Card
    rules: list[RewardRule]
    valuation: PointsValuation | None
    offers: list[Offer] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


def _slug(*parts: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", " ".join(parts).lower()).strip("_")


def extract(text: str, client: LLMClient, source_ref: str) -> Extraction:
    raw = client.complete(SYSTEM_PROMPT, USER_TEMPLATE.format(text=text))
    data = _parse_json(raw)

    card_data = dict(data["card"])
    if not card_data.get("id"):  # LLMs often leave id null; derive it
        card_data["id"] = _slug(card_data.get("issuer") or "", card_data.get("name") or "")
    if card_data.get("annual_fee") is None:
        card_data["annual_fee"] = 0.0
    if not card_data.get("currency"):
        card_data["currency"] = "GBP"
    for key in ("color_primary", "color_secondary"):
        c = card_data.get(key)
        if c and re.match(r"^[0-9a-fA-F]{6}$", c):
            card_data[key] = f"#{c}"  # tolerate missing '#'
        elif c and not re.match(r"^#[0-9a-fA-F]{6}$", c):
            card_data[key] = None  # drop junk instead of failing the run
    card = Card(**card_data)
    card.validate()

    rules, warnings = [], []
    for r in data.get("rules", []):
        rule = RewardRule(card_id=card.id, source_ref=source_ref, **r)
        if rule.category not in VALID_CATEGORIES:
            warnings.append(
                f"skipped rule with unknown category '{rule.category}' "
                f"(rate {rule.rate} {rule.unit})"
            )
            continue
        if rule.rate is None:
            warnings.append(f"skipped '{rule.category}' rule with missing rate")
            continue
        if rule.cap_amount is not None and rule.cap_period == "none":
            # Incoherent cap from the LLM: keep the rule, drop the cap rather
            # than invent a period. Original text stays in conditions.
            warnings.append(
                f"'{rule.category}' rule had cap {rule.cap_amount} without a "
                "period — cap ignored, verify against the source"
            )
            rule.cap_amount = None
        rule.validate()
        rules.append(rule)

    offers = []
    for o in data.get("offers") or []:
        offer = Offer(card_id=card.id, source_ref=source_ref, **o)
        if not offer.title:
            warnings.append("skipped offer with missing title")
            continue
        if offer.category is not None and offer.category not in VALID_CATEGORIES:
            warnings.append(
                f"offer '{offer.title}': unknown category '{offer.category}', kept as generic"
            )
            offer.category = None
        offer.validate()
        offers.append(offer)

    valuation = None
    if data.get("points_valuation"):
        valuation = PointsValuation(card_id=card.id, **data["points_valuation"])
        valuation.validate()

    return Extraction(card=card, rules=rules, valuation=valuation,
                      offers=offers, warnings=warnings)


def _parse_json(raw: str) -> dict:
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        raise ValueError(f"LLM did not return valid JSON: {e}") from e
    if "card" not in data:
        raise ValueError("LLM response missing 'card'")
    return data
