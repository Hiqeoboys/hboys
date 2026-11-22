import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geo_utils/geo_utils.dart';

import '../../core/utils/clock.dart';
import '../../features/tracking/application/tracking_runtime.dart';
import '../../features/tracking/domain/track_point.dart';
import '../../features/trails/domain/track_route.dart';
import '../power/power_profile_manager.dart';
import 'geolocator_tracking_source.dart';

/// Abstraksi sumber lokasi untuk pipeline tracking.
///
/// Memiliki dua implementasi:
/// - [RealLocationSource]: membungkus [GeolocatorTrackingSource] untuk produksi.
/// - [SimulatedLocationSource]: mengeluarkan titik berurutan sepanjang [TrackRoute]
///   untuk pengujian di mode debug.
abstract interface class LocationSource implements TrackingLocationSource {}

/// Implementasi lokasi nyata untuk produksi. Mendelegasikan langsung ke
/// [GeolocatorTrackingSource] tanpa mengubah perilaku produksi.
class RealLocationSource implements LocationSource {
  const RealLocationSource({
    GeolocatorTrackingSource delegate = const GeolocatorTrackingSource(),
  }) : _delegate = delegate;

  final GeolocatorTrackingSource _delegate;

  @override
  Future<TrackingAccess> checkAccess() => _delegate.checkAccess();

  @override
  Stream<TrackPoint> positions(PowerProfileConfig config) =>
      _delegate.positions(config);
}

/// Status skenario simulasi aktif.
enum SimulationScenarioState {
  /// Mengikuti jalur secara normal.
  idle,

  /// Berjalan sepanjang jalur sejauh 400 meter lalu berhenti di posisi tersebut.
  walkingRoute400m,

  /// Menyimpang berbelok tegak lurus sejauh 150 m lewat lintasan melengkung.
  deviatingCurved150m,

  /// Diam di posisi luar jalur (setelah menyimpang atau teleport).
  deviatedStatic,

  /// Berjalan kembali menuju titik terdekat di jalur hingga tiba di jalur.
  walkingBackToTrail,
}

/// Sumber lokasi simulasi (khusus debug/pengujian) yang menginterpolasi titik
/// sepanjang [TrackRoute] dan mendukung beragam skenario petunjuk arah.
class SimulatedLocationSource extends ChangeNotifier implements LocationSource {
  SimulatedLocationSource({
    required TrackRoute route,
    this.baseSpeedMps = 1.2,
    int speedMultiplier = 1,
    Duration emissionInterval = const Duration(seconds: 1),
    this.maxNoiseMeters = 3.0,
    this.minAccuracyM = 5.0,
    this.maxAccuracyM = 15.0,
    bool stopAtMidpointEnabled = false,
    Clock clock = const SystemClock(),
    math.Random? random,
  })  : _route = route,
        _speedMultiplier = _normalizeMultiplier(speedMultiplier),
        _emissionInterval = _clampInterval(emissionInterval),
        _stopAtMidpointEnabled = stopAtMidpointEnabled,
        _clock = clock,
        _random = random ?? math.Random(42) {
    _rebuildRouteDistances();
  }

  static const List<int> supportedSpeedMultipliers = <int>[1, 5, 10];
  static const Duration minAllowedInterval = Duration(milliseconds: 100);
  static const int midpointStopDurationSeconds = 10;

  final double baseSpeedMps;
  final double maxNoiseMeters;
  final double minAccuracyM;
  final double maxAccuracyM;
  final Clock _clock;
  final math.Random _random;

  TrackRoute _route;
  int _speedMultiplier;
  final Duration _emissionInterval;
  bool _stopAtMidpointEnabled;

  List<double> _cumulativeDistancesM = const <double>[0.0];
  double _totalDistanceM = 0.0;
  double _currentDistanceM = 0.0;
  bool _isSimulationPaused = false;
  bool _midpointStopTriggered = false;
  double _remainingStopSeconds = 0.0;
  bool _completed = false;

  // Drift GPS berkorelasi waktu dalam batas ±maxNoiseMeters agar lintasan
  // menyerupai goyangan penerima GPS nyata (±3 m dari garis jalur).
  double _driftNorthM = 0.0;
  double _driftEastM = 0.0;

