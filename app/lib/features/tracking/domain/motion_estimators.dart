import 'dart:math' as math;

/// Menghaluskan ketinggian berstandar Strava:
/// * tolak akurasi buruk (`altitudeAccuracy > 25 m` atau horizontal `> 25 m`);
/// * redam lonjakan mendadak dengan median [medianSize] (5 titik);
/// * haluskan dengan moving average [movingAverageSize] (5–7 titik) di atas
///   keluaran median agar jalan/lari datar selalu stabil 0 m tanjakan palsu.
class AltitudeSmoother {
  AltitudeSmoother({
    this.medianSize = 5,
    this.movingAverageSize = 5,
    this.maxAccuracyM = 25.0,
    this.maxHorizontalAccuracyM = 25.0,
  });

  final int medianSize;
  final int movingAverageSize;
  final double maxAccuracyM;
  final double maxHorizontalAccuracyM;

  final List<double> _recentRaw = <double>[];
  final List<double> _recentMedians = <double>[];
  double? _estimate;

  double? get value => _estimate;

  double? addIfValid(
    double altitudeM, {
    double? accuracyM,
    double? horizontalAccuracyM,
  }) {
    if (!altitudeM.isFinite) return _estimate;
    if (accuracyM != null && (!accuracyM.isFinite || accuracyM > maxAccuracyM)) {
      return _estimate;
    }
    if (horizontalAccuracyM != null &&
        (!horizontalAccuracyM.isFinite ||
            horizontalAccuracyM > maxHorizontalAccuracyM)) {
      return _estimate;
    }
    return add(
      altitudeM,
      accuracyM: accuracyM,
      horizontalAccuracyM: horizontalAccuracyM,
    );
  }

  double add(
    double altitudeM, {
    double? accuracyM,
    double? horizontalAccuracyM,
  }) {
    final verticalInvalid =
        accuracyM != null && (!accuracyM.isFinite || accuracyM > maxAccuracyM);
    final horizontalInvalid = horizontalAccuracyM != null &&
        (!horizontalAccuracyM.isFinite ||
            horizontalAccuracyM > maxHorizontalAccuracyM);
    if ((verticalInvalid || horizontalInvalid) && _estimate != null) {
      return _estimate!;
    }

    _recentRaw.add(altitudeM);
    if (_recentRaw.length > medianSize) _recentRaw.removeAt(0);
    final sorted = List<double>.of(_recentRaw)..sort();
    final median = sorted[sorted.length ~/ 2];

    _recentMedians.add(median);
    if (_recentMedians.length > movingAverageSize) _recentMedians.removeAt(0);
    final sum = _recentMedians.reduce((a, b) => a + b);
    final smoothed = sum / _recentMedians.length;
    _estimate = smoothed;
    return smoothed;
  }
}

class _Sample {
  const _Sample(this.t, this.v);
  final DateTime t;
  final double v;
}

/// Kecepatan (m/s) dan pace live pada jendela geser 10–15 detik berstandar Strava
/// (menggabungkan kecepatan sensor GPS valid dengan delta jarak/waktu melalui EMA),
/// ditambah helper pace rata-rata sesi (`movingSeconds / km`, `null` < 30 m).
class PaceEstimator {
  PaceEstimator({
    this.window = const Duration(seconds: 15),
    this.minSpan = const Duration(seconds: 10),
    this.minDistanceM = 10,
    this.minSpeedMps = 0.45,
    this.emaAlpha = 0.35,
    this.minPaceSec = 60,
    this.maxPaceSec = 3600,
  });

  final Duration window;
  final Duration minSpan;
  final double minDistanceM;
  final double minSpeedMps;
  final double emaAlpha;
  final double minPaceSec;
  final double maxPaceSec;

  final List<_Sample> _samples = <_Sample>[];
  double? _emaSpeedMps;

  /// Pace rata-rata total sesi: selalu `movingSeconds / totalDistanceKm` dan
  /// mengembalikan `null` bila jarak tersaring masih di bawah [minDistanceM] (30 m).
  static double? computeAveragePaceSecPerKm({
    required double distanceM,
    required int movingSeconds,
    double minDistanceM = 30.0,
  }) {
    if (!distanceM.isFinite || distanceM < minDistanceM || movingSeconds <= 0) {
      return null;
    }
    return movingSeconds / (distanceM / 1000.0);
  }

