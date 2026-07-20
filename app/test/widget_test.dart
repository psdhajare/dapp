import 'package:bestcard/analytics.dart';
import 'package:bestcard/dao.dart';
import 'package:bestcard/ingest_service.dart';
import 'package:bestcard/main.dart';
import 'package:bestcard/profile_store.dart';
import 'package:bestcard/rate_limiter.dart';
import 'package:bestcard/venue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';
import 'venue_test.dart' show FakeLookup;

/// Ingest service backed by a canned HTTP response.
IngestService fakeIngest(String responseBody, {int status = 200}) {
  return IngestService(
    endpoint: Uri.parse('http://fake/ingest'),
    client: MockClient((_) async => http.Response(responseBody, status,
        headers: {'content-type': 'application/json'})),
  );
}

/// Ingest service that routes /ingest and /search to different canned bodies.
IngestService fakeRouted({String? ingestBody, String? searchBody}) {
  return IngestService(
    endpoint: Uri.parse('http://fake/ingest'),
    client: MockClient((req) async {
      final body = req.url.path == '/search'
          ? (searchBody ?? '{"category":"general","offers":[]}')
          : (ingestBody ?? '{}');
      return http.Response(body, 200,
          headers: {'content-type': 'application/json'});
    }),
  );
}

const titaniumJson = '''
{
  "card": {"id": "enbd_titanium", "name": "Titanium", "issuer": "Emirates NBD",
           "network": "visa", "currency": "AED", "annual_fee": 0},
  "rules": [{"category": "dining", "rate": 3.0, "unit": "cashback_pct",
             "cap_amount": null, "cap_period": "none", "min_spend": null,
             "conditions": null, "source_ref": "t", "verified": false}],
  "valuation": null,
  "offers": [],
  "warnings": []
}
''';

