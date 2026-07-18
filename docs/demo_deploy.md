# Demo Deploy — Best Card on your phone (Cloudflare Pages)

Goal: show the app on your phone in a few hours, smooth. The app already runs
as **Flutter web**, so we deploy the web build to **Cloudflare Pages** (HTTPS,
your domain) and open it in the phone browser. This skips native builds
(Xcode/Android SDK), native SQLite, and OS permission plumbing entirely.

## Why web, not native

- Web SQLite path already works (`sqflite_common_ffi_web` + wasm).
- Browser geolocation works over Cloudflare HTTPS — no Info.plist/manifest.
- "Add to Home Screen" gives a full-screen, app-like icon (Flutter ships a PWA
  manifest + service worker).
- No provisioning profiles, no store review, no toolchain install.

## What works in the demo

- Wallet pre-seeded with 6 real cards (Emirates NBD Duo, Mashreq Cashback,
  Wio, Apple Card, Chase Sapphire, ENBD Titanium).
- **Venue chips** (restaurant / supermarket / fuel / cinema / online) →
  live re-rank of the deck. This is the reliable demo path.
- Ranked deck (winner + 2 runners), min-spend hints, cap pills, perks.
- Wallet: view cards, remove (✕ → confirm → undo).
- Profile: name + light/dark/system toggle (persists).

## What is NOT live on the deployed web app (by default)

- **Add-a-card** — the ingestion service runs on your Mac (DeepSeek key lives
  there). A phone can't reach `localhost`. Two options below.
- **"My location"** — needs a Google Places API key to map GPS→venue; without
  it, location returns "everyday spend". Use the chips instead for the demo.

---

## Tier 1 — reliable deploy (do this first)

1. Build the release web bundle:
   ```
   cd app
   flutter build web --release
   ```
2. Log in to Cloudflare (interactive — run in the session with `!`):
   ```
   ! npx wrangler login
   ```
3. Deploy the build output to Cloudflare Pages:
   ```
   npx wrangler pages deploy build/web --project-name bestcard --commit-dirty=true
   ```
   This prints a `*.pages.dev` URL. Open it on your phone — done.
4. (Optional) Attach your domain: Cloudflare dashboard → Workers & Pages →
   `bestcard` → Custom domains → add `bestcard.yourdomain.com`. DNS is
   automatic since the domain is already on Cloudflare.
5. On the phone: open the URL in Safari/Chrome → Share → **Add to Home
   Screen** for the full-screen app icon.

Demo script: open app → tap the venue chips to show the best card changing per
category → open a card's perks → switch to Wallet → open Profile → flip to
dark mode.

---

## Tier 2 — live "Add a card" (optional, if time)

Expose the Mac's ingestion service through a Cloudflare Tunnel so the phone can
reach it. Keep the Mac awake and online during the demo.

1. Start the ingestion server (holds your DeepSeek key):
   ```
   cd <repo root>
   set -a && source .env && set +a
   python3 -m ingestion.server
   ```
2. In another terminal, expose it:
   ```
   ! cloudflared tunnel --url http://localhost:8765
   ```
   Copy the printed `https://<random>.trycloudflare.com` URL.
3. Rebuild web pointing at that tunnel, then redeploy:
   ```
   cd app
   flutter build web --release \
     --dart-define=INGEST_URL=https://<random>.trycloudflare.com/ingest
   npx wrangler pages deploy build/web --project-name bestcard --commit-dirty=true
   ```
   The server already sends permissive CORS headers, so the browser call works.

Risk: the tunnel URL changes each run; if the Mac sleeps or drops network,
add-card fails. Tier 1 does not depend on any of this.

---

## Known limits (fine for a demo)

- First load fetches Google Fonts + CanvasKit from CDNs (needs network once;
  cached after). True offline-from-install needs bundled .ttf — deferred.
- No live GPS venue detection without a Places key.
- This is the web build; a real native iOS/Android app is separate later work
  (mobile SQLite swap, permissions, toolchain).
