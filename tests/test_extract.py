"""B2: extraction — mocked LLM -> validated models; malformed rejected."""

import json

import pytest

from ingestion.extract import extract
from ingestion.llm import LLMClient


class FakeLLM(LLMClient):
    def __init__(self, response: str):
        self.response = response
        self.calls = []

    def complete(self, system: str, user: str) -> str:
        self.calls.append((system, user))
        return self.response


GOOD = json.dumps({
    "card": {"id": "amex_gold", "name": "Amex Gold", "issuer": "American Express",
             "network": "amex", "currency": "GBP", "annual_fee": 195},
    "rules": [
        {"category": "dining", "rate": 4, "unit": "points_per_unit",
         "cap_amount": None, "cap_period": "none", "min_spend": None, "conditions": None},
        {"category": "grocery", "rate": 2, "unit": "points_per_unit",
         "cap_amount": 500, "cap_period": "monthly", "min_spend": None, "conditions": None},
    ],
    "points_valuation": {"points_currency": "MR", "value_per_point": 0.009},
})


def test_extract_parses_and_validates():
    llm = FakeLLM(GOOD)
    result = extract("doc text", llm, source_ref="amex.pdf")
    assert result.card.id == "amex_gold"
    assert len(result.rules) == 2
    assert result.rules[0].source_ref == "amex.pdf"
    assert result.valuation.value_per_point == 0.009
    assert llm.calls, "LLM was called"


def test_extract_captures_cost_facts_and_coerces():
    data = json.dumps({
        "card": {"id": "c", "name": "C", "issuer": "Bank", "network": "visa",
                 "currency": "AED", "annual_fee": 0,
                 "apr": "39%", "foreign_tx_fee": 2.99,
                 "min_salary": "5000", "interest_free_days": 55},
        "rules": [], "points_valuation": None,
    })
    card = extract("doc", FakeLLM(data), source_ref="x").card
    assert card.apr == 39.0            # "39%" -> 39.0
    assert card.foreign_tx_fee == 2.99
    assert card.min_salary == 5000.0
    assert card.interest_free_days == 55


def test_extract_ignores_null_points_valuation():
    # LLM often returns a valuation stub with null fields for cashback cards —
    # must not crash (regression: '<=' None vs int TypeError).
    data = json.dumps({
        "card": {"id": "c", "name": "C", "issuer": "B", "network": "visa",
                 "currency": "AED", "annual_fee": 0},
        "rules": [], "points_valuation": {"points_currency": None,
                                          "value_per_point": None},
    })
    result = extract("doc", FakeLLM(data), source_ref="x")
    assert result.valuation is None


def test_extract_rejects_malformed_json():
    with pytest.raises(ValueError):
        extract("doc", FakeLLM("not json"), source_ref="x")


def test_extract_skips_unknown_category_with_warning():
    data = json.dumps({
        "card": {"id": "c", "name": "C", "issuer": "I", "network": "visa"},
        "rules": [
            {"category": "electronics", "rate": 5, "unit": "cashback_pct"},
            {"category": "general", "rate": 1, "unit": "cashback_pct"},
        ],
        "points_valuation": None,
    })
    result = extract("doc", FakeLLM(data), source_ref="x")
    assert [r.category for r in result.rules] == ["general"]
    assert len(result.warnings) == 1
    assert "electronics" in result.warnings[0]


def test_extract_skips_rule_with_null_rate():
    data = json.dumps({
        "card": {"id": "c", "name": "C", "issuer": "I", "network": "visa"},
        "rules": [
            {"category": "dining", "rate": None, "unit": "cashback_pct"},
            {"category": "general", "rate": 1, "unit": "cashback_pct"},
        ],
        "points_valuation": None,
    })
    result = extract("doc", FakeLLM(data), source_ref="x")
    assert [r.category for r in result.rules] == ["general"]
    assert any("rate" in w for w in result.warnings)


def test_extract_cap_without_period_dropped_not_fatal():
    data = json.dumps({
        "card": {"id": "c", "name": "C", "issuer": "I", "network": "visa"},
        "rules": [
            {"category": "dining", "rate": 2, "unit": "cashback_pct",
             "cap_amount": 500, "cap_period": "none"},
        ],
        "points_valuation": None,
    })
    result = extract("doc", FakeLLM(data), source_ref="x")
    assert len(result.rules) == 1
    assert result.rules[0].cap_amount is None
    assert result.rules[0].cap_period == "none"
    assert any("cap" in w for w in result.warnings)


def test_extract_card_colors_normalized():
    data = json.dumps({
        "card": {"id": "c", "name": "C", "issuer": "I", "network": "visa",
                 "color_primary": "1B5E20",      # missing '#': tolerated
                 "color_secondary": "greenish"}, # junk: dropped
        "rules": [{"category": "general", "rate": 1, "unit": "cashback_pct"}],
        "points_valuation": None,
    })
    result = extract("doc", FakeLLM(data), source_ref="x")
    assert result.card.color_primary == "#1B5E20"
    assert result.card.color_secondary is None


def test_extract_normalizes_null_fee_and_currency():
    data = json.dumps({
        "card": {"id": "c", "name": "C", "issuer": "I", "network": "visa",
                 "currency": None, "annual_fee": None},
        "rules": [{"category": "general", "rate": 1, "unit": "cashback_pct"}],
        "points_valuation": None,
    })
    result = extract("doc", FakeLLM(data), source_ref="x")
    assert result.card.annual_fee == 0.0
    assert result.card.currency == "GBP"


def test_extract_derives_id_when_null():
    data = json.dumps({
        "card": {"id": None, "name": "Duo Credit Card", "issuer": "Emirates NBD",
                 "network": "other", "currency": "AED", "annual_fee": 0},
        "rules": [{"category": "general", "rate": 1, "unit": "cashback_pct"}],
        "points_valuation": None,
    })
    result = extract("doc", FakeLLM(data), source_ref="x")
    assert result.card.id == "emirates_nbd_duo_credit_card"
    assert result.rules[0].card_id == "emirates_nbd_duo_credit_card"


def test_extract_collects_offers():
    data = json.dumps({
        "card": {"id": "duo", "name": "Duo", "issuer": "ENBD", "network": "visa"},
        "rules": [{"category": "general", "rate": 1, "unit": "cashback_pct"}],
        "offers": [
            {"title": "Buy 1 Get 1 movie tickets", "category": "entertainment",
             "description": "Vox Cinemas weekends"},
            {"title": "Free valet", "category": "parking", "description": None},
        ],
        "points_valuation": None,
    })
    result = extract("doc", FakeLLM(data), source_ref="x")
    assert len(result.offers) == 2
    assert result.offers[0].category == "entertainment"
    assert result.offers[0].source_ref == "x"
    # Unknown offer category kept as generic (None), with warning.
    assert result.offers[1].category is None
    assert any("parking" in w for w in result.warnings)


def test_extract_no_valuation_ok():
    data = json.dumps({
        "card": {"id": "c", "name": "C", "issuer": "I", "network": "visa"},
        "rules": [{"category": "general", "rate": 1, "unit": "cashback_pct"}],
        "points_valuation": None,
    })
    result = extract("doc", FakeLLM(data), source_ref="x")
    assert result.valuation is None
