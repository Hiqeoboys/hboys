import 'package:geo_utils/geo_utils.dart';

enum TrailState { onTrail, offTrail }

/// Deteksi keluar jalur dengan histeresis: butuh beberapa titik beruntun di
/// luar [offThresholdM] untuk dianggap keluar, dan harus kembali ke dalam
/// [onThresholdM] untuk dianggap kembali. Mencegah alarm berkedip di tepi ambang.
class OffTrailDetector {
  OffTrailDetector({
    required this.trail,
    this.offThresholdM = 50,
    this.onThresholdM = 30,
    this.confirmFixes = 3,
  }) : assert(onThresholdM <= offThresholdM);

  final List<LatLng> trail;
  final double offThresholdM;
  final double onThresholdM;
  final int confirmFixes;

  TrailState _state = TrailState.onTrail;
  int _offStreak = 0;
  double? _lastDistance;

  TrailState get state => _state;

  /// Jarak ke jalur pada titik terakhir (meter), jika ada.
  double? get lastDistanceM => _lastDistance;

  /// Memperbarui dengan posisi baru; mengembalikan state terkini.
  TrailState update(LatLng position) {
    final d = distanceToPolylineMeters(position, trail);
    _lastDistance = d;
    if (_state == TrailState.onTrail) {
      if (d > offThresholdM) {
        _offStreak++;
        if (_offStreak >= confirmFixes) _state = TrailState.offTrail;
      } else {
        _offStreak = 0;
      }
    } else if (d < onThresholdM) {
      _state = TrailState.onTrail;
      _offStreak = 0;
    }
    return _state;
  }
}
