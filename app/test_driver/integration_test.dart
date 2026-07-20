import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Driver for the screenshot capture: writes each reported screenshot to
/// screenshots/<name>.png in the project root.
Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final file = File('screenshots/$name.png');
      await file.create(recursive: true);
      await file.writeAsBytes(bytes);
      return true;
    },
  );
}
