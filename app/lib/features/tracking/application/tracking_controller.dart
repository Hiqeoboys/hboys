import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/utils/clock.dart';
import '../../onboarding/permission_service.dart';
import '../../../infrastructure/auth/active_account_scope.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_connection.dart';
import '../../../infrastructure/database/repositories/drift_tracking_repository.dart';
import '../../../infrastructure/location/location_source.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../../plus/domain/cloud_backup_bundle.dart';
import '../../plus/infrastructure/supabase_cloud_backup_service.dart';
import '../../preparation/application/packing_list_store.dart';
import '../../../infrastructure/tracking/android_foreground_tracking_backend.dart';
import '../../../infrastructure/tracking/ios_local_tracking_backend.dart';
import '../../trails/data/gpx_loader.dart';
import '../../trails/domain/track_route.dart';
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
  paused,
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
  TrackingBackend? _realBackend;
  TrackingBackend? _simulationBackend;
  StreamSubscription<TrackingEvent>? _events;
  final Clock _clock = const SystemClock();

  bool _simulationEnabled = false;
  String _simulationRouteAsset = GpxLoader.defaultGpxAssetPath;
  SimulatedLocationSource? _simulatedLocationSource;

  String? _activeMountainName;
  String? _activeTrailName;
  String? _activeTrailId;
  String? _activeGroupId;
  String _activeActivityType = TrackingSession.activityHiking;

  String? get activeMountainName => _activeMountainName;
  String? get activeTrailName => _activeTrailName;
  String? get activeTrailId => _activeTrailId;
  String? get activeGroupId => _activeGroupId;
  String get activeActivityType => _status?.activityType ?? _activeActivityType;
  bool get isJoggingSession =>
      activeActivityType == TrackingSession.activityJogging;

  /// Menetapkan gunung, jalur, dan grup opsional yang sedang didaki agar
  /// tercatat di Riwayat, disinkronkan ke Supabase, serta mengarahkan mode SOS.
  void setActiveRoute({
    String? mountainName,
    String? trailName,
    String? trailId,
    String? groupId,
  }) {
    _activeActivityType = TrackingSession.activityHiking;
    _activeMountainName = mountainName;
    _activeTrailName = trailName;
    _activeTrailId = trailId;
    final trimmedGroup = groupId?.trim();
    _activeGroupId =
        (trimmedGroup != null && trimmedGroup.isNotEmpty) ? trimmedGroup : null;
  }

  /// Menghapus konteks rute & grup aktif setelah sesi pendakian berhenti.
  void clearActiveRoute() {
    _activeMountainName = null;
    _activeTrailName = null;
    _activeTrailId = null;
    _activeGroupId = null;
  }

  bool get simulationEnabled => kDebugMode && _simulationEnabled;
  String get simulationRouteAsset => _simulationRouteAsset;
  SimulatedLocationSource? get simulatedLocationSource =>
      _simulatedLocationSource;

  TrackingPhase get phase => _phase;
  TrackingStatus? get status => _status;
  PermissionReport? get permission => _permission;
  String? get error => _error;
  String? get notice => _notice;
  bool get isRecording =>
      _phase == TrackingPhase.recording ||
      _phase == TrackingPhase.paused ||
      _phase == TrackingPhase.preparing;
  bool get isPaused => _phase == TrackingPhase.paused;
  bool get isBusy =>
      _phase == TrackingPhase.initializing ||
      _phase == TrackingPhase.preparing ||
      _phase == TrackingPhase.stopping;
  bool get recoveryPending => _recoveryPending;
  TrackingRepository? get repository => _repository;

  String? get currentSessionId => _status?.sessionId;

  /// Titik sesi yang sedang ditampilkan peta. Kosong bila belum ada sesi.
  Future<List<TrackPoint>> currentTrackPoints() async {
    final sessionId = _status?.sessionId;
    final repository = _repository;
    if (sessionId == null || repository == null) return const [];
    return repository.points(sessionId);
  }

  /// Menghapus seluruh titik rekaman sesi aktif saat ini (mis. skenario teleport debug).
  Future<void> clearCurrentTrackPoints() async {
    final sessionId = _status?.sessionId;
    final repository = _repository;
    if (sessionId != null && repository != null) {
      await repository.clearPoints(sessionId);
    }
    if (_backend is IosLocalTrackingBackend) {
      (_backend as IosLocalTrackingBackend).clearCurrentPoints();
    }
    notifyListeners();
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

  Future<PermissionReport> _safeCheckPermissions() async {
    try {
      return await const PermissionService().check();
    } catch (_) {
      return PermissionReport(
        notificationGranted: !Platform.isAndroid,
        locationWhileInUse: false,
        locationAlways: false,
        locationServiceEnabled: false,
        preciseLocation: false,
        ignoringBatteryOptimizations: false,
      );
    }
  }

  Future<void> _initializeOnce() async {
    final sw = Stopwatch()..start();
    void lap(String name) {
      if (kDebugMode) {
        debugPrint('INIT_LAP $name ${sw.elapsedMilliseconds}ms');
      }
    }
    _error = null;
    _phase = TrackingPhase.initializing;
    notifyListeners();
    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        throw UnsupportedError('Pelacakan GPS hanya untuk Android/iOS.');
      }
      final file = await defaultAppDatabaseFile();
      lap('db_file');
      _database = openAppDatabase(file);
      final repository = DriftTrackingRepository(_database!);
      _repository = repository;
      _permission = await _safeCheckPermissions();
      lap('db_open+permission');

      final backend = Platform.isAndroid
          ? AndroidForegroundTrackingBackend(databasePath: file.path)
          : IosLocalTrackingBackend(
              repository: repository,
              clock: const SystemClock(),
            );
      _realBackend = backend;
      _backend = backend;
      _events = backend.events.listen(_onEvent);
      lap('backend');

      final active = await repository.findActiveSession();
      lap('active_session');
      var running = false;
      try {
        running = await backend.isRunning();
      } catch (_) {
        running = false;
      }
      lap('is_running');
      if (running) {
        _phase = TrackingPhase.preparing;
        await backend.requestStatus();
      } else if (active != null) {
        _activeActivityType = active.activityType;
        _recoveryPending = true;
        if (_permission!.readyForBackground) {
          await _startBackend(auto: true, activityType: active.activityType);
        } else {
          _notice =
              'Sesi aktif ditemukan. Lengkapi izin "Selalu" agar rekaman dapat dilanjutkan.';
          _phase = TrackingPhase.idle;
        }
      } else {
        _phase = TrackingPhase.idle;
      }
      _error = null;
      _initialized = true;
      lap('initialized');
    } catch (error) {
      if (kDebugMode) {
        debugPrint('TrackingController.initialize failed: $error');
      }
      _initializationFuture = null;
      _phase = TrackingPhase.error;
      _error = 'Pelacakan di perangkat belum siap. Coba buka ulang halaman ini.';
    } finally {
      notifyListeners();
    }
  }

  @visibleForTesting
  Future<bool> Function()? startOverride;

  @visibleForTesting
  void setRecordingForTesting({
    bool recording = true,
    TrackingStatus? status,
  }) {
    _phase = recording ? TrackingPhase.recording : TrackingPhase.idle;
    _status = status;
    _activeActivityType =
        status?.activityType ?? TrackingSession.activityHiking;
    notifyListeners();
  }

  @visibleForTesting
  void setErrorForTesting(
    String? error, {
    TrackingPhase? phase,
    bool? initialized,
  }) {
    _error = error;
    if (phase != null) _phase = phase;
    if (initialized != null) _initialized = initialized;
    notifyListeners();
  }

  Future<bool> start({
    String activityType = TrackingSession.activityHiking,
    bool allowForegroundOnly = false,
  }) async {
    final normalizedType = TrackingSession.normalizeActivityType(activityType);
    _activeActivityType = normalizedType;
    _error = null;
    if (normalizedType == TrackingSession.activityJogging) {
      _activeMountainName = null;
      _activeTrailName = null;
      _activeTrailId = null;
      _activeGroupId = null;
    }
    if (startOverride != null) return startOverride!();
    await initialize();
    if (!_initialized) return false;
    if (isRecording || _phase == TrackingPhase.stopping) return false;
    if (simulationEnabled) {
      await _ensureSimulationBackendReady();
      _simulatedLocationSource?.reset();
      return _startBackend(activityType: normalizedType);
    }
    final permission = await _safeCheckPermissions();
    _permission = permission;
    final hasAnyLocationPermission = permission.locationServiceEnabled &&
        (permission.locationWhileInUse || permission.locationAlways);
    final allowed = allowForegroundOnly
        ? hasAnyLocationPermission
        : permission.readyForBackground;
    if (!allowed) {
      _notice =
          'Izin lokasi "Selalu", lokasi presisi, layanan lokasi, dan notifikasi perlu diaktifkan.';
      _phase = TrackingPhase.idle;
      notifyListeners();
      return false;
    }
    return _startBackend(activityType: normalizedType);
  }

  /// Mengaktifkan atau menonaktifkan sumber lokasi simulasi (khusus `kDebugMode`).
  Future<void> setSimulationEnabled(bool enabled) async {
    if (!kDebugMode) return;
    await initialize();
    if (_simulationEnabled == enabled) return;
    if (isRecording) {
      await stop();
    }
    _simulationEnabled = enabled;
    if (enabled) {
      await _ensureSimulationBackendReady();
      await _switchActiveBackend(_simulationBackend);
    } else {
      await _switchActiveBackend(_realBackend);
    }
    notifyListeners();
  }

  /// Memilih berkas jalur GPX untuk simulasi (khusus `kDebugMode`).
  Future<void> setSimulationRouteAsset(String assetPath) async {
    if (!kDebugMode) return;
    _simulationRouteAsset = assetPath;
    try {
      final route = await GpxLoader.loadAsset(assetPath);
      if (_simulatedLocationSource != null) {
        _simulatedLocationSource!.setRoute(route);
      } else {
        _simulatedLocationSource = SimulatedLocationSource(route: route)
          ..addListener(notifyListeners);
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('TrackingController.setSimulationRouteAsset failed: $error');
      }
      _error = 'Jalur simulasi tidak dapat dibuka.';
    }
    notifyListeners();
  }

  /// Skenario A: Posisikan di titik awal rute dan mulai merekam jejak.
  Future<void> startSimulationAtBeginning() async {
    if (!kDebugMode) return;
    await _ensureSimulationBackendReady();
    _simulatedLocationSource?.startAtBeginning();
    if (!isRecording) {
      await start();
    }
    notifyListeners();
  }

  /// Skenario B: Berjalan di jalur sejauh 400 m sambil merekam jejak.
  Future<void> runSimulationWalk400m() async {
    if (!kDebugMode) return;
    await _ensureSimulationBackendReady();
    if (!isRecording) {
      await start();
    }
    _simulatedLocationSource?.walkRoute400m();
    notifyListeners();
  }

  /// Skenario C: Menyimpang berbelok tegak lurus sejauh 150 m (jalur memutar),
  /// tetap merekam jejak.
  Future<void> runSimulationCurvedDeviation150m() async {
    if (!kDebugMode) return;
    await _ensureSimulationBackendReady();
    if (!isRecording) {
      await start();
    }
    _simulatedLocationSource?.startCurvedDeviation150m();
    notifyListeners();
  }

  /// Skenario D: Teleport 100 m dari jalur sambil menghapus jejak rekaman
  /// untuk menguji mode petunjuk garis lurus.
  Future<void> runSimulationTeleport100m() async {
    if (!kDebugMode) return;
    await _ensureSimulationBackendReady();
    await _simulatedLocationSource?.teleportWithoutTrack100m(
      onClearTrack: clearCurrentTrackPoints,
    );
    notifyListeners();
  }

  /// Skenario E: Berjalan mengikuti arahan kembali ke jalur sampai terdeteksi
  /// sudah kembali.
  Future<void> runSimulationWalkBack() async {
    if (!kDebugMode) return;
    await _ensureSimulationBackendReady();
    _simulatedLocationSource?.walkBackToTrail();
    notifyListeners();
  }

  /// Memicu sinyal GPS buruk (akurasi 40 m selama 20 detik).
  void triggerSimulationPoorSignal() {
    if (!kDebugMode) return;
    _simulatedLocationSource?.triggerPoorSignal();
  }

  /// Jeda atau lanjut simulasi.
  void toggleSimulationPause() {
    if (!kDebugMode) return;
    _simulatedLocationSource?.togglePauseSimulation();
  }

  /// Reset posisi dan seluruh skenario simulasi.
  void resetSimulation() {
    if (!kDebugMode) return;
    _simulatedLocationSource?.reset();
  }

  Future<void> _ensureSimulationBackendReady() async {
    if (_simulatedLocationSource == null) {
      TrackRoute route;
      try {
        route = await GpxLoader.loadAsset(_simulationRouteAsset);
      } catch (_) {
        route = TrackRoute.fromPoints(
          id: 'fallback',
          name: 'Jalur Simulasi',
          points: const <TrackRoutePoint>[],
        );
      }
      _simulatedLocationSource = SimulatedLocationSource(route: route)
        ..addListener(notifyListeners);
    }
    if (_simulationBackend == null && _repository != null) {
      _simulationBackend = IosLocalTrackingBackend(
        repository: _repository!,
        clock: _clock,
        locationSource: _simulatedLocationSource!,
      );
    }
  }

  Future<void> _switchActiveBackend(TrackingBackend? next) async {
    if (next == null || _backend == next) return;
    await _events?.cancel();
    _backend = next;
    _events = next.events.listen(_onEvent);
  }

  Future<bool> _startBackend({
    bool auto = false,
    String? activityType,
  }) async {
    final backend = _backend;
    if (backend == null) return false;
    final resolvedType = TrackingSession.normalizeActivityType(
      activityType ?? _activeActivityType,
    );
    _activeActivityType = resolvedType;
    _error = null;
    _phase = TrackingPhase.preparing;
    notifyListeners();
    try {
      await backend.start(activityType: resolvedType);
      _recoveryPending = false;
      if (auto) {
        _notice = 'Melanjutkan sesi yang belum selesai...';
      }
      return true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('TrackingController._startBackend failed: $error');
      }
      _phase = TrackingPhase.error;
      _error = 'Rekaman belum bisa dimulai. Pastikan GPS aktif lalu coba lagi.';
      notifyListeners();
      return false;
    }
  }

  Future<void> pause() async {
    final backend = _backend;
    if (backend == null || _phase != TrackingPhase.recording) return;
    try {
      await backend.pause();
      if (_phase == TrackingPhase.recording) {
        _phase = TrackingPhase.paused;
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('TrackingController.pause failed: $error');
      }
      _error = 'Rekaman belum bisa dijeda. Coba lagi.';
    }
    notifyListeners();
  }

  Future<void> resume() async {
    final backend = _backend;
    if (backend == null || _phase != TrackingPhase.paused) return;
    try {
      await backend.resume();
      if (_phase == TrackingPhase.paused) {
        _phase = TrackingPhase.recording;
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('TrackingController.resume failed: $error');
      }
      _error = 'Rekaman belum bisa dilanjutkan. Coba lagi.';
    }
    notifyListeners();
  }

  Future<void> stop({
    bool reachedSummit = false,
    String? mountainName,
    String? trailName,
  }) async {
    final backend = _backend;
    if (backend == null) return;
    if (_phase == TrackingPhase.stopping) return;
    _phase = TrackingPhase.stopping;
    notifyListeners();
    final sessionIdBeforeStop = _status?.sessionId;
    final resolvedActivity = activeActivityType;
    final isJogging = resolvedActivity == TrackingSession.activityJogging;
    final resolvedReachedSummit = isJogging ? false : reachedSummit;
    final resolvedMountain = isJogging ? null : (mountainName ?? _activeMountainName);
    final resolvedTrail = isJogging ? null : (trailName ?? _activeTrailName);
    try {
      final result = await backend.stop();
      final closedOrphan = await _closeActiveSessionIfAny(
        reachedSummit: resolvedReachedSummit,
        mountainName: resolvedMountain,
        trailName: resolvedTrail,
        activityType: resolvedActivity,
      );
      if (sessionIdBeforeStop != null) {
        await _persistCompletionMetadata(
          sessionId: sessionIdBeforeStop,
          reachedSummit: resolvedReachedSummit,
          mountainName: resolvedMountain,
          trailName: resolvedTrail,
          activityType: resolvedActivity,
        );
      }
      _phase = TrackingPhase.finished;
      final notes = <String>[
        if (result.warning != null) result.warning!,
        if (closedOrphan)
          'Sesi aktif ditutup dari data tersimpan karena layanan tidak '
              'mengonfirmasi selesai.',
      ];
      _notice = notes.isEmpty ? null : notes.join(' ');
      if (_status?.sessionStatus == TrackingSessionStatus.active) {
        _status = _status!.copyWith(
          sessionStatus: TrackingSessionStatus.completed,
          isMoving: false,
          isPaused: false,
        );
      }
      if (!isJogging) {
        await _resetPrepareHikeAfterStop();
      }
      DriftTrackingRepository.notifyExternalChange();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('TrackingController.stop failed: $error');
      }
      _phase = TrackingPhase.error;
      _error = 'Rekaman belum bisa dihentikan dengan aman. Coba lagi.';
    }
    notifyListeners();
  }

  Future<void> _resetPrepareHikeAfterStop() async {
    clearActiveRoute();
    try {
      await PackingListStore.instance.clearAll();
    } catch (_) {}
    try {
      await GroupHikePlanStore.instance.completeAndResetAfterHike();
    } catch (_) {}
  }

  Future<bool> _closeActiveSessionIfAny({
    bool reachedSummit = false,
    String? mountainName,
    String? trailName,
    String? activityType,
  }) async {
    final repository = _repository;
    if (repository == null) return false;
    final active = await repository.findActiveSession();
    if (active == null) return false;
    final resolvedType = TrackingSession.normalizeActivityType(
      activityType ?? active.activityType,
    );
    final isJogging = resolvedType == TrackingSession.activityJogging;
    final completed = active.copyWith(
      endedAtUtc: _clock.nowUtc(),
      status: TrackingSessionStatus.completed,
      reachedSummit: isJogging ? false : reachedSummit,
      mountainName: isJogging ? null : (mountainName ?? active.mountainName),
      trailName: isJogging ? null : (trailName ?? active.trailName),
      trailId: isJogging ? null : (_activeTrailId ?? active.trailId),
      activityType: resolvedType,
      ownerUserId: active.ownerUserId ?? ActiveAccountScope.currentUserId(),
    );
    await repository.saveSession(completed);
    unawaited(_syncSessionToSupabase(completed));
    return true;
  }

  Future<void> _persistCompletionMetadata({
    required String sessionId,
    required bool reachedSummit,
    String? mountainName,
    String? trailName,
    String? activityType,
  }) async {
    final repository = _repository;
    if (repository == null) return;
    final existing = await repository.findSession(sessionId);
    if (existing == null) return;
    final resolvedType = TrackingSession.normalizeActivityType(
      activityType ?? existing.activityType,
    );
    final isJogging = resolvedType == TrackingSession.activityJogging;
    final updated = existing.copyWith(
      status: TrackingSessionStatus.completed,
      endedAtUtc: existing.endedAtUtc ?? _clock.nowUtc(),
      reachedSummit: isJogging ? false : (reachedSummit || existing.reachedSummit),
      mountainName: isJogging ? null : (mountainName ?? existing.mountainName),
      trailName: isJogging ? null : (trailName ?? existing.trailName),
      trailId: isJogging ? null : (_activeTrailId ?? existing.trailId),
      activityType: resolvedType,
      ownerUserId: existing.ownerUserId ?? ActiveAccountScope.currentUserId(),
    );
    await repository.saveSession(updated);
    unawaited(_syncSessionToSupabase(updated));
  }

  Future<void> _syncSessionToSupabase(TrackingSession session) async {
    try {
      final client = SupabaseServices.clientOrNull;
      final user = client?.auth.currentUser;
      if (client == null || user == null) return;
      final repo = _repository;
      String? routePolylineB64;
      if (repo != null) {
        final pts = await repo.points(session.id);
        routePolylineB64 = encodeSimplifiedRoutePolyline(pts)?.gzipBase64;
      }
      await client.from('hike_sessions').upsert(<String, dynamic>{
        'id': session.id,
        'user_id': user.id,
        'activity_type': session.activityType,
        'mountain_name': session.isJogging
            ? null
            : (session.mountainName ?? session.trailId ?? 'Pendakian'),
        'trail_name': session.isJogging ? null : session.trailName,
        'started_at': session.startedAtUtc.toUtc().toIso8601String(),
        'ended_at': (session.endedAtUtc ?? _clock.nowUtc())
            .toUtc()
            .toIso8601String(),
        'distance_m': session.distanceM,
        'elevation_gain_m': session.elevationGainM,
        'elevation_loss_m': session.elevationLossM,
        'moving_seconds': session.movingSeconds,
        'reached_summit': session.isJogging ? false : session.reachedSummit,
        if (routePolylineB64 != null) 'route_polyline_b64': routePolylineB64,
      });
      if (repo != null) {
        unawaited(
          SupabaseCloudBackupService.instance
              .backupSingleSessionIfAllowed(session, repo),
        );
      }
    } catch (_) {
      // Tetap aman secara offline: riwayat lokal selalu tersedia di SQLite.
    }
  }

  /// Dipanggil setelah halaman onboarding ditutup, tab Track dibuka, atau aplikasi aktif kembali.
  Future<void> refreshPermissionsAndResume() async {
    if (!_initialized) {
      await initialize();
      return;
    }
    _permission = await _safeCheckPermissions();
    final backend = _backend;
    if (backend == null) {
      _error = null;
      if (_phase == TrackingPhase.error) {
        _phase = TrackingPhase.idle;
      }
      notifyListeners();
      return;
    }
    var running = false;
    try {
      running = await backend.isRunning();
    } catch (_) {
      running = false;
    }
    if (running || _phase == TrackingPhase.error) {
      _error = null;
      if (!running && _phase == TrackingPhase.error) {
        _phase = TrackingPhase.idle;
      }
    } else if (_initialized && _error != null) {
      _error = null;
    }
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
    _permission = await _safeCheckPermissions();
    notifyListeners();
    return opened;
  }

  void _onEvent(TrackingEvent event) {
    switch (event) {
      case TrackingProgressEvent(:final status):
        _status = status;
        final completed =
            status.sessionStatus == TrackingSessionStatus.completed;
        _phase = completed
            ? TrackingPhase.finished
            : (status.isPaused ? TrackingPhase.paused : TrackingPhase.recording);
        _error = null;
        if (completed) {
          DriftTrackingRepository.notifyExternalChange();
        }
      case TrackingStoppedEvent(:final status, :final warning):
        final wasStopping = _phase == TrackingPhase.stopping;
        if (status != null) _status = status;
        _error = null;
        _phase = TrackingPhase.finished;
        _notice = warning;
        if (!wasStopping && !isJoggingSession) {
          unawaited(_resetPrepareHikeAfterStop());
        }
        DriftTrackingRepository.notifyExternalChange();
      case TrackingFailureEvent(:final message, :final fatal):
        if (fatal) {
          _error = message;
          _phase = TrackingPhase.error;
          unawaited(_abortServiceAfterFailure());
        } else {
          _notice = message;
        }
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

  /// Membersihkan status tampilan sesi selesai di memori saat akun berganti.
  void resetForAccountChange() {
    if (isRecording) return;
    _status = null;
    clearActiveRoute();
    _activeActivityType = TrackingSession.activityHiking;
    _recoveryPending = false;
    _error = null;
    _notice = null;
    if (_initialized) {
      _phase = TrackingPhase.idle;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    unawaited(_backend?.dispose());
    unawaited(_database?.close());
    super.dispose();
  }
}
