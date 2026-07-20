/// Local, offline profile settings: display name + theme preference.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileStore extends ChangeNotifier {
  static const _kName = 'profile_name';
  static const _kTheme = 'theme_mode';
  static const _kHistOn = 'search_history_enabled';
  static const _kHist = 'search_history';
  static const _kCountry = 'country';
  static const _kCountryUserSet = 'country_user_set';
  static const _kCurrency = 'currency';
  static const _kBirthYear = 'birth_year';
  static const _kEmployment = 'employment';
  static const _kTourSeen = 'tour_seen';
  static const _maxHistory = 10;

  final SharedPreferences _prefs;
  String _name;
  ThemeMode _themeMode;
  bool _historyEnabled;
  List<String> _history;
  String _country;
  bool _countryUserSet;
  String _currency;
  String _birthYear;
  String _employment;
  bool _tourSeen;

  ProfileStore(this._prefs)
      : _name = _prefs.getString(_kName) ?? '',
        _themeMode = _parseTheme(_prefs.getString(_kTheme)),
        _historyEnabled = _prefs.getBool(_kHistOn) ?? true,
        _history = _prefs.getStringList(_kHist) ?? [],
        _country = _prefs.getString(_kCountry) ?? '', // none until known
        _countryUserSet = _prefs.getBool(_kCountryUserSet) ?? false,
        _currency = _prefs.getString(_kCurrency) ?? 'AED',
        _birthYear = _prefs.getString(_kBirthYear) ?? '',
        _employment = _prefs.getString(_kEmployment) ?? '',
        _tourSeen = _prefs.getBool(_kTourSeen) ?? false;

  static Future<ProfileStore> load() async =>
      ProfileStore(await SharedPreferences.getInstance());

  String get name => _name;
  ThemeMode get themeMode => _themeMode;
  bool get searchHistoryEnabled => _historyEnabled;
  List<String> get searchHistory => List.unmodifiable(_history);
  String get country => _country;
  bool get countryUserSet => _countryUserSet;
  String get currency => _currency;
  String get birthYear => _birthYear;
  String get employment => _employment;
  bool get tourSeen => _tourSeen;

  /// Mark the first-run welcome tour as completed (or skipped).
  Future<void> setTourSeen() async {
    if (_tourSeen) return;
    _tourSeen = true;
    await _prefs.setBool(_kTourSeen, true);
    notifyListeners();
  }

  /// Save personal details together (name + birth year + employment status),
  /// stored locally only. Deliberately non-PII (year, not full DOB).
  Future<void> saveDetails({
    required String name,
    required String birthYear,
    required String employment,
  }) async {
    _name = name.trim();
    _birthYear = birthYear.trim();
    _employment = employment.trim();
    await _prefs.setString(_kName, _name);
    await _prefs.setString(_kBirthYear, _birthYear);
    await _prefs.setString(_kEmployment, _employment);
    notifyListeners();
  }

  /// User explicitly picked a country (won't be overridden by auto-detect).
  Future<void> setCountry(String value) async {
    _country = value;
    _countryUserSet = true;
    await _prefs.setString(_kCountry, value);
    await _prefs.setBool(_kCountryUserSet, true);
    notifyListeners();
  }

  /// Switch back to auto (location-driven) country.
  Future<void> clearCountry() async {
    _country = '';
    _countryUserSet = false;
    await _prefs.remove(_kCountry);
    await _prefs.setBool(_kCountryUserSet, false);
    notifyListeners();
  }

  /// Populate from device location — only if the user hasn't picked one.
  Future<void> autoDetectCountry(String value) async {
    if (_countryUserSet || value.isEmpty || value == _country) return;
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
