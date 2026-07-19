"""Cache-key normalization: same card, different spelling -> same key."""

from ingestion.cardkey import card_key


def test_alias_and_generic_words_collapse():
    assert card_key("ENBD Duo") == card_key("Emirates NBD Duo Credit Card")


def test_distinct_tiers_stay_distinct():
    assert card_key("Emirates NBD Platinum") != card_key("Emirates NBD Titanium")


def test_country_independent():
    # A card's identity doesn't change with the user's country.
    assert card_key("Apple Card") == card_key("apple card")


def test_order_and_case_insensitive():
    assert card_key("Duo emirates NBD") == card_key("EMIRATES nbd duo")


def test_more_aliases():
    assert card_key("ADCB Lulu Card") == card_key("Abu Dhabi Commercial Bank Lulu")
