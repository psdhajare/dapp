"""Server-side IP -> country (GeoLite2), with graceful degradation."""

from ingestion import geoip


class _FakeCountry:
    def __init__(self, code):
        self.country = type("C", (), {"iso_code": code})()


class _FakeReader:
    def country(self, ip):
        if ip == "5.6.7.8":
            return _FakeCountry("AE")
        raise ValueError("address not in database")


def test_maps_known_ip(monkeypatch):
    monkeypatch.setattr(geoip, "_reader", _FakeReader())
    assert geoip.country_for_ip("5.6.7.8") == "AE"


def test_unknown_ip_returns_empty(monkeypatch):
    monkeypatch.setattr(geoip, "_reader", _FakeReader())
    assert geoip.country_for_ip("9.9.9.9") == ""  # lookup raises -> ""


def test_empty_ip_returns_empty():
    assert geoip.country_for_ip("") == ""


def test_no_db_or_lib_returns_empty(monkeypatch):
    # No cached reader, lib unavailable, db path missing -> "" (never raises).
    monkeypatch.setattr(geoip, "_reader", None)
    monkeypatch.setattr(geoip, "geoip2", None)
    monkeypatch.setattr(geoip, "_DB_PATH", "/nonexistent/GeoLite2-Country.mmdb")
    assert geoip.country_for_ip("5.6.7.8") == ""