  /// Menambah sampel (waktu, jarak kumulatif) pada jendela 10–15 detik.
  /// Saat [isMoving] == false, live pace dibekukan/dikosongkan sehingga waktu
  /// berhenti tidak pernah mengencerkan pace berjalan/berlari berikutnya.
  void add(
    DateTime t,
    double cumulativeMeters, {
    double? instantSpeedMps,
    bool isMoving = true,
  }) {
    if (!isMoving) {
      _samples.clear();
      _emaSpeedMps = null;
      return;
    }

    _samples.add(_Sample(t, cumulativeMeters));
    while (_samples.length > 2 && t.difference(_samples[1].t) > window) {
      _samples.removeAt(0);
    }

    if (_samples.length < 2) return;
    final first = _samples.first;
    final last = _samples.last;
    final span = last.t.difference(first.t);
    final spanSec = span.inMilliseconds / 1000.0;
    final meters = last.v - first.v;
    final hasValidSensor =
        instantSpeedMps != null && instantSpeedMps.isFinite && instantSpeedMps >= minSpeedMps;

    double? candidate;
    if (span >= minSpan && meters >= minDistanceM && spanSec > 0) {
      final windowSpeed = meters / spanSec;
      candidate = hasValidSensor
          ? (0.7 * windowSpeed + 0.3 * instantSpeedMps)
          : windowSpeed;
    } else if (hasValidSensor &&
        span >= const Duration(seconds: 4) &&
        meters >= 6.0 &&
        spanSec > 0) {
      final windowSpeed = meters / spanSec;
      candidate = 0.55 * windowSpeed + 0.45 * instantSpeedMps;
    }

    if (candidate == null || candidate < minSpeedMps) {
      if (span >= minSpan && meters < minDistanceM) {
        _emaSpeedMps = null;
      }
      return;
    }

    final prev = _emaSpeedMps;
    _emaSpeedMps = prev == null
        ? candidate
        : prev + emaAlpha * (candidate - prev);
  }

  double? get speedMps {
    final s = _emaSpeedMps;
    if (s == null || s < minSpeedMps) return null;
    return s;
  }

  double? get paceSecPerKm => paceFromSpeed(speedMps);

  /// 1000 / v detik per km; `null` di luar rentang tampilan.
  double? paceFromSpeed(double? speed) {
    if (speed == null || speed <= 0) return null;
    final pace = 1000.0 / speed;
    if (pace < minPaceSec || pace > maxPaceSec) return null;
    return pace;
  }
}

class _VerticalSample {
  const _VerticalSample(
    this.t,
    this.altitude,
    this.cumulativeDistanceM,
    this.speedMps,
  );

  final DateTime t;
  final double altitude;
  final double? cumulativeDistanceM;
  final double? speedMps;
}

/// Kecepatan vertikal (m/jam) dari ketinggian terhaluskan pada jendela 45–60 detik
/// dilengkapi stationary gate dan dead-band >= 3 m pada elevasi nyata saat bergerak.
class VerticalSpeedEstimator {
  VerticalSpeedEstimator({
    this.window = const Duration(seconds: 60),
    this.minSpan = const Duration(seconds: 45),
    this.deadBandM = 3.0,
    this.minSpeedMps = 0.45,
    this.minHorizontalM = 8.0,
    this.maxMph = 3000,
  });

  final Duration window;
  final Duration minSpan;
  final double deadBandM;
  final double minSpeedMps;
  final double minHorizontalM;
  final double maxMph;

  final List<_VerticalSample> _samples = <_VerticalSample>[];
  bool _stationary = false;

  void markStationary() {
    _stationary = true;
  }

  void add(
    DateTime t,
    double smoothedAltitudeM, {
    double? cumulativeDistanceM,
    double? speedMps,
  }) {
    _stationary = speedMps != null && speedMps < minSpeedMps;
    _samples.add(
      _VerticalSample(t, smoothedAltitudeM, cumulativeDistanceM, speedMps),
    );
    while (_samples.length > 2 && t.difference(_samples[1].t) >= window) {
      _samples.removeAt(0);
    }
  }

  double? get metersPerHour {
    if (_stationary) return 0;
    if (_samples.length < 2) return null;
    final first = _samples.first;
    final last = _samples.last;

    if (last.speedMps != null && last.speedMps! < minSpeedMps) {
      return 0;
    }

    final span = last.t.difference(first.t);
    if (span < minSpan) return null;

    if (first.cumulativeDistanceM != null && last.cumulativeDistanceM != null) {
      final horizontalDelta =
          last.cumulativeDistanceM! - first.cumulativeDistanceM!;
      if (horizontalDelta < minHorizontalM) {
        return 0;
      }
    }

    final delta = last.altitude - first.altitude;
    if (delta.abs() < deadBandM) return 0;
    final mph = delta / (span.inMilliseconds / 1000.0) * 3600.0;
    return mph.clamp(-maxMph, maxMph).toDouble();
  }
}

/// Kemiringan rata-rata (pecahan, naik positif) pada jendela geser 30 detik,
/// dipakai persamaan kalori ACSM.
class GradeEstimator {
  GradeEstimator({
    this.window = const Duration(seconds: 30),
    this.minDistanceM = 5,
  });

  final Duration window;
  final double minDistanceM;

  final List<_GradeSample> _samples = <_GradeSample>[];

  void add(DateTime t, double cumulativeMeters, double smoothedAltitudeM) {
    _samples.add(_GradeSample(t, cumulativeMeters, smoothedAltitudeM));
    while (_samples.length > 2 && t.difference(_samples[1].t) >= window) {
      _samples.removeAt(0);
    }
  }

  double get grade {
    if (_samples.length < 2) return 0;
    final first = _samples.first;
    final last = _samples.last;
    final run = last.distance - first.distance;
    if (run < minDistanceM) return 0;
    return math.max(
      -0.10,
      math.min(0.35, (last.altitude - first.altitude) / run),
    );
  }
}

class _GradeSample {
  const _GradeSample(this.t, this.distance, this.altitude);
  final DateTime t;
  final double distance;
  final double altitude;
}
