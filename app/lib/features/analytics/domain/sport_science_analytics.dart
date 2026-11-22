import 'dart:math' as math;

import 'package:geo_utils/geo_utils.dart';

import '../../plus/domain/hike_analytics.dart';
import '../../tracking/domain/calorie_estimator.dart';
import '../../tracking/domain/track_point.dart';
import '../../tracking/domain/tracking_session.dart';

/// Rasio biaya metabolik berdasarkan persamaan Minetti untuk kemiringan datar
/// vs menanjak/menurun. Nilai > 1 menandakan usaha menanjak lebih berat dari
/// berjalan datar sehingga pace tersesuaikan (GAP) menjadi lebih cepat.
double gradeAdjustedCostRatio(double grade) {
  final g = grade.clamp(-0.30, 0.30).toDouble();
  final g2 = g * g;
  final g3 = g2 * g;
  final g4 = g3 * g;
  final g5 = g4 * g;
  final cost =
      155.4 * g5 - 30.4 * g4 - 43.3 * g3 + 46.3 * g2 + 19.5 * g + 3.6;
  return (cost / 3.6).clamp(0.65, 3.20).toDouble();
}

/// Mengonversi pace mentah (detik/km) menjadi Grade-Adjusted Pace (GAP).
double gradeAdjustedPace(double rawSecondsPerKm, double grade) =>
    rawSecondsPerKm / gradeAdjustedCostRatio(grade);

/// Distribusi waktu sesi menjadi 4 komponen medan & istirahat.
class TerrainDistribution {
  const TerrainDistribution({
    required this.uphillSeconds,
    required this.flatSeconds,
    required this.downhillSeconds,
    required this.stoppedSeconds,
    required this.usedSummaryFallback,
  });

  final int uphillSeconds;
  final int flatSeconds;
  final int downhillSeconds;
  final int stoppedSeconds;
  final bool usedSummaryFallback;

  int get totalSeconds =>
      uphillSeconds + flatSeconds + downhillSeconds + stoppedSeconds;

  bool get hasData => totalSeconds > 0;

  double get uphillPct =>
      totalSeconds > 0 ? (uphillSeconds / totalSeconds) * 100.0 : 0.0;
  double get flatPct =>
      totalSeconds > 0 ? (flatSeconds / totalSeconds) * 100.0 : 0.0;
  double get downhillPct =>
      totalSeconds > 0 ? (downhillSeconds / totalSeconds) * 100.0 : 0.0;
  double get stoppedPct =>
      totalSeconds > 0 ? (stoppedSeconds / totalSeconds) * 100.0 : 0.0;
}

/// Satu split per kilometer beserta elevasi naik dan Grade-Adjusted Pace (GAP).
class KmSplitEntry {
  const KmSplitEntry({
    required this.kmNumber,
    required this.label,
    required this.distanceM,
    required this.durationSeconds,
    required this.elevationGainM,
    required this.elevationLossM,
    required this.paceSecondsPerKm,
    required this.gapSecondsPerKm,
  });

  final int kmNumber;
  final String label;
  final double distanceM;
  final int durationSeconds;
  final double elevationGainM;
  final double elevationLossM;
  final double paceSecondsPerKm;
  final double gapSecondsPerKm;
}

class KmSplitReport {
  const KmSplitReport({
    required this.splits,
    required this.averageGapSecondsPerKm,
    required this.slowestGapKmNumber,
    required this.pacingConsistencyNote,
  });

  const KmSplitReport.empty()
      : splits = const <KmSplitEntry>[],
        averageGapSecondsPerKm = null,
        slowestGapKmNumber = null,
        pacingConsistencyNote =
            'Titik GPS per kilometer belum cukup untuk memecah split rute.';

  final List<KmSplitEntry> splits;
  final double? averageGapSecondsPerKm;
  final int? slowestGapKmNumber;
  final String pacingConsistencyNote;

  bool get hasData => splits.isNotEmpty;
}

/// Estimasi energi (Pandolf/ACSM), kebutuhan cairan pengganti, & saran pemulihan.
class RecoveryHydrationEstimate {
  const RecoveryHydrationEstimate({
    required this.totalKcal,
    required this.fluidReplacementMl,
    required this.recoveryNote,
    required this.assumedPackKg,
  });

  final double totalKcal;
  final int fluidReplacementMl;
  final String recoveryNote;
  final double assumedPackKg;
}

class SessionSportScienceReport {
  const SessionSportScienceReport({
    required this.terrain,
    required this.kmSplits,
    required this.recovery,
  });