  // Skenario & penyimpangan
  SimulationScenarioState _scenarioState = SimulationScenarioState.idle;
  double _routeTargetDistanceM = 0.0;
  double _deviationBaseDistanceM = 0.0;
  double _deviationProgress = 0.0; // 0.0 .. 1.0
  double _currentOffsetNorthM = 0.0;
  double _currentOffsetEastM = 0.0;
  double _poorSignalRemainingSeconds = 0.0;
  LatLng? _walkBackTargetPoint;
  LatLng? _lastEmittedPosition;

  TrackRoute get route => _route;
  int get speedMultiplier => _speedMultiplier;
  Duration get emissionInterval => _emissionInterval;
  bool get isSimulationPaused => _isSimulationPaused;
  bool get stopAtMidpointEnabled => _stopAtMidpointEnabled;
  bool get isStoppingTenSeconds => _remainingStopSeconds > 0;
  double get remainingStopSeconds => _remainingStopSeconds;
  bool get isCompleted => _completed;
  double get currentDistanceM => _currentDistanceM;
  double get totalDistanceM => _totalDistanceM;
  SimulationScenarioState get scenarioState => _scenarioState;
  bool get isPoorSignalActive => _poorSignalRemainingSeconds > 0;
  double get remainingPoorSignalSeconds => _poorSignalRemainingSeconds;
  LatLng? get lastEmittedPosition => _lastEmittedPosition;

  /// Jarak saat ini dari garis jalur dalam meter.
  double get currentOffsetFromTrailM => math.sqrt(
      _currentOffsetNorthM * _currentOffsetNorthM +
          _currentOffsetEastM * _currentOffsetEastM);

  /// Progres sepanjang jalur dalam rentang `0.0..1.0`.
  double get progress => _totalDistanceM <= 0
      ? 0.0
      : (_currentDistanceM / _totalDistanceM).clamp(0.0, 1.0).toDouble();

  /// Progres sepanjang jalur dalam persen (`0..100`).
  double get progressPercent => progress * 100.0;

  static int _normalizeMultiplier(int value) {
    if (value <= 1) return 1;
    if (value <= 5) return 5;
    return 10;
  }

  static Duration _clampInterval(Duration interval) {
    return interval < minAllowedInterval ? minAllowedInterval : interval;
  }

  void _rebuildRouteDistances() {
    final pts = _route.points;
    if (pts.isEmpty) {
      _cumulativeDistancesM = const <double>[0.0];
      _totalDistanceM = 0.0;
      _currentDistanceM = 0.0;
      _lastEmittedPosition = null;
      return;
    }
    final cum = List<double>.filled(pts.length, 0.0);
    var sum = 0.0;
    for (var i = 1; i < pts.length; i++) {
      sum += distanceMeters(pts[i - 1].position, pts[i].position);
      cum[i] = sum;
    }
    _cumulativeDistancesM = cum;
    _totalDistanceM = sum;
    _currentDistanceM = 0.0;
    _midpointStopTriggered = false;
    _remainingStopSeconds = 0.0;
    _completed = false;
    _driftNorthM = 0.0;
    _driftEastM = 0.0;
    _scenarioState = SimulationScenarioState.idle;
    _deviationBaseDistanceM = 0.0;
    _deviationProgress = 0.0;
    _currentOffsetNorthM = 0.0;
    _currentOffsetEastM = 0.0;
    _poorSignalRemainingSeconds = 0.0;
    _walkBackTargetPoint = null;
    _lastEmittedPosition = pts.first.position;
  }

  void setRoute(TrackRoute route) {
    _route = route;
    _rebuildRouteDistances();
    notifyListeners();
  }

  void setSpeedMultiplier(int multiplier) {
    final normalized = _normalizeMultiplier(multiplier);
    if (_speedMultiplier == normalized) return;
    _speedMultiplier = normalized;
    notifyListeners();
  }

  void setStopAtMidpointEnabled(bool enabled) {
    if (_stopAtMidpointEnabled == enabled) return;
    _stopAtMidpointEnabled = enabled;
    notifyListeners();
  }

