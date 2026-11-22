import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kontrak penyimpanan status sakelar gerak latar.
abstract interface class BackgroundMotionStore {
  Future<bool> readEnabled();
  Future<void> writeEnabled(bool enabled);
}

/// Implementasi penyimpanan berbasis SharedPreferences.
class SharedPreferencesBackgroundMotionStore implements BackgroundMotionStore {
  const SharedPreferencesBackgroundMotionStore();

  static const String key = 'background_motion_enabled';

  @override
  Future<bool> readEnabled() async {
    return true;
  }

  @override
  Future<void> writeEnabled(bool enabled) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(key, enabled);
    } catch (_) {}
  }
}

/// Implementasi in-memory untuk pengujian unit/widget.
class InMemoryBackgroundMotionStore implements BackgroundMotionStore {
  InMemoryBackgroundMotionStore([this.enabled = true]);

  bool enabled;
  int writes = 0;

  @override
  Future<bool> readEnabled() async => enabled;

  @override
  Future<void> writeEnabled(bool enabled) async {
    this.enabled = enabled;
    writes++;
  }
}

/// Pengendali pengaturan gerak latar aplikasi (drift).
class BackgroundMotionController extends ChangeNotifier {
  BackgroundMotionController({
    BackgroundMotionStore? store,
    bool? initialEnabled,
  }) : _store = store ?? const SharedPreferencesBackgroundMotionStore() {
    if (initialEnabled != null) {
      _enabled = initialEnabled;
      _loaded = true;
    } else {
      unawaited(_init());
    }
  }

  static final BackgroundMotionController instance =
      BackgroundMotionController();

  final BackgroundMotionStore _store;
  bool _enabled = true;
  bool _loaded = false;
  bool _userModified = false;

  bool get enabled => _enabled;
  bool get isLoaded => _loaded;

  Future<void> _init() async {
    final stored = await _store.readEnabled();
    if (!_userModified) {
      _enabled = stored;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _userModified = true;
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    await _store.writeEnabled(value);
  }
}