  final TerrainDistribution terrain;
  final KmSplitReport kmSplits;
  final RecoveryHydrationEstimate recovery;

  static SessionSportScienceReport fromSession({
    required TrackingSession session,
    required List<TrackPoint> points,
    double weightKg = kDefaultWeightKg,
    double? packKg,
  }) {
    final effectiveWeight = weightKg >= 25 ? weightKg : kDefaultWeightKg;
    final effectivePack = packKg ?? (session.isJogging ? 0.0 : 5.0);

    final terrain = _computeTerrain(session, points);
    final kmSplits = _computeKmSplits(points);
    final recovery = _computeRecovery(
      session: session,
      points: points,
      weightKg: effectiveWeight,
      packKg: effectivePack,
    );

    return SessionSportScienceReport(
      terrain: terrain,
      kmSplits: kmSplits,
      recovery: recovery,
    );
  }

  static TerrainDistribution _computeTerrain(
    TrackingSession session,
    List<TrackPoint> points,
  ) {
    final wallSeconds = session.endedAtUtc == null
        ? session.movingSeconds
        : math.max(
            session.movingSeconds,
            session.endedAtUtc!.difference(session.startedAtUtc).inSeconds,
          );

    if (points.length < 2) {
      return _fallbackTerrain(session, wallSeconds);
    }

    var uphill = 0.0;
    var flat = 0.0;
    var downhill = 0.0;
    var stopped = 0.0;
    var accounted = 0.0;

    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final dt =
          curr.timestampUtc.difference(prev.timestampUtc).inMilliseconds /
              1000.0;
      if (dt <= 0) continue;
      accounted += dt;

      final dist = distanceMeters(prev.position, curr.position);
      final speed = dist / dt;
      if (dt > 60 || speed < 0.25) {
        stopped += dt;
        continue;
      }

      final eleA = prev.altitudeM;
      final eleB = curr.altitudeM;
      if (eleA == null || eleB == null || dist < 0.5) {
        flat += dt;
        continue;
      }
      final grade = (eleB - eleA) / dist;
      if (grade > 0.03) {
        uphill += dt;
      } else if (grade < -0.03) {
        downhill += dt;
      } else {
        flat += dt;
      }
    }

    final movingObserved = uphill + flat + downhill;
    if (movingObserved <= 0) {
      return _fallbackTerrain(session, wallSeconds);
    }

