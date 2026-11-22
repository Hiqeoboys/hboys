import 'dart:async';

import '../../core/utils/clock.dart';
import '../../features/tracking/application/recording_session.dart';
import '../../features/tracking/application/tracking_backend.dart';
import '../../features/tracking/application/tracking_runtime.dart';
import '../../features/tracking/application/tracking_status.dart';
import '../../features/tracking/domain/tracking_repository.dart';
import '../../features/tracking/domain/tracking_session.dart';
import '../auth/active_account_scope.dart';
import '../location/location_source.dart';
import '../power/device_battery_reader.dart';

/// iOS tidak memakai TaskHandler: background location membuat isolate utama
/// tetap hidup saat layar terkunci. Sesi tetap ditulis ke DB yang sama.
/// Juga dipakai saat mode simulasi debug diaktifkan agar sumber lokasi simulasi
/// dapat dikendalikan langsung dari UI melalui kode tracking yang sama.
class IosLocalTrackingBackend implements TrackingBackend {
  IosLocalTrackingBackend({
    required TrackingRepository repository,
    Clock clock = const SystemClock(),
    LocationSource locationSource = const RealLocationSource(),
    BatteryReader? batteryReader,
  })  : _repository = repository,
        _clock = clock,
        _locationSource = locationSource,
        _batteryReader = batteryReader;

  final TrackingRepository _repository;
  final Clock _clock;
  final LocationSource _locationSource;
  final BatteryReader? _batteryReader;
  final StreamController<TrackingEvent> _events =
      StreamController<TrackingEvent>.broadcast();

  TrackingRuntime? _runtime;
  TrackingStatus? _lastStatus;

  @override
  Stream<TrackingEvent> get events => _events.stream;

  @override
  Future<bool> isRunning() async => _runtime != null;

  @override
  Future<void> start({
    String activityType = TrackingSession.activityHiking,
  }) async {
    if (_runtime != null) {
      await requestStatus();
      return;
    }
    final recording = await openOrStartRecordingSession(
      repository: _repository,
      clock: _clock,
      activityType: TrackingSession.normalizeActivityType(activityType),
      ownerUserId: ActiveAccountScope.currentUserId(),
    );
    final runtime = TrackingRuntime(
      recording: recording,
      location: _locationSource,
      battery: _batteryReader ?? DeviceBatteryReader(),
      onUpdate: (update) {
        final status = TrackingStatus.fromRuntimeUpdate(update);
        _lastStatus = status;
        _events.add(TrackingProgressEvent(status));
      },
      onError: (error) {
        _events.add(TrackingFailureEvent(error.message, fatal: error.fatal));
      },
    );
    await runtime.start();
    _runtime = runtime;
  }

  @override
  Future<TrackingStopResult> stop() async {
    final runtime = _runtime;
    if (runtime == null) return const TrackingStopResult(clean: true);
    await runtime.stop();
    _runtime = null;
    final status = _lastStatus;
    final event = TrackingStoppedEvent(status: status);
    _events.add(event);
    return const TrackingStopResult(clean: true);
  }

  @override
  Future<void> pause() async {
    await _runtime?.pause();
  }

  @override
  Future<void> resume() async {
    await _runtime?.resume();
  }

  /// Menghapus titik pada runtime sesi saat ini (khusus pengujian/skenario debug).
  void clearCurrentPoints() {
    _runtime?.clearPoints();
  }

  @override
  Future<void> requestStatus() async {
    final status = _lastStatus;
    if (status != null) {
      _events.add(TrackingProgressEvent(status));
    }
  }

  @override
  Future<void> dispose() async {
    await _runtime?.suspend();
    _runtime = null;
    await _events.close();
  }
}
