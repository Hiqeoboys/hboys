import '../../../infrastructure/power/power_profile_manager.dart';
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

String formatPaceValue(double? secondsPerKm) {
  if (secondsPerKm == null ||
      !secondsPerKm.isFinite ||
      secondsPerKm <= 0 ||
      secondsPerKm > 36000) {
    return '—';
  }
  final seconds = secondsPerKm.round();
  final minutes = seconds ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$rest';
}

String formatVerticalSpeedValue(double? metersPerHour) {
  if (metersPerHour == null || !metersPerHour.isFinite) return '—';
  return _grouped(metersPerHour.round());
}

String formatStepCount(int? steps) =>
    steps == null || steps < 0 ? '—' : _grouped(steps);

String formatCaloriesValue(double? kcal) =>
    kcal == null || !kcal.isFinite || kcal < 0 ? '—' : _grouped(kcal.round());

String profileLabel(PowerProfile profile) => switch (profile) {
      PowerProfile.normal => 'Normal',
      PowerProfile.saver => 'Hemat',
      PowerProfile.critical => 'Kritis',
    };

String batteryStatusLabel(int? percent, PowerProfile profile) {
  if (percent == null) return 'Baterai tidak terbaca';
  return 'Baterai $percent% · ${profileLabel(profile)}';
}

/// Sampel ketinggian dari titik yang benar-benar tercatat. Titik tanpa
/// altitud dilewati, lalu deret dipangkas agar grafik tetap ringan.
List<double> elevationSeries(
  List<TrackPoint> points, {
  int maxSamples = 64,
}) {
  final altitudes = <double>[
    for (final point in points)
      if (point.altitudeM != null) point.altitudeM!,
  ];
  if (altitudes.length <= maxSamples) return altitudes;
  return <double>[
    for (var i = 0; i < maxSamples; i++)
      altitudes[(i * (altitudes.length - 1) / (maxSamples - 1)).round()],
  ];
}

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