    final extraStopped = math.max(0.0, wallSeconds - accounted);
    return TerrainDistribution(
      uphillSeconds: uphill.round(),
      flatSeconds: flat.round(),
      downhillSeconds: downhill.round(),
      stoppedSeconds: (stopped + extraStopped).round(),
      usedSummaryFallback: false,
    );
  }

  static TerrainDistribution _fallbackTerrain(
    TrackingSession session,
    int wallSeconds,
  ) {
    final moving = math.max(0, session.movingSeconds);
    final stopped = math.max(0, wallSeconds - moving);
    if (moving == 0) {
      return TerrainDistribution(
        uphillSeconds: 0,
        flatSeconds: 0,
        downhillSeconds: 0,
        stoppedSeconds: stopped,
        usedSummaryFallback: true,
      );
    }
    final safeDist = math.max(1.0, session.distanceM);
    var upShare = (session.elevationGainM / safeDist * 3.2).clamp(0.0, 0.70);
    var downShare = (session.elevationLossM / safeDist * 2.8).clamp(0.0, 0.65);
    final combined = upShare + downShare;
    if (combined > 0.85) {
      upShare = (upShare / combined) * 0.85;
      downShare = (downShare / combined) * 0.85;
    }
    final upSec = (moving * upShare).round();
    final downSec = (moving * downShare).round();
    final flatSec = math.max(0, moving - upSec - downSec);
    return TerrainDistribution(
      uphillSeconds: upSec,
      flatSeconds: flatSec,
      downhillSeconds: downSec,
      stoppedSeconds: stopped,
      usedSummaryFallback: true,
    );
  }

  static KmSplitReport _computeKmSplits(List<TrackPoint> points) {
    if (points.length < 2) return const KmSplitReport.empty();

    final buckets = <KmSplitEntry>[];
    var bucketDist = 0.0;
    var bucketDur = 0.0;
    var bucketGain = 0.0;
    var bucketLoss = 0.0;
    var bucketGapWeighted = 0.0;
    var kmNum = 1;

    void flushBucket() {
      if (bucketDist < 200 || bucketDur <= 0) return;
      final kmFraction = bucketDist / 1000.0;
      final rawPace = bucketDur / kmFraction;
      final avgGap = (bucketGapWeighted / kmFraction).clamp(180.0, 3600.0);
      final label = bucketDist >= 850
          ? 'KM $kmNum'
          : '${(bucketDist / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
      buckets.add(
        KmSplitEntry(
          kmNumber: kmNum,
          label: label,
          distanceM: bucketDist,
          durationSeconds: bucketDur.round(),
          elevationGainM: bucketGain,
          elevationLossM: bucketLoss,
          paceSecondsPerKm: rawPace,
          gapSecondsPerKm: avgGap.toDouble(),
        ),
      );
      kmNum++;
      bucketDist = 0;
      bucketDur = 0;
      bucketGain = 0;
      bucketLoss = 0;
      bucketGapWeighted = 0;
    }

    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final dt =
          curr.timestampUtc.difference(prev.timestampUtc).inMilliseconds /
              1000.0;
      if (dt <= 0 || dt > 60) continue;
      var remDist = distanceMeters(prev.position, curr.position);
      if (remDist < 0.5) continue;

      final eleA = prev.altitudeM;
      final eleB = curr.altitudeM;
      final dEleTotal = (eleA != null && eleB != null) ? (eleB - eleA) : 0.0;
      final grade = dEleTotal / remDist;
      final costRatio = gradeAdjustedCostRatio(grade);
      var remDur = dt;
      var remGain = dEleTotal > 0 ? dEleTotal : 0.0;
      var remLoss = dEleTotal < 0 ? -dEleTotal : 0.0;

      while (remDist > 0) {
        final room = 1000.0 - bucketDist;
        final takeDist = math.min(remDist, room);
        final ratio = takeDist / remDist;
        final takeDur = remDur * ratio;

        bucketDist += takeDist;
        bucketDur += takeDur;
        bucketGain += remGain * ratio;
        bucketLoss += remLoss * ratio;
        bucketGapWeighted += takeDur / costRatio;

        remDist -= takeDist;
        remDur -= takeDur;
        remGain *= (1.0 - ratio);
        remLoss *= (1.0 - ratio);

        if (bucketDist >= 999.9) {
          flushBucket();
        }
      }
    }

    if (bucketDist >= 250 || (buckets.isEmpty && bucketDist >= 200)) {
      flushBucket();
    }

    if (buckets.isEmpty) return const KmSplitReport.empty();

    var totalDist = 0.0;
    var weightedGap = 0.0;
    var slowest = buckets.first;
    var fastest = buckets.first;
    for (final b in buckets) {
      totalDist += b.distanceM;
      weightedGap += b.gapSecondsPerKm * b.distanceM;
      if (b.gapSecondsPerKm > slowest.gapSecondsPerKm) slowest = b;
      if (b.gapSecondsPerKm < fastest.gapSecondsPerKm) fastest = b;
    }
    final avgGap = totalDist > 0 ? weightedGap / totalDist : null;

    String note;
    if (buckets.length < 2) {
      note =
          'Sesi di bawah 2 km cukup singkat. Konsistensi ritme terlihat jelas saat jarak melampaui 2 km.';
    } else {
      final spreadPct = fastest.gapSecondsPerKm > 0
          ? ((slowest.gapSecondsPerKm - fastest.gapSecondsPerKm) /
                  fastest.gapSecondsPerKm) *
              100.0
          : 0.0;
      if (spreadPct >= 20) {
        note =
            'Pace tersesuaikan paling melambat di ${slowest.label}. Turunkan ritme lebih awal pada sesi berikutnya.';
      } else {
        note =
            'Ritme Grade-Adjusted Pace (GAP) cukup stabil di sepanjang ${buckets.length} split.';
      }
    }

    return KmSplitReport(
      splits: List<KmSplitEntry>.unmodifiable(buckets),
      averageGapSecondsPerKm: avgGap,
      slowestGapKmNumber: slowest.kmNumber,
      pacingConsistencyNote: note,
    );
  }

  static RecoveryHydrationEstimate _computeRecovery({
    required TrackingSession session,
    required List<TrackPoint> points,
    required double weightKg,
    required double packKg,
  }) {
    var pandolfKcal = 0.0;
    final eta = session.isJogging ? 1.0 : 1.1;

    if (points.length >= 2) {
      for (var i = 1; i < points.length; i++) {
        final prev = points[i - 1];
        final curr = points[i];
        final dt =
            curr.timestampUtc.difference(prev.timestampUtc).inMilliseconds /
                1000.0;
        if (dt <= 0 || dt > 60) continue;
        final dist = distanceMeters(prev.position, curr.position);
        final speed = dist / dt;
        if (speed < kCalorieMinSpeedMps) continue;

        final grade = (prev.altitudeM != null &&
                curr.altitudeM != null &&
                dist >= 0.5)
            ? ((curr.altitudeM! - prev.altitudeM!) / dist).clamp(-0.30, 0.35)
            : 0.0;

        if (session.isJogging && speed > 2.2) {
          pandolfKcal += acsmKcalPerKg(
                speedMps: speed,
                grade: grade,
                seconds: dt,
              ) *
              (weightKg + packKg);
        } else {
          final v = speed.clamp(0.3, 4.0);
          final loadRatio = packKg / weightKg;
          final posGradePct = math.max(0.0, grade * 100.0);
          final watts = 1.5 * weightKg +
              2.0 * (weightKg + packKg) * (loadRatio * loadRatio) +
              eta * (weightKg + packKg) * (1.5 * v * v + 0.35 * v * posGradePct);
          final kcalPerMin = watts * 0.01433;
          pandolfKcal += kcalPerMin * (dt / 60.0);
        }
      }
    }

    if (pandolfKcal <= 0 && session.movingSeconds > 0) {
      final avgGradePct = session.distanceM > 1
          ? (session.elevationGainM / session.distanceM) * 100.0
          : 0.0;
      pandolfKcal = estimateKcal(
        weightKg: weightKg,
        movingTime: Duration(seconds: session.movingSeconds),
        avgGradePercent: avgGradePct,
        packKg: packKg,
      );
    }

    final movingHours = session.movingSeconds / 3600.0;
    final rawFluidMl = (movingHours * 550.0) + (pandolfKcal * 0.45);
    final fluidMl = (((rawFluidMl.clamp(250.0, 6000.0)) / 50.0).round() * 50)
        .toInt();

    String note;
    if (session.elevationLossM >= 500) {
      note =
          'Turunan panjang (${session.elevationLossM.round()} m) membebani otot paha depan (eksentrik). Peregangan ringan dan istirahat 24–48 jam membantu pemulihan sendi lutut.';
    } else if (session.elevationGainM >= 500 || pandolfKcal >= 900) {
      note =
          'Beban tanjakan dan energi cukup tinggi. Penuhi protein 20–30 gram dalam 2 jam setelah turun serta minum bertahap dengan elektrolit.';
    } else {
      note =
          'Sesi kategori ringan hingga menengah. Ganti cairan secara bertahap dan lakukan pendinginan singkat untuk menjaga kelenturan betis.';
    }

    return RecoveryHydrationEstimate(
      totalKcal: pandolfKcal,
      fluidReplacementMl: fluidMl,
      recoveryNote: note,
      assumedPackKg: packKg,
    );
  }
}

