// Captures real-device screenshots of the key screens for the welcome tour.
// Run on a booted simulator:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/tour_shots_test.dart -d <simulator-id>
// PNGs land in screenshots/{deck,wallet,addcard,color,search,share}.png.
import 'package:bestcard/analytics.dart';
import 'package:bestcard/app_db.dart';
import 'package:bestcard/dao.dart';
import 'package:bestcard/db_factory.dart';
import 'package:bestcard/ingest_service.dart';
import 'package:bestcard/main.dart';
import 'package:bestcard/profile_store.dart';
import 'package:bestcard/theme/concierge_theme.dart';
import 'package:bestcard/venue.dart';
import 'package:bestcard/widgets/share_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoVenue implements VenueLookup {
  @override
  Future<List<String>> nearbyTypes(double lat, double lng) async => const [];
}

const _searchJson = '''
{"merchant":"Glossy Hair Salon","category":"beauty","cached":false,
 "offers":[{"title":"20% off hair services","description":"Weekends",
   "card_hint":"American Express","valid_until":"31 Dec 2026"}]}''';

// A valid card so the add-card flow shows the preview + colour picker.
const _ingestJson = '''
{"card":{"id":"amex_platinum","name":"Platinum","issuer":"American Express",
  "network":"amex","currency":"AED","annual_fee":0},
 "rules":[{"category":"travel","rate":5.0,"unit":"cashback_pct","cap_amount":null,
   "cap_period":"none","min_spend":null,"conditions":null,"source_ref":"t",
   "verified":false}],
 "valuation":null,"offers":[],"warnings":[]}''';

Future<BestCardApp> _seededApp() async {
  SharedPreferences.setMockInitialValues({'tour_seen': true});
  final factory = resolveDbFactory();
  await factory.deleteDatabase('bestcard.db');
  final dao = CardDao(await openAppDb(factory, seed: true));
  final poiMap = await dao.loadPoiMap();
  final ingest = IngestService(
    endpoint: Uri.parse('http://local/ingest'),
    client: MockClient((req) async => http.Response(
        req.url.path == '/search' ? _searchJson : _ingestJson, 200,
        headers: {'content-type': 'application/json'})),
  );
  return BestCardApp(
    dao: dao,
    venue: VenueCategoryService(lookup: _NoVenue(), poiMap: poiMap),
    locationFn: () async => (51.5, -0.12),
    ingest: ingest,
    profile: await ProfileStore.load(),
    analytics: await Analytics.load(),
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture app screens', (tester) async {
    await tester.pumpWidget(await _seededApp());
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();

    // 1. Recommendation deck — dining.
    await tester.tap(find.byKey(const Key('sim_dining')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await binding.takeScreenshot('deck');

    // 2. Wallet.
    await tester.tap(find.byKey(const Key('wallet_button')));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('wallet');

    // 3. Add-card sheet — the "type a name" step.
    await tester.tap(find.byKey(const Key('add_card_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('new_card_field')), 'Amex Platinum');
    await tester.pumpAndSettle();
    await binding.takeScreenshot('addcard');

    // 4. Colour picker — after fetch, the preview + swatches appear.
    await tester.tap(find.byKey(const Key('confirm_add_card')));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('color');
  });

  testWidgets('capture empty states', (tester) async {
    SharedPreferences.setMockInitialValues({'tour_seen': true});
    final factory = resolveDbFactory();
    await factory.deleteDatabase('bestcard.db');
    final dao = CardDao(await openAppDb(factory)); // no seed -> empty wallet
    final poiMap = await dao.loadPoiMap();
    await tester.pumpWidget(BestCardApp(
      dao: dao,
      venue: VenueCategoryService(lookup: _NoVenue(), poiMap: poiMap),
      locationFn: () async => (51.5, -0.12),
      profile: await ProfileStore.load(),
      analytics: await Analytics.load(),
    ));
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await binding.takeScreenshot('empty_best');

    await tester.tap(find.byKey(const Key('wallet_button')));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('empty_wallet');
  });

  testWidgets('capture card info sheet', (tester) async {
    final app = await _seededApp();
    // A fake card with full, friendly-looking numbers so the info sheet is rich.
    final db = app.dao.db;
    await db.insert('cards', {
      'id': 'demo_signature',
      'name': 'Signature Rewards',
      'issuer': 'Horizon Bank',
      'network': 'visa',
      'currency': 'AED',
      'annual_fee': 750,
      'apr': 39.9,
      'foreign_tx_fee': 2.99,
      'min_salary': 15000,
      'interest_free_days': 55,
      'color_primary': '#1D3A5F',
    });
    await db.insert('reward_rules', {
      'card_id': 'demo_signature',
      'category': 'dining',
      'rate': 3.0,
      'unit': 'cashback_pct',
      'cap_period': 'none',
      'source_ref': 'demo',
      'verified': 1,
    });
    await db.insert('reward_rules', {
      'card_id': 'demo_signature',
      'category': 'travel',
      'rate': 2.0,
      'unit': 'cashback_pct',
      'cap_period': 'none',
      'source_ref': 'demo',
      'verified': 1,
    });
    // Only the demo card is held, so it sits at the top of the wallet and its
    // info button is on screen without scrolling.
    await db.delete('user_cards');
    await db.insert('user_cards', {'card_id': 'demo_signature'});

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();

    await tester.tap(find.byKey(const Key('wallet_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('info_demo_signature')));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('info');
  });

  testWidgets('capture search screen', (tester) async {
    await tester.pumpWidget(await _seededApp());
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();

    await tester.enterText(
        find.byKey(const Key('merchant_search')), 'Glossy Hair Salon');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await binding.takeScreenshot('search');
  });

  testWidgets('capture share card', (tester) async {
    const card = CardInfo(
      id: 'amex_gold',
      name: 'Gold Card',
      issuer: 'American Express',
      network: 'amex',
      colorPrimary: '#1F6146',
      held: true,
    );
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: conciergeTheme(Brightness.light),
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: ShareCard(
                card: card,
                category: 'dining',
                headline: '4 pts',
                caption: 'back on dining'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('share');
  });
}
