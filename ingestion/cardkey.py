"""Normalize a card name into a stable catalog key, so different spellings of
the same card ("ENBD Duo", "Emirates NBD Duo Credit Card") map to one entry
instead of re-fetching from the web each time.

Identity is issuer + product — NOT the user's country (a card is the same card
wherever you hold it). Country is only a search hint elsewhere, not part of the
key.
"""

from __future__ import annotations

import re

# Common bank acronyms -> full name (UAE-first). Expanded as whole words so the
# distinctive tokens match regardless of how the user typed the issuer.
_ALIASES = {
    "enbd": "emirates nbd",
    "adcb": "abu dhabi commercial",
    "fab": "first abu dhabi",
    "dib": "dubai islamic",
    "cbd": "commercial bank dubai",
    "rakbank": "rak",
    "eib": "emirates islamic",
    "sc": "standard chartered",
    "scb": "standard chartered",
}

# Generic words that don't distinguish a card. Card tiers (platinum, titanium,
# duo, signature, …) are intentionally kept — they separate cards of one bank.
_STOP = {
    "credit", "debit", "card", "cards", "the", "of", "and", "a", "an",
    "bank", "banks", "pjsc", "ltd", "llc", "co",
}


def _norm_tokens(s: str) -> set[str]:
    """Distinctive, alias-expanded tokens of a card name/query."""
    s = s.lower()
    for alias, full in _ALIASES.items():
        s = re.sub(rf"\b{alias}\b", full, s)
    return {w for w in re.split(r"[^a-z0-9]+", s) if w and w not in _STOP}


def card_key(name: str) -> str:
    """Stable key: alias-expanded, generic words dropped, distinctive tokens
    sorted. Country-independent — the card is the same product everywhere."""
    return " ".join(sorted(_norm_tokens(name)))


def matches(query: str, card_text: str, threshold: float = 0.6) -> bool:
    """True if the extracted card plausibly IS the card the user searched for:
    most of the query's distinctive tokens appear in the card's name+issuer.
    Guards against discovery returning a wrong card's document."""
    q = _norm_tokens(query)
    if not q:
        return True
    hit = len(q & _norm_tokens(card_text))
    return hit / len(q) >= threshold
