import '../../tracking/domain/tracking_session.dart';

/// Ringkasan lokal untuk layar Profil. Hanya sesi selesai yang dihitung;
/// sesi berjalan belum boleh diklaim sebagai pendakian yang selesai.
class ProfileSummary {
  const ProfileSummary({
    required this.hikeCount,
    required this.distanceM,
    required this.elevationGainM,
  });

  factory ProfileSummary.fromSessions(Iterable<TrackingSession> sessions) {
    var count = 0;
    var distance = 0.0;
    var gain = 0.0;
    for (final session in sessions) {
      if (session.status != TrackingSessionStatus.completed) continue;
      count++;
      distance += session.distanceM;
      gain += session.elevationGainM;
    }
    return ProfileSummary(
      hikeCount: count,
      distanceM: distance,
      elevationGainM: gain,
    );
  }

  final int hikeCount;
  final double distanceM;
  final double elevationGainM;

  String get hikeCountLabel => '$hikeCount';

  String get distanceLabel => formatProfileDistance(distanceM);

  String get elevationGainLabel => '${_grouped(elevationGainM.round())} m';
}

/// Angka jarak profil mengikuti contoh rancangan: 31 km dan 148 km tanpa
/// desimal. Jarak di bawah 10 km tetap satu desimal supaya pendakian pendek
/// tidak tampak nol.
String formatProfileDistance(double meters) {
  final safe = meters.isFinite && meters > 0 ? meters : 0.0;
  final km = safe / 1000;
  if (km >= 10) return '${_grouped(km.round())} km';
  final text = km.toStringAsFixed(1).replaceAll('.', ',');
  return text == '0,0' ? '0 km' : '$text km';
}

String _grouped(int value) {
  if (value == 0) return '0';
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return value < 0 ? '−$buffer' : buffer.toString();
}
