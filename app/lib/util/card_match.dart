/// Decides whether a merchant offer's `card_hint` refers to a card the user
/// actually holds. Accuracy is fundamental: a false positive (claiming an offer
/// is for your card when it isn't) makes the app untrustworthy. So matching is
/// deliberately CONSERVATIVE — it compares distinctive brand tokens (bank/card
/// identity) and ignores generic banking words, preferring a miss over a wrong
/// "in your wallet".
library;

/// Generic words that don't identify a specific bank/card. "Bank of America"
/// and "Emirates NBD" share none of their *distinctive* tokens once these are
/// removed, so one never masquerades as the other.
const _stopwords = {
  'the', 'of', 'and', 'for', 'with', 'your', 'a', 'an', 'to', 'at', 'in', 'on',
  'bank', 'banks', 'credit', 'card', 'cards', 'debit', 'account', 'accounts',
  'visa', 'mastercard', 'amex',
  'world', 'elite', 'platinum', 'gold', 'titanium', 'signature', 'infinite',
  'classic', 'standard', 'premium', 'plus', 'prime', 'select', 'privilege',
  'rewards', 'reward', 'cashback', 'points', 'miles',
  'offer', 'offers', 'deal', 'deals', 'discount', 'promotion',
};

/// Distinctive, brand-identifying tokens of a string (lowercased, ≥3 chars,
/// not generic). e.g. "Emirates NBD Duo" -> {emirates, nbd, duo}.
Set<String> distinctiveTokens(String s) => s
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((w) => w.length >= 3 && !_stopwords.contains(w))
    .toSet();

/// True if [hint] identifies the card described by [cardText] ("Issuer Name").
/// Requires at least one shared distinctive token — so "Bank of America" never
/// matches "Emirates NBD", but "Emirates NBD" matches "Emirates NBD Duo".
bool offerHintMatchesCardText(String hint, String cardText) {
  final h = distinctiveTokens(hint);
  if (h.isEmpty) return false;
  return h.intersection(distinctiveTokens(cardText)).isNotEmpty;
}

/// True if [hint] matches any of the user's held cards.
bool offerHintMatchesAny(String hint, Iterable<String> cardTexts) =>
    cardTexts.any((c) => offerHintMatchesCardText(hint, c));
