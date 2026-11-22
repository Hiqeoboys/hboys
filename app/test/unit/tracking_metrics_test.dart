import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:nama_app/features/tracking/domain/auto_pause_detector.dart';
import 'package:nama_app/features/tracking/domain/calorie_estimator.dart';
import 'package:nama_app/features/tracking/domain/distance_calculator.dart';
import 'package:nama_app/features/tracking/domain/elevation_processor.dart';
import 'package:nama_app/features/tracking/domain/elevation_profile.dart';
import 'package:nama_app/features/tracking/domain/gps_filter.dart';
import 'package:nama_app/features/tracking/domain/motion_estimators.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_engine.dart';
import 'package:nama_app/features/tracking/presentation/tracking_view_data.dart';
import 'package:nama_app/infrastructure/location/pedometer_step_counter.dart';

final t0 = DateTime.utc(2027, 6, 1, 8);

// 1 derajat lintang ~ 111.195 km.
const metersPerDegLat = 111195.0;

TrackPoint _pt({
  required double metersNorth,
  required int sec,
  double accuracyM = 5,
  double? speedMps,
  double? altitudeM,
}) =>
    TrackPoint(
      lat: -6.9 + metersNorth / metersPerDegLat,
      lon: 107.6,
      timestampUtc: t0.add(Duration(seconds: sec)),
      accuracyM: accuracyM,
      speedMps: speedMps,
      altitudeM: altitudeM,
    );

