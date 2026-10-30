import 'package:flutter/foundation.dart';

import '../../features/tracking/application/tracking_runtime.dart';
import 'device_battery_reader.dart';
import 'power_profile_manager.dart';

/// Sumber profil daya untuk seluruh antarmuka.
///
/// [PowerProfileManager] sebelumnya hanya hidup di dalam mesin pelacakan;
/// rancangan memakai profil daya juga di Beranda, Pelacakan, dan untuk
/// mematikan efek visual, jadi pembarunya dipisah di sini.
class PowerProfileController extends ChangeNotifier {
  PowerProfileController({
    BatteryReader? reader,
    PowerProfileManager? manager,
  }) : _reader = reader ?? DeviceBatteryReader(),
       _manager = manager ?? PowerProfileManager();

  final BatteryReader _reader;
  final PowerProfileManager _manager;

  int? _levelPercent;
  bool _charging = false;

  PowerProfile get profile => _manager.profile;
  int? get levelPercent => _levelPercent;
  bool get isCharging => _charging;

  /// Membaca baterai sekali. Gagal (mis. plugin tak tersedia) tidak mengubah
  /// profil: lebih baik efek visual tetap ada daripada salah mematikan.
  Future<void> refresh() async {
    try {
      final level = await _reader.levelPercent();
      final charging = await _reader.isCharging();
      final previousLevel = _levelPercent;
      final previousProfile = _manager.profile;
      _levelPercent = level;
      _charging = charging;
      _manager.update(level, charging: charging);
      if (level != previousLevel || _manager.profile != previousProfile) {
        notifyListeners();
      }
    } on Exception {
      return;
    }
  }
}