enum AcwrZone {
  insufficientData,
  recovery,
  optimal,
  elevated,
  highRisk,
}

class WeeklyLoadBucket {
  const WeeklyLoadBucket({
    required this.label,
    required this.loadScore,
    required this.sessionCount,
  });

  final String label;
  final double loadScore;
  final int sessionCount;
}

class AcwrReport {
  const AcwrReport({
    required this.weeklyBuckets,
    required this.acuteLoad,
    required this.chronicLoad,
    required this.ratio,
    required this.zone,
    required this.zoneLabel,
    required this.explanation,
  });

  final List<WeeklyLoadBucket> weeklyBuckets;
  final double acuteLoad;
  final double chronicLoad;
  final double? ratio;
  final AcwrZone zone;
  final String zoneLabel;
  final String explanation;
}

class EccentricSessionBar {
  const EccentricSessionBar({
    required this.label,
    required this.elevationLossM,
    required this.descentSpeedMPerHour,
  });

  final String label;
  final double elevationLossM;
  final double? descentSpeedMPerHour;
}

class EccentricDownhillReport {
  const EccentricDownhillReport({
    required this.bars,
    required this.totalElevationLossM,
    required this.avgDescentSpeedMPerHour,
    required this.kneeLoadLabel,
    required this.guidance,
  });

  final List<EccentricSessionBar> bars;
  final double totalElevationLossM;
  final double? avgDescentSpeedMPerHour;
  final String kneeLoadLabel;
  final String guidance;
}

class AltitudeVamReport {
  const AltitudeVamReport({
    required this.below2000Seconds,
    required this.between2000And2500Seconds,
    required this.above2500Seconds,
    required this.steepVamMPerHour,
    required this.vamNote,
  });

