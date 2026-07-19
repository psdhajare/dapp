"""Auto-discovery: card name -> official doc URL -> clean text.

Search is keyless (DuckDuckGo HTML endpoint). Ranking prefers domains that
contain words from the card name (bank domains beat aggregators).
"""

from __future__ import annotations

import re
import urllib.parse
from html.parser import HTMLParser

import requests

HEADERS = {"User-Agent": "Mozilla/5.0 (personal card-rules ingestion tool)"}
MAX_DOC_CHARS = 40_000

# Generic words that don't identify the bank.
_NOISE_WORDS = {"credit", "card", "cashback", "cash", "back", "rewards", "the", "bank"}


def search(query: str, limit: int = 10) -> list[str]:
    """DuckDuckGo HTML search -> result URLs (best-effort, keyless)."""
    resp = requests.get(
        "https://html.duckduckgo.com/html/",
        params={"q": query},
        headers=HEADERS,
        timeout=30,
    )
    resp.raise_for_status()
    return parse_search_results(resp.text)[:limit]


def parse_search_results(html: str) -> list[str]:
    """Extract result URLs from DDG HTML (links are /l/?uddg=<encoded-url>)."""
    urls = []
    for m in re.finditer(r'href="[^"]*?uddg=([^"&]+)', html):
        url = urllib.parse.unquote(m.group(1))
        if url.startswith("http") and url not in urls:
            urls.append(url)
    # Fallback: plain absolute links in result anchors.
    if not urls:
        for m in re.finditer(r'class="result__a"[^>]*href="(https?://[^"]+)"', html):
            if m.group(1) not in urls:
                urls.append(m.group(1))
    return urls


def rank_urls(urls: list[str], card_name: str) -> list[str]:
    """Prefer URLs whose domain contains identifying words from the card name."""
    words = [
        w for w in re.split(r"\W+", card_name.lower())
        if w and w not in _NOISE_WORDS
    ]

    def score(url: str) -> int:
        domain = urllib.parse.urlparse(url).netloc.lower()
        return sum(1 for w in words if w in domain.replace("-", "").replace(".", ""))

    return sorted(urls, key=score, reverse=True)


def find_doc_url(card_name: str) -> str:
    """Best official-looking URL for the card's rewards/terms doc."""
    urls = search(f"{card_name} credit card rewards cashback terms")
    if not urls:
        raise LookupError(f"no search results for: {card_name}")
    return rank_urls(urls, card_name)[0]


class _TextExtractor(HTMLParser):
    _SKIP = {"script", "style", "noscript", "svg", "head"}

    def __init__(self) -> None:
        super().__init__()
        self._skip_depth = 0
        self.parts: list[str] = []

    def handle_starttag(self, tag, attrs):
        if tag in self._SKIP:
            self._skip_depth += 1

    def handle_endtag(self, tag):
        if tag in self._SKIP and self._skip_depth:
            self._skip_depth -= 1

    def handle_data(self, data):
        if not self._skip_depth and data.strip():
            self.parts.append(data.strip())


def html_to_text(html: str) -> str:
    parser = _TextExtractor()
    parser.feed(html)
    return "\n".join(parser.parts)


def fetch_text(url: str, timeout: int = 60) -> str:
    """Fetch a URL and return clean text (HTML stripped, PDFs parsed)."""
    resp = requests.get(url, headers=HEADERS, timeout=timeout)
    resp.raise_for_status()

    content_type = resp.headers.get("content-type", "")
    if "pdf" in content_type or url.lower().endswith(".pdf"):
        import io

        import pdfplumber

        with pdfplumber.open(io.BytesIO(resp.content)) as pdf:
            text = "\n".join(page.extract_text() or "" for page in pdf.pages)
    else:
        text = html_to_text(resp.text)

    return text[:MAX_DOC_CHARS]
