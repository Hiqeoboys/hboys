import 'dart:async';

import '../../core/utils/clock.dart';
import '../../features/tracking/application/recording_session.dart';
import '../../features/tracking/application/tracking_backend.dart';
import '../../features/tracking/application/tracking_runtime.dart';
import '../../features/tracking/application/tracking_status.dart';
import '../../features/tracking/domain/tracking_repository.dart';
import '../location/geolocator_tracking_source.dart';
import '../power/device_battery_reader.dart';

/// iOS tidak memakai TaskHandler: background location membuat isolate utama
/// tetap hidup saat layar terkunci. Sesi tetap ditulis ke DB yang sama.
class IosLocalTrackingBackend implements TrackingBackend {
  IosLocalTrackingBackend({
    required TrackingRepository repository,
    Clock clock = const SystemClock(),
  })  : _repository = repository,
        _clock = clock;

  final TrackingRepository _repository;
  final Clock _clock;
  final StreamController<TrackingEvent> _events =
      StreamController<TrackingEvent>.broadcast();

  TrackingRuntime? _runtime;
  TrackingStatus? _lastStatus;

  @override
  Stream<TrackingEvent> get events => _events.stream;

  @override
  Future<bool> isRunning() async => _runtime != null;

  @override
  Future<void> start() async {
    if (_runtime != null) {
      await requestStatus();
      return;
    }
    final recording = await openOrStartRecordingSession(
      repository: _repository,
      clock: _clock,
    );
    final runtime = TrackingRuntime(
      recording: recording,
      location: const GeolocatorTrackingSource(),
      battery: DeviceBatteryReader(),
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