  final int below2000Seconds;
  final int between2000And2500Seconds;
  final int above2500Seconds;
  final double? steepVamMPerHour;
  final String vamNote;

  int get totalAltitudeSeconds =>
      below2000Seconds + between2000And2500Seconds + above2500Seconds;

  bool get hasAltitudeData => totalAltitudeSeconds > 0;

  double get below2000Pct => totalAltitudeSeconds > 0
      ? (below2000Seconds / totalAltitudeSeconds) * 100.0
      : 0.0;
  double get between2000And2500Pct => totalAltitudeSeconds > 0
      ? (between2000And2500Seconds / totalAltitudeSeconds) * 100.0
      : 0.0;
  double get above2500Pct => totalAltitudeSeconds > 0
      ? (above2500Seconds / totalAltitudeSeconds) * 100.0
      : 0.0;
}

class FatigueDriftReport {
  const FatigueDriftReport({
    required this.firstHalfGapSecPerKm,
    required this.secondHalfGapSecPerKm,
    required this.driftPercent,
    required this.sessionsUsed,
    required this.guidance,
  });

  const FatigueDriftReport.empty()
      : firstHalfGapSecPerKm = null,
        secondHalfGapSecPerKm = null,
        driftPercent = null,
        sessionsUsed = 0,
        guidance =
            'Dibutuhkan minimal satu sesi >= 500 m dengan titik GPS lengkap untuk mengukur penurunan GAP antara paruh awal dan akhir.';

  final double? firstHalfGapSecPerKm;
  final double? secondHalfGapSecPerKm;
  final double? driftPercent;
  final int sessionsUsed;
  final String guidance;

  bool get hasData =>
      firstHalfGapSecPerKm != null &&
      secondHalfGapSecPerKm != null &&
      driftPercent != null;
}

class CrossSessionSportScienceReport {
  const CrossSessionSportScienceReport({
    required this.acwr,
    required this.eccentricDownhill,
    required this.altitudeVam,
    required this.fatigueDrift,
  });

  final AcwrReport acwr;
  final EccentricDownhillReport eccentricDownhill;
  final AltitudeVamReport altitudeVam;
  final FatigueDriftReport fatigueDrift;

  static CrossSessionSportScienceReport build({
    required List<HikeSample> allSamples,
    required List<HikeSample> rangeSamples,
    DateTime? nowLocal,
  }) {
    final referenceLocal = nowLocal ?? DateTime.now();
    return CrossSessionSportScienceReport(
      acwr: _computeAcwr(allSamples, referenceLocal),
      eccentricDownhill: _computeEccentricDownhill(rangeSamples),
      altitudeVam: _computeAltitudeVam(rangeSamples),
      fatigueDrift: _computeFatigueDrift(rangeSamples),
    );
  }

  static double sessionTrainingLoad(TrackingSession session) =>
      (session.distanceM / 1000.0) + (session.elevationGainM / 100.0);

