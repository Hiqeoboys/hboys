import 'dart:math' as math;

/// Estimasi kalori berbasis MET. Ini PERKIRAAN, bukan pengukuran.
/// Koefisien di bawah adalah titik awal dan WAJIB dikalibrasi/divalidasi
/// terhadap rujukan sebelum angkanya dipromosikan ke pengguna.
double estimateKcal({
  required double weightKg,
  required Duration movingTime,
  double avgGradePercent = 0,
  double packKg = 0,
}) {
  final met = (4.5 + 0.3 * math.max(0, avgGradePercent)).clamp(3.0, 10.0).toDouble();
  final hours = movingTime.inSeconds / 3600.0;
  return met * (weightKg + packKg) * hours;
}
