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

/// Kecepatan minimum (m/s) agar kalori dihitung.
const double kCalorieMinSpeedMps = 0.3;

/// Berat badan bawaan (kg) bila profil belum diisi.
const double kDefaultWeightKg = 65;

/// Kalori per kilogram berat badan untuk satu interval, memakai persamaan jalan
/// kaki ACSM:
///
///   VO2 (ml/kg/mnt) = 3,5 + 0,1 x v + 1,8 x v x kemiringan
///   kkal/mnt        = VO2 x berat(kg) / 1000 x 5
///
/// dengan v dalam m/menit dan kemiringan sebagai pecahan (naik positif).
/// Berlaku untuk v 20-130 m/menit. Di bawah itu (merayap) dipakai MET 2,0;
/// di atasnya (lari) dipakai MET sebanding kecepatan (km/jam, 7-18).
/// Mengembalikan 0 bila kecepatan < [kCalorieMinSpeedMps].
///
/// Hasil dikalikan berat badan untuk mendapatkan kkal. Karena persamaannya
/// linear terhadap berat, layanan latar cukup menyimpan kkal per kg.
double acsmKcalPerKg({
  required double speedMps,
  required double grade,
  required double seconds,
}) {
  if (seconds <= 0 || speedMps < kCalorieMinSpeedMps) return 0;
  final vPerMin = speedMps * 60.0;
  final minutes = seconds / 60.0;
  if (vPerMin < 20) {
    // MET 2,0: 1 MET = 3,5 ml/kg/mnt.
    return (2.0 * 3.5) / 1000.0 * 5.0 * minutes;
  }
  if (vPerMin > 130) {
    final kmh = speedMps * 3.6;
    final met = kmh.clamp(7.0, 18.0).toDouble();
    return (met * 3.5) / 1000.0 * 5.0 * minutes;
  }
  final vo2 = math.max(3.5, 3.5 + 0.1 * vPerMin + 1.8 * vPerMin * grade);
  return vo2 / 1000.0 * 5.0 * minutes;
}

/// Mengakumulasi kkal/kg per interval waktu bergerak.
class KcalAccumulator {
  KcalAccumulator({this.maxGap = const Duration(seconds: 30)});

  final Duration maxGap;
  DateTime? _lastT;
  double _kcalPerKg = 0;

  double get kcalPerKg => _kcalPerKg;

  /// [speedMps] `null` berarti kecepatan belum diketahui (tidak menambah).
  void add({
    required DateTime t,
    required double? speedMps,
    required double grade,
  }) {
    final last = _lastT;
    _lastT = t;
    if (last == null || speedMps == null) return;
    final dt = t.difference(last);
    if (dt <= Duration.zero || dt > maxGap) return;
    _kcalPerKg += acsmKcalPerKg(
      speedMps: speedMps,
      grade: grade,
      seconds: dt.inMilliseconds / 1000.0,
    );
  }
}