  /// Memicu berhenti 10 detik (`speed = 0`) di posisi saat ini untuk menguji
  /// deteksi auto-pause dan Waktu bergerak vs total waktu.
  void triggerTenSecondStop() {
    _remainingStopSeconds = midpointStopDurationSeconds.toDouble();
    notifyListeners();
  }

  void pauseSimulation() {
    if (_isSimulationPaused) return;
    _isSimulationPaused = true;
    notifyListeners();
  }

  void resumeSimulation() {
    if (!_isSimulationPaused) return;
    _isSimulationPaused = false;
    notifyListeners();
  }

  void togglePauseSimulation() {
    _isSimulationPaused = !_isSimulationPaused;
    notifyListeners();
  }

  /// Skenario A: Posisikan pengguna di titik awal rute.
  void startAtBeginning() {
    _currentDistanceM = 0.0;
    _deviationBaseDistanceM = 0.0;
    _deviationProgress = 0.0;
    _currentOffsetNorthM = 0.0;
    _currentOffsetEastM = 0.0;
    _scenarioState = SimulationScenarioState.idle;
    _completed = false;
    _isSimulationPaused = false;
    _remainingStopSeconds = 0.0;
    _midpointStopTriggered = false;
    _walkBackTargetPoint = null;
    _lastEmittedPosition = _route.points.firstOrNull?.position;
    notifyListeners();
  }

  /// Skenario B: Berjalan di jalur sejauh 400 m dari posisi saat ini.
  void walkRoute400m() {
    _routeTargetDistanceM =
        math.min(_totalDistanceM, _currentDistanceM + 400.0);
    _scenarioState = SimulationScenarioState.walkingRoute400m;
    _isSimulationPaused = false;
    notifyListeners();
  }

  /// Skenario C: Berbelok tegak lurus dari jalur sejauh 150 m dengan jalur
  /// memutar (bukan garis lurus), tetap merekam jejak.
  void startCurvedDeviation150m() {
    _deviationBaseDistanceM = _currentDistanceM;
    _deviationProgress = 0.0;
    _currentOffsetNorthM = 0.0;
    _currentOffsetEastM = 0.0;
    _scenarioState = SimulationScenarioState.deviatingCurved150m;
    _isSimulationPaused = false;
    notifyListeners();
  }

  /// Skenario D: Pindah 100 m dari jalur sambil menghapus jejak rekaman
  /// (memanggil [onClearTrack]) untuk menguji petunjuk mode garis lurus.
  Future<void> teleportWithoutTrack100m({
    Future<void> Function()? onClearTrack,
  }) async {
    _deviationBaseDistanceM = _currentDistanceM;
    _deviationProgress = 1.0;
    final (rn, re, _, _) = _getSegmentBasisVectors(_deviationBaseDistanceM);
    _currentOffsetNorthM = 100.0 * rn;
    _currentOffsetEastM = 100.0 * re;
    _scenarioState = SimulationScenarioState.deviatedStatic;
    _isSimulationPaused = false;
    if (onClearTrack != null) {
      await onClearTrack();
    }
    notifyListeners();
  }

  /// Skenario E: Berjalan mengikuti arahan menuju titik terdekat di jalur
  /// sampai kembali ke jalur (< 3 m).
  void walkBackToTrail() {
    final current = _lastEmittedPosition ??
        _route.points.firstOrNull?.position ??
        const LatLng(0, 0);
    final trailPoints = _route.points.map((p) => p.position).toList();
    if (trailPoints.isNotEmpty) {
      _walkBackTargetPoint = closestPointOnPolyline(current, trailPoints);
    }
    _scenarioState = SimulationScenarioState.walkingBackToTrail;
    _isSimulationPaused = false;
    notifyListeners();
  }

  /// Memicu sinyal buruk (akurasi 40 m selama 20 detik).
  void triggerPoorSignal({
    Duration duration = const Duration(seconds: 20),
    double poorAccuracyM = 40.0,
  }) {
    _poorSignalRemainingSeconds = duration.inMilliseconds / 1000.0;
    notifyListeners();
  }

