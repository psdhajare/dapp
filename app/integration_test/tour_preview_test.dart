// Captures the welcome tour itself, to preview how the embedded screenshots
// look inside a slide. Run:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/tour_preview_test.dart -d <simulator-id>
import 'package:bestcard/screens/onboarding_screen.dart';
import 'package:bestcard/theme/concierge_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture tour slides', (tester) async {
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: conciergeTheme(Brightness.light),
      home: OnboardingScreen(onDone: () {}),
    ));
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('tour_1');

    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(const Key('tour_next')));
      await tester.pumpAndSettle();
      await binding.takeScreenshot('tour_${i + 2}');
    }
  });
}
