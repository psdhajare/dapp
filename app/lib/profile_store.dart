/// Local, offline profile settings: display name + theme preference.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileStore extends ChangeNotifier {
  static const _kName = 'profile_name';
  static const _kTheme = 'theme_mode';
  static const _kHistOn = 'search_history_enabled';
  static const _kHist = 'search_history';
  static const _kCountry = 'country';
  static const _kCurrency = 'currency';
  static const _maxHistory = 10;

  final SharedPreferences _prefs;
  String _name;
  ThemeMode _themeMode;
  bool _historyEnabled;
  List<String> _history;
  String _country;
  String _currency;

  ProfileStore(this._prefs)
      : _name = _prefs.getString(_kName) ?? '',
        _themeMode = _parseTheme(_prefs.getString(_kTheme)),
        _historyEnabled = _prefs.getBool(_kHistOn) ?? true,
        _history = _prefs.getStringList(_kHist) ?? [],
        _country = _prefs.getString(_kCountry) ?? 'United Arab Emirates',
        _currency = _prefs.getString(_kCurrency) ?? 'AED';

  static Future<ProfileStore> load() async =>
      ProfileStore(await SharedPreferences.getInstance());

  String get name => _name;
  ThemeMode get themeMode => _themeMode;
  bool get searchHistoryEnabled => _historyEnabled;
  List<String> get searchHistory => List.unmodifiable(_history);
  String get country => _country;
  String get currency => _currency;

  Future<void> setCountry(String value) async {
    _country = value;
    await _prefs.setString(_kCountry, value);
    notifyListeners();
  }

  Future<void> setCurrency(String value) async {
    _currency = value;
    await _prefs.setString(_kCurrency, value);
    notifyListeners();
  }

  Future<void> setName(String value) async {
    _name = value.trim();
    await _prefs.setString(_kName, _name);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _prefs.setString(_kTheme, mode.name);
    notifyListeners();
  }

  /// Turning history off also clears any stored terms (privacy).
  Future<void> setSearchHistoryEnabled(bool value) async {
    _historyEnabled = value;
    await _prefs.setBool(_kHistOn, value);
    if (!value) {
      _history = [];
      await _prefs.remove(_kHist);
    }
    notifyListeners();
  }

  /// Records a search term (most-recent first, deduped, capped at 10).
  Future<void> addSearch(String term) async {
    if (!_historyEnabled) return;
    term = term.trim();
    if (term.isEmpty) return;
    _history.removeWhere((e) => e.toLowerCase() == term.toLowerCase());
    _history.insert(0, term);
    if (_history.length > _maxHistory) {
      _history = _history.sublist(0, _maxHistory);
    }
    await _prefs.setStringList(_kHist, _history);
    notifyListeners();
  }

  Future<void> clearSearchHistory() async {
    _history = [];
    await _prefs.remove(_kHist);
    notifyListeners();
  }

  static ThemeMode _parseTheme(String? s) => switch (s) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
