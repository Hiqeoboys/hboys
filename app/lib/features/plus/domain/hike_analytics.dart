import 'dart:math' as math;

import 'package:geo_utils/geo_utils.dart';

import '../../tracking/domain/track_point.dart';
import '../../tracking/domain/tracking_session.dart';

/// Rentang analitik sesuai tab D4.
///
/// "Terakhir" berarti lima pendakian selesai terbaru, bukan rentang hari,
/// karena pendaki tidak selalu mendaki setiap bulan.
enum PlusAnalyticsRange { recent, year, all }

extension PlusAnalyticsRangeLabel on PlusAnalyticsRange {
  String get label => switch (this) {
        PlusAnalyticsRange.recent => 'Terakhir',
        PlusAnalyticsRange.year => 'Tahun ini',
        PlusAnalyticsRange.all => 'Semua',
      };

  /// Penjelasan singkat di bawah tab agar "Terakhir" tidak ambigu.
  String get description => switch (this) {
        PlusAnalyticsRange.recent => 'Lima pendakian selesai terbaru',
        PlusAnalyticsRange.year => 'Pendakian selesai tahun ini',
        PlusAnalyticsRange.all => 'Seluruh riwayat di HP ini',
      };
}

enum SlopeKind { uphill, flat, downhill }

extension SlopeKindLabel on SlopeKind {
  String get label => switch (this) {
        SlopeKind.uphill => 'Menanjak',
        SlopeKind.flat => 'Datar',
        SlopeKind.downhill => 'Menurun',
      };

  String get gradeHint => switch (this) {
        SlopeKind.uphill => 'kemiringan di atas 3%',
        SlopeKind.flat => 'kemiringan −3% sampai 3%',
        SlopeKind.downhill => 'kemiringan di bawah −3%',
      };
}

/// Satu sesi selesai dengan titiknya.
class HikeSample {
  const HikeSample({required this.session, required this.points});

  final TrackingSession session;
  final List<TrackPoint> points;
}

/// Pace pada satu kelas kemiringan.
///
/// Hanya dihitung dari segmen yang punya altitude dan jeda antar-titik paling
/// lama 60 detik, sehingga istirahat panjang tidak dianggap berjalan lambat.
class SlopePace {
  const SlopePace({
    required this.kind,
    required this.distanceM,
    required this.movingSeconds,
  });

  final SlopeKind kind;
  final double distanceM;
  final int movingSeconds;

  /// Minimal 100 m agar satu segmen aneh tidak menjadi "pace".
  bool get hasData => distanceM >= 100 && movingSeconds > 0;

  double? get secondsPerKm =>
      hasData ? movingSeconds / (distanceM / 1000) : null;
}

class PersonalRecord {
  const PersonalRecord({
    required this.label,
    required this.value,
    required this.occurredAtUtc,
  });

  final String label;
  final String value;
  final DateTime occurredAtUtc;
}

/// Perbandingan pace paruh pertama dan kedua per sesi.
///
/// Lambat di paruh kedua adalah sinyal kelelahan; tidak ada kategori kecepatan
/// karena aplikasi tidak memeringkat kecepatan pendaki.
class FatigueAnalysis {
  const FatigueAnalysis({
    required this.firstHalfSecondsPerKm,
    required this.secondHalfSecondsPerKm,
    required this.sessionsUsed,
  });

  const FatigueAnalysis.empty()
      : firstHalfSecondsPerKm = null,
        secondHalfSecondsPerKm = null,
        sessionsUsed = 0;

  final double? firstHalfSecondsPerKm;
  final double? secondHalfSecondsPerKm;
  final int sessionsUsed;

  bool get hasData =>
      firstHalfSecondsPerKm != null && secondHalfSecondsPerKm != null;

  /// Positif berarti paruh kedua lebih lambat.
  double? get slowdownPercent {
    final first = firstHalfSecondsPerKm;
    final second = secondHalfSecondsPerKm;
    if (first == null || second == null || first <= 0) return null;
    return ((second - first) / first) * 100;
  }
}

/// Analitik lanjutan dari sesi yang benar-benar tersimpan di perangkat.
class HikeAnalytics {
  const HikeAnalytics({
    required this.sampleCount,
    required this.distanceM,
    required this.movingSeconds,
    required this.elevationGainM,
    required this.slopePaces,
    required this.verticalSpeedMPerHour,
    required this.records,
    required this.fatigue,
  });

  const HikeAnalytics.empty()
      : sampleCount = 0,
        distanceM = 0,
        movingSeconds = 0,
        elevationGainM = 0,
        slopePaces = const <SlopePace>[],
        verticalSpeedMPerHour = null,
        records = const <PersonalRecord>[],
        fatigue = const FatigueAnalysis.empty();

  final int sampleCount;
  final double distanceM;
  final int movingSeconds;
  final double elevationGainM;
  final List<SlopePace> slopePaces;
  final double? verticalSpeedMPerHour;
  final List<PersonalRecord> records;
  final FatigueAnalysis fatigue;

