import 'package:geo_utils/geo_utils.dart';

import 'track_point.dart';

/// Mengakumulasi jarak. Pergerakan di bawah [minStepMeters] relatif terhadap
/// titik terakhir yang dihitung diabaikan agar GPS yang bergoyang saat diam
/// tidak menambah jarak.
class DistanceCalculator {
  DistanceCalculator({this.minStepMeters = 3});

  final double minStepMeters;
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
    if (d >= minStepMeters) {
      _total += d;
      _anchor = p;
    }
  }
}
