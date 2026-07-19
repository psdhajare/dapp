/// Display-name helpers. Bank legal names ("JPMORGAN CHASE BANK, N.A.") never
/// render on a card face — we show a clean issuer name instead (v1.1 spec).
library;

// Match on a lowercased substring -> canonical display name. First hit wins,
// so order the most specific keys first.
const _issuerAliases = <String, String>{
  'jpmorgan': 'Chase',
  'chase': 'Chase',
  'goldman': 'Goldman Sachs',
  'american express': 'American Express',
  'amex': 'American Express',
  'emirates nbd': 'Emirates NBD',
  'mashreq': 'Mashreq',
  'wio': 'Wio',
  'hdfc': 'HDFC Bank',
  'icici': 'ICICI Bank',
  'citibank': 'Citi',
  'citi': 'Citi',
  'barclays': 'Barclays',
  'hsbc': 'HSBC',
};

// Corporate suffixes to strip when falling back to title-casing.
final _suffix = RegExp(
  r',?\s*\b(n\.?a\.?|pjsc|p\.?j\.?s\.?c\.?|ltd|limited|inc|incorporated|'
  r'plc|bank|corporation|corp|co)\b\.?',
  caseSensitive: false,
);

/// Clean, brand-appropriate issuer name for display on cards/strips.
String displayIssuer(String raw) {
  final lower = raw.toLowerCase();
  for (final entry in _issuerAliases.entries) {
    if (lower.contains(entry.key)) return entry.value;
  }
  // Fallback: drop corporate suffixes, collapse whitespace, title-case.
  final cleaned = raw.replaceAll(_suffix, '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.isEmpty) return raw.trim();
  return cleaned
      .split(' ')
      .map((w) => w.isEmpty
          ? w
          : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
}
