import 'package:geo_utils/geo_utils.dart';

import 'auto_pause_detector.dart';
import 'calorie_estimator.dart';
import 'distance_calculator.dart';
import 'elevation_processor.dart';
import 'gps_filter.dart';
import 'motion_estimators.dart';
import 'track_point.dart';
import 'tracking_diagnostics.dart';

class TrackingSnapshot {
  const TrackingSnapshot({
    required this.distanceM,
    required this.movingTime,
    required this.elapsed,
    required this.gainM,
    required this.lossM,
    required this.isMoving,
    required this.lastPoint,
    this.paceSecPerKm,
    this.averagePaceSecPerKm,
    this.verticalSpeedMph,
    this.kcalPerKg = 0,
  });

  final double distanceM;
  final Duration movingTime;
  final Duration elapsed;
  final double gainM;
  final double lossM;
  final bool isMoving;
  final TrackPoint lastPoint;

  /// Detik per km dari kecepatan/jarak pada jendela geser 10–15 detik (EMA).
  final double? paceSecPerKm;

  /// Pace rata-rata total (`movingTime / totalDistanceKm`), `null` < 30 m.
  final double? averagePaceSecPerKm;

  /// Meter per jam (positif = naik), jendela 45–60 detik pada ketinggian
  /// terhaluskan. `null` bila jendela belum tercapai atau 0 saat diam/datar.
  final double? verticalSpeedMph;

  /// Energi terkumpul per kg berat badan (persamaan ACSM).
  final double kcalPerKg;
}

/// Menggabungkan filter GPS, jarak, elevasi, pace, kecepatan vertikal, kalori,
/// dan auto-pause berstandar Strava menjadi satu aliran metrik.
class TrackingEngine {
  TrackingEngine({
    GpsFilter? filter,
    DistanceCalculator? distance,
    ElevationProcessor? elevation,
    AutoPauseDetector? autoPause,
    bool useBarometer = false,
  })  : _filter = filter ?? GpsFilter(),
        _distance = distance ?? DistanceCalculator(),
        _elevation =
            elevation ?? ElevationProcessor(useBarometer: useBarometer),
        _autoPause = autoPause ?? AutoPauseDetector();

  final GpsFilter _filter;
  final DistanceCalculator _distance;
  final ElevationProcessor _elevation;
  final AutoPauseDetector _autoPause;
  final AltitudeSmoother _altitude = AltitudeSmoother();
  final PaceEstimator _pace = PaceEstimator();
  final VerticalSpeedEstimator _vertical = VerticalSpeedEstimator();
  final GradeEstimator _grade = GradeEstimator();
  final KcalAccumulator _kcal = KcalAccumulator();

  /// Hitungan diterima/ditolak beserta alasannya, untuk diagnosa.
  final TrackingDiagnostics diagnostics = TrackingDiagnostics();

  DateTime? _startedAt;
  TrackPoint? _prev;
  LatLng? _lastElevationAnchor;
  bool _hasElevationBaseline = false;
  TrackingSnapshot? _latest;

  /// Potret terbaru dari fix valid terakhir (`null` bila belum ada fix valid).
  TrackingSnapshot? get latestSnapshot => _latest;