  void reset() {
    _currentDistanceM = 0.0;
    _deviationBaseDistanceM = 0.0;
    _deviationProgress = 0.0;
    _currentOffsetNorthM = 0.0;
    _currentOffsetEastM = 0.0;
    _scenarioState = SimulationScenarioState.idle;
    _midpointStopTriggered = false;
    _remainingStopSeconds = 0.0;
    _poorSignalRemainingSeconds = 0.0;
    _completed = false;
    _isSimulationPaused = false;
    _driftNorthM = 0.0;
    _driftEastM = 0.0;
    _walkBackTargetPoint = null;
    _lastEmittedPosition = _route.points.firstOrNull?.position;
    notifyListeners();
  }

  @override
  Future<TrackingAccess> checkAccess() async => TrackingAccess.granted;

  @override
  Stream<TrackPoint> positions(PowerProfileConfig config) {
    Timer? timer;
    late final StreamController<TrackPoint> controller;

    void emitNext() {
      if (controller.isClosed || _isSimulationPaused) return;
      final point = stepTick(_emissionInterval);
      if (point != null && !controller.isClosed) {
        controller.add(point);
      }
    }

    controller = StreamController<TrackPoint>(
      onListen: () {
        // Emisi titik awal segera saat stream mulai didengarkan.
        if (!_isSimulationPaused && _currentDistanceM == 0.0) {
          final firstPoint = _buildPointAtDistance(
            distanceM: 0.0,
            speedMps: baseSpeedMps * _speedMultiplier,
            timestampUtc: _clock.nowUtc(),
          );
          if (firstPoint != null) {
            controller.add(firstPoint);
          }
        }
        timer = Timer.periodic(_emissionInterval, (_) => emitNext());
      },
      onPause: () => pauseSimulation(),
      onResume: () => resumeSimulation(),
      onCancel: () {
        timer?.cancel();
        timer = null;
      },
    );

    return controller.stream;
  }

