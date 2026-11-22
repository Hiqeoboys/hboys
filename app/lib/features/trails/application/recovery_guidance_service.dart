import 'dart:async';

import '../../../core/utils/clock.dart';
import '../../../infrastructure/location/shared_location_service.dart';
import '../../tracking/application/tracking_controller.dart';
import '../../tracking/domain/track_point.dart';
import '../domain/guidance_config.dart';
import '../domain/guidance_state.dart';
import '../domain/heading_provider.dart';
import '../domain/recovery_guidance_engine.dart';
import '../domain/track_route.dart';

typedef TrailPointsProvider = Future<List<TrackPoint>> Function();

/// Layanan pemandu rute kembali ke jalur utama.
///
/// Mengintegrasikan [RecoveryGuidanceEngine] dengan [SharedLocationService]
/// dan titik rekaman jejak dari [TrackingController].
class RecoveryGuidanceService {
  RecoveryGuidanceService({
    SharedLocationService? locationService,
    TrackingController? trackingController,
    TrailPointsProvider? trailPointsProvider,
    RecoveryGuidanceEngine? engine,
    HeadingProvider? headingProvider,
    Clock? clock,
    GuidanceConfig config = const GuidanceConfig(),
    Duration checkingTimeout = const Duration(seconds: 3),
  })  : _locationService = locationService ?? SharedLocationService.instance,
        _trackingController = trackingController ?? TrackingController.instance,
        _trailPointsProvider = trailPointsProvider,
        _engine = engine ?? RecoveryGuidanceEngine(config: config),
        _headingProvider = headingProvider,
        _clock = clock ?? locationService?.clock ?? const SystemClock(),
        _checkingTimeout = checkingTimeout;

  final SharedLocationService _locationService;
  final TrackingController _trackingController;
  final TrailPointsProvider? _trailPointsProvider;
  final RecoveryGuidanceEngine _engine;
  final HeadingProvider? _headingProvider;
  final Clock _clock;
  final Duration _checkingTimeout;

  LocationLease? _lease;
  TrackRoute? _activeRoute;
  bool _running = false;
  List<TrackPoint> _cachedTrail = const <TrackPoint>[];
  Timer? _checkingPositionTimer;

  GuidanceState _currentState =
      const GuidanceUnavailable(GuidanceUnavailableReason.noRoute);

  final StreamController<GuidanceState> _statesController =
      StreamController<GuidanceState>.broadcast();

  Stream<GuidanceState> get states => _statesController.stream;
  GuidanceState get currentState => _currentState;
  bool get isRunning => _running;
  TrackRoute? get activeRoute => _activeRoute;
  HeadingProvider? get headingProvider => _headingProvider;
  RecoveryGuidanceEngine get engine => _engine;

  /// Memulai layanan pemanduan untuk rute acuan [route].
  ///
  /// Dapat menerima [initialTrail] dalam memori agar tidak perlu membaca ulang database
  /// saat panel petunjuk baru dibuka.
  void start(TrackRoute route, {List<TrackPoint>? initialTrail}) {
    _activeRoute = route;
    _engine.setRoute(route);
    _running = true;
    _checkingPositionTimer?.cancel();
    _checkingPositionTimer = null;

    if (initialTrail != null) {
      _cachedTrail = List<TrackPoint>.from(initialTrail);
    }

    // Pinjam lease lokasi agar stream GPS latar depan aktif
    _lease?.release();
    _lease = _locationService.acquire();

    _locationService.removeListener(_onLocationChanged);
    _locationService.addListener(_onLocationChanged);

    // Sinkronisasi jejak dari database/provider di latar belakang
    unawaited(_refreshTrailCache());

    // Evaluasi awal segera (eksplisit)
    _evaluateExplicitRequest();
  }

  /// Menghentikan layanan pemanduan.
  void stop() {
    _running = false;
    _checkingPositionTimer?.cancel();
    _checkingPositionTimer = null;
    _locationService.removeListener(_onLocationChanged);
    _lease?.release();
    _lease = null;
    _activeRoute = null;
    _cachedTrail = const <TrackPoint>[];
    _engine.reset();

    _emitState(const GuidanceUnavailable(GuidanceUnavailableReason.noRoute));
  }

