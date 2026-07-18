"""Document loader (B3): PDF or text file -> clean text."""

from __future__ import annotations

from pathlib import Path


def load_text(path: str) -> str:
    p = Path(path)
    if not p.exists():
        raise FileNotFoundError(path)

    if p.suffix.lower() == ".pdf":
        return _load_pdf(p)
    return p.read_text(encoding="utf-8")


def _load_pdf(p: Path) -> str:
    import pdfplumber

    parts = []
    with pdfplumber.open(p) as pdf:
        for page in pdf.pages:
            parts.append(page.extract_text() or "")
    return "\n".join(parts).strip()
