/// Local, opt-in, anonymous usage counters. No PII — counters only.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Analytics extends ChangeNotifier {
  static const _kEnabled = 'analytics_enabled';
  static const _kCounts = 'analytics_counts';

  // Event name constants.
  static const searchPerformed = 'search_performed';
  static const recommendationShown = 'recommendation_shown';
  static const liveOfferViewed = 'live_offer_viewed';
  static const cardAddedSuccess = 'card_added_success';
  static const cardAddedFail = 'card_added_fail';
  static const proFeatureTapped = 'pro_feature_tapped';
  static const paywallShown = 'paywall_shown';
  static const subscribed = 'subscribed';

  final SharedPreferences _prefs;
  bool _enabled;
  Map<String, int> _counts;

  Analytics(this._prefs)
      : _enabled = _prefs.getBool(_kEnabled) ?? true,
        _counts = _decode(_prefs.getString(_kCounts));

  static Future<Analytics> load() async =>
      Analytics(await SharedPreferences.getInstance());

  bool get enabled => _enabled;

  Map<String, int> snapshot() => Map.unmodifiable(_counts);

  /// Turning analytics off also clears all counts (privacy).
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _prefs.setBool(_kEnabled, value);
    if (!value) {
      _counts = {};
      await _prefs.remove(_kCounts);
    }
    notifyListeners();
  }

  /// Increments the counter for [event] and, if given, for `event.label`.
  void log(String event, {String? label}) {
    if (!_enabled) return;
    _counts[event] = (_counts[event] ?? 0) + 1;
    final clean = _cleanLabel(label);
    if (clean != null) {
      final key = '$event.$clean';
      _counts[key] = (_counts[key] ?? 0) + 1;
    }
    _persist();
    notifyListeners();
  }

  Future<void> clear() async {
    _counts = {};
    await _prefs.setString(_kCounts, jsonEncode(_counts));
    notifyListeners();
  }

  void _persist() => _prefs.setString(_kCounts, jsonEncode(_counts));

  static String? _cleanLabel(String? label) {
    if (label == null) return null;
    var s = label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    if (s.length > 24) s = s.substring(0, 24);
    return s.isEmpty ? null : s;
  }

  static Map<String, int> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
  }
}
