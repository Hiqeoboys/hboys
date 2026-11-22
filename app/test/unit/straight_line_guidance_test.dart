import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/trails/domain/guidance_config.dart';
import 'package:nama_app/features/trails/domain/guidance_state.dart';
import 'package:nama_app/features/trails/domain/recovery_guidance_engine.dart';
import 'package:nama_app/features/trails/domain/straight_line_guidance_texts.dart';
import 'package:nama_app/features/trails/domain/track_route.dart';

TrackPoint _point({
  required double lat,
  required double lon,
  required DateTime time,
  double accuracyM = 5.0,
}) {
  return TrackPoint(
    lat: lat,
    lon: lon,
    accuracyM: accuracyM,
    timestampUtc: time,
  );
}

void main() {
  group('StraightLineGuidanceTexts - Kebijakan Keselamatan Kata Aman', () {
    test('tidak ada kata atau substring "aman" di seluruh teks petunjuk garis lurus',
        () {
      expect(StraightLineGuidanceTexts.allUserFacingTexts, isNotEmpty);

      for (final text in StraightLineGuidanceTexts.allUserFacingTexts) {
        final lower = text.toLowerCase();
        expect(
          lower.contains('aman'),
          isFalse,
          reason:
              'Teks tidak boleh memuat kata/substring "aman" karena garis lurus '
              'bukan rute yang pasti bebas bahaya: "$text"',
        );
        expect(
          lower.contains('rute aman'),
          isFalse,
          reason: 'Dilarang keras memakai frasa "rute aman"',
        );
      }
    });

    test('label mode petunjuk lurus adalah persis "Garis lurus, bukan rute"', () {
      expect(StraightLineGuidanceTexts.modeLabel, 'Garis lurus, bukan rute');
    });

    test('isi teks dialog dan kartu peringatan sesuai kontrak keselamatan', () {
      expect(StraightLineGuidanceTexts.dialogTitle, 'Peringatan penting');
      expect(
        StraightLineGuidanceTexts.dialogContent,
        contains('Petunjuk ini hanya garis lurus ke jalur terdekat'),
      );
      expect(StraightLineGuidanceTexts.dialogContent, contains('tebing, jurang, sungai'));
      expect(StraightLineGuidanceTexts.dialogCancel, 'Batal');
      expect(StraightLineGuidanceTexts.dialogSos, 'SOS');
      expect(StraightLineGuidanceTexts.dialogAcknowledge, 'Saya mengerti');
      expect(
        StraightLineGuidanceTexts.warningCardText,
        contains('Ini hanya arah lurus. Di antaranya bisa ada tebing, jurang, atau sungai.'),
      );
      expect(
        StraightLineGuidanceTexts.farFromRouteWarning,
        'Kamu jauh dari jalur. Pertimbangkan berhenti dan minta bantuan.',
      );
      expect(
        StraightLineGuidanceTexts.lowAccuracyWarning,
        'Akurasi GPS rendah, arah bisa meleset.',
      );
    });
  });

  group('RecoveryGuidanceEngine - Logika Garis Lurus (GuidanceStraightLine)', () {
    late TrackRoute testRoute;
    late RecoveryGuidanceEngine engine;

    setUp(() {
      testRoute = TrackRoute.fromPoints(
        id: 'main-trail',
        name: 'Jalur Utama',
        points: const [
          TrackRoutePoint(lat: -6.9000, lon: 108.4000), // Titik 0
          TrackRoutePoint(lat: -6.9100, lon: 108.4000), // Titik 1 (~1,1 km selatan)
        ],
      );

      engine = RecoveryGuidanceEngine(
        config: const GuidanceConfig(
          offRouteMinM: 40.0,
          offRouteDwell: Duration.zero, // Langsung off-route untuk uji
          returnToleranceM: 20.0,
          returnDwell: Duration(seconds: 3),
        ),
      )..setRoute(testRoute);
    });

    test('mode garis lurus HANYA aktif bila tanpa jejak (jejak kosong)', () {
      final t = DateTime.utc(2026, 11, 9, 10, 0, 0);

      // Posisi pengguna 100 m di barat jalur utama (lat: -6.9050, lon: 108.3991)
      final pUser = _point(lat: -6.9050, lon: 108.3991, time: t);

      // Jejak rekaman kosong:
      final state = engine.update(
        fix: pUser,
        recordedTrail: const <TrackPoint>[],
        nowUtc: t,
      );

      expect(state, isA<GuidanceStraightLine>());
      final straight = state as GuidanceStraightLine;

      // targetPoint harus berada di proyeksi jalur utama (lat: -6.9050, lon: 108.4000)
      expect(straight.targetPoint.lat, closeTo(-6.9050, 1e-4));
      expect(straight.targetPoint.lon, closeTo(108.4000, 1e-4));

      // Jarak lurus ke jalur ~100 meter
      expect(straight.distToRouteM, inInclusiveRange(95.0, 105.0));

      // Arah ke timur (jalur ada di sebelah timur pengguna): bearing ~90°
      expect(straight.bearingDeg, closeTo(90.0, 3.0));

      // Progres awal = 0.0
      expect(straight.progress, closeTo(0.0, 1e-3));
    });

    test('mode garis lurus aktif bila jejak ada tapi tidak pernah dekat jalur utama (tanpa anchor)',
        () {
      final t = DateTime.utc(2026, 11, 9, 10, 0, 0);

      // Semua titik jejak berada 120-150 m dari jalur utama (tidak ada yang <= ambang 40 m)
      final p1 = _point(
        lat: -6.9050,
        lon: 108.3986,
        time: t.subtract(const Duration(seconds: 20)),
      );
      final p2 = _point(
        lat: -6.9050,
        lon: 108.3988,
        time: t.subtract(const Duration(seconds: 10)),
      );
      final pUser = _point(lat: -6.9050, lon: 108.3990, time: t);

      final state = engine.update(
        fix: pUser,
        recordedTrail: [p1, p2, pUser],
        nowUtc: t,
      );

      // Tanpa anchor pada jalur utama -> harus fallback ke GuidanceStraightLine
      expect(state, isA<GuidanceStraightLine>());
      final straight = state as GuidanceStraightLine;
      expect(straight.distToRouteM, inInclusiveRange(105.0, 115.0));
    });

    test('perhitungan progres garis lurus meningkat saat mendekati rute dan ter-clamp 0..1',
        () {
      final t0 = DateTime.utc(2026, 11, 9, 10, 0, 0);

      // Titik awal 100 m dari jalur: progress = 0.0
      final p1 = _point(lat: -6.9050, lon: 108.3991, time: t0);
      var state = engine.update(
        fix: p1,
        recordedTrail: const <TrackPoint>[],
        nowUtc: t0,
      );
      expect(state, isA<GuidanceStraightLine>());
      expect((state as GuidanceStraightLine).progress, closeTo(0.0, 1e-2));

      // Mendekat menjadi 50 m dari jalur: progress ~ 0.5 (50%)
      final t1 = t0.add(const Duration(seconds: 10));
      final p2 = _point(lat: -6.9050, lon: 108.39955, time: t1);
      state = engine.update(
        fix: p2,
        recordedTrail: const <TrackPoint>[],
        nowUtc: t1,
      );
      expect(state, isA<GuidanceStraightLine>());
      expect((state as GuidanceStraightLine).progress, closeTo(0.5, 0.05));

      // Menjauh menjadi 120 m dari jalur: progress harus ter-clamp di 0.0 (bukan negatif)
      final t2 = t1.add(const Duration(seconds: 10));
      final p3 = _point(lat: -6.9050, lon: 108.3989, time: t2);
      state = engine.update(
        fix: p3,
        recordedTrail: const <TrackPoint>[],
        nowUtc: t2,
      );
      expect(state, isA<GuidanceStraightLine>());
      expect((state as GuidanceStraightLine).progress, equals(0.0));
    });

    test('beralih otomatis dari garis lurus ke ikuti-jejak bila jejak ber-anchor muncul',
        () {
      final t0 = DateTime.utc(2026, 11, 9, 10, 0, 0);

      // Langkah 1: Pengguna keluar jalur tanpa jejak -> GuidanceStraightLine
      final pUser = _point(lat: -6.9050, lon: 108.3991, time: t0); // 100 m off
      var state = engine.update(
        fix: pUser,
        recordedTrail: const <TrackPoint>[],
        nowUtc: t0,
      );
      expect(state, isA<GuidanceStraightLine>());

      // Langkah 2: Jejak rekaman yang memiliki anchor pada jalur utama tiba
      final pAnchor = _point(
        lat: -6.9050,
        lon: 108.4000, // Tepat di jalur (0 m off)
        time: t0.subtract(const Duration(minutes: 5)),
      );
      final pMid = _point(
        lat: -6.9050,
        lon: 108.3995, // 50 m off
        time: t0.subtract(const Duration(minutes: 2)),
      );

      final t1 = t0.add(const Duration(seconds: 5));
      state = engine.update(
        fix: pUser,
        recordedTrail: [pAnchor, pMid, pUser],
        nowUtc: t1,
      );

      // Harus beralih otomatis ke GuidanceFollowingTrail karena ada jejak yang bisa diikuti
      expect(state, isA<GuidanceFollowingTrail>());
      final following = state as GuidanceFollowingTrail;
      expect(following.guidePath.last.lon, closeTo(108.4000, 1e-4));
    });

    test('beralih otomatis dari garis lurus ke GuidanceReturned saat tiba kembali di rute',
        () {
      final t0 = DateTime.utc(2026, 11, 9, 10, 0, 0);

      // Pengguna keluar jalur 100 m tanpa jejak
      final pOff = _point(lat: -6.9050, lon: 108.3991, time: t0);
      var state = engine.update(
        fix: pOff,
        recordedTrail: const <TrackPoint>[],
        nowUtc: t0,
      );
      expect(state, isA<GuidanceStraightLine>());

      // Pengguna melangkah kembali ke dalam batas toleransi (15 m dari jalur <= 20 m)
      final t1 = t0.add(const Duration(seconds: 1));
      final pNear = _point(lat: -6.9050, lon: 108.39986, time: t1);
      state = engine.update(
        fix: pNear,
        recordedTrail: const <TrackPoint>[],
        nowUtc: t1,
      );
      // Dwell awal 0 dtk -> masih garis lurus
      expect(state, isA<GuidanceStraightLine>());

      // Setelah dwell 3,1 detik di dalam toleransi -> harus GuidanceReturned
      final t2 = t1.add(const Duration(milliseconds: 3100));
      state = engine.update(
        fix: pNear,
        recordedTrail: const <TrackPoint>[],
        nowUtc: t2,
      );
      expect(state, isA<GuidanceReturned>());

      // Fix berikutnya -> GuidanceOnRoute
      final t3 = t2.add(const Duration(seconds: 1));
      final pOn = _point(lat: -6.9050, lon: 108.4000, time: t3);
      state = engine.update(
        fix: pOn,
        recordedTrail: const <TrackPoint>[],
        nowUtc: t3,
      );
      expect(state, isA<GuidanceOnRoute>());
    });

    test('kasus khusus: akurasi GPS buruk diteruskan pada state GuidanceStraightLine',
        () {
      final t = DateTime.utc(2026, 11, 9, 10, 0, 0);
      final pLowAcc = _point(
        lat: -6.9050,
        lon: 108.3991,
        time: t,
        accuracyM: 45.0, // > 30 m
      );

      final state = engine.update(
        fix: pLowAcc,
        recordedTrail: const <TrackPoint>[],
        nowUtc: t,
      );

      expect(state, isA<GuidanceStraightLine>());
      final straight = state as GuidanceStraightLine;
      expect(straight.accuracyM, equals(45.0));
    });
  });
}
