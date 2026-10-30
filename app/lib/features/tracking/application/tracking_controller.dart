import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/utils/clock.dart';
import '../../onboarding/permission_service.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_connection.dart';
import '../../../infrastructure/database/repositories/drift_tracking_repository.dart';
import '../../../infrastructure/tracking/android_foreground_tracking_backend.dart';
import '../../../infrastructure/tracking/ios_local_tracking_backend.dart';
import '../domain/track_point.dart';
import '../domain/tracking_repository.dart';
import '../domain/tracking_session.dart';
import 'tracking_backend.dart';
import 'tracking_status.dart';

enum TrackingPhase {
  uninitialized,
  initializing,
  idle,
  preparing,
  recording,
  stopping,
  finished,
  error,
}

/// Pengendali tunggal untuk layar rekam. Dibuat sekali agar rekaman iOS tidak
/// berhenti ketika pengguna berpindah layar.
class TrackingController extends ChangeNotifier {
  TrackingController._();

  static final TrackingController instance = TrackingController._();

  TrackingPhase _phase = TrackingPhase.uninitialized;
  TrackingStatus? _status;
  PermissionReport? _permission;
  String? _error;
  String? _notice;
  bool _initialized = false;
  bool _recoveryPending = false;
  Future<void>? _initializationFuture;

  AppDatabase? _database;
  TrackingRepository? _repository;
  TrackingBackend? _backend;
  StreamSubscription<TrackingEvent>? _events;
  final Clock _clock = const SystemClock();

  TrackingPhase get phase => _phase;
  TrackingStatus? get status => _status;
  PermissionReport? get permission => _permission;
  String? get error => _error;
  String? get notice => _notice;
  bool get isRecording =>
      _phase == TrackingPhase.recording || _phase == TrackingPhase.preparing;
  bool get isBusy =>
      _phase == TrackingPhase.initializing ||
      _phase == TrackingPhase.preparing ||
      _phase == TrackingPhase.stopping;
  bool get recoveryPending => _recoveryPending;

  String? get currentSessionId => _status?.sessionId;

  /// Titik sesi yang sedang ditampilkan peta. Kosong bila belum ada sesi.
  Future<List<TrackPoint>> currentTrackPoints() async {
    final sessionId = _status?.sessionId;
    final repository = _repository;
    if (sessionId == null || repository == null) return const [];
    return repository.points(sessionId);
  }

