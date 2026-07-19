import 'package:bestcard/dao.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  test('search cache: store, hit within TTL, expire after', () async {
    final dao = CardDao(await openSeedDb());
    final t = DateTime(2026, 7, 19, 12);
    final payload = {
      'category': 'beauty',
      'offers': [
        {'title': '20% off', 'card_hint': 'Emirates NBD'}
      ],
    };
    await dao.cacheSearch('glossy salon', payload,
        ttl: const Duration(hours: 24), now: t);

    // Hit within TTL.
    final hit = await dao.cachedSearch('glossy salon',
        now: t.add(const Duration(hours: 1)));
    expect(hit, isNotNull);
    expect(hit!['category'], 'beauty');
    expect((hit['offers'] as List).first['title'], '20% off');

    // Miss after TTL (and pruned).
    final miss = await dao.cachedSearch('glossy salon',
        now: t.add(const Duration(hours: 25)));
    expect(miss, isNull);
  });

  test('loadUserCards builds engine inputs from seed DB', () async {
    final dao = CardDao(await openSeedDb());
    final cards = await dao.loadUserCards();

    expect(cards.map((c) => c.cardId).toSet(), {'amex_gold', 'barclays_cb'});

    final amex = cards.firstWhere((c) => c.cardId == 'amex_gold');
    expect(amex.valuePerPoint, 0.009);
    expect(amex.rulesByCategory['dining']!.rate, 4);
    expect(amex.rulesByCategory['grocery']!.capAmount, 500);

    final barclays = cards.firstWhere((c) => c.cardId == 'barclays_cb');
    expect(barclays.valuePerPoint, isNull);
    expect(barclays.rulesByCategory['grocery']!.unit, 'cashback_pct');
  });

  test('loadPoiMap maps places types to categories', () async {
    final dao = CardDao(await openSeedDb());
    final map = await dao.loadPoiMap();
    expect(map['restaurant'], 'dining');
    expect(map['supermarket'], 'grocery');
  });

  test('cardName returns human name', () async {
    final dao = CardDao(await openSeedDb());
    expect(await dao.cardName('amex_gold'), 'Amex Gold');
  });

  test('cardLabel combines issuer and name', () async {
    final dao = CardDao(await openSeedDb());
    expect(await dao.cardLabel('amex_gold'), 'American Express · Amex Gold');
  });

  test('allCards and setHeld manage the wallet', () async {
    final dao = CardDao(await openSeedDb());
    var cards = await dao.allCards();
    expect(cards.where((c) => c.held).length, 2);

    await dao.setHeld('amex_gold', false);
    cards = await dao.allCards();
    expect(cards.firstWhere((c) => c.id == 'amex_gold').held, isFalse);

    await dao.setHeld('amex_gold', true);
    cards = await dao.allCards();
    expect(cards.firstWhere((c) => c.id == 'amex_gold').held, isTrue);
  });

  test('insertExtraction stores card, rules, offers and holds it', () async {
    final dao = CardDao(await openSeedDb());
    await dao.insertExtraction({
      'card': {
        'id': 'enbd_titanium',
        'name': 'Titanium',
        'issuer': 'Emirates NBD',
        'network': 'visa',
        'currency': 'AED',
        'annual_fee': 0,
      },
      'rules': [
        {'category': 'dining', 'rate': 3.0, 'unit': 'cashback_pct',
         'cap_amount': null, 'cap_period': 'none', 'min_spend': null,
         'conditions': null, 'source_ref': 'test', 'verified': false},
      ],
      'valuation': null,
      'offers': [
        {'category': 'entertainment', 'title': 'BOGO tickets',
         'description': null, 'source_ref': 'test', 'verified': false},
      ],
      'warnings': [],
    });

    final cards = await dao.allCards();
    final added = cards.firstWhere((c) => c.id == 'enbd_titanium');
    expect(added.held, isTrue);
    expect(await dao.cardLabel('enbd_titanium'), 'Emirates NBD · Titanium');

    final userCards = await dao.loadUserCards();
    final rules = userCards
        .firstWhere((c) => c.cardId == 'enbd_titanium')
        .rulesByCategory;
    expect(rules['dining']!.rate, 3.0);

    final offers = await dao.offersForCategory('entertainment');
    expect(offers.map((o) => o.title), contains('BOGO tickets'));
  });

  test('offersForCategory returns wallet offers for category', () async {
    final dao = CardDao(await openSeedDb());
    final offers = await dao.offersForCategory('entertainment');
    expect(offers, hasLength(1));
    expect(offers.first.title, 'Buy 1 Get 1 movie tickets');
    expect(offers.first.cardLabel, 'Barclays · Barclays Cashback');

    // Card out of wallet -> its offers disappear.
    await dao.setHeld('barclays_cb', false);
    expect(await dao.offersForCategory('entertainment'), isEmpty);
  });
}
