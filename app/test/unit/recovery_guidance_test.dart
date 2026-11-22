import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/trails/domain/guidance_config.dart';
import 'package:nama_app/features/trails/domain/guidance_state.dart';
import 'package:nama_app/features/trails/domain/heading_provider.dart';
import 'package:nama_app/features/trails/domain/recovery_guidance_engine.dart';
import 'package:nama_app/features/trails/domain/track_route.dart';

void main() {
  group('RecoveryGuidanceEngine (Logika Murni Dart)', () {
    late TrackRoute northSouthRoute;

    setUp(() {
      // Jalur lurus ke utara di lon 108.4000 dari lat -6.9100 ke -6.8900 (~2.224 m)
      const points = <TrackRoutePoint>[
        TrackRoutePoint(lat: -6.9100, lon: 108.4000, ele: 1500),
        TrackRoutePoint(lat: -6.9050, lon: 108.4000, ele: 1550),
        TrackRoutePoint(lat: -6.9000, lon: 108.4000, ele: 1600),
        TrackRoutePoint(lat: -6.8900, lon: 108.4000, ele: 1700),
      ];
      northSouthRoute = TrackRoute.fromPoints(
        id: 'ns-route',
        name: 'Jalur Acuan Utara-Selatan',
        points: points,
      );
    });

    TrackPoint makePoint({
      required double lat,
      required double lon,
      required DateTime time,
      double accuracyM = 8.0,
      double? speedMps,
      double? heading,
    }) {
      return TrackPoint(
        lat: lat,
        lon: lon,
        timestampUtc: time,
        accuracyM: accuracyM,
        speedMps: speedMps,
        heading: heading,
      );
    }

    test('deteksi keluar jalur tidak mendeteksi pada noise 10-20 m, dan mendeteksi setelah dwell 5 dtk', () {
      final engine = RecoveryGuidanceEngine(
        config: const GuidanceConfig(
          offRouteMinM: 40.0,
          offRouteDwell: Duration(seconds: 5),
        ),
      )..setRoute(northSouthRoute);

      var t = DateTime.utc(2026, 11, 9, 10, 0, 0);

      // 1. Tepat di jalur -> GuidanceOnRoute(0 m)
      final pOn = makePoint(lat: -6.9050, lon: 108.4000, time: t);
      var state = engine.update(fix: pOn, recordedTrail: [pOn]);
      expect(state, isA<GuidanceOnRoute>());
      expect((state as GuidanceOnRoute).distanceToRouteM, closeTo(0.0, 0.1));

      // 2. Noise 10 meter ke timur (lon bergeser sedikit ~0.00009°)
      t = t.add(const Duration(seconds: 1));
      final pNoise10 = makePoint(lat: -6.9050, lon: 108.40009, time: t);
      state = engine.update(fix: pNoise10, recordedTrail: [pOn, pNoise10]);
      expect(state, isA<GuidanceOnRoute>());
      expect((state as GuidanceOnRoute).distanceToRouteM, inInclusiveRange(9.0, 11.0));

      // 3. Noise 20 meter ke timur (~0.00018°)
      t = t.add(const Duration(seconds: 1));
      final pNoise20 = makePoint(lat: -6.9050, lon: 108.40018, time: t);
      state = engine.update(fix: pNoise20, recordedTrail: [pOn, pNoise20]);
      expect(state, isA<GuidanceOnRoute>());
      expect((state as GuidanceOnRoute).distanceToRouteM, inInclusiveRange(18.0, 22.0));

      // 4. Bergerak keluar jalur 60 meter (> 40 m)
      // lon bergeser ~0.00054° (~60 m)
      t = t.add(const Duration(seconds: 1));
      final pOff1 = makePoint(lat: -6.9050, lon: 108.40054, time: t);
      state = engine.update(fix: pOff1, recordedTrail: [pOn, pOff1]);
      // Dwell baru 0 detik -> masih OnRoute
      expect(state, isA<GuidanceOnRoute>());

      // Setelah 3 detik di luar -> masih OnRoute (karena butuh 5 detik)
      t = t.add(const Duration(seconds: 3));
      final pOff2 = makePoint(lat: -6.9050, lon: 108.40054, time: t);
      state = engine.update(fix: pOff2, recordedTrail: [pOn, pOff2]);
      expect(state, isA<GuidanceOnRoute>());

      // Setelah total 5,5 detik di luar -> harus terkonfirmasi keluar jalur
      t = t.add(const Duration(milliseconds: 2500));
      final pOff3 = makePoint(lat: -6.9050, lon: 108.40054, time: t);
      state = engine.update(fix: pOff3, recordedTrail: [pOn, pOff3]);
      expect(state, isA<GuidanceFollowingTrail>());
      final following = state as GuidanceFollowingTrail;
      expect(following.offRouteM, inInclusiveRange(58.0, 62.0));
    });

    test('deteksi kembali ke jalur setelah dwell 3 dtk dengan histeresis', () {
      final engine = RecoveryGuidanceEngine(
        config: const GuidanceConfig(
          offRouteMinM: 40.0,
          offRouteDwell: Duration(seconds: 1), // cepat untuk test
          returnToleranceM: 20.0,
          returnDwell: Duration(seconds: 3),
        ),
      )..setRoute(northSouthRoute);

      var t = DateTime.utc(2026, 11, 9, 10, 0, 0);

      // Titik awal di jalur
      final pStart = makePoint(lat: -6.9050, lon: 108.4000, time: t);
      engine.update(fix: pStart, recordedTrail: [pStart]);

      // Keluar jalur 60 meter (kandidat off-route)
      t = t.add(const Duration(seconds: 2));
      final pOff1 = makePoint(lat: -6.9050, lon: 108.40054, time: t);
      engine.update(fix: pOff1, recordedTrail: [pStart, pOff1]);

      // 1,1 detik kemudian -> dwell >= offRouteDwell (1 dtk), terkonfirmasi keluar jalur
      t = t.add(const Duration(milliseconds: 1100));
      final pOff2 = makePoint(lat: -6.9050, lon: 108.40054, time: t);
      var state = engine.update(fix: pOff2, recordedTrail: [pStart, pOff1, pOff2]);
      expect(state, isA<GuidanceFollowingTrail>());

      // Mulai mendekat ke jalur: 15 m dari jalur (di dalam returnToleranceM 20 m)
      t = t.add(const Duration(seconds: 1));
      final pNear1 = makePoint(lat: -6.9050, lon: 108.400135, time: t);
      state = engine.update(fix: pNear1, recordedTrail: [pStart, pNear1]);
      // Dwell baru 0 detik -> masih FollowingTrail
      expect(state, isA<GuidanceFollowingTrail>());

      // Dwell 2 detik -> masih FollowingTrail
      t = t.add(const Duration(seconds: 2));
      final pNear2 = makePoint(lat: -6.9050, lon: 108.400135, time: t);
      state = engine.update(fix: pNear2, recordedTrail: [pStart, pNear2]);
      expect(state, isA<GuidanceFollowingTrail>());

      // Dwell 3,1 detik -> harus menghasilkan GuidanceReturned()
      t = t.add(const Duration(milliseconds: 1100));
      final pNear3 = makePoint(lat: -6.9050, lon: 108.400135, time: t);
      state = engine.update(fix: pNear3, recordedTrail: [pStart, pNear3]);
      expect(state, isA<GuidanceReturned>());

      // Fix berikutnya harus kembali ke GuidanceOnRoute
      t = t.add(const Duration(seconds: 1));
      final pBackOn = makePoint(lat: -6.9050, lon: 108.4000, time: t);
      state = engine.update(fix: pBackOn, recordedTrail: [pStart, pBackOn]);
      expect(state, isA<GuidanceOnRoute>());
    });

    test('pemilihan anchor memilih titik jejak terbaru ke belakang yang <= ambang', () {
      final engine = RecoveryGuidanceEngine(
        config: const GuidanceConfig(
          offRouteMinM: 40.0,
          offRouteDwell: Duration.zero,
        ),
      )..setRoute(northSouthRoute);

      final t0 = DateTime.utc(2026, 11, 9, 10, 0, 0);

      // Jejak rekaman:
      // T0: di jalur (0 m off)
      final t0Pt = makePoint(lat: -6.9080, lon: 108.4000, time: t0);
      // T1: di jalur (15 m off)
      final t1Pt = makePoint(
        lat: -6.9060,
        lon: 108.400135,
        time: t0.add(const Duration(seconds: 10)),
      );
      // T2: titik terakhir yang masih on-route (30 m off <= 40 m) -> INI HARUS JADI ANCHOR
      final t2Pt = makePoint(
        lat: -6.9050,
        lon: 108.40027,
        time: t0.add(const Duration(seconds: 20)),
      );
      // T3: mulai keluar (60 m off)
      final t3Pt = makePoint(
        lat: -6.9050,
        lon: 108.40054,
        time: t0.add(const Duration(seconds: 30)),
      );
      // T4: semakin jauh (100 m off)
      final t4Pt = makePoint(
        lat: -6.9050,
        lon: 108.40090,
        time: t0.add(const Duration(seconds: 40)),
      );

      final state = engine.update(
        fix: t4Pt,
        recordedTrail: [t0Pt, t1Pt, t2Pt, t3Pt, t4Pt],
        nowUtc: t4Pt.timestampUtc,
      );

      expect(state, isA<GuidanceFollowingTrail>());
      final following = state as GuidanceFollowingTrail;
      // Guide path harus berakhir di anchor (T2)
      final anchorPoint = following.guidePath.last;
      expect(anchorPoint.lat, closeTo(t2Pt.lat, 1e-5));
      expect(anchorPoint.lon, closeTo(t2Pt.lon, 1e-5));
    });

    test('bearing target akurat untuk 4 arah kardinal (Utara, Timur, Selatan, Barat)', () {
      final engine = RecoveryGuidanceEngine(
        config: const GuidanceConfig(
          offRouteMinM: 40.0,
          offRouteDwell: Duration.zero,
          lookaheadM: 30.0,
        ),
      );

      // Posisi acuan pengguna
      const centerLat = -6.9000;
      const centerLon = 108.4000;
      final t = DateTime.utc(2026, 11, 9, 10, 0, 0);

      void testBearingDirection({
        required LatLng anchorPos,
        required double expectedBearing,
        required String directionName,
      }) {
        // Rute acuan di anchor yang tegak lurus terhadap arah user -> anchor
        // agar pengguna tetap berada di luar jalur (~78 m) dan anchor berada di jalur (0 m)
        final dLat = anchorPos.lat - centerLat;
        final dLon = anchorPos.lon - centerLon;
        final route = TrackRoute.fromPoints(
          id: 'dir-route',
          name: 'Rute Arah',
          points: [
            TrackRoutePoint(lat: anchorPos.lat - dLon * 0.5, lon: anchorPos.lon + dLat * 0.5),
            TrackRoutePoint(lat: anchorPos.lat + dLon * 0.5, lon: anchorPos.lon - dLat * 0.5),
          ],
        );
        engine.setRoute(route);

        final pUser = makePoint(lat: centerLat, lon: centerLon, time: t);
        final pAnchor = makePoint(
          lat: anchorPos.lat,
          lon: anchorPos.lon,
          time: t.subtract(const Duration(seconds: 10)),
        );

        final state = engine.update(
          fix: pUser,
          recordedTrail: [pAnchor, pUser],
          nowUtc: t,
        );

        expect(state, isA<GuidanceFollowingTrail>());
        final following = state as GuidanceFollowingTrail;
        final diff = ((following.bearingDeg - expectedBearing + 540) % 360) - 180;
        expect(diff.abs(), lessThan(3.0),
            reason: 'Bearing ke $directionName harus sekitar $expectedBearing°');
      }

      // Anchor di utara (+lat) -> bearing ~0°
      testBearingDirection(
        anchorPos: const LatLng(-6.8993, 108.4000), // ~78 m ke utara
        expectedBearing: 0.0,
        directionName: 'Utara',
      );

      // Anchor di timur (+lon) -> bearing ~90°
      testBearingDirection(
        anchorPos: const LatLng(-6.9000, 108.4007), // ~77 m ke timur
        expectedBearing: 90.0,
        directionName: 'Timur',
      );

      // Anchor di selatan (-lat) -> bearing ~180°
      testBearingDirection(
        anchorPos: const LatLng(-6.9007, 108.4000), // ~78 m ke selatan
        expectedBearing: 180.0,
        directionName: 'Selatan',
      );

      // Anchor di barat (-lon) -> bearing ~270°
      testBearingDirection(
        anchorPos: const LatLng(-6.9000, 108.3993), // ~77 m ke barat
        expectedBearing: 270.0,
        directionName: 'Barat',
      );
    });

    test('jejak memutar (berkelok L) tidak dipotong diagonal secara lurus', () {
      // Skenario: Pengguna keluar jalur dan memutari jurang berbentuk huruf L:
      // Anchor berada di (0, 0).
      // Pengguna berjalan ke timur 80 m, lalu belok ke utara 80 m.
      // Posisi sekarang di ujung utara.
      // Jika dipotong lurus, arahnya diagonal barat-daya (~225°).
      // Tetapi pemanduan jejak harus membimbing ke selatan (~180°) menuju sudut L dulu!
      const lat0 = -6.9000;
      const lon0 = 108.4000;

      final route = TrackRoute.fromPoints(
        id: 'bend-route',
        name: 'Rute Sudut',
        points: const [
          TrackRoutePoint(lat: lat0, lon: lon0),
          TrackRoutePoint(lat: lat0 - 0.001, lon: lon0),
        ],
      );

      final engine = RecoveryGuidanceEngine(
        config: const GuidanceConfig(
          offRouteMinM: 30.0,
          offRouteDwell: Duration.zero,
          lookaheadM: 20.0,
          targetReachedM: 8.0,
          simplifyToleranceM: 4.0,
        ),
      )..setRoute(route);

      final t = DateTime.utc(2026, 11, 9, 10, 0, 0);

      // T0: Anchor di (lat0, lon0)
      final tAnchor = makePoint(lat: lat0, lon: lon0, time: t);
      // T1: Sudut belokan L di timur (~80 m ke timur)
      final tCorner = makePoint(
        lat: lat0,
        lon: lon0 + 0.00072,
        time: t.add(const Duration(seconds: 30)),
      );
      // T2: Posisi sekarang (~80 m ke utara dari sudut)
      final tCurrent = makePoint(
        lat: lat0 + 0.00072,
        lon: lon0 + 0.00072,
        time: t.add(const Duration(seconds: 60)),
      );

      final state = engine.update(
        fix: tCurrent,
        recordedTrail: [tAnchor, tCorner, tCurrent],
        nowUtc: tCurrent.timestampUtc,
      );

      expect(state, isA<GuidanceFollowingTrail>());
      final following = state as GuidanceFollowingTrail;

      // Sudut belokan harus tetap ada dalam guidePath (tidak dipangkas menjadi 2 titik diagonal)
      expect(following.guidePath.length, greaterThanOrEqualTo(3));

      // Arah panduan pertama dari tCurrent harus mengarah ke selatan (ke sudut L ~180°),
      // BUKAN memotong diagonal ke barat-daya (~225°)
      expect(following.bearingDeg, inInclusiveRange(170.0, 190.0),
          reason: 'Arah harus menuju sudut L ke selatan (~180°), bukan dipotong lurus');
    });

    test('switchback (jalur paralel rapat) tidak salah cocok ke segmen seberang', () {
      // Jalur switchback zig-zag:
      // Segmen A: dari (0, 0) ke (0, 100 m) [arah timur, jarak rute 0..100 m]
      // Segmen B: dari (15 m utara, 100 m timur) ke (15 m utara, 0 m) [arah barat, jarak rute 115..215 m]
      const latBase = -6.9000;
      const lonBase = 108.4000;
      // ~15 m di lintang = ~0.000135 derajat
      const dLat15m = 0.000135;
      // ~100 m di bujur = ~0.0009 derajat
      const dLon100m = 0.0009;

      final switchbackRoute = TrackRoute.fromPoints(
        id: 'switchback-route',
        name: 'Jalur Switchback',
        points: const [
          TrackRoutePoint(lat: latBase, lon: lonBase), // P0: 0,0
          TrackRoutePoint(lat: latBase, lon: lonBase + dLon100m), // P1: 0,100
          TrackRoutePoint(lat: latBase + dLat15m, lon: lonBase + dLon100m), // P2: 15,100
          TrackRoutePoint(lat: latBase + dLat15m, lon: lonBase), // P3: 15,0
        ],
      );

      final engine = RecoveryGuidanceEngine(
        config: const GuidanceConfig(
          offRouteMinM: 40.0,
          switchbackWindowMeters: 80.0,
        ),
      )..setRoute(switchbackRoute);

      var t = DateTime.utc(2026, 11, 9, 10, 0, 0);

      // Pendaki berjalan di Segmen A pada tengah jalan (lonBase + 0.00045)
      final pOnSegA = makePoint(
        lat: latBase,
        lon: lonBase + 0.00045,
        time: t,
      );
      var state = engine.update(fix: pOnSegA, recordedTrail: [pOnSegA]);
      expect(state, isA<GuidanceOnRoute>());
      expect(engine.lastProgressDistanceM, closeTo(50.0, 1.0));

      // Ada drift GPS 10 m ke arah utara (latBase + 0.00009):
      // Jarak ke Segmen A = 10 m.
      // Jarak ke Segmen B = 5 m (15 m - 10 m).
      // Meskipun secara global lebih dekat ke Segmen B (5 m vs 10 m),
      // engine harus tetap mempertahankan Segmen A karena ada di jendela progres!
      t = t.add(const Duration(seconds: 1));
      final pDriftTowardsSegB = makePoint(
        lat: latBase + 0.00009,
        lon: lonBase + 0.00045,
        time: t,
      );
      state = engine.update(
        fix: pDriftTowardsSegB,
        recordedTrail: [pOnSegA, pDriftTowardsSegB],
      );

      expect(state, isA<GuidanceOnRoute>());
      // Progres harus tetap berada di Segmen A (~50 m), bukan melompat ke Segmen B (~165 m)
      expect(engine.lastProgressDistanceM, closeTo(50.0, 2.0),
          reason: 'Pendaki tidak boleh melompat ke Segmen B seberang switchback');
    });

    test('fix basi (> 10 detik) menghasilkan GuidanceUnavailable(waitingGps)', () {
      final engine = RecoveryGuidanceEngine(
        config: const GuidanceConfig(staleFixSeconds: 10),
      )..setRoute(northSouthRoute);

      final fixTime = DateTime.utc(2026, 11, 9, 10, 0, 0);
      final p = makePoint(lat: -6.9050, lon: 108.4000, time: fixTime);

      // Fix segar (selisih 2 detik) -> valid OnRoute
      var state = engine.update(
        fix: p,
        recordedTrail: [p],
        nowUtc: fixTime.add(const Duration(seconds: 2)),
      );
      expect(state, isA<GuidanceOnRoute>());

      // Fix basi (selisih 15 detik > 10 detik) -> waitingGps
      state = engine.update(
        fix: p,
        recordedTrail: [p],
        nowUtc: fixTime.add(const Duration(seconds: 15)),
      );
      expect(state, isA<GuidanceUnavailable>());
      expect((state as GuidanceUnavailable).reason, GuidanceUnavailableReason.waitingGps);
    });

    test('jejak kosong saat keluar jalur menghasilkan GuidanceStraightLine', () {
      final engine = RecoveryGuidanceEngine(
        config: const GuidanceConfig(
          offRouteMinM: 40.0,
          offRouteDwell: Duration.zero,
        ),
      )..setRoute(northSouthRoute);

      final t = DateTime.utc(2026, 11, 9, 10, 0, 0);
      // Titik 70 meter di timur jalur
      final pOff = makePoint(lat: -6.9050, lon: 108.40063, time: t);

      // Jejak rekaman kosong
      final state = engine.update(
        fix: pOff,
        recordedTrail: const <TrackPoint>[],
        nowUtc: t,
      );

      expect(state, isA<GuidanceStraightLine>());
      final straight = state as GuidanceStraightLine;
      expect(straight.distToRouteM, inInclusiveRange(68.0, 72.0));
      // Titik target harus berada di jalur utama
      expect(straight.targetPoint.lon, closeTo(108.4000, 1e-4));
      // Bearing harus mengarah ke barat (~270°) menuju jalur
      expect(straight.bearingDeg, inInclusiveRange(268.0, 272.0));
    });
  });

  group('HeadingProvider', () {
    test('memilih GPS course saat kecepatan > ambang (1.0 m/s)', () {
      final provider = HeadingProvider(headingSpeedThresholdMps: 1.0);

      // Kecepatan 2.5 m/s dengan heading GPS 120°
      final movingFix = TrackPoint(
        lat: -6.9000,
        lon: 108.4000,
        accuracyM: 5.0,
        speedMps: 2.5,
        heading: 120.0,
        timestampUtc: DateTime.utc(2026, 11, 9, 10, 0, 0),
      );

      provider.updateGpsFix(movingFix);
      final reading = provider.currentReading;
      expect(reading, isNotNull);
      expect(reading!.source, HeadingSource.gpsCourse);
      expect(reading.headingDeg, 120.0);
      expect(reading.needsCalibration, isFalse);

      provider.dispose();
    });

    test('memilih kompas dengan low-pass filter saat diam (speed <= 1.0 m/s)', () {
      final provider = HeadingProvider(
        headingSpeedThresholdMps: 1.0,
        lowPassAlpha: 0.5,
      );

      // Fix diam (speed 0 m/s)
      final staticFix = TrackPoint(
        lat: -6.9000,
        lon: 108.4000,
        accuracyM: 5.0,
        speedMps: 0.0,
        timestampUtc: DateTime.utc(2026, 11, 9, 10, 0, 0),
      );
      provider.updateGpsFix(staticFix);

      // Masukkan kompas mentah 80°
      provider.updateCompassRaw(80.0, accuracyDeg: 10.0);
      expect(provider.currentReading?.source, HeadingSource.compass);
      expect(provider.currentReading?.headingDeg, 80.0);
      expect(provider.currentReading?.needsCalibration, isFalse);

      // Masukkan kompas mentah 90° -> low-pass filter alpha 0.5 menghasilkan 85°
      provider.updateCompassRaw(90.0, accuracyDeg: 10.0);
      expect(provider.currentReading?.headingDeg, closeTo(85.0, 0.1));

      // Akurasi buruk 45° -> needsCalibration = true
      provider.updateCompassRaw(90.0, accuracyDeg: 45.0);
      expect(provider.currentReading?.needsCalibration, isTrue);

      provider.dispose();
    });
  });
}
