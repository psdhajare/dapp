/// Recommendation engine: given a spend category and the user's cards, pick the
/// card with the highest effective reward. Pure logic — no I/O, no LLM.
library;

/// A single reward rule for a card in one category.
class Rule {
  final String category;
  final double rate;

  /// 'cashback_pct' or 'points_per_unit'.
  final String unit;
  final double? capAmount;

  /// 'none' | 'monthly' | 'quarterly' | 'yearly'.
  final String capPeriod;

  /// Monthly spend required for this rate to apply. The engine assumes the
  /// user has NOT met it: the rule is excluded from selection and surfaced as
  /// a hint instead.
  final double? minSpend;

  const Rule({
    required this.category,
    required this.rate,
    required this.unit,
    this.capAmount,
    this.capPeriod = 'none',
    this.minSpend,
  });

  bool get hasCap => capAmount != null && capPeriod != 'none';
}

/// A card the user holds: its rules keyed by category, plus points valuation.
class CardRules {
  final String cardId;
  final Map<String, Rule> rulesByCategory;

  /// Value of one point in the card's currency (e.g. GBP). Null for cashback-only.
  final double? valuePerPoint;

  const CardRules({
    required this.cardId,
    required this.rulesByCategory,
    this.valuePerPoint,
  });
}

/// A better rate the user could unlock by meeting a rule's minimum spend.
class MinSpendHint {
  final String cardId;
  final double effectiveRate;
  final double minSpend;

  const MinSpendHint({
    required this.cardId,
    required this.effectiveRate,
    required this.minSpend,
  });
}

/// The engine's answer.
class Recommendation {
  final String cardId;

  /// Category whose rule was applied (may be 'general' fallback).
  final String categoryUsed;

  /// Effective reward in currency per 1 unit spent (e.g. 0.04 = 4% back).
  final double effectiveRate;

  final bool hasCap;
  final double? capAmount;
  final String capPeriod;

  /// Min-spend rules that would beat this pick if their threshold were met.
  final List<MinSpendHint> hints;

  const Recommendation({
    required this.cardId,
    required this.categoryUsed,
    required this.effectiveRate,
    required this.hasCap,
    this.capAmount,
    this.capPeriod = 'none',
    this.hints = const [],
  });
}

/// Effective currency return per unit spent for a rule.
double effectiveRate(Rule rule, double? valuePerPoint) {
  switch (rule.unit) {
    case 'cashback_pct':
      return rule.rate / 100.0;
    case 'points_per_unit':
      if (valuePerPoint == null) {
        throw ArgumentError('points_per_unit rule needs valuePerPoint');
      }
      return rule.rate * valuePerPoint;
    default:
      throw ArgumentError('unknown unit: ${rule.unit}');
  }
}

/// Resolve the rule a card applies for [category], falling back to 'general'.
Rule? _ruleFor(CardRules card, String category) =>
    card.rulesByCategory[category] ?? card.rulesByCategory['general'];

/// Pick the best card for [category] among [cards].
///
/// v1: uses headline rates and flags any cap. v1.5: pass [spentByCard]
/// (cardId -> amount already spent this cap period in this category) to enforce
/// caps — once spend reaches the cap, that card falls back to its 'general' rate.
///
/// Returns null if no card has any applicable rule.
/// Rank every scorable card for [category], best first. Only the winner
/// carries min-spend hints.
List<Recommendation> rankCards(
  String category,
  List<CardRules> cards, {
  Map<String, double>? spentByCard,
}) {
  final candidates = <Recommendation>[];
  final lockedRules = <(String cardId, Rule rule, double value)>[];

  for (final card in cards) {
    var rule = _ruleFor(card, category);
    if (rule == null) continue;

    // Points rule without a known point value can't be compared — skip it.
    if (rule.unit == 'points_per_unit' && card.valuePerPoint == null) continue;

    // A min-spend rule is assumed unmet: it can't win, but record it so it can
    // become a hint. The card falls back to its general rule for the pick.
    if (rule.minSpend != null) {
      lockedRules.add(
          (card.cardId, rule, effectiveRate(rule, card.valuePerPoint)));
      final fallback = card.rulesByCategory['general'];
      if (fallback == null || fallback.minSpend != null) continue;
      rule = fallback;
      if (rule.unit == 'points_per_unit' && card.valuePerPoint == null) continue;
    }

    // v1.5 enforcement: if capped and spend has reached the cap, drop to general.
    if (spentByCard != null &&
        rule.hasCap &&
        (spentByCard[card.cardId] ?? 0) >= rule.capAmount!) {
      final fallback = card.rulesByCategory['general'];
      if (fallback == null) continue;
      rule = fallback;
    }

    candidates.add(Recommendation(
      cardId: card.cardId,
      categoryUsed: rule.category,
      effectiveRate: effectiveRate(rule, card.valuePerPoint),
      hasCap: rule.hasCap,
      capAmount: rule.capAmount,
      capPeriod: rule.capPeriod,
    ));
  }

  candidates.sort((a, b) => b.effectiveRate.compareTo(a.effectiveRate));
  if (candidates.isEmpty) return candidates;

  final best = candidates.first;
  final hints = [
    for (final (cardId, rule, value) in lockedRules)
      if (value > best.effectiveRate)
        MinSpendHint(
            cardId: cardId, effectiveRate: value, minSpend: rule.minSpend!),
  ]..sort((a, b) => b.effectiveRate.compareTo(a.effectiveRate));

  candidates[0] = Recommendation(
    cardId: best.cardId,
    categoryUsed: best.categoryUsed,
    effectiveRate: best.effectiveRate,
    hasCap: best.hasCap,
    capAmount: best.capAmount,
    capPeriod: best.capPeriod,
    hints: hints,
  );
  return candidates;
}

/// Pick the best card for [category] among [cards] — first of [rankCards].
Recommendation? selectBestCard(
  String category,
  List<CardRules> cards, {
  Map<String, double>? spentByCard,
}) {
  final ranked = rankCards(category, cards, spentByCard: spentByCard);
  return ranked.isEmpty ? null : ranked.first;
}
