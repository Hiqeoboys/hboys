import 'dart:async';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../features/tracking/application/recording_session.dart';
import '../../../features/tracking/application/tracking_backend.dart';
import '../../../features/tracking/application/tracking_runtime.dart';
import '../../../features/tracking/application/tracking_status.dart';
import '../../core/utils/clock.dart';
import '../database/app_database.dart';
import '../database/database_connection.dart';
import '../database/repositories/drift_tracking_repository.dart';
import '../location/geolocator_tracking_source.dart';
import '../power/device_battery_reader.dart';

/// Titik masuk isolate latar Android. Harus top-level dan punya entry point.
@pragma('vm:entry-point')
void trackingTaskCallback() {
  FlutterForegroundTask.setTaskHandler(TrackingTaskHandler());
}

class TrackingTaskHandler extends TaskHandler {
  AppDatabase? _database;
  TrackingRuntime? _runtime;
  TrackingStatus? _lastStatus;
  bool _stopping = false;
  DateTime? _lastNotificationAt;
  final Clock _clock = const SystemClock();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final path = await FlutterForegroundTask.getData<String>(
      key: TrackingTaskProtocol.databasePathKey,
    );
    if (path == null) {
      await _failStart('Lokasi database rekaman tidak ditemukan.');
      return;
    }

    try {
      _database = openAppDatabase(File(path));
      final repository = DriftTrackingRepository(_database!);
      const location = GeolocatorTrackingSource();
      final access = await location.checkAccess();
      if (access != TrackingAccess.granted) {
        await _failStart(TrackingAccessException(access).message);
        return;
      }

      final recording = await openOrStartRecordingSession(
        repository: repository,
        clock: _clock,
      );
      final runtime = TrackingRuntime(
        recording: recording,
        location: location,
        battery: DeviceBatteryReader(),
        onUpdate: _onUpdate,
        onError: (error) => _sendError(error.message, fatal: error.fatal),
      );
      _runtime = runtime;
      await runtime.start();
      _sendStatus(TrackingTaskProtocol.startedType);
      await _updateNotification(force: true);
    } catch (error) {
      await _failStart('Gagal memulai rekaman: $error');
    }
  }

  void _onUpdate(TrackingRuntimeUpdate update) {
    _lastStatus = TrackingStatus.fromRuntimeUpdate(update);
    _sendStatus(TrackingTaskProtocol.updateType);
    unawaited(_updateNotification());
  }

  void _sendStatus(String type) {
    final status = _lastStatus;
    if (status == null) return;
    FlutterForegroundTask.sendDataToMain(status.toMap(type));
  }

  void _sendError(String message, {bool fatal = false}) {
    FlutterForegroundTask.sendDataToMain({
      'type': TrackingTaskProtocol.errorType,
      'message': message,
      'fatal': fatal,
    });
  }

  Future<void> _failStart(String message) async {
    _sendError(message, fatal: true);
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Rekaman tidak dapat dimulai',
      notificationText: message,
    );
  }

  Future<void> _updateNotification({bool force = false}) async {
    final status = _lastStatus;
    if (status == null) return;
    final now = _clock.nowUtc();
    final last = _lastNotificationAt;
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(seconds: 30)) {
      return;
    }
    _lastNotificationAt = now;
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Merekam pendakian',
      notificationText:
          '${_distanceText(status.distanceM)} • ${_durationText(status.elapsedSeconds)} • ${status.profile.name}',
    );
  }

  String _distanceText(double meters) =>
      '${(meters / 1000).toStringAsFixed(2)} km';

  String _durationText(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h}j ${m.toString().padLeft(2, '0')}m';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    final command = data[TrackingTaskProtocol.commandKey];
    if (command == TrackingTaskProtocol.stopCommand) {
      unawaited(_finishAndStopService());
    } else if (command == TrackingTaskProtocol.statusCommand) {
      _sendStatus(TrackingTaskProtocol.updateType);
    }
  }

  Future<void> _finishAndStopService() async {
    if (_stopping) return;
    _stopping = true;
    try {
      await _runtime?.stop();
      final status = _lastStatus;
      FlutterForegroundTask.sendDataToMain(
        status?.toMap(TrackingTaskProtocol.stoppedType) ??
            {'type': TrackingTaskProtocol.stoppedType},
      );
      await FlutterForegroundTask.stopService();
    } catch (error) {
      _sendError('Gagal menghentikan rekaman: $error', fatal: true);
    } finally {
      _stopping = false;
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') {
      unawaited(_finishAndStopService());
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _runtime?.suspend();
    await _database?.close();
    _database = null;
    _runtime = null;
  }
}
