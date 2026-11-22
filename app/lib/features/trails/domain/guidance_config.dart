import 'dart:math' as math;

/// Konfigurasi parameter mesin pemandu rute kembali ke jalur.
class GuidanceConfig {
  const GuidanceConfig({
    this.offRouteMinM = 40.0,
    this.offRouteAccuracyFactor = 2.0,
    this.offRouteDwell = const Duration(seconds: 5),
    this.returnToleranceM = 20.0,
    this.returnDwell = const Duration(seconds: 3),
    this.lookaheadM = 25.0,
    this.targetReachedM = 12.0,
    this.trailMaxAccuracyM = 30.0,
    this.trailResampleM = 5.0,
    this.simplifyToleranceM = 4.0,
    this.staleFixSeconds = 10,
    this.headingSpeedThresholdMps = 1.0,
    this.switchbackWindowMeters = 300.0,
  });

  /// Ambang minimal jarak keluar jalur sebelum dinyatakan menyimpang (40 m).
  final double offRouteMinM;

  /// Faktor pengali akurasi GPS untuk menghitung ambang keluar jalur dinamis.
  final double offRouteAccuracyFactor;

  /// Durasi berturut-turut berada di luar ambang sebelum status keluar jalur aktif (5 dtk).
  final Duration offRouteDwell;

  /// Toleransi jarak kembali ke jalur (20 m).
  final double returnToleranceM;

  /// Durasi berturut-turut di dalam toleransi sebelum dinyatakan kembali (3 dtk).
  final Duration returnDwell;

  /// Jarak pandang ke depan pada jejak mundur untuk menentukan titik target (25 m).
  final double lookaheadM;

  /// Ambang jarak ke target untuk maju ke titik berikutnya pada jejak mundur (12 m).
  final double targetReachedM;

  /// Akurasi GPS maksimal titik jejak yang boleh dipakai untuk pemanduan (30 m).
  final double trailMaxAccuracyM;

  /// Jarak interpolasi ulang (resample) jejak terekam (5 m).
  final double trailResampleM;

  /// Toleransi Douglas-Peucker untuk menyederhanakan jejak (4 m).
  final double simplifyToleranceM;

  /// Batas umur data GPS sebelum dianggap basi (10 detik).
  final int staleFixSeconds;

  /// Ambang kecepatan untuk memilih course GPS vs kompas (1,0 m/s).
  final double headingSpeedThresholdMps;

  /// Jendela maju-mundur sepanjang rute untuk preferensi segmen switchback (300 m).
  final double switchbackWindowMeters;

  /// Ambang jarak keluar jalur: max(offRouteMinM, offRouteAccuracyFactor * akurasi).
  double offRouteThresholdM(double accuracyM) =>
      math.max(offRouteMinM, offRouteAccuracyFactor * accuracyM);

  /// Ambang jarak kembali ke jalur: max(returnToleranceM, akurasi).
  double returnThresholdM(double accuracyM) =>
      math.max(returnToleranceM, accuracyM);
}

