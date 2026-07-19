"""Card face-color extraction from product images (image gen in-memory, no net)."""

import io

from PIL import Image

from ingestion import cardimage, discover


def _png(pixels: list[tuple[int, int, int]], size=(40, 40)) -> bytes:
    """A PNG that's mostly `pixels[0]` background with a `pixels[1]` block."""
    im = Image.new("RGB", size, pixels[0])
    if len(pixels) > 1:
        for x in range(10, 30):
            for y in range(10, 30):
                im.putpixel((x, y), pixels[1])
    buf = io.BytesIO()
    im.save(buf, format="PNG")
    return buf.getvalue()


def test_colors_picks_vibrant_over_white_background():
    # White background dominates by count but is filtered; orange wins.
    orange = (224, 138, 46)
    data = _png([(255, 255, 255), orange])
    primary, secondary = cardimage.colors_from_image(data)
    assert primary == "#E08A2E"
    # Secondary is a darker shade of the same hue.
    assert secondary == "#AE6B23"


def test_colors_returns_none_on_garbage():
    assert cardimage.colors_from_image(b"not an image") is None


def test_card_image_url_prefers_og_image():
    html = (
        '<html><head>'
        '<meta property="og:image" content="/img/card.png">'
        '</head></html>'
    )
    url = cardimage.card_image_url(html, "https://bank.example/cards/gold")
    assert url == "https://bank.example/img/card.png"


def test_card_image_url_falls_back_to_card_img():
    html = '<img src="https://cdn.x/hero.jpg"><img class="credit-card" src="/c.png">'
    url = cardimage.card_image_url(html, "https://bank.example/x")
    assert url == "https://bank.example/c.png"


def test_card_image_url_none_when_absent():
    assert cardimage.card_image_url("<html></html>", "https://x") is None


def test_card_colors_pipeline(monkeypatch):
    orange = (224, 138, 46)
    monkeypatch.setattr(
        discover, "fetch_html",
        lambda url, timeout=15: '<meta property="og:image" content="/card.png">',
    )
    monkeypatch.setattr(
        discover, "fetch_bytes",
        lambda url, timeout=15: _png([(255, 255, 255), orange]),
    )
    assert cardimage.card_colors("https://bank.example/gold") == ("#E08A2E", "#AE6B23")


def test_card_colors_skips_non_http():
    assert cardimage.card_colors("file.pdf") is None


def test_card_colors_swallows_errors(monkeypatch):
    def boom(url, timeout=15):
        raise RuntimeError("network down")

    monkeypatch.setattr(discover, "fetch_html", boom)
    assert cardimage.card_colors("https://bank.example/gold") is None
