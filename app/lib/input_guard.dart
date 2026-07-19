/// Client-side validation for free-text search inputs (merchant + card name).
/// Mirrors the server's `ingestion/security.py` so junk/injection is rejected
/// before it ever leaves the device. Flutter renders plain text (no HTML/JS
/// execution), so this is about blocking abuse + reducing backend load, with
/// the server enforcing the same rules as the real boundary.
library;

class InputGuardException implements Exception {
  final String message;
  InputGuardException(this.message);
  @override
  String toString() => message;
}

const _maxLen = 80;

// Building blocks of script / SQL / template / shell injection.
final _blocked = RegExp(
  r"(<\s*script|javascript:|data:|vbscript:|on\w+\s*=|"
  r"union\s+select|drop\s+table|insert\s+into|delete\s+from|update\s+\w+\s+set|"
  r"--|/\*|\{\{|\}\}|\$\{|\$\(|`|\bexec\b|\beval\b)",
  caseSensitive: false,
);

// Allowlist: any-language letters/digits, spaces, and basic name punctuation.
final _allowed = RegExp(r"^[\p{L}\p{N} \-&.'/(),]+$", unicode: true);

/// Returns a normalized safe query, or throws [InputGuardException].
String sanitizeQuery(String raw) {
  final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) {
    throw InputGuardException('Type a name to search.');
  }
  if (t.length > _maxLen) {
    throw InputGuardException('Too long — keep it under $_maxLen characters.');
  }
  if (_blocked.hasMatch(t)) {
    throw InputGuardException('That looks unsafe. Enter a plain name.');
  }
  if (!_allowed.hasMatch(t)) {
    throw InputGuardException(
        'Use letters, numbers, and basic punctuation only.');
  }
  return t;
}
