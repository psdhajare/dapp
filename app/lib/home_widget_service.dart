/// Pushes the current "best card" to the iOS home-screen widget via the shared
/// App Group. The native WidgetKit extension (ios/BestCardWidget) reads the same
/// JSON. No-op on platforms without the widget.
library;

import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import 'dao.dart';
import 'util/formatting.dart';

const _appGroupId = 'group.com.dapp.bestcard';
const _dataKey = 'best_card';
const _siriKey = 'siri_category';
const _widgetName = 'BestCardWidget'; // must match the WidgetKit `kind`

/// Returns a category the user requested via Siri ("best card for groceries"),
/// then clears it so it fires once. Null if none pending. Best-effort.
Future<String?> consumeSiriCategory() async {
  try {
    await HomeWidget.setAppGroupId(_appGroupId);
    final value = await HomeWidget.getWidgetData<String>(_siriKey);
    if (value != null && value.isNotEmpty) {
      await HomeWidget.saveWidgetData<String>(_siriKey, null);
      return value;
    }
  } catch (_) {}
  return null;
}

/// Write the best card for [category] so the home-screen widget can show it.
/// Best-effort: any failure (e.g. widget not installed) is swallowed.
Future<void> updateBestCardWidget({
  required CardInfo card,
  required String category,
  required String headline,
  required String caption,
}) async {
  try {
    await HomeWidget.setAppGroupId(_appGroupId);
    final payload = jsonEncode({
      'category': category,
      'issuer': displayIssuer(card.issuer),
      'name': card.name,
      'headline': headline,
      'caption': caption,
      'primary': card.colorPrimary ?? '#2B2B33',
      'secondary': card.colorSecondary ?? '#131318',
    });
    await HomeWidget.saveWidgetData<String>(_dataKey, payload);
    await HomeWidget.updateWidget(iOSName: _widgetName);
  } catch (_) {
    // Widget not set up / unsupported platform — ignore.
  }
}
