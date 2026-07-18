/// Local, offline profile settings: display name + theme preference.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileStore extends ChangeNotifier {
  static const _kName = 'profile_name';
  static const _kTheme = 'theme_mode';

  final SharedPreferences _prefs;
  String _name;
  ThemeMode _themeMode;

  ProfileStore(this._prefs)
      : _name = _prefs.getString(_kName) ?? '',
        _themeMode = _parseTheme(_prefs.getString(_kTheme));

  static Future<ProfileStore> load() async =>
      ProfileStore(await SharedPreferences.getInstance());

  String get name => _name;
  ThemeMode get themeMode => _themeMode;

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

  static ThemeMode _parseTheme(String? s) => switch (s) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
