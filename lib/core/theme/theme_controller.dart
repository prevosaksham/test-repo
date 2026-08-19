import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide light/dark control. The "Dark Mode" item in the More menu flips
/// this; the choice is persisted and applied via [ValueNotifier] so the whole
/// app rebuilds instantly.
class ThemeController {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  static const String _key = 'theme_mode';

  final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);

  /// Load the saved preference once at startup.
  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    switch (sp.getString(_key)) {
      case 'dark':
        mode.value = ThemeMode.dark;
        break;
      case 'light':
        mode.value = ThemeMode.light;
        break;
      default:
        mode.value = ThemeMode.system;
    }
  }

  /// Force light or dark and remember it.
  Future<void> setDark(bool dark) async {
    mode.value = dark ? ThemeMode.dark : ThemeMode.light;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, dark ? 'dark' : 'light');
  }
}
