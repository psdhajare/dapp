"""JS-rendering fetch fallback via a hosted render API (provider-agnostic).

Bank "lifestyle"/deals portals are client-rendered SPAs: a plain HTTP fetch
returns no text, so their offers can't be extracted. When a render provider is
configured (RENDER_API_KEY), fetch the *browser-rendered* text so the same LLM
extractor can read the offer — one capability that works for any bank in any
country, no per-site code.

Used only as a fallback when the plain fetch yields nothing, so cost stays
bounded (and results are cached upstream). No key configured -> returns ""
(behaviour is identical to before; nothing breaks).

Add a provider = add a branch here, mirroring the LLM factory.
"""

from __future__ import annotations

import os

import requests

_PROVIDER = os.environ.get("RENDER_PROVIDER", "firecrawl").lower()
_KEY = os.environ.get("RENDER_API_KEY", "")
_TIMEOUT = int(os.environ.get("RENDER_TIMEOUT", "30"))


def is_configured() -> bool:
    return bool(_KEY)


def render_text(url: str) -> str:
    """Browser-rendered text/markdown for [url], or '' if unconfigured/failed."""
    if not _KEY:
        return ""
    try:
        if _PROVIDER == "firecrawl":
            resp = requests.post(
                "https://api.firecrawl.dev/v1/scrape",
                json={"url": url, "formats": ["markdown"],
                      "onlyMainContent": True},
                headers={"Authorization": f"Bearer {_KEY}"},
                timeout=_TIMEOUT,
            )
            resp.raise_for_status()
            data = resp.json().get("data") or {}
            return data.get("markdown") or ""
        raise ValueError(f"unknown render provider: {_PROVIDER}")
    except Exception:
        return ""  # degrade to no-render; never break a search
