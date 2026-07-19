import 'package:bestcard/analytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('default enabled is true', () async {
    final a = await Analytics.load();
    expect(a.enabled, isTrue);
    expect(a.snapshot(), isEmpty);
  });

  test('log increments counter and snapshot reflects it', () async {
    final a = await Analytics.load();
    a.log(Analytics.searchPerformed);
    a.log(Analytics.searchPerformed);
    expect(a.snapshot()[Analytics.searchPerformed], 2);
  });

  test('label creates the event.label sub-counter', () async {
    final a = await Analytics.load();
    a.log(Analytics.searchPerformed, label: 'dining');
    final snap = a.snapshot();
    expect(snap[Analytics.searchPerformed], 1);
    expect(snap['${Analytics.searchPerformed}.dining'], 1);
  });

  test('snapshot is unmodifiable', () async {
    final a = await Analytics.load();
    a.log(Analytics.searchPerformed);
    expect(() => a.snapshot()['x'] = 1, throwsUnsupportedError);
  });

  test('when disabled, log is a no-op and counts are cleared', () async {
    final a = await Analytics.load();
    a.log(Analytics.searchPerformed);
    expect(a.snapshot(), isNotEmpty);

    await a.setEnabled(false);
    expect(a.enabled, isFalse);
    expect(a.snapshot(), isEmpty);

    a.log(Analytics.searchPerformed);
    expect(a.snapshot(), isEmpty);
  });

  test('re-enabling starts from empty', () async {
    final a = await Analytics.load();
    a.log(Analytics.searchPerformed);
    await a.setEnabled(false);
    await a.setEnabled(true);
    expect(a.snapshot(), isEmpty);
    a.log(Analytics.paywallShown);
    expect(a.snapshot()[Analytics.paywallShown], 1);
  });

  test('label sanitization strips junk symbols and spaces', () async {
    final a = await Analytics.load();
    a.log(Analytics.searchPerformed, label: 'Fine Dining!');
    expect(a.snapshot()['${Analytics.searchPerformed}.finedining'], 1);
  });

  test('label that is empty after cleaning is dropped', () async {
    final a = await Analytics.load();
    a.log(Analytics.searchPerformed, label: '!!! @@@');
    final snap = a.snapshot();
    expect(snap[Analytics.searchPerformed], 1);
    expect(snap.length, 1);
  });

  test('label is capped at 24 chars', () async {
    final a = await Analytics.load();
    a.log(Analytics.searchPerformed, label: 'a' * 40);
    expect(a.snapshot()['${Analytics.searchPerformed}.${'a' * 24}'], 1);
  });

  test('clear zeroes counts', () async {
    final a = await Analytics.load();
    a.log(Analytics.searchPerformed);
    await a.clear();
    expect(a.snapshot(), isEmpty);
  });

  test('counts persist across reloads', () async {
    final a = await Analytics.load();
    a.log(Analytics.subscribed);
    await Future<void>.delayed(Duration.zero);
    final b = await Analytics.load();
    expect(b.snapshot()[Analytics.subscribed], 1);
  });
}
