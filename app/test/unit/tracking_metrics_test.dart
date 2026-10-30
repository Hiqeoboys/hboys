import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/tracking/domain/auto_pause_detector.dart';
import 'package:nama_app/features/tracking/domain/calorie_estimator.dart';
import 'package:nama_app/features/tracking/domain/distance_calculator.dart';
import 'package:nama_app/features/tracking/domain/elevation_processor.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_engine.dart';

final t0 = DateTime.utc(2027, 6, 1, 8);

// 1 derajat lintang ~ 111.195 km.
const metersPerDegLat = 111195.0;

void main() {
  group('ElevationProcessor', () {
    test('noise di bawah ambang tidak dihitung', () {
      final e = ElevationProcessor();
      for (final a in [100.0, 102.0, 100.0, 101.5, 99.0, 102.0, 100.0]) {
        e.add(a);
      }
      expect(e.gainMeters, 0);
      expect(e.lossMeters, 0);
    });

    test('tanjakan nyata dihitung', () {
      final e = ElevationProcessor();
      for (var a = 100.0; a <= 112; a += 1) {
        e.add(a);
      }
      expect(e.gainMeters, closeTo(12, 0.001));
    });

    test('turunan dihitung terpisah', () {
      final e = ElevationProcessor()
        ..add(200)
        ..add(190);
      expect(e.lossMeters, closeTo(10, 0.001));
      expect(e.gainMeters, 0);
    });
  });

  group('AutoPauseDetector', () {
    test('berhenti 10 detik setelah melambat', () {
      final d = AutoPauseDetector();
      for (var s = 0; s <= 30; s++) {
        d.update(t0.add(Duration(seconds: s)), 1.2);
      }
      for (var s = 31; s <= 60; s++) {
        d.update(t0.add(Duration(seconds: s)), 0);
      }
      expect(d.isMoving, isFalse);
      expect(d.movingTime.inSeconds, inInclusiveRange(38, 42));
    });

    test('lanjut bergerak saat kecepatan naik lagi', () {
      final d = AutoPauseDetector();
      d.update(t0, 1.2);
      for (var s = 1; s <= 20; s++) {
        d.update(t0.add(Duration(seconds: s)), 0);
      }
      expect(d.isMoving, isFalse);
      d.update(t0.add(const Duration(seconds: 21)), 1.5);
      expect(d.isMoving, isTrue);
    });

    test('celah sinyal tidak dihitung sebagai waktu bergerak', () {
      final d = AutoPauseDetector();
      d.update(t0, 1.2);
      d.update(t0.add(const Duration(minutes: 10)), 1.2);
      expect(d.movingTime, Duration.zero);
    });
  });

  group('DistanceCalculator', () {
    TrackPoint at(double meters, int s) => TrackPoint(
          lat: -6.9 + meters / metersPerDegLat,
          lon: 107.6,
          timestampUtc: t0.add(Duration(seconds: s)),
          accuracyM: 5,
        );

    test('jitter kecil tidak menambah jarak', () {
      final d = DistanceCalculator();
      for (var i = 0; i < 20; i++) {
        d.add(at(i.isEven ? 0 : 1.5, i));
      }
      expect(d.totalMeters, 0);
    });

    test('akumulasi langkah nyata', () {
      final d = DistanceCalculator();
      for (var i = 0; i <= 10; i++) {
        d.add(at(i * 10.0, i));
      }
      expect(d.totalMeters, closeTo(100, 1));
    });
  });

  test('estimasi kalori: 70 kg, 1 jam, datar = 315 kkal', () {
    expect(
      estimateKcal(weightKg: 70, movingTime: const Duration(hours: 1)),
      closeTo(315, 0.01),
    );
  });

  group('TrackingEngine', () {
    test('jalan lurus 1,2 m/s selama 60 detik', () {
      final engine = TrackingEngine();
      TrackingSnapshot? last;
      for (var s = 0; s <= 60; s += 5) {
        last = engine.onFix(TrackPoint(
          lat: -6.9 + (1.2 * s) / metersPerDegLat,
          lon: 107.6,
          timestampUtc: t0.add(Duration(seconds: s)),
          accuracyM: 5,
          altitudeM: 1000 + s * 0.2, // naik 12 m dalam 60 detik
        ));
      }
      expect(last, isNotNull);
      expect(last!.distanceM, closeTo(72, 2));
      expect(last.isMoving, isTrue);
      expect(last.movingTime.inSeconds, closeTo(60, 1));
      expect(last.paceSecPerKm, isNotNull);
      // 1,2 m/s ~ 833 detik/km
      expect(last.paceSecPerKm!, closeTo(833, 40));
      expect(last.gainM, greaterThan(8));
    });

    test('titik buruk tidak mengubah metrik', () {
      final engine = TrackingEngine();
      final ok = engine.onFix(TrackPoint(
        lat: -6.9, lon: 107.6, timestampUtc: t0, accuracyM: 5,
      ));
      expect(ok, isNotNull);
      final bad = engine.onFix(TrackPoint(
        lat: -6.9, lon: 107.6, timestampUtc: t0.add(const Duration(seconds: 5)), accuracyM: 90,
      ));
      expect(bad, isNull);
    });
  });
}