  static AcwrReport _computeAcwr(
    List<HikeSample> allSamples,
    DateTime referenceLocal,
  ) {
    final refDay = DateTime(
      referenceLocal.year,
      referenceLocal.month,
      referenceLocal.day,
    );
    final loads = List<double>.filled(4, 0.0);
    final counts = List<int>.filled(4, 0);

    for (final sample in allSamples) {
      final started = sample.session.startedAtUtc.toLocal();
      final sessionDay = DateTime(started.year, started.month, started.day);
      final ageDays = refDay.difference(sessionDay).inDays;
      if (ageDays < 0 || ageDays >= 28) continue;

      final load = sessionTrainingLoad(sample.session);
      if (ageDays < 7) {
        loads[3] += load;
        counts[3]++;
      } else if (ageDays < 14) {
        loads[2] += load;
        counts[2]++;
      } else if (ageDays < 21) {
        loads[1] += load;
        counts[1]++;
      } else {
        loads[0] += load;
        counts[0]++;
      }
    }

    final total28d = loads[0] + loads[1] + loads[2] + loads[3];
    final acute = loads[3];
    final chronic = total28d / 4.0;
    final ratio = chronic >= 0.5 ? acute / chronic : null;

    AcwrZone zone;
    String zoneLabel;
    String explanation;
    if (ratio == null) {
      zone = AcwrZone.insufficientData;
      zoneLabel = 'Data 28 hari belum cukup';
      explanation =
          'ACWR membandingkan beban 7 hari terakhir dengan rata-rata 4 minggu terakhir (100 m tanjakan dihitung setara 1 km datar).';
    } else if (ratio > 1.5) {
      zone = AcwrZone.highRisk;
      zoneLabel = 'Waspada: Risiko Cedera Overuse';
      explanation =
          'Lonjakan beban minggu ini melebihi 1,5 kali rata-rata bulanan. Sisipkan hari pemulihan agar otot dan sendi sempat beradaptasi.';
    } else if (ratio > 1.3) {
      zone = AcwrZone.elevated;
      zoneLabel = 'Beban Meningkat';
      explanation =
          'Beban latihan 7 hari terakhir berada sedikit di atas zona aman (0,8–1,3). Pantau rasa pegal sebelum menambah jarak.';
    } else if (ratio >= 0.8) {
      zone = AcwrZone.optimal;
      zoneLabel = 'Progres Optimal';
      explanation =
          'Rasio 0,8–1,3 menunjukkan kenaikan beban 7 hari terakhir selaras dengan kebugaran dasar 4 minggu terakhir.';
    } else {
      zone = AcwrZone.recovery;
      zoneLabel = 'Fase Pemulihan';
      explanation =
          'Rasio di bawah 0,8 menandakan intensitas minggu ini lebih ringan, cocok untuk pemulihan setelah pendakian berat.';
    }

    const labels = <String>['M-3', 'M-2', 'M-1', '7 hr'];
    final buckets = <WeeklyLoadBucket>[
      for (var i = 0; i < 4; i++)
        WeeklyLoadBucket(
          label: labels[i],
          loadScore: loads[i],
          sessionCount: counts[i],
        ),
    ];

    return AcwrReport(
      weeklyBuckets: buckets,
      acuteLoad: acute,
      chronicLoad: chronic,
      ratio: ratio,
      zone: zone,
      zoneLabel: zoneLabel,
      explanation: explanation,
    );
  }

  static ({double verticalM, double seconds}) _analyzeSustainedVertical(
    List<TrackPoint> points, {
    required bool uphill,
  }) {
    if (points.length < 2) return (verticalM: 0.0, seconds: 0.0);

    // Haluskan ketinggian (moving average 5 titik) agar fluktuasi GPS sesaat
    // di jalan datar tidak ikut terbaca sebagai tanjakan/turunan curam.
    final smoothedAlt = List<double?>.filled(points.length, null);
    for (var i = 0; i < points.length; i++) {
      if (points[i].altitudeM == null || !points[i].altitudeM!.isFinite) {
        continue;
      }
      var sum = 0.0;
      var cnt = 0;
      for (var k = math.max(0, i - 2);
          k <= math.min(points.length - 1, i + 2);
          k++) {
        final a = points[k].altitudeM;
        if (a != null && a.isFinite) {
          sum += a;
          cnt++;
        }
      }
      if (cnt > 0) smoothedAlt[i] = sum / cnt;
    }

    const minNetVerticalM = 15.0;
    const minDurationSec = 120.0;
    const minGrade = 0.05;

    var qualifiedVerticalM = 0.0;
    var qualifiedSeconds = 0.0;

    var segDistM = 0.0;
    var segDurSec = 0.0;
    var segNetVertM = 0.0;
    var offSlopeDistM = 0.0;

    void flushSegment() {
      if (segNetVertM >= minNetVerticalM &&
          segDurSec >= minDurationSec &&
          segDistM > 0 &&
          (segNetVertM / segDistM) >= minGrade) {
        qualifiedVerticalM += segNetVertM;
        qualifiedSeconds += segDurSec;
      }
      segDistM = 0.0;
      segDurSec = 0.0;
      segNetVertM = 0.0;
      offSlopeDistM = 0.0;
    }

    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final dt =
          curr.timestampUtc.difference(prev.timestampUtc).inMilliseconds /
              1000.0;
      if (dt <= 0 || dt > 60) {
        flushSegment();
        continue;
      }
      final dist = distanceMeters(prev.position, curr.position);
      final speed = dist / dt;
      if (dist < 1.0 || speed < 0.4) {
        flushSegment();
        continue;
      }
      final eleA = smoothedAlt[i - 1];
      final eleB = smoothedAlt[i];
      if (eleA == null || eleB == null) {
        flushSegment();
        continue;
      }
      final dVert = uphill ? (eleB - eleA) : (eleA - eleB);
      final grade = dVert / dist;
      if (grade >= minGrade) {
        segDistM += dist;
        segDurSec += dt;
        segNetVertM += dVert;
        offSlopeDistM = 0.0;
      } else if (segDistM > 0 && grade >= 0 && offSlopeDistM + dist <= 40.0) {
        // Toleransi bagian datar pendek <= 40 m di tengah satu segmen menanjak/menurun.
        segDistM += dist;
        segDurSec += dt;
        segNetVertM += dVert;
        offSlopeDistM += dist;
      } else {
        flushSegment();
      }
    }
    flushSegment();

