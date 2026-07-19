/// Offline merchant -> category guess for an instant best-card pick. Mirrors the
/// definite cases of the Python keyword classifier (ingestion/classify.py); the
/// backend /search refines the category when live offers come back.
library;

const _keywords = <String, String>{
  'salon': 'beauty', 'spa': 'beauty', 'barber': 'beauty', 'beauty': 'beauty',
  'nail': 'beauty', 'hair': 'beauty', 'makeup': 'beauty', 'grooming': 'beauty',
  'clinic': 'health', 'pharmacy': 'health', 'hospital': 'health',
  'dental': 'health', 'dentist': 'health', 'optical': 'health',
  'medical': 'health', 'wellness': 'health', 'physio': 'health',
  'restaurant': 'dining', 'cafe': 'dining', 'coffee': 'dining',
  'grill': 'dining', 'kitchen': 'dining', 'bistro': 'dining', 'diner': 'dining',
  'sushi': 'dining', 'burger': 'dining', 'pizzeria': 'dining',
  'supermarket': 'grocery', 'grocery': 'grocery', 'hypermarket': 'grocery',
  'carrefour': 'grocery', 'lulu': 'grocery', 'spinneys': 'grocery',
  'petrol': 'fuel', 'adnoc': 'fuel', 'enoc': 'fuel', 'fuel': 'fuel',
  'hotel': 'travel', 'resort': 'travel', 'airline': 'travel',
  'airways': 'travel', 'booking': 'travel', 'airbnb': 'travel',
  'metro': 'transit', 'taxi': 'transit', 'careem': 'transit', 'uber': 'transit',
  'parking': 'transit', 'salik': 'transit',
  'cinema': 'entertainment', 'movie': 'entertainment', 'vox': 'entertainment',
  'netflix': 'entertainment', 'cinepolis': 'entertainment',
  'amazon': 'online', 'noon': 'online', 'flipkart': 'online',
  'myntra': 'online', 'aliexpress': 'online',
};

/// Best-guess category for a merchant, or 'general' if unknown.
String categoryForMerchant(String merchant) {
  final text = merchant.toLowerCase();
  // Longest keyword first, so multi-word keys win over substrings.
  final keys = _keywords.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final k in keys) {
    if (text.contains(k)) return _keywords[k]!;
  }
  return 'general';
}
