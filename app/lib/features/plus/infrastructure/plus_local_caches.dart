import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/clock.dart';
import '../domain/cloud_backup.dart';
import '../domain/route_weather.dart';

/// Cache prakiraan per rute. Kunci memakai base64url nama rute agar nama
/// berspasi atau berkarakter Indonesia tidak bentrok.
class SharedPreferencesRouteWeatherCache implements RouteWeatherCache {
  const SharedPreferencesRouteWeatherCache();

  static const String keyPrefix = 'plus_route_weather_v1_';

  String _key(String routeName) =>
      '$keyPrefix${base64Url.encode(utf8.encode(routeName))}';

  @override
  Future<RouteWeatherForecast?> read(String routeName) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key(routeName));
    if (raw == null) return null;
    try {
      return RouteWeatherForecast.tryParse(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(RouteWeatherForecast forecast) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key(forecast.routeName),
      jsonEncode(forecast.toJson()),
    );
  }
}

class InMemoryRouteWeatherCache implements RouteWeatherCache {
  final Map<String, RouteWeatherForecast> entries =
      <String, RouteWeatherForecast>{};
  int writes = 0;

  @override
  Future<RouteWeatherForecast?> read(String routeName) async =>
      entries[routeName];

  @override
  Future<void> write(RouteWeatherForecast forecast) async {
    entries[forecast.routeName] = forecast;
    writes++;
  }
}

/// Menyimpan pilihan cadangan dan kode pemulihan di perangkat.
///
/// Belum ada server: [CloudBackupState.connected] tetap false dan waktu
/// cadangan terakhir tidak pernah diisi oleh implementasi ini.
class SharedPreferencesCloudBackupRepository implements CloudBackupRepository {
  SharedPreferencesCloudBackupRepository({
    this.deviceName = 'Perangkat ini',
    Clock clock = const SystemClock(),
    math.Random? random,
  })  : _clock = clock,
        _random = random ?? math.Random.secure();

  static const String key = 'plus_cloud_backup_v1';

  final String deviceName;
  final Clock _clock;
  final math.Random _random;

  @override
  Future<CloudBackupState> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(key);
    if (raw != null) {
      try {
        final parsed = CloudBackupState.tryParse(
          jsonDecode(raw),
          fallbackCode: _newRecoveryCode(),
        );
        if (parsed != null) {
          final withDevice = _withCurrentDevice(parsed);
          if (withDevice.devices.length != parsed.devices.length) {
            await _write(preferences, withDevice);
          }
          return withDevice;
        }
      } on FormatException {
        // Kode lama yang rusak diganti di bawah.
      }
    }
    final state = CloudBackupState(
      autoBackup: false,
      recoveryCode: _newRecoveryCode(),
      devices: <BackupDevice>[_currentDevice()],
      connected: false,
    );
    await _write(preferences, state);
    return state;
  }

  @override
  Future<CloudBackupState> setAutoBackup(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    final current = await load();
    final next = current.copyWith(autoBackup: enabled);
    await _write(preferences, next);
    return next;
  }

  CloudBackupState _withCurrentDevice(CloudBackupState state) {
    if (state.devices.any((device) => device.current)) return state;
    return state.copyWith(
      devices: <BackupDevice>[...state.devices, _currentDevice()],
    );
  }

  BackupDevice _currentDevice() => BackupDevice(
        name: deviceName,
        lastActiveUtc: _clock.nowUtc(),
        current: true,
      );

  Future<void> _write(
    SharedPreferences preferences,
    CloudBackupState state,
  ) async {
    await preferences.setString(key, jsonEncode(state.toJson()));
  }

  /// Kode 16 karakter dalam empat kelompok; tanpa huruf/angka yang mudah
  /// tertukar (0/O, 1/I).
  String _newRecoveryCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final buffer = StringBuffer();
    for (var group = 0; group < 4; group++) {
      if (group > 0) buffer.write('-');
      for (var i = 0; i < 4; i++) {
        buffer.write(alphabet[_random.nextInt(alphabet.length)]);
      }
    }
    return buffer.toString();
  }
}

class InMemoryCloudBackupRepository implements CloudBackupRepository {
  InMemoryCloudBackupRepository(this.state);

  CloudBackupState state;
  int writes = 0;

  @override
  Future<CloudBackupState> load() async => state;

  @override
  Future<CloudBackupState> setAutoBackup(bool enabled) async {
    state = state.copyWith(autoBackup: enabled);
    writes++;
    return state;
  }
}
