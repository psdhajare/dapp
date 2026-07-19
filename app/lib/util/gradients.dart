import 'dart:math';

/// Preset card-face gradients the user picks from when adding a card.
/// Beats guessing colors from the web: always looks right, zero latency.
/// `(name, primaryHex, secondaryHex)` — primary top-left, secondary bottom-right.
class CardGradient {
  final String name;
  final String primary;
  final String secondary;
  const CardGradient(this.name, this.primary, this.secondary);
}

const presetGradients = <CardGradient>[
  CardGradient('Graphite', '#2B2B33', '#131318'),
  CardGradient('Midnight', '#1D3A5F', '#0C1E33'),
  CardGradient('Ocean', '#1E6F8E', '#0C3B4E'),
  CardGradient('Emerald', '#1F6146', '#0C3327'),
  CardGradient('Teal', '#17544D', '#0A2E2A'),
  CardGradient('Amber', '#E08A2E', '#B5661A'),
  CardGradient('Wine', '#5A2438', '#331320'),
  CardGradient('Royal', '#3D2A63', '#20153A'),
  CardGradient('Silver', '#E9E6DE', '#C6C0B3'),
];

/// A random preset — the default assigned before the user picks one.
CardGradient randomGradient([Random? rng]) {
  final r = rng ?? Random();
  return presetGradients[r.nextInt(presetGradients.length)];
}

/// `count` gradients starting with `first`, the rest distinct presets so a
/// multi-card product's cards don't all look the same.
List<CardGradient> distinctGradients(CardGradient first, int count) {
  final out = [first];
  for (final g in presetGradients) {
    if (out.length >= count) break;
    if (g.name != first.name) out.add(g);
  }
  return out.take(count).toList();
}