  bool get isEmpty => sampleCount == 0;

  static HikeAnalytics build(List<HikeSample> samples) {
    if (samples.isEmpty) return const HikeAnalytics.empty();

    var distanceM = 0.0;
    var movingSeconds = 0;
    var elevationGainM = 0.0;
    final slopeDistance = <SlopeKind, double>{
      for (final kind in SlopeKind.values) kind: 0,
    };
    final slopeSeconds = <SlopeKind, int>{
      for (final kind in SlopeKind.values) kind: 0,
    };

    var firstDistance = 0.0;
    var firstSeconds = 0;
    var secondDistance = 0.0;
    var secondSeconds = 0;
    var fatigueSessions = 0;

    for (final sample in samples) {
      final session = sample.session;
      distanceM += session.distanceM;
      movingSeconds += session.movingSeconds;
      elevationGainM += session.elevationGainM;

      for (var i = 1; i < sample.points.length; i++) {
        final previous = sample.points[i - 1];
        final current = sample.points[i];
        final seconds = current.timestampUtc
                .difference(previous.timestampUtc)
                .inMilliseconds /
            1000;
        if (seconds <= 0 || seconds > 60) continue;
        final segmentM = distanceMeters(previous.position, current.position);
        if (segmentM < 0.5) continue;
        final altitudeA = previous.altitudeM;
        final altitudeB = current.altitudeM;
        if (altitudeA == null || altitudeB == null) continue;
        final grade = (altitudeB - altitudeA) / segmentM;
        final kind = grade > 0.03
            ? SlopeKind.uphill
            : (grade < -0.03 ? SlopeKind.downhill : SlopeKind.flat);
        slopeDistance[kind] = slopeDistance[kind]! + segmentM;
        slopeSeconds[kind] = slopeSeconds[kind]! + seconds.round();
      }

      final halves = _halves(sample);
      if (halves != null) {
        fatigueSessions++;
        firstDistance += halves.first.distanceM;
        firstSeconds += halves.first.seconds;
        secondDistance += halves.second.distanceM;
        secondSeconds += halves.second.seconds;
      }
    }

    final records = _records(samples);
    final verticalSpeed = movingSeconds > 0 && elevationGainM > 0
        ? elevationGainM / (movingSeconds / 3600)
        : null;

    final hasFatigue = fatigueSessions > 0 &&
        firstDistance >= 500 &&
        secondDistance >= 500 &&
        firstSeconds > 0 &&
        secondSeconds > 0;

    return HikeAnalytics(
      sampleCount: samples.length,
      distanceM: distanceM,
      movingSeconds: movingSeconds,
      elevationGainM: elevationGainM,
      slopePaces: <SlopePace>[
        for (final kind in SlopeKind.values)
          SlopePace(
            kind: kind,
            distanceM: slopeDistance[kind]!,
            movingSeconds: slopeSeconds[kind]!,
          ),
      ],
      verticalSpeedMPerHour: verticalSpeed,
      records: records,
      fatigue: hasFatigue
          ? FatigueAnalysis(
              firstHalfSecondsPerKm: firstSeconds / (firstDistance / 1000),
              secondHalfSecondsPerKm: secondSeconds / (secondDistance / 1000),
              sessionsUsed: fatigueSessions,
            )
          : const FatigueAnalysis.empty(),
    );
  }

  static List<PersonalRecord> _records(List<HikeSample> samples) {
    if (samples.isEmpty) return const <PersonalRecord>[];
    var longest = samples.first;
    var highestGain = samples.first;
    var longestTime = samples.first;
    for (final sample in samples) {
      if (sample.session.distanceM > longest.session.distanceM) {
        longest = sample;
      }
      if (sample.session.elevationGainM > highestGain.session.elevationGainM) {
        highestGain = sample;
      }
      if (sample.session.movingSeconds > longestTime.session.movingSeconds) {
        longestTime = sample;
      }
    }
    return <PersonalRecord>[
      PersonalRecord(
        label: 'Jarak terjauh',
        value: '${(longest.session.distanceM / 1000).toStringAsFixed(1)} km',
        occurredAtUtc: longest.session.startedAtUtc,
      ),
      PersonalRecord(
        label: 'Elevasi terbesar',
        value: '${highestGain.session.elevationGainM.round()} m',
        occurredAtUtc: highestGain.session.startedAtUtc,
      ),
      PersonalRecord(
        label: 'Durasi bergerak',
        value:
            '${(longestTime.session.movingSeconds / 3600).toStringAsFixed(1)} jam',
        occurredAtUtc: longestTime.session.startedAtUtc,
      ),
    ];
  }

