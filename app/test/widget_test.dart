import 'package:bestcard/dao.dart';
import 'package:bestcard/ingest_service.dart';
import 'package:bestcard/main.dart';
import 'package:bestcard/profile_store.dart';
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
}) async {
  SharedPreferences.setMockInitialValues({});
  final dao = CardDao(await openSeedDb());
  final poiMap = await dao.loadPoiMap();
  return BestCardApp(
    dao: dao,
    venue: VenueCategoryService(lookup: FakeLookup(venueTypes), poiMap: poiMap),
    locationFn: () async => (51.5, -0.12),
    ingest: ingest,
    profile: await ProfileStore.load(),
  );
}

void main() {
  testWidgets('location flow shows issuer and card name plus cap flag',
      (tester) async {
    await tester.pumpWidget(await buildApp(venueTypes: ['supermarket']));

    await tester.tap(find.byIcon(Icons.near_me));
    await tester.pumpAndSettle();

    // Grocery: amex 2pts*0.9p = 1.8% beats barclays 1% cashback.
    expect(find.byKey(const Key('best_card')), findsOneWidget);
    expect(find.text('AMERICAN EXPRESS'), findsOneWidget);
    expect(find.text('Amex Gold'), findsOneWidget);
    expect(find.byKey(const Key('cap_flag')), findsOneWidget);
  });

  testWidgets('simulation chip picks category without location',
      (tester) async {
    await tester.pumpWidget(await buildApp());

    await tester.tap(find.byKey(const Key('sim_dining')));
    await tester.pumpAndSettle();

    expect(find.text('Amex Gold'), findsOneWidget);
    expect(find.textContaining('back on dining'), findsOneWidget);
  });

  testWidgets('min-spend rule excluded from pick but shown as hint',
      (tester) async {
    await tester.pumpWidget(await buildApp());

    // Online: barclays 5% needs 3000/mo (assumed unmet) -> amex general wins.
    await tester.tap(find.byKey(const Key('sim_online')));
    await tester.pumpAndSettle();

    expect(find.text('Amex Gold'), findsOneWidget);
    final hint = find.byKey(const Key('min_spend_hint'));
    expect(hint, findsOneWidget);
    expect(
      find.textContaining('Barclays · Barclays Cashback hits 5.00%'),
      findsOneWidget,
    );
    expect(find.textContaining('reaches 3000'), findsOneWidget);
  });

  testWidgets('offers for the category are listed', (tester) async {
    await tester.pumpWidget(await buildApp());

    await tester.tap(find.byKey(const Key('sim_entertainment')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('offer')), findsOneWidget);
    expect(find.text('Buy 1 Get 1 movie tickets'), findsOneWidget);
  });

  testWidgets('adding a card via the wallet sheet ingests it',
      (tester) async {
    await tester.pumpWidget(await buildApp(ingest: fakeIngest(titaniumJson)));

    await tester.tap(find.byKey(const Key('wallet_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add_card_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('new_card_field')), 'Emirates NBD Titanium');
    await tester.tap(find.byKey(const Key('confirm_add_card')));
    await tester.pumpAndSettle();

    expect(find.text('Titanium'), findsOneWidget);
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
    expect(find.textContaining('no search results'), findsOneWidget);
  });

  testWidgets('profile: set name and switch theme to dark', (tester) async {
    await tester.pumpWidget(await buildApp());

    await tester.tap(find.byKey(const Key('profile_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('profile_name_field')), 'Prasad');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    // App is now in dark mode.
    final ctx = tester.element(find.text('Dark'));
    expect(Theme.of(ctx).brightness, Brightness.dark);

    // Back on the home screen the greeting uses the name.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('Prasad'), findsOneWidget);
  });

  testWidgets('removing a card via ✕ changes the recommendation',
      (tester) async {
    await tester.pumpWidget(await buildApp());

    await tester.tap(find.byKey(const Key('sim_grocery')));
    await tester.pumpAndSettle();
    expect(find.text('Amex Gold'), findsOneWidget);

    await tester.tap(find.byKey(const Key('wallet_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('remove_amex_gold')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_remove')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Best card'));
    await tester.pumpAndSettle();

    // Amex gone -> barclays grocery 1% is now the pick.
    expect(find.text('Barclays Cashback'), findsOneWidget);
    expect(find.text('BARCLAYS'), findsOneWidget);
  });
}
