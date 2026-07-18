import 'package:engine/engine.dart';
import 'package:test/test.dart';

// Fixtures mirroring db/seed.sql.
final amex = CardRules(
  cardId: 'amex_gold',
  valuePerPoint: 0.009,
  rulesByCategory: {
    'dining': const Rule(category: 'dining', rate: 4, unit: 'points_per_unit'),
    'grocery': const Rule(
        category: 'grocery',
        rate: 2,
        unit: 'points_per_unit',
        capAmount: 500,
        capPeriod: 'monthly'),
    'general': const Rule(category: 'general', rate: 1, unit: 'points_per_unit'),
  },
);

final barclays = CardRules(
  cardId: 'barclays_cb',
  rulesByCategory: {
    'grocery': const Rule(category: 'grocery', rate: 1.0, unit: 'cashback_pct'),
    'general': const Rule(category: 'general', rate: 0.5, unit: 'cashback_pct'),
  },
);

void main() {
  group('effectiveRate', () {
    test('cashback percent', () {
      expect(
        effectiveRate(const Rule(category: 'x', rate: 1.5, unit: 'cashback_pct'), null),
        closeTo(0.015, 1e-9),
      );
    });

    test('points times valuation', () {
      expect(
        effectiveRate(
            const Rule(category: 'x', rate: 4, unit: 'points_per_unit'), 0.009),
        closeTo(0.036, 1e-9),
      );
    });

    test('points rule without valuation throws', () {
      expect(
        () => effectiveRate(
            const Rule(category: 'x', rate: 1, unit: 'points_per_unit'), null),
        throwsArgumentError,
      );
    });
  });

  group('selectBestCard', () {
    test('dining: amex 4pts*0.9p = 3.6% beats barclays general 0.5%', () {
      final r = selectBestCard('dining', [amex, barclays])!;
      expect(r.cardId, 'amex_gold');
      expect(r.categoryUsed, 'dining');
      expect(r.effectiveRate, closeTo(0.036, 1e-9));
    });

    test('grocery: amex 2pts*0.9p=1.8% beats barclays 1% cashback', () {
      final r = selectBestCard('grocery', [amex, barclays])!;
      expect(r.cardId, 'amex_gold');
      expect(r.effectiveRate, closeTo(0.018, 1e-9));
    });

    test('unknown category falls back to general (barclays 0.5% > amex 0.9%*1=0.9%)', () {
      final r = selectBestCard('entertainment', [amex, barclays])!;
      expect(r.categoryUsed, 'general');
      expect(r.cardId, 'amex_gold'); // 1pt*0.9p = 0.9% > 0.5%
      expect(r.effectiveRate, closeTo(0.009, 1e-9));
    });

    test('flags cap when best rule is capped', () {
      final r = selectBestCard('grocery', [amex, barclays])!;
      expect(r.hasCap, isTrue);
      expect(r.capAmount, 500);
      expect(r.capPeriod, 'monthly');
    });

    test('no cap flag on uncapped best rule', () {
      final r = selectBestCard('dining', [amex, barclays])!;
      expect(r.hasCap, isFalse);
    });

    test('skips points rules when card has no valuation', () {
      final noVal = CardRules(
        cardId: 'points_no_val',
        rulesByCategory: {
          'dining': const Rule(
              category: 'dining', rate: 100, unit: 'points_per_unit'),
        },
      );
      // Would win on rate if valued, but must be skipped -> barclays general wins.
      final r = selectBestCard('dining', [noVal, barclays])!;
      expect(r.cardId, 'barclays_cb');
    });

    test('returns null when no card matches and no general', () {
      final sparse = CardRules(
        cardId: 'x',
        rulesByCategory: {
          'fuel': const Rule(category: 'fuel', rate: 1, unit: 'cashback_pct'),
        },
      );
      expect(selectBestCard('dining', [sparse]), isNull);
    });
  });

  group('min-spend rules', () {
    // Mirrors ENBD Duo: 5% grocery but only with AED 5000/month spend.
    final duo = CardRules(
      cardId: 'duo',
      rulesByCategory: {
        'grocery': const Rule(
            category: 'grocery',
            rate: 5,
            unit: 'cashback_pct',
            capAmount: 500,
            capPeriod: 'monthly',
            minSpend: 5000),
        'general': const Rule(category: 'general', rate: 0.5, unit: 'cashback_pct'),
      },
    );
    final mashreq = CardRules(
      cardId: 'mashreq',
      rulesByCategory: {
        'general': const Rule(category: 'general', rate: 1, unit: 'cashback_pct'),
      },
    );

    test('rule with min spend is assumed unmet and excluded from pick', () {
      final r = selectBestCard('grocery', [duo, mashreq])!;
      expect(r.cardId, 'mashreq'); // duo grocery 5% skipped, duo general 0.5 < 1
      expect(r.effectiveRate, closeTo(0.01, 1e-9));
    });

    test('excluded min-spend rule that beats winner becomes a hint', () {
      final r = selectBestCard('grocery', [duo, mashreq])!;
      expect(r.hints, hasLength(1));
      expect(r.hints.first.cardId, 'duo');
      expect(r.hints.first.effectiveRate, closeTo(0.05, 1e-9));
      expect(r.hints.first.minSpend, 5000);
    });

    test('min-spend rule worse than winner produces no hint', () {
      final weak = CardRules(
        cardId: 'weak',
        rulesByCategory: {
          'grocery': const Rule(
              category: 'grocery', rate: 0.2, unit: 'cashback_pct', minSpend: 9999),
        },
      );
      final r = selectBestCard('grocery', [weak, mashreq])!;
      expect(r.hints, isEmpty);
    });
  });

  group('rankCards', () {
    test('returns all scorable cards sorted by effective rate', () {
      final ranked = rankCards('grocery', [amex, barclays]);
      expect(ranked.map((r) => r.cardId).toList(),
          ['amex_gold', 'barclays_cb']);
      expect(ranked[0].effectiveRate, closeTo(0.018, 1e-9));
      expect(ranked[1].effectiveRate, closeTo(0.01, 1e-9));
    });

    test('selectBestCard equals first of rankCards', () {
      final best = selectBestCard('dining', [amex, barclays])!;
      final ranked = rankCards('dining', [amex, barclays]);
      expect(best.cardId, ranked.first.cardId);
      expect(best.effectiveRate, ranked.first.effectiveRate);
    });

    test('unscorable cards are left out', () {
      final noVal = CardRules(
        cardId: 'points_no_val',
        rulesByCategory: {
          'dining':
              const Rule(category: 'dining', rate: 9, unit: 'points_per_unit'),
        },
      );
      final ranked = rankCards('dining', [noVal, barclays]);
      expect(ranked.map((r) => r.cardId), ['barclays_cb']);
    });
  });

  group('cap enforcement (v1.5)', () {
    test('over cap drops amex grocery to general, barclays 1% now wins', () {
      final r = selectBestCard('grocery', [amex, barclays],
          spentByCard: {'amex_gold': 600})!;
      expect(r.cardId, 'barclays_cb');
      expect(r.effectiveRate, closeTo(0.01, 1e-9));
    });

    test('under cap keeps amex grocery', () {
      final r = selectBestCard('grocery', [amex, barclays],
          spentByCard: {'amex_gold': 100})!;
      expect(r.cardId, 'amex_gold');
    });
  });
}
