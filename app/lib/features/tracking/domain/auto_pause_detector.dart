/// Mendeteksi berhenti/bergerak untuk menghitung waktu bergerak (moving time).
class AutoPauseDetector {
  AutoPauseDetector({
    this.pauseBelowMps = 0.5,
    this.resumeAboveMps = 0.8,
    this.pauseAfter = const Duration(seconds: 10),
    this.maxGap = const Duration(seconds: 30),
  });

  final double pauseBelowMps;
  final double resumeAboveMps;
  final Duration pauseAfter;

  /// Selisih waktu antar update yang lebih besar dari ini (sinyal hilang)
  /// tidak dihitung sebagai waktu bergerak.
  final Duration maxGap;

  DateTime? _lastT;
  DateTime? _slowSince;
  bool _moving = true;
  Duration _movingTime = Duration.zero;

  bool get isMoving => _moving;
  Duration get movingTime => _movingTime;

  void update(DateTime t, double speedMps) {
    final last = _lastT;
    _lastT = t;
    if (last == null) return;
    final dt = t.difference(last);
    if (dt.isNegative) return;

    if (_moving) {
      if (speedMps < pauseBelowMps) {
        _slowSince ??= t;
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
    }
  }
}
