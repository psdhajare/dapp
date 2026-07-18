-- Hand-seeded fixture data: 2 cards, rules, valuation, POI map.
-- Used by tests and as a starter DB before real ingestion runs.

INSERT INTO cards (id, name, issuer, network, currency, annual_fee) VALUES
    ('amex_gold', 'Amex Gold', 'American Express', 'amex', 'GBP', 195),
    ('barclays_cb', 'Barclays Cashback', 'Barclays', 'visa', 'GBP', 0);

-- Amex Gold: points card. 4 pts/£ dining, 2 pts/£ grocery (capped), 1 pt/£ else.
INSERT INTO reward_rules
    (card_id, category, rate, unit, cap_amount, cap_period, source_ref, verified) VALUES
    ('amex_gold', 'dining',  4, 'points_per_unit', NULL, 'none',    'seed', 1),
    ('amex_gold', 'grocery', 2, 'points_per_unit', 500, 'monthly', 'seed', 1),
    ('amex_gold', 'general', 1, 'points_per_unit', NULL, 'none',    'seed', 1);

-- Barclays: flat cashback. 1% grocery, 0.5% general, 5% online but only with
-- a 3000/month spend (exercises min-spend hints).
INSERT INTO reward_rules
    (card_id, category, rate, unit, cap_amount, cap_period, min_spend, source_ref, verified) VALUES
    ('barclays_cb', 'grocery', 1.0, 'cashback_pct', NULL, 'none', NULL, 'seed', 1),
    ('barclays_cb', 'general', 0.5, 'cashback_pct', NULL, 'none', NULL, 'seed', 1),
    ('barclays_cb', 'online', 5.0, 'cashback_pct', NULL, 'none', 3000, 'seed', 1);

INSERT INTO card_offers (card_id, category, title, description, source_ref, verified) VALUES
    ('barclays_cb', 'entertainment', 'Buy 1 Get 1 movie tickets', 'Weekend shows', 'seed', 1);

-- Amex points worth 0.9p each (0.009 GBP).
INSERT INTO points_valuation (card_id, points_currency, value_per_point) VALUES
    ('amex_gold', 'Membership Rewards', 0.009);

INSERT INTO user_cards (card_id) VALUES ('amex_gold'), ('barclays_cb');
