/// Pemformat angka dan waktu bahasa Indonesia untuk layar Plus.
///
/// Semua waktu masuk dalam UTC dan hanya diubah ke lokal di sini, supaya
/// perhitungan domain tetap memakai satu zona waktu.
library;

const List<String> _monthsShort = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];

const List<String> _daysLong = <String>[
  'Senin',
  'Selasa',
  'Rabu',
  'Kamis',
  'Jumat',
  'Sabtu',
  'Minggu',
];

String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// Bilangan bulat dengan titik ribuan, mis. 1.250.
String groupDigits(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return negative ? '−$buffer' : buffer.toString();
}

/// Desimal dengan koma, mis. 3,2.
String formatDecimal(double value, {int digits = 1}) =>
    value.toStringAsFixed(digits).replaceAll('.', ',');

String formatKm(double meters) {
  final km = meters / 1000;
  return '${formatDecimal(km, digits: km >= 100 ? 0 : 1)} km';
}

String formatMeters(double meters) => '${groupDigits(meters.round())} m';

String formatDuration(int seconds) {
  final total = seconds < 0 ? 0 : seconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  if (hours > 0) return '${hours}j ${_twoDigits(minutes)}m';
  return '$minutes mnt';
}

String formatClock(DateTime time) =>
    '${_twoDigits(time.hour)}.${_twoDigits(time.minute)}';

String formatDate(DateTime time) {
  final local = time.toLocal();
  return '${local.day} ${_monthsShort[local.month - 1]} ${local.year}';
}

String formatDayDate(DateTime time) {
  final local = time.toLocal();
  return '${_daysLong[local.weekday - 1]}, ${local.day} '
      '${_monthsShort[local.month - 1]}';
}

String formatDayShort(DateTime time) {
  final local = time.toLocal();
  return _daysLong[local.weekday - 1];
}

String formatDayMonth(DateTime time) {
  final local = time.toLocal();
  return '${local.day} ${_monthsShort[local.month - 1]}';
}

String formatMonthYear(DateTime time) {
  final local = time.toLocal();
  return '${_monthsShort[local.month - 1]} ${local.year}';
}

/// Pace dalam detik per kilometer, mis. 12:30 /km.
String formatPace(double secondsPerKm) {
  final total = secondsPerKm.round();
  final minutes = total ~/ 60;
  final seconds = total % 60;
  return '$minutes:${_twoDigits(seconds)} /km';
}

String formatTemperature(double celsius) => '${celsius.round()}°C';

/// Kode tanggal ISO singkat untuk nama berkas, mis. 2026-10-31.
String isoDateForFile(DateTime time) {
  final local = time.toLocal();
  return '${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)}';
}
