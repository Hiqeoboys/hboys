import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../features/tracking/application/tracking_runtime.dart';
import 'device_battery_reader.dart';
import 'power_profile_manager.dart';

/// Sumber status Mode Hemat Baterai OS sebenarnya (`PowerManager.isPowerSaveMode`).
/// Tidak pernah membaca `isIgnoringBatteryOptimizations`.
abstract interface class OsPowerSaveSource {
  Future<bool> isPowerSaveMode();
  Stream<bool> changes();
}

class MethodChannelOsPowerSaveSource implements OsPowerSaveSource {
  const MethodChannelOsPowerSaveSource();

  static const MethodChannel _method = MethodChannel('id.nama.nama_app/power');
  static const EventChannel _events =
      EventChannel('id.nama.nama_app/power_save_changes');

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  @override
  Future<bool> isPowerSaveMode() async {
    if (!_isAndroid) return false;
    try {
      return await _method.invokeMethod<bool>('isPowerSaveMode') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Stream<bool> changes() {
    if (!_isAndroid) return const Stream<bool>.empty();
    return _events
        .receiveBroadcastStream()
        .where((event) => event is bool)
        .cast<bool>();
  }
}

/// Sumber profil daya untuk seluruh antarmuka.
///
/// [PowerProfileManager] sebelumnya hanya hidup di dalam mesin pelacakan;
/// rancangan memakai profil daya juga di Beranda, Pelacakan, dan untuk
/// mematikan efek visual, jadi pembarunya dipisah di sini.
class PowerProfileController extends ChangeNotifier {
  PowerProfileController({
    BatteryReader? reader,
    PowerProfileManager? manager,
    OsPowerSaveSource? osPowerSaveSource,
    bool initialOsPowerSaveMode = false,
  })  : _reader = reader ?? DeviceBatteryReader(),
        _manager = manager ?? PowerProfileManager(),
        _osPowerSaveSource =
            osPowerSaveSource ?? const MethodChannelOsPowerSaveSource(),
        _osPowerSaveMode = initialOsPowerSaveMode;

  final BatteryReader _reader;
  final PowerProfileManager _manager;
  final OsPowerSaveSource _osPowerSaveSource;

  int? _levelPercent;
  bool _charging = false;
  bool _osPowerSaveMode;
  StreamSubscription<bool>? _osPowerSaveSub;

  PowerProfile get profile => _manager.profile;
  int? get levelPercent => _levelPercent;
  bool get isCharging => _charging;

  /// Status nyata `PowerManager.isPowerSaveMode` dari OS Android.
  bool get isOsPowerSaveMode => _osPowerSaveMode;

  /// Membaca baterai dan status hemat baterai OS, serta mulai mendengarkan
  /// broadcast `ACTION_POWER_SAVE_MODE_CHANGED`.
  Future<void> refresh() async {
    _ensureOsPowerSaveListener();
    var changed = false;
    try {
      final level = await _reader.levelPercent();
      final charging = await _reader.isCharging();
      final previousLevel = _levelPercent;
      final previousProfile = _manager.profile;
      _levelPercent = level;
      _charging = charging;
      _manager.update(level, charging: charging);
      if (level != previousLevel || _manager.profile != previousProfile) {
        changed = true;
      }
    } on Exception {
      // Gagal membaca level baterai tidak mematikan pembaruan status OS.
    }
    try {
      final osSaver = await _osPowerSaveSource.isPowerSaveMode();
      if (osSaver != _osPowerSaveMode) {
        _osPowerSaveMode = osSaver;
        changed = true;
      }
    } catch (_) {}
    if (changed) {
      notifyListeners();
    }
  }

  void _ensureOsPowerSaveListener() {
    if (_osPowerSaveSub != null) return;
    try {
      _osPowerSaveSub = _osPowerSaveSource.changes().listen(
        (active) {
          if (active == _osPowerSaveMode) return;
          _osPowerSaveMode = active;
          notifyListeners();
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    unawaited(_osPowerSaveSub?.cancel());
    _osPowerSaveSub = null;
    super.dispose();
  }
}