Future<BestCardApp> buildApp({
  List<String> venueTypes = const [],
  IngestService? ingest,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues({'tour_seen': true, ...prefs});
  final dao = CardDao(await openSeedDb());
  final poiMap = await dao.loadPoiMap();
  return BestCardApp(
    dao: dao,
    venue: VenueCategoryService(lookup: FakeLookup(venueTypes), poiMap: poiMap),
    locationFn: () async => (51.5, -0.12),
    ingest: ingest,
    profile: await ProfileStore.load(),
    analytics: await Analytics.load(),
  );
}

void main() {
  setUp(queryRateLimiter.reset); // isolate the shared limiter per test

  testWidgets('malicious merchant search is blocked client-side (no backend call)',
      (tester) async {
    var backendCalls = 0;
    final ingest = IngestService(
      endpoint: Uri.parse('http://fake/ingest'),
      client: MockClient((req) async {
        backendCalls++;
        return http.Response('{"category":"general","offers":[]}', 200,
            headers: {'content-type': 'application/json'});
      }),
    );
    await tester.pumpWidget(await buildApp(ingest: ingest));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('merchant_search')), "'; DROP TABLE cards;--");
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(); // build the error toast (avoid pumpAndSettle: toast
    await tester.pump(const Duration(milliseconds: 400)); // has lingering timers

    expect(backendCalls, 0);                    // never left the device
    expect(find.textContaining('unsafe'), findsOneWidget); // error shown

    await tester.pump(const Duration(seconds: 4)); // flush toast timers
  });

  testWidgets('location flow shows issuer and card name plus cap flag',
      (tester) async {
    await tester.pumpWidget(await buildApp(venueTypes: ['supermarket']));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chip_location')));
    await tester.pumpAndSettle();

    // Grocery: amex 2pts*0.9p = 1.8% beats barclays 1% cashback.
    expect(find.byKey(const Key('best_card')), findsOneWidget);
    expect(find.text('AMERICAN EXPRESS'), findsOneWidget);
    expect(find.text('Amex Gold'), findsOneWidget);
    // Cap pill sits below the deck — scroll it into view before asserting.
    await tester.dragUntilVisible(
        find.byKey(const Key('cap_flag')),
        find.byType(Scrollable).first,
        const Offset(0, -100));
    expect(find.byKey(const Key('cap_flag')), findsOneWidget);

    await tester.pump(const Duration(seconds: 3)); // flush celebration timers
  });

  testWidgets('simulation chip picks category without location',
      (tester) async {
    await tester.pumpWidget(await buildApp());

    await tester.tap(find.byKey(const Key('sim_dining')));
    await tester.pumpAndSettle();

    expect(find.text('Amex Gold'), findsOneWidget);
    expect(find.textContaining('back on dining'), findsOneWidget);
  });

  testWidgets('switching category refreshes the winner percentage (no stale rate)',
      (tester) async {
    await tester.pumpWidget(await buildApp());

    // Amex wins both, so the card set is unchanged across the switch — this is
    // the case that used to show a stale rate.
    await tester.tap(find.byKey(const Key('sim_dining')));
    await tester.pumpAndSettle();
    expect(find.text('3.60%'), findsOneWidget); // 4 pts * 0.9p

    await tester.tap(find.byKey(const Key('sim_grocery')));
    await tester.pumpAndSettle();
    expect(find.text('1.80%'), findsOneWidget); // 2 pts * 0.9p
    expect(find.text('3.60%'), findsNothing); // old rate must be gone
  });

  testWidgets('min-spend rule excluded from pick but shown as hint',
      (tester) async {
    await tester.pumpWidget(await buildApp());

    // Online: barclays 5% needs 3000/mo (assumed unmet) -> amex general wins.
    await tester.tap(find.byKey(const Key('sim_online')));
    await tester.pumpAndSettle();

    expect(find.text('Amex Gold'), findsOneWidget);
    final hint = find.byKey(const Key('min_spend_hint'));
    // Hint pill sits below the deck — scroll it into view before asserting.
    await tester.dragUntilVisible(
        hint, find.byType(Scrollable).first, const Offset(0, -100));
    expect(hint, findsOneWidget);
    expect(
      find.textContaining('Barclays · Barclays Cashback hits 5.00%'),
      findsOneWidget,
    );
    expect(find.textContaining('reaches 3000'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3)); // flush celebration timers
  });

  testWidgets('offers for the category are listed', (tester) async {
    await tester.pumpWidget(await buildApp());

    await tester.tap(find.byKey(const Key('sim_entertainment')));
    await tester.pumpAndSettle();

    // Offers list sits below the deck — scroll it into view before asserting.
    await tester.dragUntilVisible(find.byKey(const Key('offer')),
        find.byType(Scrollable).first, const Offset(0, -100));
    expect(find.byKey(const Key('offer')), findsOneWidget);
    expect(find.text('Buy 1 Get 1 movie tickets'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3)); // flush celebration timers
  });

  testWidgets('adding a card via the wallet sheet ingests it',
      (tester) async {
    // The add-card sheet (preview + colour picker + button) is taller than the
    // default 800x600 test surface; give it room so it doesn't overflow.
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(await buildApp(ingest: fakeIngest(titaniumJson)));

    await tester.tap(find.byKey(const Key('wallet_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add_card_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('new_card_field')), 'Emirates NBD Titanium');
    // Step 1: fetch -> card preview + colour picker appear in the sheet.
    await tester.tap(find.byKey(const Key('confirm_add_card')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('swatch_Graphite')), findsOneWidget);

    // Step 2: confirm -> card saved to the wallet.
    await tester.tap(find.byKey(const Key('confirm_add_card')));
    await tester.pumpAndSettle();

    expect(find.text('Titanium'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3)); // flush lingering timers
  });

  testWidgets('failed ingestion shows the error in the sheet',
      (tester) async {
    await tester.pumpWidget(await buildApp(
        ingest: fakeIngest('{"error": "no search results"}', status: 500)));

    await tester.tap(find.byKey(const Key('wallet_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add_card_button')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('new_card_field')), 'Nope');
    await tester.tap(find.byKey(const Key('confirm_add_card')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('add_card_error')), findsOneWidget);
    // A non-404 backend failure now surfaces a friendly message (kFriendlyError)
    // in the sheet rather than echoing the raw backend error string.
    expect(find.textContaining('something went wrong'), findsOneWidget);
  });

  testWidgets('search a merchant: keyword category + live offers with badges',
      (tester) async {
    // card_hint points at a card the seed wallet holds (Amex Gold) so the offer
    // surfaces as a held ("In your wallet") offer rather than a non-held one.
    const searchJson = '''
      {"merchant":"Glossy Hair Salon","category":"beauty","cached":false,
       "offers":[
         {"title":"20% off hair services","description":"Weekends",
          "card_hint":"American Express","valid_until":"31 Dec 2026"}]}''';
    await tester.pumpWidget(
        await buildApp(ingest: fakeRouted(searchBody: searchJson)));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('merchant_search')), 'Glossy Hair Salon');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    // Bounded pumps: the loading spinner + one-shot on-card crackers are
    // perpetual/animated, so pumpAndSettle would time out. Pump enough for the
    // mocked network + DB + the ~1.5s celebration to settle.
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Best-card header reflects the searched merchant.
    expect(find.textContaining('Best at Glossy Hair Salon'), findsOneWidget);
    // Live offer rendered with limited-time + wallet badges. It sits below the
    // deck — scroll it into view before asserting.
    await tester.dragUntilVisible(find.byKey(const Key('merchant_offer')),
        find.byType(Scrollable).first, const Offset(0, -100));
    expect(find.byKey(const Key('merchant_offer')), findsOneWidget);
    expect(find.text('20% off hair services'), findsOneWidget);
    expect(find.textContaining('Until 31 Dec 2026'), findsOneWidget);
    expect(find.text('In your wallet'), findsOneWidget); // Amex Gold held

    await tester.pump(const Duration(seconds: 3)); // flush celebration timers
  });

  testWidgets('search with no offers shows empty message', (tester) async {
    await tester.pumpWidget(await buildApp(
        ingest: fakeRouted(
            searchBody: '{"category":"beauty","offers":[],"cached":false}')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('merchant_search')), 'Zzxq Place');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Empty-offers message sits below the deck — scroll it into view.
    final empty = find.textContaining('None of your cards has an offer');
    await tester.dragUntilVisible(
        empty, find.byType(Scrollable).first, const Offset(0, -100));
    expect(empty, findsOneWidget);

    await tester.pump(const Duration(seconds: 3)); // flush lingering timers
  });

  testWidgets('profile: set name and switch theme to dark', (tester) async {
    // Year + employment are mandatory; seed them so the test only drives name.
    await tester.pumpWidget(await buildApp(
        prefs: {'birth_year': '1990', 'employment': 'Employed'}));

    await tester.tap(find.byKey(const Key('profile_button')));
    await tester.pumpAndSettle();

    final list = find.byType(Scrollable).first;

    await tester.enterText(
        find.byKey(const Key('profile_name_field')), 'Prasad');

    // Save sits at the bottom of a lazy ListView — scroll it into view first.
    await tester.scrollUntilVisible(
        find.byKey(const Key('save_profile')), 300,
        scrollable: list);
    await tester.tap(find.byKey(const Key('save_profile')));
    await tester.pumpAndSettle();

    // Theme control is higher up — scroll back to it.
    await tester.scrollUntilVisible(find.text('Dark'), -300, scrollable: list);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    // App is now in dark mode.
    final ctx = tester.element(find.text('Dark'));
    expect(Theme.of(ctx).brightness, Brightness.dark);

    // Back on the home screen the greeting uses the name.
    await tester.scrollUntilVisible(find.byKey(const Key('profile_back')), -300,
        scrollable: list);
    await tester.tap(find.byKey(const Key('profile_back')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Prasad'), findsAtLeastNWidgets(1));

    await tester.pump(const Duration(seconds: 2)); // flush the Saved snackbar
  });

  testWidgets('swiping a card away changes the recommendation',
      (tester) async {
    await tester.pumpWidget(await buildApp());

    await tester.tap(find.byKey(const Key('sim_grocery')));
    await tester.pumpAndSettle();
    expect(find.text('Amex Gold'), findsOneWidget);

    await tester.tap(find.byKey(const Key('wallet_button')));
    await tester.pumpAndSettle();

    // Swipe reveals the Remove action (card does NOT fully dismiss), then tap it.
    await tester.drag(find.byKey(const Key('card_amex_gold')),
        const Offset(-260, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remove_amex_gold')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Best card'));
    await tester.pumpAndSettle();

    // Amex gone -> barclays grocery 1% is now the pick.
    expect(find.text('Barclays Cashback'), findsOneWidget);
    expect(find.text('BARCLAYS'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3)); // flush the removed-toast timer
  });
}
