import '../../../infrastructure/power/power_profile_manager.dart';
import '../domain/elevation_profile.dart';
import '../domain/track_point.dart';

/// Teks metrik Pelacakan. Semua nilai berasal dari rekaman nyata; nilai yang
/// belum punya sumber ditampilkan "—", bukan angka karangan.
String formatTimer(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final secs = safe % 60;
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${secs.toString().padLeft(2, '0')}';
}

String formatDistanceValue(double meters) {
  final km = meters / 1000;
  return _decimal(km, 1);
}

String formatElevationValue(double meters) => _grouped(meters.round());

/// Pace dalam menit:detik per km, dibatasi ke 3:00 (180 dtk) s/d 60:00 (3600 dtk).
String formatPaceValue(double? secondsPerKm) {
  if (secondsPerKm == null ||
      !secondsPerKm.isFinite ||
      secondsPerKm < 180 ||
      secondsPerKm > 3600) {
    return '—';
  }
  final seconds = secondsPerKm.round();
  final minutes = seconds ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$rest';
}

/// Kecepatan vertikal dalam m/jam, dibatasi ke +/- 3.000 m/jam.
String formatVerticalSpeedValue(double? metersPerHour) {
  if (metersPerHour == null || !metersPerHour.isFinite) return '—';
  final clamped = metersPerHour.clamp(-3000.0, 3000.0);
  return _grouped(clamped.round());
}

String formatStepCount(int? steps, {bool estimated = false}) {
  if (steps == null || steps < 0) return '—';
  final grouped = _grouped(steps);
  return estimated ? '~$grouped' : grouped;
}

String formatCaloriesValue(double? kcal) =>
    kcal == null || !kcal.isFinite || kcal < 0 ? '—' : _grouped(kcal.round());

/// Benar bila fix valid terakhir sudah lebih tua dari [maxAge] (bawaan 10 detik).
bool isFixStale(
  DateTime? lastValidFixAtUtc,
  DateTime nowUtc, {
  Duration maxAge = const Duration(seconds: 10),
}) {
  if (lastValidFixAtUtc == null) return false;
  return nowUtc.difference(lastValidFixAtUtc) > maxAge;
}

String profileLabel(PowerProfile profile) => switch (profile) {
      PowerProfile.normal => 'Normal',
      PowerProfile.saver => 'Hemat',
      PowerProfile.critical => 'Kritis',
    };

/// Sampel ketinggian dari titik yang benar-benar tercatat (tiap 10 m atau 5 dtk,
/// dihaluskan rata-rata bergerak 5 titik, maksimal 120 titik).
List<double> elevationSeries(
  List<TrackPoint> points, {
  int maxSamples = 120,
}) =>
    buildElevationProfile(points, maxSamples: maxSamples);

String _decimal(double value, int digits) {
  final text = value.toStringAsFixed(digits);
  return text.replaceAll('.', ',');
}

String _grouped(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return negative ? '-$buffer' : buffer.toString();
}
