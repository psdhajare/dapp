"""B3: document loader — text read, missing file, PDF dispatch."""

import pytest

from ingestion import loader


def test_loads_text_file(tmp_path):
    f = tmp_path / "doc.txt"
    f.write_text("dining 5% cashback")
    assert loader.load_text(str(f)) == "dining 5% cashback"


def test_missing_file_raises(tmp_path):
    with pytest.raises(FileNotFoundError):
        loader.load_text(str(tmp_path / "nope.txt"))


def test_pdf_dispatches_to_pdf_reader(tmp_path, monkeypatch):
    f = tmp_path / "doc.pdf"
    f.write_bytes(b"%PDF-1.4 fake")
    monkeypatch.setattr(loader, "_load_pdf", lambda p: "pdf text")
    assert loader.load_text(str(f)) == "pdf text"
