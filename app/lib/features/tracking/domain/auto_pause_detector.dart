/// Mendeteksi berhenti/bergerak untuk menghitung waktu bergerak (`movingTime`).
///
/// Memulai dalam kondisi diam (`isMoving == false`) sehingga pengguna yang
/// hanya berdiri di titik awal tidak mengumpulkan waktu bergerak palsu.
class AutoPauseDetector {
  AutoPauseDetector({
    this.pauseBelowMps = 0.45,
    this.resumeAboveMps = 0.45,
    this.pauseAfter = const Duration(seconds: 4),
    this.maxGap = const Duration(seconds: 60),
  });

  final double pauseBelowMps;
  final double resumeAboveMps;
  final Duration pauseAfter;

  /// Selisih waktu antar update yang lebih besar dari ini (sinyal hilang)
  /// tidak dihitung sebagai waktu bergerak.
  final Duration maxGap;

  DateTime? _lastT;
  DateTime? _slowSince;
  bool _moving = false;
  Duration _movingTime = Duration.zero;

  bool get isMoving => _moving;
  Duration get movingTime => _movingTime;

  /// Dipanggil saat fix ditolak oleh movement gate (`jitter` / diam) sehingga
  /// waktu berhenti tidak pernah dihitung ke [movingTime] dan [lastT] tetap maju.
  void onStationaryFix(DateTime t) {
    final last = _lastT;
    if (last == null || t.isAfter(last)) {
      _lastT = t;
    }
    _moving = false;
    _slowSince = null;
  }

  void update(DateTime t, double speedMps) {
    final last = _lastT;
    _lastT = t;
    if (last == null) {
      _moving = speedMps >= resumeAboveMps;
      return;
    }
    final dt = t.difference(last);
    if (dt.isNegative) return;

    if (_moving) {
      if (speedMps < pauseBelowMps) {
        _slowSince ??= last;
        if (t.difference(_slowSince!) >= pauseAfter) {
          _moving = false;
          return;
        }
      } else {
        _slowSince = null;
      }
      if (dt <= maxGap) _movingTime += dt;
    } else if (speedMps >= resumeAboveMps) {
      _moving = true;
      _slowSince = null;
      if (dt <= maxGap) _movingTime += dt;
    }
  }
}
