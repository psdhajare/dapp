# Best Card — UX Design Brief

## What the product is

A personal, offline-first mobile app (Flutter, iOS-first) that answers one
question at the moment of payment: **"Which of my credit cards should I use
right here, right now, to earn the most rewards?"**

The user stands at a till (restaurant, supermarket, fuel station), opens the
app, and within ~2 seconds sees the winning card from their own wallet, with
the effective reward rate. No accounts, no bank logins, no transaction data —
card reward rules are ingested automatically from banks' public documentation
by a companion service. All data lives on the device.

Target user today: a single power user (the founder). Target soon: anyone
with 3–10 credit cards who wants to stop guessing at checkout. The design
must feel trustworthy (it deals with money), instant, and quietly premium —
think Apple Wallet meets a personal finance concierge, not a bank portal and
not a gamified points app.

## Brand adjectives

Precise, calm, confident, financial-grade, effortless. Never: cluttered,
loud, cartoonish, corporate-bank-beige.

---

## Current app structure (as built)

Two tabs in a bottom navigation bar: **Best card** and **Wallet**.

### Screen 1 — Best card (home / recommendation)

Purpose: instant answer at the point of payment.

Current layout, top to bottom:

1. **Large title** "Best card" + subtitle "Where are you paying?"
2. **Context chip row** (horizontally scrollable):
   - "My location" chip with a navigation-arrow icon — uses GPS + Places API
     to detect the venue type (restaurant → dining, supermarket → grocery…).
   - Five icon-only chips simulating venue types: restaurant (fork/knife),
     supermarket (cart), fuel (pump), cinema (clapper), online (shopping bag).
     Tooltips carry the label. Selected chip fills with accent color.
3. **Section label** — "Best for everyday spend" (default, general category
   on app open) or "Best for dining" etc. after a chip is chosen.
4. **Winner card** — a realistic credit-card visual (ISO 7810 aspect ratio,
   1.586:1): issuer name top-left, contactless icon, EMV chip, big effective
   rate ("5.00%" + "back on dining"), card name bottom-left, network mark
   (Visa / Mastercard circles / Amex) bottom-right. Card background uses the
   **real physical card's colors** (stored per card as two hex values from
   ingestion; falls back to an issuer-hashed dark gradient when unknown).
   Text/ink color auto-switches black/white by background luminance (Apple
   Card is near-white, so ink is black).
5. **Runner-up tiles** — ranks 2 and 3 as compact rows: rank number, small
   card-color swatch, card name + issuer, effective rate on the right.
6. **Info pills** (contextual, only when relevant):
   - Orange cap pill: "Rewards cap: 500 per month".
   - Blue min-spend hint pill: "Emirates NBD · Duo Credit Card would give
     5.00% if your monthly spend is 5000". (Rules with unmet minimum monthly
     spend are excluded from winning but surfaced as an upsell hint.)
7. **Perks section** — "PERKS FOR DINING" eyebrow label, then compact offer
   tiles: circular category icon, offer title (1 line), description (max 2
   lines), small card-color swatch + card name. Only offers matching the
   current category are shown (e.g. BOGO cinema tickets appear for
   entertainment, dining programmes for dining).
8. Elements animate in with a staggered fade + slide-up (110 ms stagger).

Empty state: "No card in your wallet covers X yet. Add one in the Wallet
tab."

### Screen 2 — Wallet

Purpose: manage which cards the user holds.

1. **Large title** "Wallet" + helper line "Tap ✕ on a card to remove it."
2. **Card list** — each held card rendered as the same realistic card visual
   (real colors, chip, contactless, masked number dots, network mark), with
   a small ✕ button in the top-right corner. Swipe-left also removes.
3. **Remove flow** — ✕ opens an iOS-style bottom action sheet: card label,
   destructive red "Remove from wallet", "Cancel". After removal a floating
   snackbar with "Undo" auto-dismisses in 3 s.
4. **"Add a card" primary button** pinned at the bottom.
5. **Add flow** — bottom sheet with a single text field ("e.g. Emirates NBD
   Titanium"). User types a card's name in plain words; the backend finds
   the bank's official page, extracts reward rules/colors/offers via LLM,
   and the card appears in the wallet (~30–60 s). Progress copy: "Reading
   the fine print…". Errors show inline in red (e.g. lookup failed).

### Companion (not a phone screen, for context)

A local Python service does the ingestion. Invisible to the user except as
the add-card wait state. No design needed beyond that wait/progress moment.

---

## User flows

**Flow A — at the till (the core moment, must be fastest):**
Open app → (optional) tap "My location" or a venue chip → see winner card +
rate → pay with it. Two taps max, ideally zero (app opens on everyday-spend
ranking).

**Flow B — simulate/plan:**
Open app → tap venue chips one by one → compare which card wins where →
note min-spend hints ("if I put 5,000/month through Duo, groceries jump to
5%").

**Flow C — manage wallet:**
Wallet tab → add a card by typing its name → wait state → card appears with
its real design colors → recommendation updates everywhere. Remove via ✕ +
confirm, undo within 3 s.

---

## What we want from you (the designer)

### Deliverable 1 — three candidate design systems

Propose **three distinct design directions**, each presented in **both light
and dark mode**, applied to our two real screens (Best card with a winner +
runner-ups + perks; Wallet with 3–4 cards). For each direction give:

- Name + one-paragraph rationale (what feeling it optimizes for).
- Full palette: background layers, surface, primary accent, semantic colors
  (success/warn for cap + hint pills), on-card ink rules. Light + dark
  values for every token.
- Typography: professional, sophisticated typeface pairing (display +
  text). No default-feeling system stacks unless deliberately chosen;
  suggest licensed/Google alternatives (e.g. neue-grotesk-class, humanist
  sans, or a quiet serif for display). Include the numeric style for the
  big rate figure — tabular figures matter to us.
- Component treatments: chips, pills, offer tiles, bottom sheets, nav bar,
  snackbar.
- How the **card visual** sits in this system (shadows, radius, lighting).
  Note: card faces use each bank's real colors — the system must make
  arbitrary card colors look at home in both modes.
- Motion language: entrance stagger, chip selection, tab transitions,
  add-card progress state.

### Deliverable 2 — after we pick one

Full design system on the chosen direction: token sheet (light + dark),
all components in all states (default/selected/disabled/loading/error),
both screens pixel-final for iPhone (390×844 safe areas), the add-card and
remove-card sheets, empty states, and the app icon. Export tokens in a
developer-friendly form (JSON or Flutter ThemeData-ready values).

### Constraints

- Flutter Material 3 is the implementation base — designs should map to it
  without fighting the framework.
- Both modes are first-class; the user may keep dark permanently.
- The realistic card visual is the product's hero — everything else should
  defer to it.
- Financial-grade legibility: rates and card names never truncate
  ambiguously; contrast AA minimum everywhere, AAA for the rate figure.
- One accent color max per direction; semantic orange/blue pills must
  survive both modes.
- No lorem ipsum — use the real content from this brief in mockups
  (Mashreq Cashback 5% dining, Emirates NBD Duo cap 500/month, Apple Card
  white face, etc.).