  /// Memajukan simulasi sebesar satu langkah [dt] dan mengembalikan [TrackPoint]
  /// dengan timestamp waktu nyata ([Clock.nowUtc] atau [overrideTimestampUtc]).
  TrackPoint? stepTick(
    Duration dt, {
    DateTime? overrideTimestampUtc,
  }) {
    final pts = _route.points;
    if (pts.isEmpty) return null;

    final nowUtc = overrideTimestampUtc ?? _clock.nowUtc();
    final dtSec = math.max(0.1, dt.inMilliseconds / 1000.0);

    // Hitung mundur sinyal buruk bila aktif
    if (_poorSignalRemainingSeconds > 0) {
      _poorSignalRemainingSeconds =
          math.max(0.0, _poorSignalRemainingSeconds - dtSec);
    }

    // Periksa apakah opsi berhenti 10 detik di tengah jalur aktif
    if (_remainingStopSeconds > 0) {
      _remainingStopSeconds = math.max(0.0, _remainingStopSeconds - dtSec);
      final stationaryPoint = _buildPointAtDistance(
        distanceM: _currentDistanceM,
        speedMps: 0.0,
        timestampUtc: nowUtc,
        stationary: true,
      );
      notifyListeners();
      return stationaryPoint;
    }

    if (_isSimulationPaused) return null;

    switch (_scenarioState) {
      case SimulationScenarioState.idle:
        if (_completed) {
          final endPoint = _buildPointAtDistance(
            distanceM: _totalDistanceM,
            speedMps: 0.0,
            timestampUtc: nowUtc,
            stationary: true,
          );
          notifyListeners();
          return endPoint;
        }
        return _advanceAlongRoute(dtSec, nowUtc);

      case SimulationScenarioState.walkingRoute400m:
        final segSpeedMps = _segmentBaseSpeedAt(_currentDistanceM);
        final effectiveSpeedMps = segSpeedMps * _speedMultiplier;
        final stepMeters = effectiveSpeedMps * dtSec;
        final nextDist =
            math.min(_routeTargetDistanceM, _currentDistanceM + stepMeters);
        _currentDistanceM = nextDist;
        if (_currentDistanceM >= _routeTargetDistanceM) {
          _scenarioState = SimulationScenarioState.idle;
        }
        final point = _buildPointAtDistance(
          distanceM: _currentDistanceM,
          speedMps: effectiveSpeedMps,
          timestampUtc: nowUtc,
        );
        notifyListeners();
        return point;

      case SimulationScenarioState.deviatingCurved150m:
        final segSpeedMps = _segmentBaseSpeedAt(_deviationBaseDistanceM);
        final effectiveSpeedMps = segSpeedMps * _speedMultiplier;
        const detourLengthM = 180.0;
        final deltaU = (effectiveSpeedMps * dtSec) / detourLengthM;
        _deviationProgress = math.min(1.0, _deviationProgress + deltaU);

        final u = _deviationProgress;
        // Jarak tegak lurus mencapai 150m di u = 1.0 (sinus pi/2)
        final dPerp = 150.0 * math.sin(math.pi * 0.5 * u);
        // Jarak sejajar melengkung maju hingga 40m dan kembali ke 0 di u = 1.0
        final dPara = 40.0 * math.sin(math.pi * u);

        final (rn, re, fn, fe) =
            _getSegmentBasisVectors(_deviationBaseDistanceM);
        _currentOffsetNorthM = dPerp * rn + dPara * fn;
        _currentOffsetEastM = dPerp * re + dPara * fe;

        if (_deviationProgress >= 1.0) {
          _scenarioState = SimulationScenarioState.deviatedStatic;
        }

        final point = _buildOffTrailPoint(
          baseDistanceM: _deviationBaseDistanceM,
          offsetNorthM: _currentOffsetNorthM,
          offsetEastM: _currentOffsetEastM,
          speedMps: _scenarioState == SimulationScenarioState.deviatedStatic
              ? 0.0
              : effectiveSpeedMps,
          timestampUtc: nowUtc,
        );
        notifyListeners();
        return point;

      case SimulationScenarioState.deviatedStatic:
        final point = _buildOffTrailPoint(
          baseDistanceM: _deviationBaseDistanceM,
          offsetNorthM: _currentOffsetNorthM,
          offsetEastM: _currentOffsetEastM,
          speedMps: 0.0,
          timestampUtc: nowUtc,
          stationary: true,
        );
        notifyListeners();
        return point;

      case SimulationScenarioState.walkingBackToTrail:
        final target = _walkBackTargetPoint;
        final currentPos = _lastEmittedPosition;
        if (target == null || currentPos == null) {
          _scenarioState = SimulationScenarioState.idle;
          return _advanceAlongRoute(dtSec, nowUtc);
        }

        final distToTarget = distanceMeters(currentPos, target);
        final bearingToTarget = bearingDegrees(currentPos, target);
        final segSpeedMps = _segmentBaseSpeedAt(_deviationBaseDistanceM);
        final effectiveSpeedMps = segSpeedMps * _speedMultiplier;
        final stepM = effectiveSpeedMps * dtSec;

        if (distToTarget <= stepM || distToTarget <= 3.0) {
          // Tiba kembali di jalur
          _scenarioState = SimulationScenarioState.idle;
          _currentOffsetNorthM = 0.0;
          _currentOffsetEastM = 0.0;
          _deviationProgress = 0.0;
          _currentDistanceM = _findRouteDistanceForPoint(target);
          final returnPoint = _buildPointAtDistance(
            distanceM: _currentDistanceM,
            speedMps: effectiveSpeedMps,
            timestampUtc: nowUtc,
          );
          notifyListeners();
          return returnPoint;
        }

        // Melangkah mendekati target
        final radHeading = bearingToTarget * math.pi / 180.0;
        final stepNorthM = stepM * math.cos(radHeading);
        final stepEastM = stepM * math.sin(radHeading);

        _currentOffsetNorthM += stepNorthM;
        _currentOffsetEastM += stepEastM;

        final point = _buildOffTrailPoint(
          baseDistanceM: _deviationBaseDistanceM,
          offsetNorthM: _currentOffsetNorthM,
          offsetEastM: _currentOffsetEastM,
          speedMps: effectiveSpeedMps,
          timestampUtc: nowUtc,
          customHeading: bearingToTarget,
        );
        notifyListeners();
        return point;
    }
  }

