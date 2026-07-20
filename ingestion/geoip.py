"""Local IP -> country using MaxMind GeoLite2, so the server infers the user's
country with zero client involvement.

The database is NOT in the repo (MaxMind licence). Provide it on the server and
point GEOIP_DB at it (default /opt/geoip/GeoLite2-Country.mmdb); refresh monthly
with geoipupdate. If the lib or DB is missing, lookups return "" (the caller
just falls back to a location-agnostic search) — never an error.

Memory note: the reader is opened once and memory-mapped (a few MB), reused
across all requests. Never opened per-request.
"""

from __future__ import annotations

import os
import threading

try:  # optional dependency; absent in unit tests / dev
    import geoip2.database  # type: ignore
except ImportError:  # pragma: no cover
    geoip2 = None  # type: ignore

_DB_PATH = os.environ.get("GEOIP_DB", "/opt/geoip/GeoLite2-Country.mmdb")
_reader = None
_lock = threading.Lock()


def _get_reader():
    """Open the mmdb once (mmap), thread-safe. None if unavailable."""
    global _reader
    if _reader is not None:
        return _reader
    if geoip2 is None or not os.path.exists(_DB_PATH):
        return None
    with _lock:
        if _reader is None:
            try:
                _reader = geoip2.database.Reader(_DB_PATH)
            except Exception:  # corrupt/unreadable db -> degrade gracefully
                return None
    return _reader


def country_for_ip(ip: str) -> str:
    """ISO alpha-2 country for [ip] (e.g. 'AE'), or '' if unknown/unavailable."""
    if not ip:
        return ""
    reader = _get_reader()
    if reader is None:
        return ""
    try:
        return reader.country(ip).country.iso_code or ""
    except Exception:  # private/invalid IP, not found, etc.
        return ""
