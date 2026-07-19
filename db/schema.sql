-- Best-Card Recommender — SQLite schema (contract shared by ingestion tool + app).
-- Extensible by design: cap data and spend_log present from day one so cap
-- enforcement can be added later with no migration.

PRAGMA foreign_keys = ON;

-- Canonical spend categories (fixed small taxonomy). Populated as part of the
-- schema contract, not sample data.
CREATE TABLE categories (
    name TEXT PRIMARY KEY
);

INSERT INTO categories (name) VALUES
    ('dining'), ('grocery'), ('fuel'), ('travel'), ('transit'),
    ('online'), ('utilities'), ('entertainment'), ('beauty'), ('health'),
    ('general');

CREATE TABLE cards (
    id                 TEXT PRIMARY KEY,
    name               TEXT NOT NULL,
    issuer             TEXT NOT NULL,
    network            TEXT NOT NULL,  -- payment scheme; validated in Python
    currency           TEXT NOT NULL DEFAULT 'GBP',
    annual_fee         REAL NOT NULL DEFAULT 0,
    apr                REAL,     -- annual percentage rate on balances (%)
    foreign_tx_fee     REAL,     -- % fee on foreign-currency spend
    min_salary         REAL,     -- monthly income requirement
    interest_free_days INTEGER,  -- grace period on purchases
    color_primary      TEXT,  -- '#RRGGBB' of the physical card design, if known
    color_secondary    TEXT
);

-- Reward rate for a card in a category. Cap fields stored always; enforcement
-- is a later concern (v1 flags the cap, v1.5 enforces via spend_log).
CREATE TABLE reward_rules (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    card_id    TEXT NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    category   TEXT NOT NULL REFERENCES categories(name),
    rate       REAL NOT NULL,
    unit       TEXT NOT NULL CHECK (unit IN ('cashback_pct', 'points_per_unit')),
    cap_amount REAL,                        -- NULL = no cap
    cap_period TEXT NOT NULL DEFAULT 'none'
                 CHECK (cap_period IN ('none', 'monthly', 'quarterly', 'yearly')),
    min_spend  REAL,                        -- NULL = no minimum
    conditions TEXT,                        -- free text, human-readable
    source_ref TEXT,                        -- where this rule came from (doc/url)
    verified   INTEGER NOT NULL DEFAULT 0 CHECK (verified IN (0, 1)),
    UNIQUE (card_id, category)
);

-- Value of one point in the card's currency. Lets points cards be compared to
-- cashback cards. Only needed for cards that earn points.
CREATE TABLE points_valuation (
    card_id         TEXT PRIMARY KEY REFERENCES cards(id) ON DELETE CASCADE,
    points_currency TEXT NOT NULL,
    value_per_point REAL NOT NULL           -- in the card's currency
);

-- Maps a Places API venue type to a canonical category. Part of the schema
-- contract (app infrastructure, not card data).
CREATE TABLE poi_category_map (
    places_type TEXT PRIMARY KEY,
    category    TEXT NOT NULL REFERENCES categories(name)
);

INSERT INTO poi_category_map (places_type, category) VALUES
    ('restaurant', 'dining'),
    ('cafe', 'dining'),
    ('bar', 'dining'),
    ('meal_takeaway', 'dining'),
    ('supermarket', 'grocery'),
    ('grocery_or_supermarket', 'grocery'),
    ('convenience_store', 'grocery'),
    ('gas_station', 'fuel'),
    ('airport', 'travel'),
    ('lodging', 'travel'),
    ('train_station', 'transit'),
    ('subway_station', 'transit'),
    ('movie_theater', 'entertainment'),
    ('beauty_salon', 'beauty'),
    ('hair_care', 'beauty'),
    ('spa', 'beauty'),
    ('pharmacy', 'health'),
    ('drugstore', 'health'),
    ('doctor', 'health'),
    ('hospital', 'health'),
    ('dentist', 'health');

-- Cards the user actually holds (the "wallet").
CREATE TABLE user_cards (
    card_id TEXT PRIMARY KEY REFERENCES cards(id) ON DELETE CASCADE
);

-- Non-rate benefits (e.g. buy-1-get-1 movie tickets). category NULL = applies
-- to any spend.
CREATE TABLE card_offers (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    card_id     TEXT NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    category    TEXT REFERENCES categories(name),
    title       TEXT NOT NULL,
    description TEXT,
    source_ref  TEXT,
    verified    INTEGER NOT NULL DEFAULT 0 CHECK (verified IN (0, 1)),
    UNIQUE (card_id, title)
);

-- Per-payment log. Empty in v1; enables cap enforcement later without migration.
CREATE TABLE spend_log (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    card_id   TEXT NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    category  TEXT NOT NULL REFERENCES categories(name),
    amount    REAL NOT NULL,
    currency  TEXT NOT NULL DEFAULT 'GBP',
    timestamp TEXT NOT NULL               -- ISO 8601
);

-- Client cache-aside for merchant /search results. Keyed by the normalized
-- query; payload is the raw server JSON (category + offers). Wallet-independent
-- so the deck/held-highlights are recomputed from the current wallet each time.
CREATE TABLE search_cache (
    query_key   TEXT PRIMARY KEY,
    payload_json TEXT NOT NULL,
    expires_at  INTEGER NOT NULL          -- epoch millis
);
