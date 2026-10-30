import 'package:geo_utils/geo_utils.dart';

import 'track_point.dart';

/// Membuang titik GPS yang buruk: akurasi jelek dan lompatan tidak wajar.
class GpsFilter {
  GpsFilter({
    this.maxAccuracyM = 25,
    this.maxSpeedMps = 12,
    this.minJumpMeters = 20,
    this.maxConsecutiveJumpRejects = 5,
  });

  final double maxAccuracyM;

  /// Kecepatan tersirat di atas ini dianggap lompatan (pendaki ~1-2 m/s).
  final double maxSpeedMps;

  /// Lompatan di bawah jarak ini tidak diperiksa (jitter normal).
  final double minJumpMeters;

  /// Setelah sekian penolakan beruntun, titik baru dijadikan acuan baru
  /// (mencegah semua titik ditolak jika titik pertama ternyata pencilan).
  final int maxConsecutiveJumpRejects;

  TrackPoint? _last;
  int _jumpRejects = 0;

  TrackPoint? get lastAccepted => _last;

  /// Mengembalikan titik jika diterima, `null` jika ditolak.
  TrackPoint? accept(TrackPoint p) {
    if (p.accuracyM > maxAccuracyM) return null;

    final last = _last;
    if (last != null) {
      final dt = p.timestampUtc.difference(last.timestampUtc).inMilliseconds / 1000.0;
      if (dt <= 0) return null;
      final d = distanceMeters(last.position, p.position);
      if (d > minJumpMeters &&
          d / dt > maxSpeedMps &&
          _jumpRejects < maxConsecutiveJumpRejects) {
        _jumpRejects++;
        return null;
      }
    }
    _jumpRejects = 0;
    _last = p;
    return p;
  }

  void reset() {
    _last = null;
    _jumpRejects = 0;
  }
}
