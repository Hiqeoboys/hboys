import 'dart:async';

import '../../../infrastructure/power/power_profile_manager.dart';
import '../domain/track_point.dart';
import '../domain/tracking_engine.dart';
import '../domain/tracking_session.dart';
import 'recording_session.dart';

enum TrackingAccess {
  granted,
  whileInUse,
  denied,
  deniedForever,
  unableToDetermine,
  serviceDisabled,
}

class TrackingAccessException implements Exception {
  const TrackingAccessException(this.access);

  final TrackingAccess access;

  String get message => switch (access) {
        TrackingAccess.granted => 'Izin lokasi tersedia.',
        TrackingAccess.whileInUse =>
          'Izin lokasi harus "Selalu" agar rekaman berjalan di latar belakang.',
        TrackingAccess.denied => 'Izin lokasi belum diberikan.',
        TrackingAccess.deniedForever =>
          'Izin lokasi ditolak permanen. Buka pengaturan aplikasi.',
        TrackingAccess.unableToDetermine =>
          'Status izin lokasi tidak diketahui.',
        TrackingAccess.serviceDisabled => 'Layanan lokasi perangkat dimatikan.',
      };

  @override
  String toString() => message;
}

abstract interface class TrackingLocationSource {
  Future<TrackingAccess> checkAccess();
  Stream<TrackPoint> positions(PowerProfileConfig config);
}

abstract interface class BatteryReader {
  Future<int> levelPercent();
  Future<bool> isCharging();
}

class TrackingRuntimeUpdate {
  const TrackingRuntimeUpdate({
    required this.session,
    required this.snapshot,
    required this.pointCount,
    required this.profile,
    required this.batteryPercent,
    required this.isPaused,
  });

  final TrackingSession session;
  final TrackingSnapshot? snapshot;
  final int pointCount;
  final PowerProfile profile;
  final int? batteryPercent;
  final bool isPaused;
}

class TrackingRuntimeError {
  const TrackingRuntimeError(this.message, {this.fatal = false});

  final String message;
  final bool fatal;
}

/// Menjalankan aliran GPS, menulis tiap fix lewat [RecordingSession], dan
/// menyesuaikan interval/akurasi GPS ketika profil daya berubah.
class TrackingRuntime {
  TrackingRuntime({
    required RecordingSession recording,
    required TrackingLocationSource location,
    required BatteryReader battery,
    required void Function(TrackingRuntimeUpdate update) onUpdate,
    required void Function(TrackingRuntimeError error) onError,
    PowerProfileManager? power,
    this.batteryPollInterval = const Duration(minutes: 1),
  })  : _recording = recording,
        _location = location,
        _battery = battery,
        _onUpdate = onUpdate,
        _onError = onError,
        _power = power ?? PowerProfileManager();

  final RecordingSession _recording;
  final TrackingLocationSource _location;
  final BatteryReader _battery;
  final void Function(TrackingRuntimeUpdate update) _onUpdate;
  final void Function(TrackingRuntimeError error) _onError;
  final PowerProfileManager _power;
  final Duration batteryPollInterval;

  StreamSubscription<TrackPoint>? _subscription;
  Timer? _batteryTimer;
  Future<void> _fixQueue = Future<void>.value();
  int? _batteryPercent;
  bool _started = false;
  bool _stopped = false;
  bool _paused = false;

  PowerProfile get profile => _power.profile;
  TrackingSession get session => _recording.session;
  bool get isPaused => _paused;

  Future<void> start() async {
    if (_started) return;
    final access = await _location.checkAccess();
    if (access != TrackingAccess.granted) {
      throw TrackingAccessException(access);
    }
    await _refreshBattery();
    _started = true;
    await _startLocation();
    _batteryTimer = Timer.periodic(
      batteryPollInterval,
      (_) => unawaited(_refreshBattery()),
    );
    _emit();
  }

  Future<void> _startLocation() async {
    await _subscription?.cancel();
    final config = PowerProfileConfig.of(_power.profile);
    _subscription = _location.positions(config).listen(
      _enqueueFix,
      onError: (Object error) {
        _onError(
            TrackingRuntimeError('Aliran GPS berhenti: $error', fatal: true));
      },
    );
  }

  void _enqueueFix(TrackPoint point) {
    _fixQueue = _fixQueue.then((_) async {
      try {
        final snapshot = await _recording.onFix(point);
        if (snapshot != null) _emit();
      } catch (error) {
        _onError(TrackingRuntimeError('Gagal menyimpan titik GPS: $error',
            fatal: true));
      }
    });
  }

  Future<void> _refreshBattery() async {
    try {
      final level = await _battery.levelPercent();
      final charging = await _battery.isCharging();
      _batteryPercent = level;
      final before = _power.profile;
      final after = _power.update(level, charging: charging);
      if (_started && !_paused && after != before) {
        await _startLocation();
        _emit();
      }
    } catch (error) {
      _onError(TrackingRuntimeError('Gagal membaca baterai: $error'));
    }
  }

  /// Menghentikan aliran GPS tanpa menutup sesi. Waktu bergerak tidak
  /// bertambah karena celah antar titik melebihi [AutoPauseDetector.maxGap].
  Future<void> pause() async {
    if (!_started || _stopped || _paused) return;
    _paused = true;
    await _subscription?.cancel();
    _subscription = null;
    _emit();
  }

  Future<void> resume() async {
    if (!_started || _stopped || !_paused) return;
    _paused = false;
    await _startLocation();
    _emit();
  }

  Future<TrackingSession> stop() async {
    if (_stopped) return _recording.session;
    _stopped = true;
    _batteryTimer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    await _fixQueue;
    final finished = await _recording.finish();
    _emit();
    return finished;
  }

  /// Menghentikan sumber daya tanpa menyelesaikan sesi. Dipakai ketika proses
  /// layanan dimatikan; sesi tetap aktif untuk dipulihkan.
  Future<void> suspend() async {
    if (_stopped) return;
    _stopped = true;
    _batteryTimer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    await _fixQueue;
  }

  void _emit() {
    try {
      _onUpdate(
        TrackingRuntimeUpdate(
          session: _recording.session,
          snapshot: _recording.snapshot,
          pointCount: _recording.pointCount,
          profile: _power.profile,
          batteryPercent: _batteryPercent,
          isPaused: _paused,
        ),
      );
    } catch (_) {
      // Callback UI/task tidak boleh menghentikan penulisan titik.
    }
  }
}
