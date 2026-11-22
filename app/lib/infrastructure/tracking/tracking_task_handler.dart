import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../features/tracking/application/recording_session.dart';
import '../../../features/tracking/application/tracking_backend.dart';
import '../../../features/tracking/application/tracking_runtime.dart';
import '../../../features/tracking/application/tracking_status.dart';
import '../../../features/tracking/domain/tracking_session.dart';
import '../../core/utils/clock.dart';
import '../database/app_database.dart';
import '../database/database_connection.dart';
import '../database/repositories/drift_tracking_repository.dart';
import '../location/location_source.dart';
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
  Timer? _logTimer;
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

    final rawActivityType = await FlutterForegroundTask.getData<String>(
      key: TrackingTaskProtocol.activityTypeKey,
    );
    final activityType = TrackingSession.normalizeActivityType(rawActivityType);
    final rawOwnerUserId = await FlutterForegroundTask.getData<String>(
      key: TrackingTaskProtocol.ownerUserIdKey,
    );
    final ownerUserId =
        (rawOwnerUserId != null && rawOwnerUserId.trim().isNotEmpty)
            ? rawOwnerUserId.trim()
            : null;

    try {
      _database = openAppDatabase(File(path));
      final repository = DriftTrackingRepository(
        _database!,
        ownerUserIdProvider: () => ownerUserId,
      );
      const location = RealLocationSource();
      final access = await location.checkAccess();
      if (access != TrackingAccess.granted) {
        await _failStart(TrackingAccessException(access).message);
        return;
      }

      final recording = await openOrStartRecordingSession(
        repository: repository,
        clock: _clock,
        activityType: activityType,
        ownerUserId: ownerUserId,
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
      _startDebugLog();
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

  /// Log ringkas tiap 5 detik ke konsol (hanya build debug): hitungan fix
  /// diterima/ditolak beserta alasannya, fix terakhir, dan umurnya.
  void _startDebugLog() {
    if (!kDebugMode) return;
    _logTimer?.cancel();
    _logTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final diag = _lastStatus?.diagnostics;
      if (diag == null || diag.received == 0) {
        debugPrint('[GPS] belum ada fix dari penyedia lokasi');
        return;
      }
      final at = diag.lastReceivedAtUtc;
      final age =
          at == null ? '-' : '${_clock.nowUtc().difference(at).inSeconds}';
      debugPrint('[GPS] ${diag.summary()} umur=${age}s');
    });
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
      notificationTitle: status.isPaused
          ? 'Rekaman dijeda'
          : (status.isJogging ? 'Merekam jogging' : 'Merekam pendakian'),
      notificationText: status.isPaused
          ? 'Jeda • ${_distanceText(status.distanceM)} • ${_durationText(status.elapsedSeconds)}'
          : '${_distanceText(status.distanceM)} • ${_durationText(status.elapsedSeconds)} • ${status.profile.name}',
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
    } else if (command == TrackingTaskProtocol.pauseCommand) {
      unawaited(_setPaused(true));
    } else if (command == TrackingTaskProtocol.resumeCommand) {
      unawaited(_setPaused(false));
    } else if (command == TrackingTaskProtocol.statusCommand) {
      _sendStatus(TrackingTaskProtocol.updateType);
    }
  }

  Future<void> _setPaused(bool paused) async {
    final runtime = _runtime;
    if (runtime == null) return;
    if (paused) {
      await runtime.pause();
    } else {
      await runtime.resume();
    }
    await _updateNotification(force: true);
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
    _logTimer?.cancel();
    _logTimer = null;
    await _runtime?.suspend();
    await _database?.close();
    _database = null;
    _runtime = null;
  }
}
