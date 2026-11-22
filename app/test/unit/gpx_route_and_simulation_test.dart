import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/map/domain/track_geojson.dart';
import 'package:nama_app/features/tracking/domain/tracking_engine.dart';
import 'package:nama_app/features/trails/data/gpx_loader.dart';
import 'package:nama_app/features/trails/domain/track_route.dart';
import 'package:nama_app/infrastructure/location/location_source.dart';

void main() {
  group('TrackRoute & GpxLoader (Bagian A)', () {
    test('menghitung jarak Haversine secara akurat', () {
      // 1 derajat lintang di ekuator ~ 111.195 m; 0.01 derajat ~ 1.111,95 m
      const points = <TrackRoutePoint>[
        TrackRoutePoint(lat: -6.9000, lon: 108.4000, ele: 1400),
        TrackRoutePoint(lat: -6.8900, lon: 108.4000, ele: 1500),
        TrackRoutePoint(lat: -6.8800, lon: 108.4000, ele: 1600),
      ];
      final distM = computeHaversineDistanceM(points);
      expect(distM, closeTo(2223.9, 5.0));
    });

    test('menghitung tanjakan dari data elevasi bernoise tanpa menghitung noise mikro', () {
      // Kenaikan murni 100 m (1500 -> 1600) disertai osilasi noise ±1,5 m
      final noisyElevations = <double?>[];
      for (var i = 0; i <= 100; i++) {
        final base = 1500.0 + i * 1.0;
        final noise = (i.isEven ? 1.4 : -1.4);
        noisyElevations.add(base + noise);
      }
      final stats = computeElevationStats(
        noisyElevations,
        thresholdM: 2.5,
        smoothingWindow: 5,
      );
      // Tanjakan sebenarnya 100 m; dengan perataan + histeresis 2,5 m tidak
      // membengkak akibat osilasi ±1,4 m di tiap titik.
      expect(stats.gainM, inInclusiveRange(95.0, 103.0));
      expect(stats.lossM, lessThan(3.0));
      expect(stats.minElevationM, closeTo(1501.4, 2.0));
      expect(stats.maxElevationM, closeTo(1601.4, 2.0));
    });

    test('GpxLoader menangani file tanpa elevasi/waktu, multi-segmen, dan <rte>', () {
      const multiSegWithoutEleOrTime = '''
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1">
  <trk>
    <name>Jalur Multi Segmen</name>
    <trkseg>
      <trkpt lat="-6.9100" lon="108.4100"></trkpt>
      <trkpt lat="-6.9050" lon="108.4100"></trkpt>
    </trkseg>
    <trkseg>
      <trkpt lat="-6.9000" lon="108.4100"></trkpt>
    </trkseg>
  </trk>
</gpx>
''';
      final trkRoute = GpxLoader.parseString(multiSegWithoutEleOrTime);
      expect(trkRoute.name, 'Jalur Multi Segmen');
      expect(trkRoute.points.length, 3);
      expect(trkRoute.totalDistanceM, greaterThan(1000));
      expect(trkRoute.totalElevationGainM, 0);
      expect(trkRoute.minElevationM, isNull);
      expect(trkRoute.maxElevationM, isNull);

      const rteOnlyGpx = '''
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1">
  <rte>
    <name>Rute Alternatif</name>
    <rtept lat="-6.9100" lon="108.4100"><ele>1200</ele></rtept>
    <rtept lat="-6.9000" lon="108.4100"><ele>1350</ele></rtept>
  </rte>
</gpx>
''';
      final rteRoute = GpxLoader.parseString(rteOnlyGpx);
      expect(rteRoute.name, 'Rute Alternatif');
      expect(rteRoute.points.length, 2);
      expect(rteRoute.minElevationM, 1200);
      expect(rteRoute.maxElevationM, 1350);
    });

    test('Douglas-Peucker menyederhanakan titik kolinear dan mempertahankan titik asli', () {
      final rawXml = File('assets/gpx/tes.gpx').readAsStringSync();
      final route = GpxLoader.parseString(
        rawXml,
        id: 'tes',
        simplifyToleranceM: 5.0,
      );

      expect(route.name, 'Jalur Pendakian Gn. Ciremai via Apuy');
      expect(route.points.length, 513);
      expect(route.simplifiedPoints.length, 92);
      expect(route.simplifiedPoints.length, lessThan(route.points.length));
      expect(route.simplifiedPoints.length, greaterThanOrEqualTo(2));
      expect(route.simplifiedPoints.first.lat, route.points.first.lat);
      expect(route.simplifiedPoints.last.lat, route.points.last.lat);

      final lineGeoJson = trackRouteLineToGeoJson(route);
      expect(lineGeoJson, contains('LineString'));
      expect(
        trackRouteMarkerToGeoJson(route.startPoint, role: 'start'),
        contains('"role":"start"'),
      );
      expect(
        trackRouteMarkerToGeoJson(route.endPoint, role: 'end'),
        contains('"role":"end"'),
      );
    });
  });

  group('SimulatedLocationSource & Pipeline Tracking (Bagian B)', () {
    test('interpolasi kecepatan mengikuti 1x, 5x, 10x dan timestamp GPX bila ada', () {
      const points = <TrackRoutePoint>[
        TrackRoutePoint(lat: -6.9000, lon: 108.4000, ele: 1500),
        TrackRoutePoint(lat: -6.8900, lon: 108.4000, ele: 1550),
      ];
      final route = TrackRoute.fromPoints(
        id: 'interp',
        name: 'Uji Interpolasi',
        points: points,
      );

      final sim = SimulatedLocationSource(
        route: route,
        baseSpeedMps: 1.2,
        speedMultiplier: 1,
        maxNoiseMeters: 0,
      );

      final t0 = DateTime.utc(2026, 11, 8, 6, 0, 0);
      final p1 = sim.stepTick(const Duration(seconds: 1), overrideTimestampUtc: t0)!;
      expect(p1.speedMps, closeTo(1.2, 1e-6));
      expect(sim.currentDistanceM, closeTo(1.2, 1e-6));
      expect(p1.heading, isNotNull);
      expect(p1.accuracyM, inInclusiveRange(5.0, 15.0));

      sim.setSpeedMultiplier(5);
      final p2 = sim.stepTick(
        const Duration(seconds: 1),
        overrideTimestampUtc: t0.add(const Duration(seconds: 1)),
      )!;
      expect(p2.speedMps, closeTo(6.0, 1e-6));
      expect(sim.currentDistanceM, closeTo(7.2, 1e-6));

      sim.setSpeedMultiplier(10);
      final p3 = sim.stepTick(
        const Duration(seconds: 1),
        overrideTimestampUtc: t0.add(const Duration(seconds: 2)),
      )!;
      expect(p3.speedMps, closeTo(12.0, 1e-6));
      expect(sim.currentDistanceM, closeTo(19.2, 1e-6));
    });

    test('total jarak hasil simulasi 1x cocok dengan jarak GPX dalam toleransi 3%', () {
      final rawXml = File('assets/gpx/tes.gpx').readAsStringSync();
      final route = GpxLoader.parseString(rawXml, id: 'tes');

      final sim = SimulatedLocationSource(
        route: route,
        baseSpeedMps: 1.2,
        speedMultiplier: 1,
        maxNoiseMeters: 3.0,
        minAccuracyM: 5.0,
        maxAccuracyM: 15.0,
        random: math.Random(12345),
      );

      final engine = TrackingEngine();
      var now = DateTime.utc(2026, 11, 8, 6, 0, 0);

      // Titik awal
      final startPt = sim.stepTick(
        const Duration(milliseconds: 100),
        overrideTimestampUtc: now,
      );
      if (startPt != null) {
        engine.onFix(startPt);
      }

      while (!sim.isCompleted) {
        now = now.add(const Duration(seconds: 1));
        final fix = sim.stepTick(
          const Duration(seconds: 1),
          overrideTimestampUtc: now,
        );
        if (fix == null) break;
        engine.onFix(fix);
      }

      final snapshot = engine.latestSnapshot!;
      final gpxDistanceM = route.totalDistanceM;
      final trackedDistanceM = snapshot.distanceM;
      final relativeDiff = (trackedDistanceM - gpxDistanceM).abs() / gpxDistanceM;

      // Verifikasi dalam toleransi 3% (0.03)
      expect(
        relativeDiff,
        lessThanOrEqualTo(0.03),
        reason:
            'Jarak simulasi 1x (${trackedDistanceM.toStringAsFixed(1)} m) harus '
            'berada dalam ±3% dari jarak GPX (${gpxDistanceM.toStringAsFixed(1)} m), '
            'selisih=${(relativeDiff * 100).toStringAsFixed(2)}%',
      );
    });

    test('simulasi jalur penuh pada kecepatan 10x (beserta jeda 10 dtk di tengah jalur)', () {
      final rawXml = File('assets/gpx/tes.gpx').readAsStringSync();
      final route = GpxLoader.parseString(rawXml, id: 'tes');

      final sim = SimulatedLocationSource(
        route: route,
        baseSpeedMps: 1.2,
        speedMultiplier: 10,
        maxNoiseMeters: 3.0,
        minAccuracyM: 5.0,
        maxAccuracyM: 15.0,
        stopAtMidpointEnabled: true,
        random: math.Random(42),
      );

      final engine = TrackingEngine();
      var now = DateTime.utc(2026, 11, 8, 7, 0, 0);
      var nonNullPaceCount = 0;

      while (!sim.isCompleted) {
        now = now.add(const Duration(seconds: 1));
        final fix = sim.stepTick(
          const Duration(seconds: 1),
          overrideTimestampUtc: now,
        );
        if (fix == null) break;
        engine.onFix(fix);
        if (engine.latestSnapshot?.paceSecPerKm != null) {
          nonNullPaceCount++;
        }
      }

      final snap = engine.latestSnapshot!;
      final diag = engine.diagnostics;

      // Pastikan simulasi 10x selesai mencapai 100% rute
      expect(sim.progress, closeTo(1.0, 1e-6));
      expect(snap.distanceM, greaterThan(0));
      expect(snap.movingTime, lessThan(snap.elapsed));
      expect(nonNullPaceCount, greaterThan(0));

      // Cetak laporan metrik lengkap untuk dokumentasi hasil uji 10x
      // ignore: avoid_print
      print(
        '=== LAPORAN SIMULASI 10x (tes.gpx) ===\n'
        'Jarak GPX         : ${route.totalDistanceM.toStringAsFixed(1)} m (${(route.totalDistanceM / 1000).toStringAsFixed(2)} km)\n'
        'Jarak Akhir Track : ${snap.distanceM.toStringAsFixed(1)} m (${(snap.distanceM / 1000).toStringAsFixed(2)} km)\n'
        'Tanjakan GPX      : ${route.totalElevationGainM.toStringAsFixed(1)} m\n'
        'Tanjakan Track    : ${snap.gainM.toStringAsFixed(1)} m\n'
        'Turunan GPX       : ${route.totalElevationLossM.toStringAsFixed(1)} m\n'
        'Turunan Track     : ${snap.lossM.toStringAsFixed(1)} m\n'
        'Elevasi Min/Maks  : ${route.minElevationM?.toStringAsFixed(0)} / ${route.maxElevationM?.toStringAsFixed(0)} mdpl\n'
        'Waktu Total       : ${snap.elapsed.inSeconds} dtk\n'
        'Waktu Bergerak    : ${snap.movingTime.inSeconds} dtk\n'
        'Fix Diterima/Lolos: ${diag.received} / ${diag.accepted} (Ditolak: ${diag.rejected} -> akurasi:${diag.rejectedAccuracy}, loncatan:${diag.rejectedJump}, jitter:${diag.rejectedJitter}, dupTime:${diag.rejectedDuplicateTime})\n'
        'Sampel Pace Valid : $nonNullPaceCount\n'
        'Titik Asli vs DP  : ${route.points.length} vs ${route.simplifiedPoints.length}',
      );
    });
  });
}
