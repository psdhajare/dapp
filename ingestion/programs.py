"""Loyalty / partner programs bundled with credit cards (e.g. Wio → The
Entertainer). Many UAE offers reach a cardholder through such a program rather
than a direct bank page, so we check whether a merchant participates in the
programs the user's cards grant.

Curated, data-driven: adding a card→program link or a new program is a one-line
edit here — no logic change. Keeping this map complete for the user's cards is
what makes offer coverage complete.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from . import discover


@dataclass
class Program:
    key: str
    name: str            # display name, shown as "via <name>"
    default_offer: str   # the program's standard benefit at any member merchant
    value_pct: float     # effective saving of that benefit (buy-1-get-1 ≈ 50)
    short_label: str     # deck badge, e.g. "1+1"
    # Domains whose readable pages authoritatively list member merchants.
    member_domains: tuple[str, ...]


PROGRAMS: dict[str, Program] = {
    "entertainer": Program(
        key="entertainer",
        name="The Entertainer",
        default_offer="Buy 1 Get 1 free",
        value_pct=50,
        short_label="1+1",
        member_domains=("theentertainerme.com",),
    ),
    # Add more as cards are mapped, e.g. smiles, visa_offers, mastercard.
}

# Which programs a card grants, keyed by a distinctive token of the card/issuer.
# Matched against the card's lowercase tokens (see programs_for_cards).
CARD_PROGRAMS: dict[str, tuple[str, ...]] = {
    "wio": ("entertainer",),
    # "adcb": ("entertainer",),  # example: add when confirmed
}


def _tokens(s: str) -> set[str]:
    return {w for w in re.split(r"\W+", s.lower()) if len(w) > 2}


def programs_for_cards(cards: list[str]) -> list[str]:
    """Programs granted by any of the given card names. De-duped, order-stable."""
    out: list[str] = []
    for card in cards:
        toks = _tokens(card)
        for key, progs in CARD_PROGRAMS.items():
            if key in toks:
                for p in progs:
                    if p not in out:
                        out.append(p)
    return out


def granting_cards(program: str, cards: list[str]) -> list[str]:
    """Which of the user's cards grant [program] (for offer attribution)."""
    return [c for c in cards
            if any(k in _tokens(c) and program in CARD_PROGRAMS[k]
                   for k in CARD_PROGRAMS)]


def merchant_on_program(merchant: str, program: str,
                        timeout: int = 12) -> bool:
    """True if [merchant] is a member of [program] — confirmed from a readable
    member-listing page that actually names the merchant."""
    prog = PROGRAMS.get(program)
    if not prog:
        return False
    tokens = [w for w in re.split(r"\W+", merchant.lower()) if len(w) > 2]
    if not tokens:
        return False
    try:
        results = discover.search(f"{merchant} {prog.name}")
    except Exception:
        return False
    for url in results[:8]:
        if not any(d in url.lower() for d in prog.member_domains):
            continue
        try:
            text = discover.fetch_text(url, timeout=timeout)
        except Exception:
            continue
        low = text.lower()
        # Require the merchant to actually appear on the member page.
        if any(tok in low for tok in tokens):
            return True
    return False