  Future<TrackPoint?> latestRecordedPoint() async {
    final sessionId = _status?.sessionId;
    final repository = _repository;
    if (sessionId == null || repository == null) return null;
    return repository.latestPoint(sessionId);
  }

  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initializationFuture ??= _initializeOnce();
  }

  Future<void> _initializeOnce() async {
    _phase = TrackingPhase.initializing;
    notifyListeners();
    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        throw UnsupportedError('Pelacakan GPS hanya untuk Android/iOS.');
      }
      final file = await defaultAppDatabaseFile();
      _database = openAppDatabase(file);
      final repository = DriftTrackingRepository(_database!);
      _repository = repository;
      _permission = await const PermissionService().check();

      final backend = Platform.isAndroid
          ? AndroidForegroundTrackingBackend(databasePath: file.path)
          : IosLocalTrackingBackend(
              repository: repository,
              clock: const SystemClock(),
            );
      _backend = backend;
      _events = backend.events.listen(_onEvent);

      final active = await repository.findActiveSession();
      final running = await backend.isRunning();
      if (running) {
        _phase = TrackingPhase.preparing;
        await backend.requestStatus();
      } else if (active != null) {
        _recoveryPending = true;
        if (_permission!.readyForBackground) {
          await _startBackend(auto: true);
        } else {
          _notice =
              'Sesi aktif ditemukan. Lengkapi izin "Selalu" agar rekaman dapat dilanjutkan.';
          _phase = TrackingPhase.idle;
        }
      } else {
        _phase = TrackingPhase.idle;
      }
      _initialized = true;
    } catch (error) {
      _phase = TrackingPhase.error;
      _error = 'Gagal menyiapkan rekaman: $error';
    } finally {
      notifyListeners();
    }
  }

  Future<bool> start() async {
    await initialize();
    if (isRecording || _phase == TrackingPhase.stopping) return false;
    final permission = await const PermissionService().check();
    _permission = permission;
    if (!permission.readyForBackground) {
      _notice =
          'Izin lokasi "Selalu", lokasi presisi, layanan lokasi, dan notifikasi perlu diaktifkan.';
      _phase = TrackingPhase.idle;
      notifyListeners();
      return false;
    }
    return _startBackend();
  }

  Future<bool> _startBackend({bool auto = false}) async {
    final backend = _backend;
    if (backend == null) return false;
    _error = null;
    _phase = TrackingPhase.preparing;
    notifyListeners();
    try {
      await backend.start();
      _recoveryPending = false;
      if (auto) {
        _notice = 'Melanjutkan sesi yang belum selesai...';
      }
      return true;
    } catch (error) {
      _phase = TrackingPhase.error;
      _error = 'Gagal memulai rekaman: $error';
      notifyListeners();
      return false;
    }
  }

  Future<void> stop() async {
    final backend = _backend;
    if (backend == null) return;
    if (_phase == TrackingPhase.stopping) return;
    _phase = TrackingPhase.stopping;
    notifyListeners();
    try {
      final result = await backend.stop();
      final closedOrphan = await _closeActiveSessionIfAny();
      _phase = TrackingPhase.finished;
      final notes = <String>[
        if (result.warning != null) result.warning!,
        if (closedOrphan)
          'Sesi aktif ditutup dari data tersimpan karena layanan tidak '
              'mengonfirmasi selesai.',
      ];
      _notice = notes.isEmpty ? null : notes.join(' ');
      if (_status?.sessionStatus == TrackingSessionStatus.active) {
        _status = TrackingStatus(
          sessionId: _status!.sessionId,
          sessionStatus: TrackingSessionStatus.completed,
          startedAtUtc: _status!.startedAtUtc,
          distanceM: _status!.distanceM,
          movingSeconds: _status!.movingSeconds,
          elapsedSeconds: _status!.elapsedSeconds,
          elevationGainM: _status!.elevationGainM,
          elevationLossM: _status!.elevationLossM,
          isMoving: false,
          pointCount: _status!.pointCount,
          profile: _status!.profile,
          paceSecPerKm: _status!.paceSecPerKm,
          verticalSpeedMph: _status!.verticalSpeedMph,
          batteryPercent: _status!.batteryPercent,
        );
      }
    } catch (error) {
      _phase = TrackingPhase.error;
      _error = 'Gagal menghentikan rekaman: $error';
    }
    notifyListeners();
  }

  Future<bool> _closeActiveSessionIfAny() async {
    final repository = _repository;
    if (repository == null) return false;
    final active = await repository.findActiveSession();
    if (active == null) return false;
    await repository.saveSession(
      active.copyWith(
        endedAtUtc: _clock.nowUtc(),
        status: TrackingSessionStatus.completed,
      ),
    );
    return true;
  }

  /// Dipanggil setelah halaman onboarding ditutup atau aplikasi kembali aktif.
  Future<void> refreshPermissionsAndResume() async {
    if (!_initialized) {
      await initialize();
      return;
    }
    _permission = await const PermissionService().check();
    final backend = _backend;
    if (backend == null) return;
    final running = await backend.isRunning();
    if (!running && _phase == TrackingPhase.recording) {
      final active = await _repository?.findActiveSession();
      if (active == null) {
        _phase = TrackingPhase.finished;
        _recoveryPending = false;
        _notice = 'Layanan latar sudah berhenti dan tidak ada sesi aktif.';
      } else {
        _recoveryPending = true;
        if (_permission!.readyForBackground) {
          await _startBackend(auto: true);
        } else {
          _phase = TrackingPhase.idle;
          _notice = 'Layanan latar berhenti. Lengkapi izin agar sesi aktif '
              'dapat dilanjutkan.';
        }
      }
    } else if (!running && _recoveryPending) {
      if (_permission!.readyForBackground) {
        await _startBackend(auto: true);
      }
    }
    notifyListeners();
  }

  Future<bool> openPermissionSettings() async {
    final opened = await const PermissionService().openSettings();
    _permission = await const PermissionService().check();
    notifyListeners();
    return opened;
  }

  void _onEvent(TrackingEvent event) {
    switch (event) {
      case TrackingProgressEvent(:final status):
        _status = status;
        _phase = status.sessionStatus == TrackingSessionStatus.completed
            ? TrackingPhase.finished
            : TrackingPhase.recording;
        _error = null;
      case TrackingStoppedEvent(:final status, :final warning):
        if (status != null) _status = status;
        _phase = TrackingPhase.finished;
        _notice = warning;
      case TrackingFailureEvent(:final message, :final fatal):
        _error = message;
        _phase = fatal ? TrackingPhase.error : _phase;
        if (fatal) unawaited(_abortServiceAfterFailure());
    }
    notifyListeners();
  }

  Future<void> _abortServiceAfterFailure() async {
    try {
      await _backend?.stop();
    } catch (_) {
      // Pesan kegagalan utama sudah ditampilkan; kegagalan pembersihan tidak
      // boleh menutupinya.
    }
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    unawaited(_backend?.dispose());
    unawaited(_database?.close());
    super.dispose();
  }
}
