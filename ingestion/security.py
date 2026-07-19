"""Input hardening for user-supplied search text (merchant / card name).

Defense-in-depth: even though DB access is parameterized and the Flutter UI
renders plain text (no HTML/JS execution), every free-text value that reaches
the web-search + LLM pipeline is validated here — server-side, so a tampered or
non-app client can't bypass it.
"""

from __future__ import annotations

import re
import threading
import time
from collections import defaultdict, deque

MAX_LEN = 80

# Allowlist: letters (any language), digits, spaces, and a few name punctuation.
# Everything else (<, >, {, }, ;, =, ", `, :, |, \, $, [, ]) is rejected — which
# removes the building blocks of script / SQL / template / shell injection.
_ALLOWED = re.compile(r"^[\w \-&.'/(),]+$", re.UNICODE)

# Explicit blocklist for payloads that could slip through as "words".
_BLOCKED = re.compile(
    r"(<\s*script|javascript:|data:|vbscript:|on\w+\s*=|"
    r"union\s+select|drop\s+table|insert\s+into|delete\s+from|update\s+\w+\s+set|"
    r"--|/\*|\{\{|\}\}|\$\{|\$\(|`|\bexec\b|\beval\b)",
    re.IGNORECASE,
)


class InputError(ValueError):
    """Raised when a query is empty, too long, or contains disallowed content."""


def sanitize_query(text: object) -> str:
    """Validate + normalize a user search term. Raises InputError if unsafe."""
    if not isinstance(text, str):
        raise InputError("query must be text")
    # Collapse whitespace (also drops newlines/tabs) and keep only printable chars.
    t = " ".join(text.split())
    t = "".join(ch for ch in t if ch.isprintable())
    if not t:
        raise InputError("query is empty")
    if len(t) > MAX_LEN:
        raise InputError(f"query too long (max {MAX_LEN} chars)")
    if _BLOCKED.search(t):
        raise InputError("query contains a disallowed pattern")
    if not _ALLOWED.match(t):
        raise InputError("query contains invalid characters")
    return t


class RateLimiter:
    """Sliding-window limiter keyed by an arbitrary id (e.g. client IP)."""

    def __init__(self, limit: int, window_seconds: int = 60) -> None:
        self.limit = limit
        self.window = window_seconds
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def allow(self, key: str, now: float | None = None) -> bool:
        now = time.time() if now is None else now
        with self._lock:
            dq = self._hits[key]
            cutoff = now - self.window
            while dq and dq[0] <= cutoff:
                dq.popleft()
            if len(dq) >= self.limit:
                return False
            dq.append(now)
            return True
