"""Auto-discovery: card name -> official doc URL -> clean text.

Search is keyless (DuckDuckGo HTML endpoint). Ranking prefers domains that
contain words from the card name (bank domains beat aggregators).
"""

from __future__ import annotations

import os
import re
import urllib.parse
from html.parser import HTMLParser

import requests

# A real browser UA — search engines block unusual/custom agents outright.
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                  "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
}
MAX_DOC_CHARS = 40_000

# Generic words that don't identify the bank.
_NOISE_WORDS = {"credit", "card", "cashback", "cash", "back", "rewards", "the", "bank"}


def _brave(query: str) -> list[str] | None:
    """Brave Search API — reliable from a server IP. Free tier ~2000/mo.
    Set BRAVE_API_KEY to enable. Returns None (skip) when not configured."""
    key = os.environ.get("BRAVE_API_KEY")
    if not key:
        return None
    resp = requests.get(
        "https://api.search.brave.com/res/v1/web/search",
        params={"q": query, "count": 10},
        headers={"X-Subscription-Token": key, "Accept": "application/json"},
        timeout=20,
    )
    resp.raise_for_status()
    return [r["url"] for r in resp.json().get("web", {}).get("results", [])]


def _serper(query: str) -> list[str] | None:
    """Serper.dev (Google results). Set SERPER_API_KEY to enable."""
    key = os.environ.get("SERPER_API_KEY")
    if not key:
        return None
    resp = requests.post(
        "https://google.serper.dev/search",
        json={"q": query},
        headers={"X-API-KEY": key, "Content-Type": "application/json"},
        timeout=20,
    )
    resp.raise_for_status()
    return [r["link"] for r in resp.json().get("organic", []) if r.get("link")]


def _ddg(query: str) -> list[str]:
    resp = requests.get("https://html.duckduckgo.com/html/",
                        params={"q": query}, headers=HEADERS, timeout=20)
    resp.raise_for_status()
    return parse_search_results(resp.text)


def _bing(query: str) -> list[str]:
    resp = requests.get("https://www.bing.com/search",
                        params={"q": query}, headers=HEADERS, timeout=20)
    resp.raise_for_status()
    urls: list[str] = []
    for m in re.finditer(r'<h2>\s*<a[^>]+href="(https?://[^"]+)"', resp.text):
        u = m.group(1)
        if "bing.com" not in u and u not in urls:
            urls.append(u)
    return urls


def _mojeek(query: str) -> list[str]:
    resp = requests.get("https://www.mojeek.com/search",
                        params={"q": query}, headers=HEADERS, timeout=20)
    resp.raise_for_status()
    urls, seen = [], set()
    for m in re.finditer(r'<a[^>]+class="[^"]*title[^"]*"[^>]+href="(https?://[^"]+)"',
                         resp.text):
        u = m.group(1)
        if u not in seen:
            seen.add(u)
            urls.append(u)
    return urls


# Tried in order; first engine that returns results wins. Keyed APIs (reliable
# from a server IP) go first when configured; keyless scrapers are the fallback.
_ENGINES = (_brave, _serper, _ddg, _bing, _mojeek)


def search(query: str, limit: int = 10) -> list[str]:
    """Web search with provider fallback. Prefers a keyed API (BRAVE_API_KEY /
    SERPER_API_KEY) when set; otherwise scrapes DDG/Bing/Mojeek."""
    last_exc: Exception | None = None
    for engine in _ENGINES:
        try:
            urls = engine(query)
            if urls:
                return urls[:limit]
        except Exception as e:  # engine blocked/errored -> try the next
            last_exc = e
            continue
    if last_exc:
        raise last_exc
    return []


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


def find_doc_url(card_name: str, country: str = "") -> str:
    """Best official-looking URL for the card's rewards/terms doc.

    Tries several query shapes (a single over-specified query often returns zero
    results) and only fails if none do."""
    c = f" {country}" if country else ""
    queries = [
        f"{card_name}{c}",
        f"{card_name} credit card{c}",
        f"{card_name} rewards terms fees{c}",
        card_name,  # last resort: bare name, no country
    ]
    seen: list[str] = []
    for q in queries:
        try:
            for u in search(q):
                if u not in seen:
                    seen.append(u)
        except Exception:
            continue
        if len(seen) >= 5:
            break
    if not seen:
        raise LookupError(f"no search results for: {card_name}")
    return rank_urls(seen, card_name)[0]


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
