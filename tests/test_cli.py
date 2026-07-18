"""B4: CLI glue end-to-end with a mocked LLM and temp DB."""

from ingestion.cli import run
from ingestion.db import Database
from tests.test_extract import GOOD, FakeLLM


def test_run_extracts_and_writes_db(tmp_path):
    doc = tmp_path / "amex.txt"
    doc.write_text("Amex Gold rewards ...")
    db_path = tmp_path / "cards.db"

    result = run(str(doc), str(db_path), provider=None, client=FakeLLM(GOOD))

    assert result.card.id == "amex_gold"

    db = Database(str(db_path))
    assert db.get_card("amex_gold").name == "Amex Gold"
    rules = db.get_rules("amex_gold")
    assert {r.category for r in rules} == {"dining", "grocery"}
    assert db.get_valuation("amex_gold").value_per_point == 0.009