    return (verticalM: qualifiedVerticalM, seconds: qualifiedSeconds);
  }

  static EccentricDownhillReport _computeEccentricDownhill(
    List<HikeSample> samples,
  ) {
    if (samples.isEmpty) {
      return const EccentricDownhillReport(
        bars: <EccentricSessionBar>[],
        totalElevationLossM: 0,
        avgDescentSpeedMPerHour: null,
        kneeLoadLabel: 'Belum ada data turunan',
        guidance:
            'Beban turun tercatat saat sesi memiliki penurunan elevasi nyata dengan titik GPS berketinggian.',
      );
    }

    final recent = samples.take(6).toList().reversed.toList(growable: false);
    final bars = <EccentricSessionBar>[];
    var totalLoss = 0.0;
    var descentGainSum = 0.0;
    var descentHoursSum = 0.0;

    for (final sample in recent) {
      final s = sample.session;
      final local = s.startedAtUtc.toLocal();
      final label = '${local.day}/${local.month}';
      final sustained = _analyzeSustainedVertical(sample.points, uphill: false);

      final sessionLoss =
          s.elevationLossM > 0 ? s.elevationLossM : sustained.verticalM;
      totalLoss += sessionLoss;

      double? descentSpeed;
      if (sustained.verticalM >= 15.0 && sustained.seconds >= 120.0) {
        final hrs = sustained.seconds / 3600.0;
        descentSpeed = sustained.verticalM / hrs;
        descentGainSum += sustained.verticalM;
        descentHoursSum += hrs;
      }

      bars.add(
        EccentricSessionBar(
          label: label,
          elevationLossM: sessionLoss,
          descentSpeedMPerHour: descentSpeed,
        ),
      );
    }

    final avgSpeed =
        descentHoursSum > 0 ? descentGainSum / descentHoursSum : null;
    final avgLossPerSession = totalLoss / recent.length;

    String kneeLoadLabel;
    String guidance;
    if (avgSpeed == null && avgLossPerSession < 300) {
      kneeLoadLabel = avgLossPerSession > 0 ? 'Ringan' : 'Medan datar · ringan';
      guidance =
          'Sesi terlalu datar atau singkat (turunan nyata < 15 m / < 2 menit) untuk menghitung kecepatan turun spesifik. Stres lutut tergolong ringan.';
    } else if (avgLossPerSession >= 700 || (avgSpeed != null && avgSpeed >= 520)) {
      kneeLoadLabel = 'Tinggi · jaga lutut';
      guidance =
          'Turunan curam menghasilkan beban eksentrik tinggi pada tempurung lutut (patellofemoral). Gunakan trekking pole dan perpendek langkah saat turun.';
    } else if (avgLossPerSession >= 300) {
      kneeLoadLabel = 'Menengah';
      guidance =
          'Beban turunan berada di rentang wajar pendakian. Jaga kontrol paha depan dan hindari mengunci lutut saat menjejak batu.';
    } else {
      kneeLoadLabel = 'Ringan';
      guidance =
          'Akumulasi penurunan masih ringan sehingga stres benturan pada sendi lutut relatif rendah.';
    }

    return EccentricDownhillReport(
      bars: bars,
      totalElevationLossM: totalLoss,
      avgDescentSpeedMPerHour: avgSpeed,
      kneeLoadLabel: kneeLoadLabel,
      guidance: guidance,
    );
  }

  static AltitudeVamReport _computeAltitudeVam(List<HikeSample> samples) {
    var below2k = 0.0;
    var mid2k25 = 0.0;
    var above25 = 0.0;
    var sustainedGain = 0.0;
    var sustainedSec = 0.0;

    for (final sample in samples) {
      for (var i = 1; i < sample.points.length; i++) {
        final prev = sample.points[i - 1];
        final curr = sample.points[i];
        final dt =
            curr.timestampUtc.difference(prev.timestampUtc).inMilliseconds /
                1000.0;
        if (dt <= 0 || dt > 60) continue;
        final eleA = prev.altitudeM;
        final eleB = curr.altitudeM;
        if (eleA == null || eleB == null) continue;

        final avgAlt = (eleA + eleB) / 2.0;
        if (avgAlt > 2500) {
          above25 += dt;
        } else if (avgAlt >= 2000) {
          mid2k25 += dt;
        } else {
          below2k += dt;
        }
      }

      final sustained = _analyzeSustainedVertical(sample.points, uphill: true);
      sustainedGain += sustained.verticalM;
      sustainedSec += sustained.seconds;
    }

    double? vam;
    String vamNote;
    if (sustainedGain >= 15.0 && sustainedSec >= 120.0) {
      vam = sustainedGain / (sustainedSec / 3600.0);
      vamNote =
          'VAM (kecepatan naik vertikal rata-rata) dihitung hanya pada segmen tanjakan nyata >= 5% (minimal +15 m dan >= 2 menit).';
    } else {
      vamNote =
          'Belum ada segmen tanjakan nyata (minimal +15 m selama >= 2 menit dengan kemiringan >= 5%) pada sesi terpilih.';
    }

    return AltitudeVamReport(
      below2000Seconds: below2k.round(),
      between2000And2500Seconds: mid2k25.round(),
      above2500Seconds: above25.round(),
      steepVamMPerHour: vam,
      vamNote: vamNote,
    );
  }

  static FatigueDriftReport _computeFatigueDrift(List<HikeSample> samples) {
    var firstDist = 0.0;
    var firstGapSec = 0.0;
    var secondDist = 0.0;
    var secondGapSec = 0.0;
    var used = 0;

    for (final sample in samples) {
      final pts = sample.points;
      if (pts.length < 10) continue;
      final cumulative = <double>[0.0];
      for (var i = 1; i < pts.length; i++) {
        cumulative.add(
          cumulative.last + distanceMeters(pts[i - 1].position, pts[i].position),
        );
      }
      final totalDist = cumulative.last;
      if (totalDist < 500) continue;
      final mid = totalDist / 2.0;

      var h1Dist = 0.0;
      var h1Sec = 0.0;
      var h2Dist = 0.0;
      var h2Sec = 0.0;

      for (var i = 1; i < pts.length; i++) {
        final dt = pts[i].timestampUtc
                .difference(pts[i - 1].timestampUtc)
                .inMilliseconds /
            1000.0;
        if (dt <= 0 || dt > 120) continue;
        final seg = cumulative[i] - cumulative[i - 1];
        if (seg < 0.5) continue;

        final eleA = pts[i - 1].altitudeM;
        final eleB = pts[i].altitudeM;
        final grade = (eleA != null && eleB != null) ? (eleB - eleA) / seg : 0.0;
        final eqSec = dt / gradeAdjustedCostRatio(grade);
        final segMid = (cumulative[i] + cumulative[i - 1]) / 2.0;
        if (segMid <= mid) {
          h1Dist += seg;
          h1Sec += eqSec;
        } else {
          h2Dist += seg;
          h2Sec += eqSec;
        }
      }

      if (h1Dist >= 200 && h2Dist >= 200 && h1Sec > 0 && h2Sec > 0) {
        used++;
        firstDist += h1Dist;
        firstGapSec += h1Sec;
        secondDist += h2Dist;
        secondGapSec += h2Sec;
      }
    }

    if (used == 0 ||
        firstDist < 200 ||
        secondDist < 200 ||
        firstGapSec <= 0 ||
        secondGapSec <= 0) {
      return const FatigueDriftReport.empty();
    }

    final firstGap = firstGapSec / (firstDist / 1000.0);
    final secondGap = secondGapSec / (secondDist / 1000.0);
    final drift = ((secondGap - firstGap) / firstGap) * 100.0;

    String guidance;
    if (drift >= 12) {
      guidance =
          'Grade-Adjusted Pace (GAP, yakni kecepatan setara medan datar) melambat cukup tajam di paruh kedua. Jadwalkan asupan karbohidrat dan jeda minum lebih rutin sejak paruh awal.';
    } else if (drift > 4) {
      guidance =
          'Ada perlambatan ringan pada paruh kedua setelah efek tanjakan dinetralkan oleh perhitungan GAP. Kondisi daya tahan tergolong terjaga.';
    } else if (drift < -4) {
      guidance =
          'Paruh kedua lebih kencang dibanding paruh pertama pada hitungan GAP. Pembagian tenaga sejak awal jalur sudah sangat baik.';
    } else {
      guidance =
          'GAP paruh pertama dan kedua nyaris seimbang, menandakan pengaturan tempo yang stabil sepanjang jalur.';
    }

    return FatigueDriftReport(
      firstHalfGapSecPerKm: firstGap,
      secondHalfGapSecPerKm: secondGap,
      driftPercent: drift,
      sessionsUsed: used,
      guidance: guidance,
    );
  }
}
