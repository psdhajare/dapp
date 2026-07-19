/// Drop near-duplicate offers. The same deal often appears twice phrased
/// differently — e.g. "Cine Royal Cinemas" and "Royal Cinemas" — so we compare
/// word sets rather than exact strings. Two offers are duplicates when one's
/// words are a subset of the other's, or their word sets overlap heavily.
List<T> dedupeByText<T>(
  Iterable<T> items,
  String Function(T) text, {
  double threshold = 0.6,
}) {
  final kept = <T>[];
  final keptTokens = <Set<String>>[];
  for (final item in items) {
    final tokens = _tokens(text(item));
    final isDup = tokens.isNotEmpty &&
        keptTokens.any((k) => _similar(tokens, k, threshold));
    if (!isDup) {
      kept.add(item);
      keptTokens.add(tokens);
    }
  }
  return kept;
}

bool _similar(Set<String> a, Set<String> b, double threshold) {
  if (a.isEmpty || b.isEmpty) return false;
  final inter = a.intersection(b).length;
  if (inter == a.length || inter == b.length) return true; // one ⊆ other
  return inter / a.union(b).length >= threshold;
}

Set<String> _tokens(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .split(RegExp(r'\s+'))
    .where((w) => w.length >= 2)
    .toSet();
