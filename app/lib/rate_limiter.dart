/// Client-side sliding-window rate limiter. One shared instance caps a user to
/// 10 lookups per minute across the merchant search + add-card flows (the
/// server enforces its own limit too as the real boundary).
library;

class ClientRateLimiter {
  final int limit;
  final Duration window;
  final List<DateTime> _hits = [];

  ClientRateLimiter({
    this.limit = 10,
    this.window = const Duration(minutes: 1),
  });

  /// Records and allows a call, or returns false if over the limit.
  bool tryAcquire([DateTime? now]) {
    now ??= DateTime.now();
    _hits.removeWhere((t) => now!.difference(t) > window);
    if (_hits.length >= limit) return false;
    _hits.add(now);
    return true;
  }

  /// Clears recorded calls (used by tests).
  void reset() => _hits.clear();

  /// How long until the next call would be allowed.
  Duration retryAfter([DateTime? now]) {
    if (_hits.length < limit) return Duration.zero;
    now ??= DateTime.now();
    final wait = window - now.difference(_hits.first);
    return wait.isNegative ? Duration.zero : wait;
  }
}

/// App-wide limiter shared by every user-initiated lookup.
final queryRateLimiter = ClientRateLimiter(limit: 10);
