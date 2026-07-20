import 'package:bestcard/screens/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(VoidCallback onDone) =>
      MaterialApp(home: OnboardingScreen(onDone: onDone));

  testWidgets('carousel advances through slides and finishes on Get started',
      (tester) async {
    var done = false;
    await tester.pumpWidget(wrap(() => done = true));

    // First slide.
    expect(find.text('Always pay with your best card'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    // Advance to the last slide (7 slides -> 6 taps).
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(const Key('tour_next')));
      await tester.pumpAndSettle();
    }

    // Last slide shows the finish action, not Skip.
    expect(find.text('Get started'), findsOneWidget);
    expect(find.textContaining('stays on your phone'), findsOneWidget);
    expect(tester.widget<TextButton>(find.byKey(const Key('tour_skip')))
        .onPressed, isNull);

    await tester.tap(find.byKey(const Key('tour_next')));
    await tester.pumpAndSettle();
    expect(done, isTrue);
  });

  testWidgets('Skip finishes the tour immediately', (tester) async {
    var done = false;
    await tester.pumpWidget(wrap(() => done = true));

    await tester.tap(find.byKey(const Key('tour_skip')));
    await tester.pumpAndSettle();
    expect(done, isTrue);
  });
}
