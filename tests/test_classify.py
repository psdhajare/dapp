"""Merchant -> category classification: keyword-first, LLM fallback."""

from ingestion.classify import classify, classify_by_keyword
from tests.test_extract import FakeLLM


def test_keyword_hits_need_no_llm():
    assert classify_by_keyword('Glossy Hair Salon') == 'beauty'
    assert classify_by_keyword('City Dental Clinic') == 'health'
    assert classify_by_keyword('Sushi House restaurant') == 'dining'
    assert classify_by_keyword('ADNOC petrol') == 'fuel'
    assert classify_by_keyword('VOX Cinema') == 'entertainment'


def test_unknown_keyword_returns_none():
    assert classify_by_keyword('Zzxq Widgets Ltd') is None


def test_classify_uses_keyword_without_client():
    # No client passed, but keyword resolves -> no LLM needed.
    assert classify('Downtown Barber Shop') == 'beauty'


def test_classify_falls_back_to_general_when_unknown_and_no_client():
    assert classify('Zzxq Widgets Ltd') == 'general'


def test_classify_uses_llm_for_unknown():
    llm = FakeLLM('{"category": "health"}')
    assert classify('Zzxq Collective XYZ', llm) == 'health'
    assert llm.calls  # LLM was consulted (no keyword hit)


def test_classify_llm_bad_category_defaults_general():
    assert classify('Zzxq Unknownplace', FakeLLM('{"category": "casino"}')) == 'general'
