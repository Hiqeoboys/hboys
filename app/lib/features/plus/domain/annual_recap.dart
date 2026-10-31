import 'dart:math' as math;
import 'dart:ui';

import '../../kartu/domain/kartu_data.dart';
import '../../tracking/domain/tracking_session.dart';
import 'hike_analytics.dart';

/// Ringkasan satu tahun dari sesi yang benar-benar tersimpan di perangkat.
///
/// Perbandingan memakai periode yang sama tahun lalu (1 Januari sampai tanggal
/// hari ini), bukan total setahun penuh, supaya awal tahun tidak terlihat
/// selalu kalah. Nama gunung belum disimpan di sesi, jadi bagian "gunung
/// tertinggi" memakai titik GPS paling tinggi dan menyebutnya apa adanya.
class AnnualRecap {
  const AnnualRecap({
    required this.year,
    required this.comparisonEndLocal,
    required this.sessionCount,
    required this.distanceM,
    required this.movingSeconds,
    required this.elevationGainM,
    required this.previousSessionCount,
    required this.previousDistanceM,
    this.highestAltitudeM,
    this.highestAltitudeAtUtc,
    this.hardestAtUtc,
    this.hardestDistanceM = 0,
    this.hardestElevationGainM = 0,
    this.route,
  });

  final int year;

  /// Akhir periode pembanding tahun lalu, mis. 31 Oktober 2025 23.59.
  final DateTime comparisonEndLocal;

  final int sessionCount;
  final double distanceM;
  final int movingSeconds;
  final double elevationGainM;

  final int previousSessionCount;
  final double previousDistanceM;

  final double? highestAltitudeM;
  final DateTime? highestAltitudeAtUtc;

  final DateTime? hardestAtUtc;
  final double hardestDistanceM;
  final double hardestElevationGainM;

  /// Rute sesi terberat yang dinormalkan ke 0..1 untuk pratinjau kartu.
  final List<Offset>? route;

  bool get isEmpty => sessionCount == 0;
  int get previousYear => year - 1;
  int get sessionDelta => sessionCount - previousSessionCount;

  /// Null bila jarak tahun lalu nol; dibiarkan null agar UI tidak membagi nol.
  double? get distanceChangePercent {
    if (previousDistanceM <= 0) return null;
    return ((distanceM - previousDistanceM) / previousDistanceM) * 100;
  }

  Offset? get routeStart =>
      route == null || route!.isEmpty ? null : route!.first;
  Offset? get routeEnd => route == null || route!.isEmpty ? null : route!.last;

  /// Bobot usaha relatif: jarak (km), tanjakan (100 m = 1 km), dan durasi
  /// gerak (1 jam = 0,5 km). Tidak memakai kecepatan agar tidak menjadi
  /// kategori perlombaan.
  static double effortScore(TrackingSession session) =>
      session.distanceM / 1000 +
      session.elevationGainM / 100 +
      (session.movingSeconds / 3600) * 0.5;

  static AnnualRecap build({
    required List<HikeSample> samples,
    required DateTime nowLocal,
  }) {
    final year = nowLocal.year;
    final previousYear = year - 1;
    final comparisonEndLocal =
        DateTime(previousYear, nowLocal.month, nowLocal.day, 23, 59, 59, 999);
    final comparisonEndUtc = comparisonEndLocal.toUtc();

    final current = <HikeSample>[];
    var previousSessionCount = 0;
    var previousDistanceM = 0.0;
    for (final sample in samples) {
      if (sample.session.status != TrackingSessionStatus.completed) continue;
      final startedLocal = sample.session.startedAtUtc.toLocal();
      if (startedLocal.year == year) {
        current.add(sample);
      } else if (startedLocal.year == previousYear &&
          !sample.session.startedAtUtc.isAfter(comparisonEndUtc)) {
        previousSessionCount++;
        previousDistanceM += sample.session.distanceM;
      }
    }

    var distanceM = 0.0;
    var movingSeconds = 0;
    var elevationGainM = 0.0;
    double? highestAltitudeM;
    DateTime? highestAltitudeAtUtc;
    HikeSample? hardest;
    var hardestEffort = double.negativeInfinity;

    for (final sample in current) {
      final session = sample.session;
      distanceM += session.distanceM;
      movingSeconds += session.movingSeconds;
      elevationGainM += session.elevationGainM;
      final effort = effortScore(session);
      if (effort > hardestEffort) {
        hardestEffort = effort;
        hardest = sample;
      }
      for (final point in sample.points) {
        final altitude = point.altitudeM;
        if (altitude == null) continue;
        if (highestAltitudeM == null || altitude > highestAltitudeM) {
          highestAltitudeM = altitude;
          highestAltitudeAtUtc = point.timestampUtc;
        }
      }
    }

    List<Offset>? route;
    if (hardest != null && hardest.points.length >= 2) {
      route = KartuData.fromSession(hardest.session, hardest.points)?.route;
    }
    if (route != null && route.length < 2) route = null;

    return AnnualRecap(
      year: year,
      comparisonEndLocal: comparisonEndLocal,
      sessionCount: current.length,
      distanceM: distanceM,
      movingSeconds: movingSeconds,
      elevationGainM: elevationGainM,
      previousSessionCount: previousSessionCount,
      previousDistanceM: previousDistanceM,
      highestAltitudeM: highestAltitudeM,
      highestAltitudeAtUtc: highestAltitudeAtUtc,
      hardestAtUtc: hardest?.session.startedAtUtc,
      hardestDistanceM: hardest?.session.distanceM ?? 0,
      hardestElevationGainM: hardest?.session.elevationGainM ?? 0,
      route: route,
    );
  }

  /// Bagian terbesar dari dua nilai, minimal 1 agar bar tidak membagi nol.
  static double barFraction(double value, double other) {
    final maxValue = math.max(math.max(value, other), 1);
    return (value / maxValue).clamp(0.0, 1.0);
  }
}
