import '../../tracking/domain/tracking_session.dart';

/// Mengembalikan `true` hanya untuk sesi selesai yang valid (punya jarak atau
/// waktu bergerak nyata, bukan sesi uji/batal kosong 0 m / 0 dtk).
bool isMeaningfulCompletedSession(TrackingSession session) {
  if (session.status != TrackingSessionStatus.completed) return false;
  return session.distanceM >= 10.0 ||
      session.movingSeconds >= 60 ||
      session.elevationGainM > 0;
}

/// Nilai tanjakan kanonik satu sesi agar Profil, Riwayat, & Analitik selalu
/// menjumlahkan angka yang persis sama.
double canonicalSessionElevationGain(TrackingSession session) {
  final gain = session.elevationGainM;
  if (!gain.isFinite || gain <= 0) return 0.0;
  return gain;
}

/// Mengembalikan hanya sesi pendakian (non-jogging) selesai yang valid.
List<TrackingSession> validCompletedHikingSessions(
  Iterable<TrackingSession> sessions,
) =>
    sessions
        .where((s) => isMeaningfulCompletedSession(s) && !s.isJogging)
        .toList(growable: false);

/// Ringkasan lokal untuk layar Profil. Hanya sesi pendakian (non-jogging)
/// selesai yang valid dihitung agar statistik Profil konsisten 100% dengan
/// tab Riwayat Pendakian.
class ProfileSummary {
  const ProfileSummary({
    required this.hikeCount,
    required this.distanceM,
    required this.elevationGainM,
  });

  static const ProfileSummary empty = ProfileSummary(
    hikeCount: 0,
    distanceM: 0,
    elevationGainM: 0,
  );

  factory ProfileSummary.fromSessions(Iterable<TrackingSession> sessions) {
    var count = 0;
    var distance = 0.0;
    var gain = 0.0;
    for (final session in validCompletedHikingSessions(sessions)) {
      count++;
      if (session.distanceM.isFinite && session.distanceM > 0) {
        distance += session.distanceM;
      }
      gain += canonicalSessionElevationGain(session);
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
