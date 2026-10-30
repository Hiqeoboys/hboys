import 'package:geo_utils/geo_utils.dart';

import 'auto_pause_detector.dart';
import 'distance_calculator.dart';
import 'elevation_processor.dart';
import 'gps_filter.dart';
import 'track_point.dart';

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
    this.verticalSpeedMph,
  });

  final double distanceM;
  final Duration movingTime;
  final Duration elapsed;
  final double gainM;
  final double lossM;
  final bool isMoving;
  final TrackPoint lastPoint;

  /// Detik per km, dihaluskan dengan jendela 60 detik. `null` jika belum cukup data.
  final double? paceSecPerKm;

  /// Meter per jam (positif = naik), jendela 5 menit. `null` jika belum cukup data.
  final double? verticalSpeedMph;
}

/// Menggabungkan filter GPS, jarak, elevasi, dan auto-pause menjadi satu
/// aliran metrik. Murni Dart: mudah diuji dengan fixture GPX.
class TrackingEngine {
  TrackingEngine({
    GpsFilter? filter,
    DistanceCalculator? distance,
    ElevationProcessor? elevation,
    AutoPauseDetector? autoPause,
  })  : _filter = filter ?? GpsFilter(),
        _distance = distance ?? DistanceCalculator(),
        _elevation = elevation ?? ElevationProcessor(),
        _autoPause = autoPause ?? AutoPauseDetector();

  final GpsFilter _filter;
  final DistanceCalculator _distance;
  final ElevationProcessor _elevation;
  final AutoPauseDetector _autoPause;

  static const Duration _paceWindow = Duration(seconds: 60);
  static const Duration _verticalWindow = Duration(minutes: 5);

  final List<(DateTime, double)> _distWindow = [];
  final List<(DateTime, double)> _altWindow = [];
  DateTime? _startedAt;
  TrackPoint? _prev;

  /// Memproses satu titik mentah. Mengembalikan `null` jika titik ditolak filter.
  TrackingSnapshot? onFix(TrackPoint raw) {
    final p = _filter.accept(raw);
    if (p == null) return null;

    _startedAt ??= p.timestampUtc;
    _distance.add(p);
    final alt = p.altitudeM;
    if (alt != null) {
      _elevation.add(alt);
      _altWindow.add((p.timestampUtc, alt));
    }

    final speed = p.speedMps ?? _impliedSpeed(p);
    _autoPause.update(p.timestampUtc, speed);
    _prev = p;

    _distWindow.add((p.timestampUtc, _distance.totalMeters));
    _trim(_distWindow, p.timestampUtc, _paceWindow);
    _trim(_altWindow, p.timestampUtc, _verticalWindow);

    return TrackingSnapshot(
      distanceM: _distance.totalMeters,
      movingTime: _autoPause.movingTime,
      elapsed: p.timestampUtc.difference(_startedAt!),
      gainM: _elevation.gainMeters,
      lossM: _elevation.lossMeters,
      isMoving: _autoPause.isMoving,
      lastPoint: p,
      paceSecPerKm: _pace(),
      verticalSpeedMph: _verticalSpeed(),
    );
  }

  double _impliedSpeed(TrackPoint p) {
    final prev = _prev;
    if (prev == null) return 0;
    final dt = p.timestampUtc.difference(prev.timestampUtc).inMilliseconds / 1000.0;
    if (dt <= 0) return 0;
    return distanceMeters(prev.position, p.position) / dt;
  }

  void _trim(List<(DateTime, double)> window, DateTime now, Duration span) {
    while (window.length > 1 && now.difference(window.first.$1) > span) {
      window.removeAt(0);
    }
  }

  double? _pace() {
    if (_distWindow.length < 2) return null;
    final first = _distWindow.first;
    final last = _distWindow.last;
    final meters = last.$2 - first.$2;
    final seconds = last.$1.difference(first.$1).inMilliseconds / 1000.0;
    if (meters < 10 || seconds <= 0) return null;
    return seconds / (meters / 1000.0);
  }

  double? _verticalSpeed() {
    if (_altWindow.length < 2) return null;
    final first = _altWindow.first;
    final last = _altWindow.last;
    final seconds = last.$1.difference(first.$1).inMilliseconds / 1000.0;
    if (seconds < 30) return null;
    return (last.$2 - first.$2) / seconds * 3600.0;
  }
}
