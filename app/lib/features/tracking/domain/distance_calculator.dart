import 'package:geo_utils/geo_utils.dart';

import 'track_point.dart';

/// Mengakumulasi jarak sebagai jumlah Haversine antar titik yang lolos filter.
///
/// Penyaringan goyangan GPS (perpindahan kecil) dilakukan oleh `GpsFilter`;
/// [minStepMeters] tersedia untuk pemakaian mandiri dan bernilai 0 secara
/// bawaan.
class DistanceCalculator {
  DistanceCalculator({
    this.minStepMeters = 2.0,
    this.minMovingSpeedMps = 0.8,
  });

  final double minStepMeters;
  final double minMovingSpeedMps;
  TrackPoint? _anchor;
  double _total = 0;

  double get totalMeters => _total;

  void add(TrackPoint p) {
    final anchor = _anchor;
    if (anchor == null) {
      _anchor = p;
      return;
    }
    final d = distanceMeters(anchor.position, p.position);
    final measuredSpeed = p.speedMps ?? 0;
    if (d >= minStepMeters || measuredSpeed > minMovingSpeedMps) {
      _total += d;
      _anchor = p;
    }
  }
}
