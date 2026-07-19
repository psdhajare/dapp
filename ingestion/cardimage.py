"""Derive a card's real face color from its product image.

Text-based color guessing by the LLM is unreliable, so we find the card's image
on the bank page (og:image, else a card-ish <img>), download it, and compute the
dominant vibrant color from the pixels. For multi-color cards this picks the most
prominent saturated color; the secondary is a darker shade for the gradient.
"""

from __future__ import annotations

import colorsys
import io
import re
from collections import Counter
from urllib.parse import urljoin

from . import discover

_OG_IMAGE = re.compile(
    r'<meta[^>]+(?:property|name)=["\'](?:og:image|twitter:image)["\']'
    r'[^>]+content=["\']([^"\']+)["\']',
    re.IGNORECASE,
)
# An <img> whose src or alt hints it's the card render.
_IMG_TAG = re.compile(r'<img[^>]+>', re.IGNORECASE)
_SRC = re.compile(r'src=["\']([^"\']+)["\']', re.IGNORECASE)


def card_image_url(html: str, base_url: str) -> str | None:
    """Best card-image URL from a page: prefer og:image, else a card-ish <img>."""
    if not html:
        return None
    m = _OG_IMAGE.search(html)
    if m:
        return urljoin(base_url, m.group(1))
    for tag in _IMG_TAG.findall(html):
        low = tag.lower()
        if 'card' in low or 'credit' in low:
            src = _SRC.search(tag)
            if src:
                url = urljoin(base_url, src.group(1))
                if re.search(r'\.(png|jpg|jpeg|webp)', url, re.IGNORECASE):
                    return url
    return None


def colors_from_image(data: bytes) -> tuple[str, str] | None:
    """Dominant vibrant color (+ darker shade) as (#RRGGBB, #RRGGBB), or None."""
    from PIL import Image  # pdfplumber already pulls Pillow in

    try:
        im = Image.open(io.BytesIO(data)).convert("RGB")
    except Exception:
        return None
    im.thumbnail((120, 120))
    counts = Counter(im.getdata())

    best_rgb = None
    best_score = -1.0
    for rgb, cnt in counts.items():
        r, g, b = (c / 255 for c in rgb)
        _, s, v = colorsys.rgb_to_hsv(r, g, b)
        if v > 0.92 and s < 0.15:  # near-white background
            continue
        if v < 0.12:  # near-black
            continue
        # Favor frequent AND saturated pixels so the card's brand color wins
        # over neutral plastic/borders.
        score = cnt * (0.35 + 0.65 * s)
        if score > best_score:
            best_score = score
            best_rgb = rgb

    if best_rgb is None:
        if not counts:
            return None
        best_rgb = counts.most_common(1)[0][0]

    primary = "#%02X%02X%02X" % best_rgb
    r, g, b = best_rgb
    secondary = "#%02X%02X%02X" % (int(r * 0.78), int(g * 0.78), int(b * 0.78))
    return primary, secondary


def card_colors(source_url: str) -> tuple[str, str] | None:
    """Full pipeline: page URL -> card image -> (primary, secondary). Best-effort."""
    if not source_url.lower().startswith("http"):
        return None
    try:
        html = discover.fetch_html(source_url)
        img_url = card_image_url(html, source_url)
        if not img_url:
            return None
        return colors_from_image(discover.fetch_bytes(img_url))
    except Exception:
        return None
