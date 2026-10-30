import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

ThemeMode themeModeFromName(String? name) => switch (name) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

/// Penyimpanan pilihan tampilan. Diabstraksi supaya bisa diuji tanpa plugin.
abstract interface class ThemeModeStore {
  Future<ThemeMode> readMode();
  Future<void> writeMode(ThemeMode mode);
}

class SharedPreferencesThemeModeStore implements ThemeModeStore {
  const SharedPreferencesThemeModeStore();

  static const String key = 'app_theme_mode';

  @override
  Future<ThemeMode> readMode() async {
    final preferences = await SharedPreferences.getInstance();
    return themeModeFromName(preferences.getString(key));
  }

  @override
  Future<void> writeMode(ThemeMode mode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, mode.name);
  }
}

class InMemoryThemeModeStore implements ThemeModeStore {
  InMemoryThemeModeStore([this.mode = ThemeMode.system]);

  ThemeMode mode;
  int writes = 0;

  @override
  Future<ThemeMode> readMode() async => mode;

  @override
  Future<void> writeMode(ThemeMode mode) async {
    this.mode = mode;
    writes++;
  }
}

/// Pilihan Terang / Gelap / Ikuti sistem.
///
/// Disimpan lokal dan diterapkan seketika tanpa memulai ulang aplikasi:
/// [mode] dibaca `MaterialApp` lewat [ListenableBuilder].
class ThemeModeController extends ChangeNotifier {
  ThemeModeController({ThemeModeStore store = const SharedPreferencesThemeModeStore()})
    : _store = store;

  static final ThemeModeController instance = ThemeModeController();

  final ThemeModeStore _store;
  ThemeMode _mode = ThemeMode.system;
  bool _loaded = false;

  ThemeMode get mode => _mode;

  /// Bawaan rancangan adalah Ikuti sistem sampai pengguna memilih sendiri.
  Future<void> load() async {
    if (_loaded) return;
    final stored = await _store.readMode();
    _loaded = true;
    if (stored != _mode) {
      _mode = stored;
      notifyListeners();
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await _store.writeMode(mode);
  }
}