  /// Membagi jarak sesi menjadi dua paruh dan menjumlahkan waktu berjalan.
  ///
  /// Sesi tanpa titik cukup atau tanpa pergerakan dilewati; jeda lebih dari
  /// 120 detik tidak dihitung supaya istirahat panjang tidak dianggap
  /// "melambat".
  static ({_Half first, _Half second})? _halves(HikeSample sample) {
    final points = sample.points;
    if (points.length < 10) return null;
    final cumulative = <double>[0];
    for (var i = 1; i < points.length; i++) {
      cumulative.add(
        cumulative.last +
            distanceMeters(points[i - 1].position, points[i].position),
      );
    }
    final total = cumulative.last;
    if (total < 500) return null;
    final middle = total / 2;
    var firstDistance = 0.0;
    var firstSeconds = 0;
    var secondDistance = 0.0;
    var secondSeconds = 0;
    for (var i = 1; i < points.length; i++) {
      final seconds = points[i]
              .timestampUtc
              .difference(points[i - 1].timestampUtc)
              .inMilliseconds /
          1000;
      if (seconds <= 0 || seconds > 120) continue;
      final segment = cumulative[i] - cumulative[i - 1];
      final midpoint = (cumulative[i] + cumulative[i - 1]) / 2;
      if (midpoint <= middle) {
        firstDistance += segment;
        firstSeconds += seconds.round();
      } else {
        secondDistance += segment;
        secondSeconds += seconds.round();
      }
    }
    if (firstDistance <= 0 || secondDistance <= 0) return null;
    return (
      first: _Half(firstDistance, firstSeconds),
      second: _Half(secondDistance, secondSeconds),
    );
  }
}

class _Half {
  const _Half(this.distanceM, this.seconds);

  final double distanceM;
  final int seconds;

  double get secondsPerKm => seconds / (distanceM / 1000);
}

/// Median pace jelajah pribadi dalam km/jam dari sesi selesai.
///
/// Median dipakai agar satu rekaman yang meloncat tidak menggeser estimasi.
/// Nilai di luar 1–8 km/jam diabaikan sebagai galat GPS.
double? personalPaceKmh(List<TrackingSession> sessions) {
  final paces = <double>[];
  for (final session in sessions) {
    if (session.status != TrackingSessionStatus.completed) continue;
    if (session.distanceM < 500 || session.movingSeconds < 300) continue;
    final pace = (session.distanceM / 1000) / (session.movingSeconds / 3600);
    if (pace < 1 || pace > 8) continue;
    paces.add(pace);
  }
  if (paces.isEmpty) return null;
  paces.sort();
  final middle = paces.length ~/ 2;
  if (paces.length.isOdd) return paces[middle];
  return (paces[middle - 1] + paces[middle]) / 2;
}

/// Jarak jalur dari titik rute.
double routeDistanceM(List<LatLng> points) {
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += distanceMeters(points[i - 1], points[i]);
  }
  return total;
}

/// Titik tengah rute, dipakai menghitung matahari terbenam.
LatLng? routeCenter(List<LatLng> points) {
  if (points.isEmpty) return null;
  var lat = 0.0;
  var lon = 0.0;
  for (final point in points) {
    lat += point.lat;
    lon += point.lon;
  }
  return LatLng(lat / points.length, lon / points.length);
}

/// Perkiraan matahari terbenam lokal dengan rumus NOAA sederhana.
///
/// Akurasi beberapa menit; nilai selalu ditampilkan sebagai "perkiraan".
/// Null berarti matahari tidak terbenam pada tanggal itu (kutub).
DateTime? estimatedSunset({
  required DateTime dateLocal,
  required double latitude,
  required double longitude,
}) {
  final date = DateTime(dateLocal.year, dateLocal.month, dateLocal.day);
  final dayOfYear = date.difference(DateTime(date.year)).inDays + 1;
  final declinationDeg =
      -23.44 * math.cos(2 * math.pi * (dayOfYear + 10) / 365);
  final latitudeRad = latitude * math.pi / 180;
  final declinationRad = declinationDeg * math.pi / 180;
  final cosHourAngle = (math.sin(-0.833 * math.pi / 180) -
          math.sin(latitudeRad) * math.sin(declinationRad)) /
      (math.cos(latitudeRad) * math.cos(declinationRad));
  if (cosHourAngle < -1 || cosHourAngle > 1) return null;
  final hourAngleDeg = math.acos(cosHourAngle) * 180 / math.pi;

  final b = 2 * math.pi * (dayOfYear - 81) / 364;
  final equationOfTimeMinutes =
      9.87 * math.sin(2 * b) - 7.53 * math.cos(b) - 1.5 * math.sin(b);
  final offsetHours = dateLocal.timeZoneOffset.inMinutes / 60;
  final solarNoonHours =
      12 - equationOfTimeMinutes / 60 - (longitude - 15 * offsetHours) / 15;
  final sunsetHours = solarNoonHours + hourAngleDeg / 15;
  final minutes = (sunsetHours * 60).round();
  return DateTime(date.year, date.month, date.day)
      .add(Duration(minutes: minutes));
}
