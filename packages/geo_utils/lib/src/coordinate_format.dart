import 'geo.dart';

/// Derajat desimal, mis. "-6.917500, 107.619100".
String formatDecimal(LatLng p, {int digits = 6}) =>
    '${p.lat.toStringAsFixed(digits)}, ${p.lon.toStringAsFixed(digits)}';

/// Derajat-menit-detik, mis. `6° 55' 3.0" S 107° 37' 8.8" E`.
String formatDms(LatLng p) {
  String one(double value, String positive, String negative) {
    final hemisphere = value >= 0 ? positive : negative;
    final abs = value.abs();
    var degrees = abs.floor();
    final minutesFull = (abs - degrees) * 60;
    var minutes = minutesFull.floor();
    var seconds = double.parse(((minutesFull - minutes) * 60).toStringAsFixed(1));
    if (seconds >= 60) {
      seconds = 0;
      minutes += 1;
    }
    if (minutes >= 60) {
      minutes = 0;
      degrees += 1;
    }
    return "$degrees° $minutes' ${seconds.toStringAsFixed(1)}\" $hemisphere";
  }

  return '${one(p.lat, 'N', 'S')} ${one(p.lon, 'E', 'W')}';
}

// TODO(tim): formatUtm(LatLng) -- tim SAR sering memakai UTM. Implementasikan
// dan uji dengan titik acuan resmi sebelum dipakai di pesan SOS.