  void _evaluateExplicitRequest() {
    final locState = _locationService.state;
    switch (locState.status) {
      case LiveLocationStatus.serviceDisabled:
        _emitState(
          const GuidanceUnavailable(GuidanceUnavailableReason.needsLocation),
        );
        return;
      case LiveLocationStatus.permissionDenied:
      case LiveLocationStatus.permissionDeniedForever:
        _emitState(
          const GuidanceUnavailable(GuidanceUnavailableReason.needsPermission),
        );
        return;
      case LiveLocationStatus.idle:
      case LiveLocationStatus.searching:
      case LiveLocationStatus.error:
      case LiveLocationStatus.active:
        break;
    }

    final fix = _locationService.freshPoint ?? locState.point;
    final now = _clock.nowUtc();
    final isFresh = fix != null &&
        (now.difference(fix.timestampUtc).inMilliseconds / 1000.0) <=
            _engine.config.staleFixSeconds;

    if (isFresh) {
      _headingProvider?.updateGpsFix(fix);
      final nextState = _engine.update(
        fix: fix,
        recordedTrail: _cachedTrail,
        nowUtc: now,
        isExplicitRequest: true,
      );
      _emitState(nextState);
    } else {
      // Tidak ada fix segar dalam batas umur: tampilkan "Memeriksa posisi"
      // paling lama [_checkingTimeout] (3 detik), lalu kembali ke "Menunggu sinyal GPS".
      _emitState(const GuidanceCheckingPosition());
      _startCheckingPositionTimer();
    }
  }

  void _startCheckingPositionTimer() {
    _checkingPositionTimer?.cancel();
    _checkingPositionTimer = Timer(_checkingTimeout, () {
      if (!_running) return;
      if (_currentState is GuidanceCheckingPosition) {
        _emitState(
          const GuidanceUnavailable(GuidanceUnavailableReason.waitingGps),
        );
      }
    });
  }

  void _onLocationChanged() {
    if (!_running) return;

    final locState = _locationService.state;
    switch (locState.status) {
      case LiveLocationStatus.serviceDisabled:
        _checkingPositionTimer?.cancel();
        _emitState(
          const GuidanceUnavailable(GuidanceUnavailableReason.needsLocation),
        );
        return;
      case LiveLocationStatus.permissionDenied:
      case LiveLocationStatus.permissionDeniedForever:
        _checkingPositionTimer?.cancel();
        _emitState(
          const GuidanceUnavailable(GuidanceUnavailableReason.needsPermission),
        );
        return;
      case LiveLocationStatus.idle:
      case LiveLocationStatus.searching:
      case LiveLocationStatus.error:
        if (locState.point == null) {
          if (_currentState is! GuidanceCheckingPosition) {
            _emitState(
              const GuidanceUnavailable(GuidanceUnavailableReason.waitingGps),
            );
          }
          return;
        }
      case LiveLocationStatus.active:
        break;
    }

    final fix = _locationService.freshPoint ?? locState.point;
    if (fix == null) {
      if (_currentState is! GuidanceCheckingPosition) {
        _emitState(
          const GuidanceUnavailable(GuidanceUnavailableReason.waitingGps),
        );
      }
      return;
    }

    final now = _clock.nowUtc();
    final fixAgeSec = now.difference(fix.timestampUtc).inMilliseconds / 1000.0;
    if (fixAgeSec > _engine.config.staleFixSeconds) {
      if (_currentState is! GuidanceCheckingPosition) {
        _emitState(
          const GuidanceUnavailable(GuidanceUnavailableReason.waitingGps),
        );
      }
      return;
    }

    // Fix valid dan segar diterima
    _checkingPositionTimer?.cancel();
    _headingProvider?.updateGpsFix(fix);

    // Tambahkan ke jejak cache bila titik baru
    if (_cachedTrail.isEmpty ||
        _cachedTrail.last.timestampUtc != fix.timestampUtc) {
      _cachedTrail = [..._cachedTrail, fix];
    }

    final isFirstResolution = _currentState is GuidanceCheckingPosition ||
        _currentState is GuidanceUnavailable;

    final nextState = _engine.update(
      fix: fix,
      recordedTrail: _cachedTrail,
      nowUtc: now,
      isExplicitRequest: isFirstResolution,
    );

    _emitState(nextState);
  }

  Future<void> _refreshTrailCache() async {
    try {
      final points = _trailPointsProvider != null
          ? await _trailPointsProvider()
          : await _trackingController.currentTrackPoints();
      if (!_running) return;
      if (points.isNotEmpty &&
          (_cachedTrail.isEmpty || points.length > _cachedTrail.length)) {
        _cachedTrail = points;
        if (_engine.isOffRoute) {
          final fix =
              _locationService.freshPoint ?? _locationService.state.point;
          if (fix != null) {
            final nextState = _engine.update(
              fix: fix,
              recordedTrail: _cachedTrail,
              nowUtc: _clock.nowUtc(),
            );
            _emitState(nextState);
          }
        }
      }
    } catch (_) {}
  }

  void _emitState(GuidanceState state) {
    _currentState = state;
    if (!_statesController.isClosed) {
      _statesController.add(state);
    }
  }

  void dispose() {
    stop();
    _headingProvider?.dispose();
    _statesController.close();
  }
}
