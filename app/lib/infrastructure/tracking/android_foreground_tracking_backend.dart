import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../features/tracking/application/tracking_backend.dart';
import '../../features/tracking/application/tracking_status.dart';
import 'tracking_foreground_service.dart';
import 'tracking_task_handler.dart';

class AndroidForegroundTrackingBackend implements TrackingBackend {
  AndroidForegroundTrackingBackend({required this.databasePath}) {
    TrackingForegroundService.initialize();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  final String databasePath;
  final StreamController<TrackingEvent> _events =
      StreamController<TrackingEvent>.broadcast();

  Completer<TrackingStoppedEvent?>? _stopCompleter;
  TrackingStatus? _lastStatus;

  @override
  Stream<TrackingEvent> get events => _events.stream;

  @override
  Future<bool> isRunning() => FlutterForegroundTask.isRunningService;

  @override
  Future<void> start() async {
    if (await isRunning()) {
      await requestStatus();
      return;
    }
    final saved = await FlutterForegroundTask.saveData(
      key: TrackingTaskProtocol.databasePathKey,
      value: databasePath,
    );
    if (!saved) {
      throw StateError('Gagal menyimpan lokasi database untuk layanan latar.');
    }
    final result = await FlutterForegroundTask.startService(
      serviceId: 4101,
      serviceTypes: const [ForegroundServiceTypes.location],
      notificationTitle: 'Merekam pendakian',
      notificationText: 'Menyiapkan GPS...',
      notificationButtons: const [
        NotificationButton(id: 'stop', text: 'Hentikan'),
      ],
      callback: trackingTaskCallback,
    );
    if (result is ServiceRequestFailure) {
      throw result.error;
    }
  }

  @override
  Future<TrackingStopResult> stop() async {
    if (!await isRunning()) {
      return const TrackingStopResult(clean: true);
    }
    final completer = Completer<TrackingStoppedEvent?>();
    _stopCompleter = completer;
    FlutterForegroundTask.sendDataToTask({
      TrackingTaskProtocol.commandKey: TrackingTaskProtocol.stopCommand,
    });

    TrackingStoppedEvent? stopped;
    try {
      stopped = await completer.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      stopped = null;
    } finally {
      _stopCompleter = null;
    }

    // TaskHandler sudah memanggil stopService sendiri setelah mengirim
    // `stopped`. Memanggil stopService lagi dari sini balapan dengan penutupan
    // itu dan gagal dengan ServiceNotStartedException.
    if (stopped == null && await isRunning()) {
      final result = await FlutterForegroundTask.stopService();
      if (result is ServiceRequestFailure &&
          !_isAlreadyStopped(result.error)) {
        throw result.error;
      }
    }
    return TrackingStopResult(
      clean: stopped != null,
      warning: stopped == null
          ? 'Layanan tidak mengonfirmasi sesi selesai. Periksa status sesi.'
          : stopped.warning,
    );
  }

  @override
  Future<void> pause() async {
    if (!await isRunning()) return;
    FlutterForegroundTask.sendDataToTask({
      TrackingTaskProtocol.commandKey: TrackingTaskProtocol.pauseCommand,
    });
  }

  @override
  Future<void> resume() async {
    if (!await isRunning()) return;
    FlutterForegroundTask.sendDataToTask({
      TrackingTaskProtocol.commandKey: TrackingTaskProtocol.resumeCommand,
    });
  }

  @override
  Future<void> requestStatus() async {
    if (!await isRunning()) return;
    FlutterForegroundTask.sendDataToTask({
      TrackingTaskProtocol.commandKey: TrackingTaskProtocol.statusCommand,
    });
  }

  void _onTaskData(Object data) {
    if (data is! Map) return;
    final type = data['type'];
    try {
      if (type == TrackingTaskProtocol.startedType ||
          type == TrackingTaskProtocol.updateType) {
        final status = TrackingStatus.fromMap(data);
        _lastStatus = status;
        _events.add(
          TrackingProgressEvent(
            status,
            started: type == TrackingTaskProtocol.startedType,
          ),
        );
      } else if (type == TrackingTaskProtocol.stoppedType) {
        final status = data.containsKey('sessionId')
            ? TrackingStatus.fromMap(data)
            : _lastStatus;
        final event = TrackingStoppedEvent(status: status);
        _stopCompleter?.complete(event);
        _events.add(event);
      } else if (type == TrackingTaskProtocol.errorType) {
        _events.add(
          TrackingFailureEvent(
            data['message'] as String? ?? 'Kesalahan rekaman tidak diketahui.',
            fatal: data['fatal'] == true,
          ),
        );
      }
    } on FormatException catch (error) {
      _events.add(TrackingFailureEvent('Pesan layanan tidak valid: $error'));
    }
  }

  @override
  Future<void> dispose() async {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    await _events.close();
  }

  bool _isAlreadyStopped(Object error) =>
      error is ServiceNotStartedException ||
      (error is PlatformException && error.code == 'ServiceNotStartedException');
}
