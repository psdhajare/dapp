import 'package:bestcard/util/offer_dedupe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<String> dedupe(List<String> xs) => dedupeByText(xs, (s) => s);

  test('drops subset merchant-name variants', () {
    // "Royal Cinemas" ⊆ "Cine Royal Cinemas" -> one kept (the first seen).
    expect(dedupe(['Cine Royal Cinemas', 'Royal Cinemas']),
        ['Cine Royal Cinemas']);
  });

  test('drops heavily overlapping phrasings', () {
    expect(
      dedupe(['Buy 1 Get 1 at Vox Cinemas', 'Buy 1 Get 1 Vox Cinemas deal']),
      ['Buy 1 Get 1 at Vox Cinemas'],
    );
  });

  test('keeps genuinely different offers', () {
    final out = dedupe(['20% off dining at Zuma', 'Free valet parking at Dubai Mall']);
    expect(out.length, 2);
  });

  test('keeps offers with no shared words', () {
    expect(dedupe(['Airport lounge access', 'Cashback on fuel']).length, 2);
  });

  test('preserves order and first occurrence', () {
    expect(dedupe(['Royal Cinemas', 'Cine Royal Cinemas', 'Vox Cinemas']),
        ['Royal Cinemas', 'Vox Cinemas']);
  });
}