  TrackPoint? _advanceAlongRoute(double dtSec, DateTime nowUtc) {
    final segSpeedMps = _segmentBaseSpeedAt(_currentDistanceM);
    final effectiveSpeedMps = segSpeedMps * _speedMultiplier;
    final stepMeters = effectiveSpeedMps * dtSec;

    final prevDist = _currentDistanceM;
    final nextDist = math.min(_totalDistanceM, _currentDistanceM + stepMeters);

    // Jika melewati titik tengah (50%) dan opsi berhenti 10 detik diaktifkan
    final halfDist = _totalDistanceM * 0.5;
    if (_stopAtMidpointEnabled &&
        !_midpointStopTriggered &&
        prevDist < halfDist &&
        nextDist >= halfDist) {
      _currentDistanceM = halfDist;
      _midpointStopTriggered = true;
      _remainingStopSeconds = midpointStopDurationSeconds.toDouble();
      final midPoint = _buildPointAtDistance(
        distanceM: _currentDistanceM,
        speedMps: 0.0,
        timestampUtc: nowUtc,
        stationary: true,
      );
      notifyListeners();
      return midPoint;
    }

    _currentDistanceM = nextDist;
    if (_currentDistanceM >= _totalDistanceM) {
      _completed = true;
    }

    final point = _buildPointAtDistance(
      distanceM: _currentDistanceM,
      speedMps: effectiveSpeedMps,
      timestampUtc: nowUtc,
    );
    notifyListeners();
    return point;
  }

  (double, double, double, double) _getSegmentBasisVectors(double distanceM) {
    final pts = _route.points;
    if (pts.length < 2) return (0.0, 1.0, 1.0, 0.0);
    final idx = _findSegmentIndex(distanceM);
    final p0 = pts[idx];
    final p1 = pts.length > idx + 1 ? pts[idx + 1] : p0;
    final heading = bearingDegrees(p0.position, p1.position);
    final perpHeading = (heading + 90.0) % 360.0;
    final radH = heading * math.pi / 180.0;
    final radP = perpHeading * math.pi / 180.0;
    return (
      math.cos(radP), // rn
      math.sin(radP), // re
      math.cos(radH), // fn
      math.sin(radH), // fe
    );
  }

  double _findRouteDistanceForPoint(LatLng pt) {
    final pts = _route.points;
    if (pts.isEmpty) return 0.0;
    if (pts.length == 1) return 0.0;
    var bestDist = double.infinity;
    var bestIndex = 0;
    for (var i = 0; i < pts.length - 1; i++) {
      final d =
          distanceToSegmentMeters(pt, pts[i].position, pts[i + 1].position);
      if (d < bestDist) {
        bestDist = d;
        bestIndex = i;
      }
    }
    final p0 = pts[bestIndex].position;
    final p1 = pts[bestIndex + 1].position;
    final segLen = distanceMeters(p0, p1);
    if (segLen <= 0) return _cumulativeDistancesM[bestIndex];
    final d0 = distanceMeters(p0, pt);
    final d1 = distanceMeters(p1, pt);
    final t = ((d0 * d0 - d1 * d1 + segLen * segLen) / (2 * segLen * segLen))
        .clamp(0.0, 1.0);
    return _cumulativeDistancesM[bestIndex] + t * segLen;
  }

