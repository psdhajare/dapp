import 'package:bestcard/dao.dart';
import 'package:bestcard/theme/concierge_theme.dart';
import 'package:bestcard/widgets/card_visual.dart';
import 'package:bestcard/widgets/share_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ShareCard renders title, brand footer and a CardVisual',
      (tester) async {
    const card = CardInfo(
      id: 'test',
      name: 'Test Rewards',
      issuer: 'Test Bank',
      network: 'visa',
      colorPrimary: '#2B2B33',
      held: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: conciergeTheme(Brightness.light),
        home: const Scaffold(
          body: Center(
            child: ShareCard(
              card: card,
              category: 'dining',
              headline: '5%',
              caption: 'back on dining',
            ),
          ),
        ),
      ),
    );

    expect(find.text('My best card for dining'), findsOneWidget);
    expect(
        find.text('ToroKard · always pay with your best card'), findsOneWidget);
    expect(find.byType(CardVisual), findsOneWidget);
  });
}