  /// Memproses satu titik mentah. Fix yang tidak melewati movement gate
  /// (`jitter` / diam) membekukan jarak, waktu bergerak, dan elevasi total.
  TrackingSnapshot? onFix(TrackPoint raw) {
    final reason = _filter.evaluate(raw);
    diagnostics.record(raw, reason);
    if (reason != null && reason != FixRejectReason.jitter) return null;
    final accepted = reason == null;

    final t = raw.timestampUtc;
    _startedAt ??= t;

    if (!accepted) {
      final implied = _impliedSpeed(raw);
      final rawSpeed = (raw.speedMps != null && raw.speedMps!.isFinite)
          ? raw.speedMps!
          : implied;
      final filterSpeed = _filter.smoothedSpeedMps ?? rawSpeed;
      final distFromAccepted = _filter.lastAccepted == null
          ? 0.0
          : distanceMeters(_filter.lastAccepted!.position, raw.position);
      final waitingStepWhileMoving = reason == FixRejectReason.jitter &&
          _autoPause.isMoving &&
          rawSpeed >= _filter.movingSpeedMps &&
          filterSpeed >= _filter.movingSpeedMps &&
          distFromAccepted >= 1.0;

      if (waitingStepWhileMoving) {
        // Langkah di antara fix (< 2,5 m pada GPS 1–2 detik) saat berjalan stabil:
        // pertahankan movingTime & jendela pace, tetapi tetap kunci jarak & elevasi
        // sampai ambang >= 2,5 m / >= 4,0 m terpenuhi.
        _autoPause.update(t, filterSpeed);
        _prev = raw;
        final frozenAlt = _altitude.value;
        _latest = TrackingSnapshot(
          distanceM: _distance.totalMeters,
          movingTime: _autoPause.movingTime,
          elapsed: t.difference(_startedAt!),
          gainM: _elevation.gainMeters,
          lossM: _elevation.lossMeters,
          isMoving: _autoPause.isMoving,
          lastPoint:
              frozenAlt != null ? raw.copyWith(altitudeM: frozenAlt) : raw,
          paceSecPerKm: _pace.paceSecPerKm,
          averagePaceSecPerKm: PaceEstimator.computeAveragePaceSecPerKm(
            distanceM: _distance.totalMeters,
            movingSeconds: _autoPause.movingTime.inSeconds,
          ),
          verticalSpeedMph: _vertical.metersPerHour,
          kcalPerKg: _kcal.kcalPerKg,
        );
        return null;
      }

      // Fix diam / jitter nyata: kunci total jarak, waktu bergerak, dan elevasi
      // agar mengangkat/menggoyang HP saat berhenti selalu menghasilkan 0 m.
      _autoPause.onStationaryFix(t);
      _pace.add(t, _distance.totalMeters, isMoving: false);
      _vertical.markStationary();
      _prev = raw;

      final frozenAlt = _altitude.value;
      final avgPace = PaceEstimator.computeAveragePaceSecPerKm(
        distanceM: _distance.totalMeters,
        movingSeconds: _autoPause.movingTime.inSeconds,
      );
      _latest = TrackingSnapshot(
        distanceM: _distance.totalMeters,
        movingTime: _autoPause.movingTime,
        elapsed: t.difference(_startedAt!),
        gainM: _elevation.gainMeters,
        lossM: _elevation.lossMeters,
        isMoving: false,
        lastPoint: frozenAlt != null ? raw.copyWith(altitudeM: frozenAlt) : raw,
        paceSecPerKm: null,
        averagePaceSecPerKm: avgPace,
        verticalSpeedMph: 0,
        kcalPerKg: _kcal.kcalPerKg,
      );
      return null;
    }

    final implied = _impliedSpeed(raw);
    final rawSpeed = (raw.speedMps != null && raw.speedMps!.isFinite)
        ? raw.speedMps!
        : implied;
    final effectiveSpeed =
        _filter.smoothedSpeedMps != null && _filter.smoothedSpeedMps! > 0
            ? _filter.smoothedSpeedMps!
            : rawSpeed;

    _distance.add(raw);
    final distance = _distance.totalMeters;
    _autoPause.update(t, effectiveSpeed);
    _prev = raw;

    final moving = _autoPause.isMoving;
    _pace.add(
      t,
      distance,
      instantSpeedMps: raw.speedMps,
      isMoving: moving,
    );
    final paceSpeed = _pace.speedMps ?? effectiveSpeed;

    double? smoothAlt = _altitude.value;
    final alt = raw.altitudeM;
    final horizontalOk = raw.accuracyM.isFinite &&
        raw.accuracyM >= 0 &&
        raw.accuracyM <= _altitude.maxHorizontalAccuracyM;
    final verticalOk = raw.altitudeAccuracyM == null ||
        (raw.altitudeAccuracyM!.isFinite &&
            raw.altitudeAccuracyM! <= _altitude.maxAccuracyM);

    final horizFromEleAnchor = _lastElevationAnchor == null
        ? 0.0
        : distanceMeters(_lastElevationAnchor!, raw.position);
    final elevationUnlocked = !_hasElevationBaseline ||
        (moving && effectiveSpeed >= 0.4 && horizFromEleAnchor >= 4.0);

    if (elevationUnlocked &&
        alt != null &&
        alt.isFinite &&
        horizontalOk &&
        verticalOk) {
      smoothAlt = _altitude.addIfValid(
        alt,
        accuracyM: raw.altitudeAccuracyM,
        horizontalAccuracyM: raw.accuracyM,
      );
      if (smoothAlt != null) {
        _lastElevationAnchor = raw.position;
        _hasElevationBaseline = true;
        _elevation.add(smoothAlt, cumulativeDistanceM: distance);
        _vertical.add(
          t,
          smoothAlt,
          cumulativeDistanceM: distance,
          speedMps: paceSpeed,
        );
        _grade.add(t, distance, smoothAlt);
      }
    } else if (!moving) {
      _vertical.markStationary();
    }

    _kcal.add(
      t: t,
      speedMps: moving ? (_pace.speedMps ?? effectiveSpeed) : 0.0,
      grade: _grade.grade,
    );

    final avgPace = PaceEstimator.computeAveragePaceSecPerKm(
      distanceM: distance,
      movingSeconds: _autoPause.movingTime.inSeconds,
    );

    final filteredPoint =
        smoothAlt != null ? raw.copyWith(altitudeM: smoothAlt) : raw;

    final snapshot = TrackingSnapshot(
      distanceM: distance,
      movingTime: _autoPause.movingTime,
      elapsed: t.difference(_startedAt!),
      gainM: _elevation.gainMeters,
      lossM: _elevation.lossMeters,
      isMoving: moving,
      lastPoint: filteredPoint,
      paceSecPerKm: _pace.paceSecPerKm,
      averagePaceSecPerKm: avgPace,
      verticalSpeedMph: _vertical.metersPerHour,
      kcalPerKg: _kcal.kcalPerKg,
    );
    _latest = snapshot;
    return snapshot;
  }

  double _impliedSpeed(TrackPoint p) {
    final prev = _prev;
    if (prev == null) return 0;
    final dt =
        p.timestampUtc.difference(prev.timestampUtc).inMilliseconds / 1000.0;
    if (dt <= 0) return 0;
    return distanceMeters(prev.position, p.position) / dt;
  }
}
