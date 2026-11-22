import 'package:geo_utils/geo_utils.dart';

import 'track_point.dart';

/// Alasan sebuah fix tidak masuk rekaman.
enum FixRejectReason {
  /// Akurasi horizontal lebih buruk dari ambang.
  accuracy,

  /// Timestamp sama atau lebih lama dari fix sebelumnya.
  duplicateTime,

  /// Kecepatan tersirat melampaui batas wajar (loncatan GPS).
  jump,

  /// Perpindahan terlalu kecil atau kecepatan terlalu lambat saat diam (goyangan GPS).
  jitter,
}

/// Filter GPS berstandar Strava untuk akurasi jarak, kecepatan, & gerak nyata.
///
/// Aturan utama:
/// * akurasi <= [maxAccuracyM] (20 m) pada kondisi normal, atau <= [poorSignalAccuracyM]
///   (25 m) hanya saat pemanasan awal [warmupDuration] (20 detik) / kanopi hutan
///   setelah penolakan akurasi beruntun;
/// * timestamp duplikat atau mundur dibuang;
/// * loncatan dengan kecepatan tersirat > [maxSpeedMps] (12 m/s) dibuang;
/// * movement gate: perpindahan < [minMoveM] (2,5 m) ATAU kecepatan tersmooth (EMA)
///   < [movingSpeedMps] (0,45 m/s) dianggap diam (`jitter`) sehingga jarak, waktu
///   bergerak, dan elevasi tetap terkunci.
class GpsFilter {
  GpsFilter({
    this.maxAccuracyM = 20.0,
    this.poorSignalAccuracyM = 25.0,
    this.warmupDuration = const Duration(seconds: 20),
    this.maxSpeedMps = 12.0,
    this.minJumpMeters = 20.0,
    this.maxConsecutiveJumpRejects = 5,
    this.minMoveM = 2.5,
    this.movingSpeedMps = 0.45,
    this.speedEmaAlpha = 0.45,
  });

  final double maxAccuracyM;
  final double poorSignalAccuracyM;
  final Duration warmupDuration;

  /// Kecepatan tersirat di atas ini dianggap lompatan GPS (pendaki ~1–2 m/s).
  final double maxSpeedMps;

  /// Lompatan di bawah jarak ini tidak diperiksa sebagai loncatan.
  final double minJumpMeters;

  /// Setelah sekian penolakan loncatan beruntun, titik baru dijadikan acuan baru.
  final int maxConsecutiveJumpRejects;

  final double minMoveM;
  final double movingSpeedMps;
  final double speedEmaAlpha;

  TrackPoint? _last;
  DateTime? _firstFixAt;
  DateTime? _lastSeenAt;
  int _jumpRejects = 0;
  int _accuracyRejects = 0;
  double? _smoothedSpeedMps;

  TrackPoint? get lastAccepted => _last;
  double? get smoothedSpeedMps => _smoothedSpeedMps;

  /// Menilai satu fix. Mengembalikan `null` bila diterima, selain itu alasan
  /// penolakan. Titik acuan hanya maju untuk fix bergerak yang diterima.
  FixRejectReason? evaluate(TrackPoint p) {
    _firstFixAt ??= p.timestampUtc;
    final inWarmup = p.timestampUtc.difference(_firstFixAt!) <= warmupDuration;

    final previousSeen = _lastSeenAt;
    if (previousSeen != null && !p.timestampUtc.isAfter(previousSeen)) {
      return FixRejectReason.duplicateTime;
    }
    _lastSeenAt = p.timestampUtc;

    final allowPoorFallback = inWarmup || _accuracyRejects >= 3;
    final accuracyLimit = allowPoorFallback ? poorSignalAccuracyM : maxAccuracyM;
    if (!p.accuracyM.isFinite || p.accuracyM < 0 || p.accuracyM > accuracyLimit) {
      _accuracyRejects++;
      return FixRejectReason.accuracy;
    }
    _accuracyRejects = 0;

    final last = _last;
    if (last != null) {
      final dt =
          p.timestampUtc.difference(last.timestampUtc).inMilliseconds / 1000.0;
      if (dt <= 0) return FixRejectReason.duplicateTime;
      final d = distanceMeters(last.position, p.position);
      final implicitSpeed = d / dt;
      if (d > minJumpMeters &&
          implicitSpeed > maxSpeedMps &&
          _jumpRejects < maxConsecutiveJumpRejects) {
        _jumpRejects++;
        return FixRejectReason.jump;
      }

      final hasSensorSpeed =
          p.speedMps != null && p.speedMps!.isFinite && p.speedMps! >= 0;
      final rawSpeed = hasSensorSpeed
          ? ((p.speedMps! == 0 && d < 4.0)
              ? 0.0
              : 0.5 * p.speedMps! + 0.5 * implicitSpeed)
          : implicitSpeed;

      final prevEma = _smoothedSpeedMps;
      if (prevEma == null ||
          (prevEma < movingSpeedMps &&
              rawSpeed >= movingSpeedMps &&
              d >= minMoveM)) {
        _smoothedSpeedMps = rawSpeed;
      } else {
        _smoothedSpeedMps = prevEma + speedEmaAlpha * (rawSpeed - prevEma);
      }

      if (d < minMoveM || _smoothedSpeedMps! < movingSpeedMps) {
        if (d < minMoveM && rawSpeed < movingSpeedMps) {
          _smoothedSpeedMps = _smoothedSpeedMps! * (1.0 - speedEmaAlpha);
        }
        return FixRejectReason.jitter;
      }
    } else if (p.speedMps != null && p.speedMps!.isFinite && p.speedMps! >= 0) {
      _smoothedSpeedMps = p.speedMps!;
    }

    _jumpRejects = 0;
    _last = p;
    return null;
  }

  /// Kompatibilitas: mengembalikan titik bila diterima, `null` bila tidak.
  TrackPoint? accept(TrackPoint p) => evaluate(p) == null ? p : null;

  void reset() {
    _last = null;
    _firstFixAt = null;
    _lastSeenAt = null;
    _jumpRejects = 0;
    _accuracyRejects = 0;
    _smoothedSpeedMps = null;
  }
}
