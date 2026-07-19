"""Cache-key normalization: same card, different spelling -> same key."""

from ingestion.cardkey import card_key


def test_alias_and_generic_words_collapse():
    a = card_key("ENBD Duo", "UAE")
    b = card_key("Emirates NBD Duo Credit Card", "uae")
    assert a == b


def test_distinct_tiers_stay_distinct():
    assert card_key("Emirates NBD Platinum", "UAE") != \
        card_key("Emirates NBD Titanium", "UAE")


def test_country_is_part_of_key():
    assert card_key("Wio Credit", "UAE") != card_key("Wio Credit", "India")


def test_order_and_case_insensitive():
    assert card_key("Duo emirates NBD", "AE") == card_key("EMIRATES nbd duo", "ae")


def test_more_aliases():
    assert card_key("ADCB Lulu Card", "UAE") == \
        card_key("Abu Dhabi Commercial Bank Lulu", "UAE")
