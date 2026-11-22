import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/features/trails/domain/track_route.dart';
import 'package:nama_app/infrastructure/location/location_source.dart';

void main() {
  group('SimulatedLocationSource Scenarios', () {
    late TrackRoute testRoute;
    late List<LatLng> trailLatLngs;

    setUp(() {
      // Jalur lurus ke utara sepanjang ~1.112 meter (dari lat -6.9100 ke -6.9000 pada lon 108.4000)
      const points = <TrackRoutePoint>[
        TrackRoutePoint(lat: -6.9100, lon: 108.4000, ele: 1500),
        TrackRoutePoint(lat: -6.9050, lon: 108.4000, ele: 1550),
        TrackRoutePoint(lat: -6.9000, lon: 108.4000, ele: 1600),
      ];
      testRoute = TrackRoute.fromPoints(
        id: 'test-scenario-route',
        name: 'Jalur Pengujian Skenario',
        points: points,
      );
      trailLatLngs = points.map((p) => p.position).toList();
    });

    test('posisi mengikuti jalur dengan jarak sesuai kecepatan (1x, 5x, 10x)', () {
      final clock = FakeClock(DateTime.utc(2026, 11, 9, 8, 0, 0));
      final sim = SimulatedLocationSource(
        route: testRoute,
        baseSpeedMps: 1.2,
        speedMultiplier: 1,
        maxNoiseMeters: 0,
        clock: clock,
      );

      // Pada 1x (1,2 m/s): 10 detik menghasilkan 12 meter
      for (var i = 0; i < 10; i++) {
        clock.advance(const Duration(seconds: 1));
        sim.stepTick(const Duration(seconds: 1));
      }
      expect(sim.currentDistanceM, closeTo(12.0, 0.05));
      expect(sim.lastEmittedPosition, isNotNull);
      expect(
        distanceToPolylineMeters(sim.lastEmittedPosition!, trailLatLngs),
        closeTo(0.0, 0.05),
      );

      // Pada 5x (6,0 m/s): 10 detik menghasilkan 60 meter tambahan (total 72 m)
      sim.setSpeedMultiplier(5);
      for (var i = 0; i < 10; i++) {
        clock.advance(const Duration(seconds: 1));
        sim.stepTick(const Duration(seconds: 1));
      }
      expect(sim.currentDistanceM, closeTo(72.0, 0.1));

      // Pada 10x (12,0 m/s): 5 detik menghasilkan 60 meter tambahan (total 132 m)
      sim.setSpeedMultiplier(10);
      for (var i = 0; i < 5; i++) {
        clock.advance(const Duration(seconds: 1));
        sim.stepTick(const Duration(seconds: 1));
      }
      expect(sim.currentDistanceM, closeTo(132.0, 0.2));
    });

    test('skenario jalan di jalur 400 m berhenti tepat setelah 400 m', () {
      final clock = FakeClock(DateTime.utc(2026, 11, 9, 8, 0, 0));
      final sim = SimulatedLocationSource(
        route: testRoute,
        baseSpeedMps: 1.2,
        speedMultiplier: 10, // 12 m/s
        maxNoiseMeters: 0,
        clock: clock,
      );

      final startDistance = sim.currentDistanceM;
      sim.walkRoute400m();
      expect(sim.scenarioState, SimulationScenarioState.walkingRoute400m);

      // Berjalan hingga skenario selesai
      while (sim.scenarioState == SimulationScenarioState.walkingRoute400m) {
        clock.advance(const Duration(seconds: 1));
        sim.stepTick(const Duration(seconds: 1));
      }

      // Harus berhenti di jarak +400 m dan status kembali ke idle
      expect(sim.scenarioState, SimulationScenarioState.idle);
      expect(sim.currentDistanceM - startDistance, closeTo(400.0, 0.5));

      // Step berikutnya saat idle tidak menambah jarak target
      clock.advance(const Duration(seconds: 1));
      sim.stepTick(const Duration(seconds: 1));
      // Sekarang berjalan normal dari 400 m
      expect(sim.currentDistanceM - startDistance, greaterThan(400.0));
    });

    test('skenario menyimpang menghasilkan jarak ke jalur sekitar 150 m lewat lintasan melengkung', () {
      final clock = FakeClock(DateTime.utc(2026, 11, 9, 8, 0, 0));
      final sim = SimulatedLocationSource(
        route: testRoute,
        baseSpeedMps: 1.2,
        speedMultiplier: 5, // 6 m/s
        maxNoiseMeters: 0,
        clock: clock,
      );

      // Jalankan sedikit di jalur
      for (var i = 0; i < 5; i++) {
        clock.advance(const Duration(seconds: 1));
        sim.stepTick(const Duration(seconds: 1));
      }

      sim.startCurvedDeviation150m();
      expect(sim.scenarioState, SimulationScenarioState.deviatingCurved150m);

      var sawCurvedDisplacement = false;

      // Jalankan sampai penyimpangan selesai mencapai posisi statis di luar jalur
      while (sim.scenarioState == SimulationScenarioState.deviatingCurved150m) {
        clock.advance(const Duration(seconds: 1));
        final point = sim.stepTick(const Duration(seconds: 1));
        if (point != null) {
          final dist = distanceToPolylineMeters(point.position, trailLatLngs);
          if (dist > 20 && dist < 120) {
            // Memastikan lintasan intermediate terjadi
            sawCurvedDisplacement = true;
          }
        }
      }

      expect(sawCurvedDisplacement, isTrue,
          reason: 'Harus melintasi titik belok antara (jalur memutar)');
      expect(sim.scenarioState, SimulationScenarioState.deviatedStatic);

      // Jarak akhir tegak lurus ke polyline harus sekitar 150 meter (toleransi ±2 m)
      final endPos = sim.lastEmittedPosition!;
      final finalDist = distanceToPolylineMeters(endPos, trailLatLngs);
      expect(finalDist, closeTo(150.0, 2.0));
      expect(sim.currentOffsetFromTrailM, closeTo(150.0, 2.0));
    });

    test('skenario teleport memindahkan posisi 100 m dan memanggil pembersihan jejak', () async {
      final sim = SimulatedLocationSource(
        route: testRoute,
        baseSpeedMps: 1.2,
        maxNoiseMeters: 0,
      );

      var clearTrackCalled = false;
      await sim.teleportWithoutTrack100m(
        onClearTrack: () async {
          clearTrackCalled = true;
        },
      );

      expect(clearTrackCalled, isTrue,
          reason: 'Callback onClearTrack harus dipanggil untuk menghapus jejak');
      expect(sim.scenarioState, SimulationScenarioState.deviatedStatic);

      // Posisi sekarang harus berjarak sekitar 100 m dari jalur
      final point = sim.stepTick(const Duration(seconds: 1))!;
      final dist = distanceToPolylineMeters(point.position, trailLatLngs);
      expect(dist, closeTo(100.0, 2.0));
      expect(point.speedMps, 0.0);
    });

    test('skenario jalan kembali mengarahkan pengguna hingga tiba kembali di jalur (< 3 m)', () async {
      final clock = FakeClock(DateTime.utc(2026, 11, 9, 8, 0, 0));
      final sim = SimulatedLocationSource(
        route: testRoute,
        baseSpeedMps: 1.2,
        speedMultiplier: 10, // 12 m/s
        maxNoiseMeters: 0,
        clock: clock,
      );

      // Teleport 100 m dari jalur
      await sim.teleportWithoutTrack100m();
      sim.stepTick(const Duration(seconds: 1));
      expect(distanceToPolylineMeters(sim.lastEmittedPosition!, trailLatLngs),
          closeTo(100.0, 2.0));

      // Mulai jalan kembali
      sim.walkBackToTrail();
      expect(sim.scenarioState, SimulationScenarioState.walkingBackToTrail);

      // Berjalan mendekati jalur sampai skenario selesai
      var steps = 0;
      while (sim.scenarioState == SimulationScenarioState.walkingBackToTrail &&
          steps < 100) {
        steps++;
        clock.advance(const Duration(seconds: 1));
        sim.stepTick(const Duration(seconds: 1));
      }

      // Harus tiba kembali di jalur
      expect(sim.scenarioState, SimulationScenarioState.idle);
      final returnDist =
          distanceToPolylineMeters(sim.lastEmittedPosition!, trailLatLngs);
      expect(returnDist, lessThanOrEqualTo(3.0),
          reason: 'Pengguna harus berada kembali di jalur (jarak <= 3 m)');
    });

    test('skenario sinyal buruk menghasilkan akurasi 40 m selama 20 detik', () {
      final clock = FakeClock(DateTime.utc(2026, 11, 9, 8, 0, 0));
      final sim = SimulatedLocationSource(
        route: testRoute,
        baseSpeedMps: 1.2,
        maxNoiseMeters: 0,
        minAccuracyM: 5.0,
        maxAccuracyM: 10.0,
        clock: clock,
      );

      // Akurasi normal (5-10 m)
      final pNormal = sim.stepTick(const Duration(seconds: 1))!;
      expect(pNormal.accuracyM, inInclusiveRange(5.0, 10.0));

      // Picu sinyal buruk 20 detik
      sim.triggerPoorSignal(duration: const Duration(seconds: 20));
      expect(sim.isPoorSignalActive, isTrue);

      // Selama 20 detik: akurasi 40-45 m
      for (var s = 0; s < 19; s++) {
        clock.advance(const Duration(seconds: 1));
        final p = sim.stepTick(const Duration(seconds: 1))!;
        expect(p.accuracyM, inInclusiveRange(40.0, 45.0));
      }

      // Setelah 20 detik lewat: akurasi kembali normal
      clock.advance(const Duration(seconds: 2));
      final pRecovered = sim.stepTick(const Duration(seconds: 1))!;
      expect(sim.isPoorSignalActive, isFalse);
      expect(pRecovered.accuracyM, inInclusiveRange(5.0, 10.0));
    });

    test('jeda dan reset menghentikan dan mengembalikan posisi ke titik awal', () {
      final clock = FakeClock(DateTime.utc(2026, 11, 9, 8, 0, 0));
      final sim = SimulatedLocationSource(
        route: testRoute,
        baseSpeedMps: 1.2,
        clock: clock,
      );

      clock.advance(const Duration(seconds: 10));
      sim.stepTick(const Duration(seconds: 10));
      expect(sim.currentDistanceM, greaterThan(0));

      // Jeda
      sim.pauseSimulation();
      expect(sim.isSimulationPaused, isTrue);
      final pPaused = sim.stepTick(const Duration(seconds: 5));
      expect(pPaused, isNull, reason: 'Saat jeda tidak ada titik yang diemisikan');

      // Lanjut
      sim.resumeSimulation();
      expect(sim.isSimulationPaused, isFalse);

      // Reset
      sim.reset();
      expect(sim.currentDistanceM, 0.0);
      expect(sim.scenarioState, SimulationScenarioState.idle);
      expect(sim.currentOffsetFromTrailM, 0.0);
    });
  });
}