void main() {
  group('GpsFilter (Strava)', () {
    test('menerima akurasi <= 25 m saat warmup 20 dtk, lalu <= 20 m', () {
      final f = GpsFilter();
      expect(
        f.evaluate(_pt(metersNorth: 0, sec: 0, accuracyM: 24)),
        isNull,
      );
      expect(
        f.evaluate(_pt(metersNorth: 15, sec: 15, accuracyM: 24, speedMps: 1.0)),
        isNull,
      );
      expect(
        f.evaluate(_pt(metersNorth: 30, sec: 25, accuracyM: 23, speedMps: 1.2)),
        FixRejectReason.accuracy,
      );
      expect(
        f.evaluate(_pt(metersNorth: 30, sec: 26, accuracyM: 18, speedMps: 1.3)),
        isNull,
      );
    });

    test('menolak timestamp duplikat atau mundur', () {
      final f = GpsFilter();
      expect(f.evaluate(_pt(metersNorth: 0, sec: 10)), isNull);
      expect(
        f.evaluate(_pt(metersNorth: 5, sec: 10)),
        FixRejectReason.duplicateTime,
      );
      expect(
        f.evaluate(_pt(metersNorth: 10, sec: 8)),
        FixRejectReason.duplicateTime,
      );
    });

    test('menolak loncatan kecepatan implisit > 12 m/s', () {
      final f = GpsFilter();
      expect(f.evaluate(_pt(metersNorth: 0, sec: 0)), isNull);
      // 50 m dalam 2 detik = 25 m/s (> 12 m/s)
      expect(
        f.evaluate(_pt(metersNorth: 50, sec: 2)),
        FixRejectReason.jump,
      );
    });

    test('menolak perpindahan < 2,5 m atau kecepatan < 0,45 m/s sebagai jitter',
        () {
      final f = GpsFilter();
      expect(f.evaluate(_pt(metersNorth: 0, sec: 0)), isNull);
      expect(
        f.evaluate(_pt(metersNorth: 1.2, sec: 2, speedMps: 0.2)),
        FixRejectReason.jitter,
      );
      // Walau sensor speed 1,1 m/s, perpindahan < 2,5 m tetap diabaikan agar diam tidak nambah jarak
      expect(
        f.evaluate(_pt(metersNorth: 1.2, sec: 3, speedMps: 1.1)),
        FixRejectReason.jitter,
      );
      // Perpindahan >= 2,5 m dan speed >= 0,45 m/s diterima
      expect(
        f.evaluate(_pt(metersNorth: 3.0, sec: 4, speedMps: 1.0)),
        isNull,
      );
    });
  });

  group('Haversine & DistanceCalculator (1B)', () {
    test('Haversine menghitung jarak akurat', () {
      const a = LatLng(-6.9, 107.6);
      const b = LatLng(-6.9 + 500 / metersPerDegLat, 107.6);
      expect(distanceMeters(a, b), closeTo(500, 0.5));
    });

    test('jitter kecil tidak menambah jarak', () {
      final d = DistanceCalculator();
      for (var i = 0; i < 20; i++) {
        d.add(_pt(metersNorth: i.isEven ? 0 : 1.5, sec: i));
      }
      expect(d.totalMeters, 0);
    });

    test('akumulasi langkah nyata', () {
      final d = DistanceCalculator();
      for (var i = 0; i <= 10; i++) {
        d.add(_pt(metersNorth: i * 10.0, sec: i));
      }
      expect(d.totalMeters, closeTo(100, 1));
    });
  });

  group('PaceEstimator (Strava 10-15 dtk EMA)', () {
    test('mengembalikan null bila jendela < 10 dtk, < 10 m, atau < 0,45 m/s',
        () {
      final p = PaceEstimator();
      p.add(t0, 0);
      p.add(t0.add(const Duration(seconds: 5)), 15);
      expect(p.paceSecPerKm, isNull); // < 10 detik tanpa sensor speed

      final pShort = PaceEstimator();
      pShort.add(t0, 0);
      pShort.add(t0.add(const Duration(seconds: 15)), 8);
      expect(pShort.paceSecPerKm, isNull); // < 10 meter

      final pSlow = PaceEstimator();
      pSlow.add(t0, 0);
      pSlow.add(t0.add(const Duration(seconds: 15)), 5); // 0,33 m/s < 0,45
      expect(pSlow.paceSecPerKm, isNull);
    });

    test('menghitung pace pada jendela geser 15 detik dan rata-rata < 30 m = null',
        () {
      final p = PaceEstimator();
      for (var s = 0; s <= 15; s += 3) {
        p.add(
          t0.add(Duration(seconds: s)),
          s * 1.25,
          instantSpeedMps: 1.25,
        ); // 1,25 m/s = 13:20/km
      }
      expect(p.paceSecPerKm, closeTo(800, 1));
      expect(formatPaceValue(p.paceSecPerKm), '13:20');
      expect(formatPaceValue(120), '—'); // < 3:00/km
      expect(formatPaceValue(3700), '—'); // > 60:00/km
      expect(
        PaceEstimator.computeAveragePaceSecPerKm(
          distanceM: 25,
          movingSeconds: 20,
        ),
        isNull,
      );
      expect(
        PaceEstimator.computeAveragePaceSecPerKm(
          distanceM: 1000,
          movingSeconds: 600,
        ),
        closeTo(600, 0.1),
      );
    });
  });

  group('ElevationProcessor & VerticalSpeedEstimator (Strava)', () {
    test('histeresis GPS 8,0 m mengabaikan noise <= 8 m dan barometer 3 m mengabaikan <= 3 m',
        () {
      final gpsEle = ElevationProcessor();
      for (final a in [100.0, 106.2, 100.2, 107.4, 99.5, 105.8, 100.0]) {
        gpsEle.add(a);
      }
      expect(gpsEle.gainMeters, 0);
      expect(gpsEle.lossMeters, 0);

      final baroEle = ElevationProcessor(useBarometer: true);
      for (final a in [100.0, 102.5, 100.1, 102.8, 100.0]) {
        baroEle.add(a);
      }
      expect(baroEle.gainMeters, 0);
    });

    test('tanjakan dan turunan nyata dihitung dengan histeresis GPS 8,0 m', () {
      final e = ElevationProcessor();
      for (var a = 100.0; a <= 116; a += 1) {
        e.add(a);
      }
      expect(e.gainMeters, closeTo(16, 0.001));
      e.add(106);
      expect(e.lossMeters, closeTo(10, 0.001));
    });

    test('menggoyang HP di tempat menghasilkan 0 m tanjakan dan 0 m/jam kec. vertikal',
        () {
      final engine = TrackingEngine();
      TrackingSnapshot? latest;
      for (var s = 0; s <= 60; s += 2) {
        // Posisi GPS hampir diam (jitter < 1 m), tetapi ketinggian digoyang +/- 8 m
        // bahkan dengan galat vertikal buruk sesekali.
        final shakeAlt = 1000.0 + (s.isEven ? 8.0 : -8.0);
        engine.onFix(
          TrackPoint(
            lat: -6.9 + (s.isEven ? 0.0 : 0.000003),
            lon: 107.6,
            timestampUtc: t0.add(Duration(seconds: s)),
            accuracyM: 6,
            speedMps: 0.05,
            altitudeM: shakeAlt,
            altitudeAccuracyM: s % 6 == 0 ? 25.0 : 4.0,
          ),
        );
        latest = engine.latestSnapshot;
      }
      expect(latest, isNotNull);
      expect(latest!.gainM, 0);
      expect(latest.lossM, 0);
      expect(latest.verticalSpeedMph, 0);
    });

    test('AltitudeSmoother menolak sampel dengan galat vertikal > 25 m atau horizontal > 25 m', () {
      final s = AltitudeSmoother();
      s.addIfValid(1000, accuracyM: 4, horizontalAccuracyM: 6);
      final afterBadVertical = s.addIfValid(1200, accuracyM: 26, horizontalAccuracyM: 6);
      expect(afterBadVertical, closeTo(1000, 0.01));
      final afterBadHorizontal = s.addIfValid(1300, accuracyM: 4, horizontalAccuracyM: 28);
      expect(afterBadHorizontal, closeTo(1000, 0.01));
    });

    test('AltitudeSmoother meredam lonjakan dengan median 5 titik + moving average', () {
      final s = AltitudeSmoother();
      for (var i = 0; i < 4; i++) {
        s.add(1000);
      }
      // Lonjakan palsu 1050 m tidak langsung menarik output ke 1050
      final afterSpike = s.add(1050);
      expect(afterSpike, closeTo(1000, 0.5));
    });

    test('kecepatan vertikal jendela 45-60 dtk dengan dead-band < 3 m menghasilkan 0 m/jam', () {
      final v = VerticalSpeedEstimator();
      v.add(t0, 1000.0);
      v.add(t0.add(const Duration(seconds: 30)), 1001.2);
      expect(v.metersPerHour, isNull); // belum 45 detik
      v.add(t0.add(const Duration(seconds: 50)), 1002.4); // delta 2,4 m < 3 m
      expect(v.metersPerHour, 0);
    });

    test('kecepatan vertikal menghitung m/jam dan clamp +/- 3000', () {
      final v = VerticalSpeedEstimator();
      v.add(t0, 1000.0);
      v.add(t0.add(const Duration(seconds: 60)), 1010.0); // +10 m / 60s = 600 m/j
      expect(v.metersPerHour, closeTo(600, 0.1));

      final extreme = VerticalSpeedEstimator();
      extreme.add(t0, 1000.0);
      extreme.add(t0.add(const Duration(seconds: 60)), 1080.0);
      expect(extreme.metersPerHour, 3000);
    });
  });

  group('ACSM Calorie Estimator (1E)', () {
    test('kecepatan < 0,3 m/s menghasilkan 0 kkal', () {
      expect(
        acsmKcalPerKg(speedMps: 0.25, grade: 0, seconds: 60),
        0,
      );
    });

    test('persamaan jalan kaki ACSM untuk jalan datar dan menanjak', () {
      // v = 1,25 m/s = 75 m/menit, datar (grade = 0), 1 menit, berat 65 kg:
      // VO2 = 3,5 + 0,1 * 75 = 11,0 ml/kg/mnt
      // kkal/mnt = 11,0 * 65 / 1000 * 5 = 3,575 kkal
      final flatPerKg = acsmKcalPerKg(speedMps: 1.25, grade: 0, seconds: 60);
      expect(flatPerKg * 65, closeTo(3.575, 0.01));

      // Menanjak grade 10% (0,10):
      // VO2 = 3,5 + 7,5 + 1,8 * 75 * 0,10 = 24,5 ml/kg/mnt
      // kkal/mnt = 24,5 * 65 / 1000 * 5 = 7,9625 kkal
      final climbPerKg =
          acsmKcalPerKg(speedMps: 1.25, grade: 0.10, seconds: 60);
      expect(climbPerKg * 65, closeTo(7.9625, 0.01));
    });

    test('estimasi kalori MET klasik: 70 kg, 1 jam, datar = 315 kkal', () {
      expect(
        estimateKcal(weightKg: 70, movingTime: const Duration(hours: 1)),
        closeTo(315, 0.01),
      );
    });
  });

  group('Perkiraan Langkah & Kubik Monoton (1F & 1G)', () {
    test('perkiraan langkah dari jarak memakai 0,415 x tinggi_m', () {
      // 850 m / (0,415 * 1,70) = 850 / 0,7055 = 1204,8 -> 1205
      expect(
        estimateStepsFromDistance(distanceM: 850, heightCm: 170),
        1205,
      );
    });

    test('interpolasi kubik monoton Fritsch-Carlson tidak pernah overshoot',
        () {
      final y = <double>[1000, 1000, 1020, 1020, 1015, 1040, 1040];
      const h = 10.0;
      final m = monotoneTangents(y, h);
      for (var k = 0; k < y.length - 1; k++) {
        final lo = math.min(y[k], y[k + 1]);
        final hi = math.max(y[k], y[k + 1]);
        for (var step = 0; step <= 20; step++) {
          final x = (k + step / 20.0) * h;
          final val = evaluateMonotone(y, m, h, x);
          expect(val, greaterThanOrEqualTo(lo - 1e-6));
          expect(val, lessThanOrEqualTo(hi + 1e-6));
        }
      }
    });
  });

  group('AutoPauseDetector', () {
    test('berhenti setelah melambat melewati pauseAfter (4 dtk)', () {
      final d = AutoPauseDetector();
      for (var s = 0; s <= 30; s++) {
        d.update(t0.add(Duration(seconds: s)), 1.2);
      }
      for (var s = 31; s <= 60; s++) {
        d.update(t0.add(Duration(seconds: s)), 0);
      }
      expect(d.isMoving, isFalse);
      expect(d.movingTime.inSeconds, inInclusiveRange(33, 36));
    });
  });

  group('Simulasi GPX (1I)', () {
    test('simulasi GPX 1: jalan datar 500 m (1,25 m/s selama 400 detik)', () {
      final engine = TrackingEngine();
      TrackingSnapshot? last;
      for (var s = 0; s <= 400; s += 2) {
        // Noise altitud kecil +/- 0,6 m di tanah datar
        final noise = math.sin(s * 0.3) * 0.6;
        last = engine.onFix(_pt(
          metersNorth: s * 1.25,
          sec: s,
          accuracyM: 6,
          speedMps: 1.25,
          altitudeM: 500.0 + noise,
        ));
      }
      expect(last, isNotNull);
      expect(last!.distanceM, closeTo(500, 1.5));
      expect(formatPaceValue(last.paceSecPerKm), '13:20');
      expect(last.gainM, 0);
      expect(last.verticalSpeedMph, 0);
      final kcal65 = last.kcalPerKg * 65.0;
      expect(kcal65, closeTo(23.5, 2.0));
    });

    test('simulasi GPX 2: tanjakan 200 m horizontal (+24 m elevasi, 200 detik)',
        () {
      final engine = TrackingEngine();
      TrackingSnapshot? last;
      for (var s = 0; s <= 200; s += 2) {
        last = engine.onFix(_pt(
          metersNorth: s * 1.0,
          sec: s,
          accuracyM: 5,
          speedMps: 1.0,
          altitudeM: 1200.0 + s * 0.12, // +24 m dalam 200 detik (grade 12%)
        ));
      }
      expect(last, isNotNull);
      expect(last!.distanceM, closeTo(200, 1.0));
      expect(formatPaceValue(last.paceSecPerKm), '16:40');
      expect(last.gainM, greaterThan(15.0));
      expect(last.verticalSpeedMph, closeTo(432, 25));
      final kcal65 = last.kcalPerKg * 65.0;
      expect(kcal65, closeTo(23.0, 3.0));
    });
  });
}
