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


def _brave(query: str, country: str = "") -> list[str] | None:
    """Brave Search API — reliable from a server IP and locale-aware. Free tier
    ~2000/mo. Set BRAVE_API_KEY to enable. Returns None (skip) when not
    configured. `country` (ISO alpha-2, e.g. 'AE') regionally biases results."""
    key = os.environ.get("BRAVE_API_KEY")
    if not key:
        return None
    params = {"q": query, "count": 10}
    if country:
        params["country"] = country.upper()  # e.g. AE -> UAE results
    resp = requests.get(
        "https://api.search.brave.com/res/v1/web/search",
        params=params,
        headers={"X-Subscription-Token": key, "Accept": "application/json"},
        timeout=20,
    )
    resp.raise_for_status()
    return [r["url"] for r in resp.json().get("web", {}).get("results", [])]


def _searxng(query: str, country: str = "") -> list[str] | None:
    """Self-hosted SearXNG metasearch (free, no key, aggregates engines).
    Set SEARXNG_URL (e.g. http://localhost:8888) to enable. SearXNG must have
    the JSON format enabled (search.formats: [html, json] in settings.yml)."""
    base = os.environ.get("SEARXNG_URL")
    if not base:
        return None
    params = {"q": query, "format": "json"}
    if country:  # SearXNG language tag, e.g. en-AE; a soft regional hint.
        params["language"] = f"en-{country.upper()}"
    resp = requests.get(
        base.rstrip("/") + "/search",
        params=params,
        headers=HEADERS,
        timeout=20,
    )
    resp.raise_for_status()
    return [r["url"] for r in resp.json().get("results", []) if r.get("url")]


def _serper(query: str, country: str = "") -> list[str] | None:
    """Serper.dev (Google results). Set SERPER_API_KEY to enable."""
    key = os.environ.get("SERPER_API_KEY")
    if not key:
        return None
    body = {"q": query}
    if country:
        body["gl"] = country.lower()  # Google 'gl' geo-location param
    resp = requests.post(
        "https://google.serper.dev/search",
        json=body,
        headers={"X-API-KEY": key, "Content-Type": "application/json"},
        timeout=20,
    )
    resp.raise_for_status()
    return [r["link"] for r in resp.json().get("organic", []) if r.get("link")]


def _ddg(query: str, country: str = "") -> list[str]:
    resp = requests.get("https://html.duckduckgo.com/html/",
                        params={"q": query}, headers=HEADERS, timeout=20)
    resp.raise_for_status()
    return parse_search_results(resp.text)


def _bing(query: str, country: str = "") -> list[str]:
    resp = requests.get("https://www.bing.com/search",
                        params={"q": query}, headers=HEADERS, timeout=20)
    resp.raise_for_status()
    urls: list[str] = []
    for m in re.finditer(r'<h2>\s*<a[^>]+href="(https?://[^"]+)"', resp.text):
        u = m.group(1)
        if "bing.com" not in u and u not in urls:
            urls.append(u)
    return urls


def _mojeek(query: str, country: str = "") -> list[str]:
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


# Tried in order; first engine that returns results wins. Brave is the default
# (locale-aware, reliable from a server IP); it self-skips when BRAVE_API_KEY is
# absent, falling through to the free self-hosted SearXNG and keyless scrapers.
_ENGINES = (_brave, _searxng, _serper, _ddg, _bing, _mojeek)


def search(query: str, country: str = "", limit: int = 10) -> list[str]:
    """Web search with provider fallback. Brave first when BRAVE_API_KEY is set
    (regionally biased by `country`); otherwise SearXNG / keyless scrapers."""
    last_exc: Exception | None = None
    for engine in _ENGINES:
        try:
            urls = engine(query, country)
            if urls:
                return urls[:limit]
        except Exception as e:  # engine blocked/errored -> try the next
            last_exc = e
            continue
    if last_exc:
        raise last_exc
    return []


# Reliable-from-a-server engines merged for recall (no scrapers: they're
# blocked from server IPs and their timeouts would stall the merge). Each
# self-skips when unconfigured.
_MERGE_ENGINES = (_brave, _searxng, _serper)


def search_all(query: str, country: str = "", limit: int = 15) -> list[str]:
    """UNION results across engines (recall over speed): Brave's localization +
    SearXNG's index coverage, so one engine's gaps are filled by another. Falls
    back to the first-wins scraper chain only if the merge engines yield nothing.
    Used where missing a page loses a real offer (merchant discovery)."""
    seen: list[str] = []
    for engine in _MERGE_ENGINES:
        try:
            for u in engine(query, country) or []:
                if u not in seen:
                    seen.append(u)
        except Exception:
            continue
    if seen:
        return seen[:limit]
    try:  # nothing from Brave/SearXNG/Serper -> last-resort scrapers
        return search(query, country, limit)
    except Exception:
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


def find_doc_urls(card_name: str, country: str = "", n: int = 6) -> list[str]:
    """Ranked candidate doc URLs for the card. Tries several query shapes (a
    single over-specified query often returns zero results). The caller should
    verify the extracted card matches, trying the next candidate if not."""
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
            for u in search(q, country=country):
                if u not in seen:
                    seen.append(u)
        except Exception:
            continue
        if len(seen) >= 8:
            break
    return rank_urls(seen, card_name)[:n]


def find_doc_url(card_name: str, country: str = "") -> str:
    """Single best doc URL (raises if none)."""
    urls = find_doc_urls(card_name, country, n=1)
    if not urls:
        raise LookupError(f"no search results for: {card_name}")
    return urls[0]


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