  TrackPoint? _buildOffTrailPoint({
    required double baseDistanceM,
    required double offsetNorthM,
    required double offsetEastM,
    required double speedMps,
    required DateTime timestampUtc,
    double? customHeading,
    bool stationary = false,
  }) {
    final pts = _route.points;
    if (pts.isEmpty) return null;

    final clampedDist = baseDistanceM.clamp(0.0, _totalDistanceM).toDouble();
    final idx = _findSegmentIndex(clampedDist);
    final p0 = pts[idx];
    final p1 = pts.length > idx + 1 ? pts[idx + 1] : p0;
    final segStart = _cumulativeDistancesM[idx];
    final segLen =
        pts.length > idx + 1 ? _cumulativeDistancesM[idx + 1] - segStart : 0.0;
    final t =
        segLen > 0 ? ((clampedDist - segStart) / segLen).clamp(0.0, 1.0) : 0.0;

    final baseLat = p0.lat + (p1.lat - p0.lat) * t;
    final baseLon = p0.lon + (p1.lon - p0.lon) * t;
    double? baseAlt;
    if (p0.ele != null && p1.ele != null) {
      baseAlt = p0.ele! + (p1.ele! - p0.ele!) * t;
    } else {
      baseAlt = p0.ele ?? p1.ele;
    }

    const metersPerDegreeLat = earthRadiusM * math.pi / 180.0;
    final metersPerDegreeLon =
        metersPerDegreeLat * math.cos(baseLat * math.pi / 180.0);

    double lat = baseLat + (offsetNorthM / metersPerDegreeLat);
    double lon = baseLon;
    if (metersPerDegreeLon.abs() > 1e-6) {
      lon += offsetEastM / metersPerDegreeLon;
    }

    final double heading;
    if (customHeading != null) {
      heading = customHeading;
    } else if (_lastEmittedPosition != null) {
      final d = distanceMeters(_lastEmittedPosition!, LatLng(lat, lon));
      if (d > 0.1) {
        heading = bearingDegrees(_lastEmittedPosition!, LatLng(lat, lon));
      } else {
        heading = bearingDegrees(p0.position, p1.position);
      }
    } else {
      heading = bearingDegrees(p0.position, p1.position);
    }

    _lastEmittedPosition = LatLng(lat, lon);

    final double accuracyM;
    if (_poorSignalRemainingSeconds > 0) {
      accuracyM = 40.0 + _random.nextDouble() * 5.0;
    } else {
      final accuracyRange = math.max(0.0, maxAccuracyM - minAccuracyM);
      accuracyM = minAccuracyM + _random.nextDouble() * accuracyRange;
    }

    if (maxNoiseMeters > 0 && !stationary) {
      final stepScale = math.min(0.35, 0.12 * maxNoiseMeters);
      _driftNorthM = (_driftNorthM * 0.94 +
              (_random.nextDouble() * 2.0 - 1.0) * stepScale)
          .clamp(-maxNoiseMeters, maxNoiseMeters)
          .toDouble();
      _driftEastM = (_driftEastM * 0.94 +
              (_random.nextDouble() * 2.0 - 1.0) * stepScale)
          .clamp(-maxNoiseMeters, maxNoiseMeters)
          .toDouble();
      lat += _driftNorthM / metersPerDegreeLat;
      if (metersPerDegreeLon.abs() > 1e-6) {
        lon += _driftEastM / metersPerDegreeLon;
      }
    }

    return TrackPoint(
      lat: lat,
      lon: lon,
      altitudeM: baseAlt,
      altitudeAccuracyM: 6.0,
      speedMps: speedMps,
      speedAccuracyMps: 0.4,
      heading: heading,
      accuracyM: accuracyM,
      timestampUtc: timestampUtc,
      receivedAtUtc: timestampUtc,
      isMocked: true,
    );
  }

  /// Kecepatan dasar segmen pada jarak [distanceM]: memakai selisih waktu GPX
  /// bila tersedia dan wajar (0,3..6,0 m/s), atau [baseSpeedMps] (1,2 m/s).
  double _segmentBaseSpeedAt(double distanceM) {
    final pts = _route.points;
    if (pts.length < 2) return baseSpeedMps;
    final idx = _findSegmentIndex(distanceM);
    final p0 = pts[idx];
    final p1 = pts[idx + 1];
    final t0 = p0.time;
    final t1 = p1.time;
    if (t0 != null && t1 != null && t1.isAfter(t0)) {
      final dtSec = t1.difference(t0).inMilliseconds / 1000.0;
      final segLen =
          _cumulativeDistancesM[idx + 1] - _cumulativeDistancesM[idx];
      if (dtSec > 0 && segLen > 0) {
        final gpxSpeed = segLen / dtSec;
        if (gpxSpeed.isFinite && gpxSpeed >= 0.3 && gpxSpeed <= 6.0) {
          return gpxSpeed;
        }
      }
    }
    return baseSpeedMps;
  }

