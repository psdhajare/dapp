"""CLI glue (B4): doc -> load -> extract -> print for human verify -> write DB.

Two modes:
  python -m ingestion.cli path/to/doc.pdf        # local file
  python -m ingestion.cli --auto "Card Name"     # find doc online, whole flow
"""

from __future__ import annotations

import argparse
import sys

from . import cardimage, discover
from .db import Database
from .extract import Extraction, extract
from .llm import get_client
from .loader import load_text


def run(path: str, db_path: str, provider: str | None, client=None) -> Extraction:
    """Ingest a local doc file."""
    text = load_text(path)
    return _ingest(text, source_ref=path, db_path=db_path,
                   provider=provider, client=client)


def run_auto(card_name: str, db_path: str, provider: str | None,
             client=None, url: str | None = None) -> Extraction:
    """Whole flow: card name -> find official doc -> fetch -> extract -> DB."""
    url = url or discover.find_doc_url(card_name)
    print(f"Doc: {url}")
    text = discover.fetch_text(url)
    if not text.strip():
        raise ValueError(f"empty document at {url}")
    return _ingest(text, source_ref=url, db_path=db_path,
                   provider=provider, client=client)


def _ingest(text: str, source_ref: str, db_path: str,
            provider: str | None, client=None) -> Extraction:
    client = client or get_client(provider)
    result = extract(text, client, source_ref=source_ref)

    # Prefer the card's real face color from its image over the LLM's guess.
    colors = cardimage.card_colors(source_ref)
    if colors:
        result.card.color_primary, result.card.color_secondary = colors

    _print_summary(result)

    db = Database(db_path)
    db.init_schema_if_needed()
    db.upsert_card(result.card)
    for rule in result.rules:
        db.upsert_rule(rule)
    if result.valuation:
        db.upsert_valuation(result.valuation)
    for offer in result.offers:
        db.upsert_offer(offer)
    db.mark_held(result.card.id)
    db.close()
    return result


def _print_summary(r: Extraction) -> None:
    print(f"Card: {r.card.name} ({r.card.issuer}, {r.card.network}, {r.card.currency})")
    for rule in r.rules:
        cap = f" cap {rule.cap_amount}/{rule.cap_period}" if rule.cap_amount else ""
        print(f"  {rule.category}: {rule.rate} {rule.unit}{cap}")
    if r.valuation:
        print(f"  points: {r.valuation.value_per_point}/pt")
    for o in r.offers:
        print(f"  offer [{o.category or 'any'}]: {o.title}")
    for w in r.warnings:
        print(f"  WARNING: {w}")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Ingest a card doc into the rules DB.")
    ap.add_argument("source", help="path to card doc (PDF/text), or card name with --auto")
    ap.add_argument("--auto", action="store_true",
                    help="treat source as a card name; find its doc online")
    ap.add_argument("--url", default=None,
                    help="with --auto: skip search, use this doc URL")
    ap.add_argument("--db", default="db/cards.db", help="SQLite DB path")
    ap.add_argument("--provider", default=None, help="LLM provider (default: env/deepseek)")
    args = ap.parse_args(argv)

    if args.auto:
        run_auto(args.source, args.db, args.provider, url=args.url)
    else:
        run(args.source, args.db, args.provider)
    return 0


if __name__ == "__main__":
    sys.exit(main())