  int _findSegmentIndex(double distanceM) {
    final n = _cumulativeDistancesM.length;
    if (n < 2) return 0;
    var low = 0;
    var high = n - 2;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (_cumulativeDistancesM[mid + 1] < distanceM) {
        low = mid + 1;
      } else if (_cumulativeDistancesM[mid] > distanceM) {
        high = mid - 1;
      } else {
        return mid;
      }
    }
    return low.clamp(0, n - 2);
  }

  TrackPoint? _buildPointAtDistance({
    required double distanceM,
    required double speedMps,
    required DateTime timestampUtc,
    bool stationary = false,
  }) {
    final pts = _route.points;
    if (pts.isEmpty) return null;
    if (pts.length == 1) {
      final only = pts.first;
      _lastEmittedPosition = only.position;
      return TrackPoint(
        lat: only.lat,
        lon: only.lon,
        altitudeM: only.ele,
        speedMps: speedMps,
        heading: 0.0,
        accuracyM: _poorSignalRemainingSeconds > 0
            ? 40.0 + _random.nextDouble() * 5.0
            : minAccuracyM,
        timestampUtc: timestampUtc,
        receivedAtUtc: timestampUtc,
        isMocked: true,
      );
    }

    final clampedDist = distanceM.clamp(0.0, _totalDistanceM).toDouble();
    final idx = _findSegmentIndex(clampedDist);
    final p0 = pts[idx];
    final p1 = pts[idx + 1];
    final segStart = _cumulativeDistancesM[idx];
    final segLen = _cumulativeDistancesM[idx + 1] - segStart;
    final t =
        segLen > 0 ? ((clampedDist - segStart) / segLen).clamp(0.0, 1.0) : 0.0;

    final baseLat = p0.lat + (p1.lat - p0.lat) * t;
    final baseLon = p0.lon + (p1.lon - p0.lon) * t;

    double? baseAlt;
    if (p0.ele != null && p1.ele != null) {
      baseAlt = p0.ele! + (p1.ele! - p0.ele!) * t;
    } else {
      baseAlt = p0.ele ?? p1.ele;
    }

    final heading = bearingDegrees(p0.position, p1.position);

    final double accuracyM;
    if (_poorSignalRemainingSeconds > 0) {
      accuracyM = 40.0 + _random.nextDouble() * 5.0;
    } else {
      final accuracyRange = math.max(0.0, maxAccuracyM - minAccuracyM);
      accuracyM = minAccuracyM + _random.nextDouble() * accuracyRange;
    }

    double lat = baseLat;
    double lon = baseLon;
    final isEndpoint = clampedDist <= 0.0 ||
        (clampedDist >= _totalDistanceM && _totalDistanceM > 0);
    if (maxNoiseMeters > 0 && !isEndpoint && !stationary) {
      final stepScale = math.min(0.35, 0.12 * maxNoiseMeters);
      _driftNorthM = (_driftNorthM * 0.94 +
              (_random.nextDouble() * 2.0 - 1.0) * stepScale)
          .clamp(-maxNoiseMeters, maxNoiseMeters)
          .toDouble();
      _driftEastM = (_driftEastM * 0.94 +
              (_random.nextDouble() * 2.0 - 1.0) * stepScale)
          .clamp(-maxNoiseMeters, maxNoiseMeters)
          .toDouble();

      const metersPerDegreeLat = earthRadiusM * math.pi / 180.0;
      final metersPerDegreeLon =
          metersPerDegreeLat * math.cos(baseLat * math.pi / 180.0);
      lat += _driftNorthM / metersPerDegreeLat;
      if (metersPerDegreeLon.abs() > 1e-6) {
        lon += _driftEastM / metersPerDegreeLon;
      }
    }

    _lastEmittedPosition = LatLng(lat, lon);

    return TrackPoint(
      lat: lat,
      lon: lon,
      altitudeM: baseAlt,
      altitudeAccuracyM: 6.0,
      speedMps: speedMps,
      speedAccuracyMps: 0.4,
      heading: heading,
      accuracyM: accuracyM,
      timestampUtc: timestampUtc,
      receivedAtUtc: timestampUtc,
      isMocked: true,
    );
  }
}
