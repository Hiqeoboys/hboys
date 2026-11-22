import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/trails/application/recovery_guidance_service.dart';
import 'package:nama_app/features/trails/domain/guidance_config.dart';
import 'package:nama_app/features/trails/domain/guidance_state.dart';
import 'package:nama_app/features/trails/domain/recovery_guidance_engine.dart';
import 'package:nama_app/features/trails/domain/track_route.dart';
import 'package:nama_app/infrastructure/location/shared_location_service.dart';

import '../support/location_fakes.dart';

void main() {
  group('Diagnosa & Verifikasi Perbaikan Pemandu Jalur (Recovery Guidance)', () {
    late TrackRoute route;

    setUp(() {
      const points = <TrackRoutePoint>[
        TrackRoutePoint(lat: -6.9100, lon: 108.4000, ele: 1500),
        TrackRoutePoint(lat: -6.9050, lon: 108.4000, ele: 1550),
        TrackRoutePoint(lat: -6.9000, lon: 108.4000, ele: 1600),
      ];
      route = TrackRoute.fromPoints(
        id: 'test-route',
        name: 'Jalur Ciremai Uji',
        points: points,
      );
    });

    test('1. Garis Waktu SEBELUM Perbaikan (Membuktikan Akar Masalah)', () {
      final logs = <String>[];
      void recordLog(String msg, DateTime t, [DateTime? base]) {
        final relMs = base != null ? t.difference(base).inMilliseconds : 0;
        logs.add('[+${relMs.toString().padLeft(4, ' ')} ms | ${t.toIso8601String()}] $msg');
      }

      final tButton = DateTime.utc(2026, 11, 14, 10, 0, 0, 0);
      recordLog('Tombol petunjuk jalur ditekan oleh pengguna', tButton, tButton);

      // Sebelum perbaikan: engine tanpa parameter isExplicitRequest (dwell selalu diuji)
      final engine = RecoveryGuidanceEngine(
        config: const GuidanceConfig(
          offRouteMinM: 40.0,
          offRouteDwell: Duration(seconds: 5),
          staleFixSeconds: 10,
        ),
      );
      engine.setRoute(route);

      // Titik saat ini: lon 108.40080 (~88 meter di luar jalur utama 108.4000)
      final tFix1 = tButton.subtract(const Duration(seconds: 2));
      final fix1 = TrackPoint(
        lat: -6.9050,
        lon: 108.40080,
        timestampUtc: tFix1,
        accuracyM: 8.0,
      );

      final trail = [
        TrackPoint(lat: -6.9050, lon: 108.4000, timestampUtc: tFix1.subtract(const Duration(seconds: 60)), accuracyM: 8.0),
        TrackPoint(lat: -6.9050, lon: 108.40040, timestampUtc: tFix1.subtract(const Duration(seconds: 30)), accuracyM: 8.0),
        fix1,
      ];

      final tSub = tButton.add(const Duration(milliseconds: 5));
      recordLog('Langganan stream petunjuk dibuat', tSub, tButton);

      // Fix pertama diterima mesin (t=40 ms)
      final tFirstProcess = tButton.add(const Duration(milliseconds: 40));
      final fixAge = tFirstProcess.difference(fix1.timestampUtc).inMilliseconds / 1000.0;
      recordLog('Fix pertama diterima mesin. Umur fix: ${fixAge.toStringAsFixed(2)} dtk', tFirstProcess, tButton);

      // Evaluasi fix pertama (sebelum perbaikan: isExplicitRequest false secara implisit)
      final state1 = engine.update(
        fix: fix1,
        recordedTrail: trail,
        nowUtc: tFirstProcess,
        isExplicitRequest: false,
      );
      recordLog('Emisi 1: ${state1.runtimeType} (isOffRoute: ${engine.isOffRoute}) -> UI menampilkan "Kamu masih di jalur"', tFirstProcess, tButton);

      // Fix kedua datang setelah 2,5 detik
      final tFix2 = tButton.add(const Duration(milliseconds: 2500));
      final fix2 = TrackPoint(
        lat: -6.9050,
        lon: 108.40082,
        timestampUtc: tFix2,
        accuracyM: 8.0,
      );
      final state2 = engine.update(
        fix: fix2,
        recordedTrail: [...trail, fix2],
        nowUtc: tFix2,
        isExplicitRequest: false,
      );
      recordLog('Emisi 2 (t=2.5s): ${state2.runtimeType} -> UI tetap "Kamu masih di jalur" karena dwell baru 2.46s < 5s', tFix2, tButton);

      // Fix ketiga datang setelah 5,2 detik
      final tFix3 = tButton.add(const Duration(milliseconds: 5200));
      final fix3 = TrackPoint(
        lat: -6.9050,
        lon: 108.40085,
        timestampUtc: tFix3,
        accuracyM: 8.0,
      );
      final state3 = engine.update(
        fix: fix3,
        recordedTrail: [...trail, fix2, fix3],
        nowUtc: tFix3,
        isExplicitRequest: false,
      );
      recordLog('Emisi 3 (t=5.2s): ${state3.runtimeType} -> UI baru berubah ke "Ikuti jejak" setelah dwell 5 detik selesai!', tFix3, tButton);

      expect(state1, isA<GuidanceOnRoute>());
      expect(state2, isA<GuidanceOnRoute>());
      expect(state3, isA<GuidanceFollowingTrail>());
    });

    test('2. Garis Waktu SESUDAH Perbaikan (Permintaan Eksplisit Langsung < 500 ms)', () async {
      final logs = <String>[];
      void recordLog(String msg, DateTime t, [DateTime? base]) {
        final relMs = base != null ? t.difference(base).inMilliseconds : 0;
        logs.add('[+${relMs.toString().padLeft(4, ' ')} ms | ${t.toIso8601String()}] $msg');
      }

      final tButton = DateTime.utc(2026, 11, 14, 10, 0, 0, 0);
      recordLog('Tombol petunjuk jalur ditekan oleh pengguna', tButton, tButton);

      final clock = FakeClock(tButton);
      final backend = FakeForegroundBackend();
      final feed = FakeRecordingFeed();
      final locService = SharedLocationService(
        backend: backend,
        recordingFeed: feed,
        clock: clock,
      );

      final tFix = tButton.subtract(const Duration(seconds: 2));
      final currentFix = TrackPoint(
        lat: -6.9050,
        lon: 108.40080, // ~88 m off-route
        timestampUtc: tFix,
        accuracyM: 8.0,
      );
      feed.update(recording: true, latest: currentFix);
      final lease = locService.acquire();
      await pumpEventQueue();

      final trail = [
        TrackPoint(lat: -6.9050, lon: 108.4000, timestampUtc: tFix.subtract(const Duration(seconds: 60)), accuracyM: 8.0),
        TrackPoint(lat: -6.9050, lon: 108.40040, timestampUtc: tFix.subtract(const Duration(seconds: 30)), accuracyM: 8.0),
        currentFix,
      ];

      final stopwatch = Stopwatch()..start();
      final service = RecoveryGuidanceService(
        locationService: locService,
        clock: clock,
      );

      // Mulai petunjuk dengan jejak memori awal
      service.start(route, initialTrail: trail);
      stopwatch.stop();

      final tEvaluated = tButton.add(stopwatch.elapsed);
      recordLog(
        'State instan saat panel dibuka: ${service.currentState.runtimeType} (waktu eksekusi: ${stopwatch.elapsedMicroseconds} µs)',
        tEvaluated,
        tButton,
      );

      // Verifikasi: langsung GuidanceFollowingTrail, tanpa jeda dwell, waktu < 500 ms
      expect(service.currentState, isA<GuidanceFollowingTrail>());
      expect(stopwatch.elapsedMilliseconds, lessThan(500));

      service.dispose();
      lease.release();
      locService.dispose();
    });

    test('3. Fix Basi (> 10 detik) menghasilkan GuidanceCheckingPosition lalu waitingGps setelah 3 dtk', () async {
      final t0 = DateTime.utc(2026, 11, 14, 10, 0, 0);
      final clock = FakeClock(t0);
      final backend = FakeForegroundBackend();
      final feed = FakeRecordingFeed();
      final locService = SharedLocationService(
        backend: backend,
        recordingFeed: feed,
        clock: clock,
      );

      // Fix terakhir 15 detik yang lalu (> 10 detik staleFixSeconds)
      final stalePoint = TrackPoint(
        lat: -6.9050,
        lon: 108.40080,
        timestampUtc: t0.subtract(const Duration(seconds: 15)),
        accuracyM: 8.0,
      );
      feed.update(recording: true, latest: stalePoint);
      final lease = locService.acquire();
      await pumpEventQueue();

      final service = RecoveryGuidanceService(
        locationService: locService,
        clock: clock,
        checkingTimeout: const Duration(milliseconds: 50),
      );

      service.start(route);

      // State awal saat belum ada fix segar: GuidanceCheckingPosition
      expect(service.currentState, isA<GuidanceCheckingPosition>());

      // Tunggu hingga timer habis
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(service.currentState, isA<GuidanceUnavailable>());
      final unavail = service.currentState as GuidanceUnavailable;
      expect(unavail.reason, GuidanceUnavailableReason.waitingGps);

      service.dispose();
      lease.release();
      locService.dispose();
    });

    test('4. Dwell tetap berlaku untuk transisi otomatis (streaming latar belakang)', () async {
      final t0 = DateTime.utc(2026, 11, 14, 10, 0, 0);
      final clock = FakeClock(t0);
      final backend = FakeForegroundBackend();
      final feed = FakeRecordingFeed();
      final locService = SharedLocationService(
        backend: backend,
        recordingFeed: feed,
        clock: clock,
      );

      // Titik awal tepat di jalur utama
      final onRouteFix = TrackPoint(
        lat: -6.9050,
        lon: 108.4000,
        timestampUtc: t0,
        accuracyM: 5.0,
      );
      feed.update(recording: true, latest: onRouteFix);
      final lease = locService.acquire();
      await pumpEventQueue();

      final service = RecoveryGuidanceService(
        locationService: locService,
        clock: clock,
      );

      service.start(route, initialTrail: [onRouteFix]);
      expect(service.currentState, isA<GuidanceOnRoute>());

      // Pengguna mulai bergeser keluar jalur secara bertahap (streaming background)
      final t1 = t0.add(const Duration(seconds: 2));
      clock.advance(const Duration(seconds: 2));
      final offRouteFix1 = TrackPoint(
        lat: -6.9050,
        lon: 108.40080, // ~88 m keluar jalur
        timestampUtc: t1,
        accuracyM: 5.0,
      );
      feed.update(latest: offRouteFix1);
      await pumpEventQueue();

      // Karena transisi streaming otomatis, dwell 5 detik masih berjalan (t=2 dtk < 5 dtk)
      expect(service.currentState, isA<GuidanceOnRoute>());

      // Maju lagi 5.5 detik dari t1 (> 5 dtk dwell dari kemunculan kandidat pertama)
      final t2 = t1.add(const Duration(milliseconds: 5500));
      clock.advance(const Duration(milliseconds: 5500));
      final offRouteFix2 = TrackPoint(
        lat: -6.9050,
        lon: 108.40082,
        timestampUtc: t2,
        accuracyM: 5.0,
      );
      feed.update(latest: offRouteFix2);
      await pumpEventQueue();

      // Sekarang dwell 5 dtk terpenuhi, otomatis bertransisi ke GuidanceFollowingTrail
      expect(service.currentState, isA<GuidanceFollowingTrail>());

      service.dispose();
      lease.release();
      locService.dispose();
    });

    test('5. Optimasi kinerja: evaluasi mesin UI thread <= 5 ms dengan jejak 1.000 titik', () {
      final t0 = DateTime.utc(2026, 11, 14, 10, 0, 0);
      final engine = RecoveryGuidanceEngine();
      engine.setRoute(route);

      // Buat jejak panjang 1.000 titik
      final longTrail = <TrackPoint>[];
      for (var i = 0; i < 900; i++) {
        longTrail.add(TrackPoint(
          lat: -6.9100 + (i * 0.00001),
          lon: 108.4000,
          timestampUtc: t0.add(Duration(seconds: i)),
          accuracyM: 5.0,
        ));
      }
      // 100 titik terakhir keluar jalur menuju lon 108.40090
      for (var i = 0; i < 100; i++) {
        longTrail.add(TrackPoint(
          lat: -6.9010,
          lon: 108.4000 + (i * 0.000009),
          timestampUtc: t0.add(Duration(seconds: 900 + i)),
          accuracyM: 5.0,
        ));
      }

      // Jalankan 30 iterasi update dengan timestamp fix selalu segar
      final durationsMs = <double>[];
      for (var iter = 0; iter < 30; iter++) {
        final now = t0.add(Duration(seconds: 1000 + iter));
        final currentFix = TrackPoint(
          lat: -6.9010,
          lon: 108.40089,
          timestampUtc: now.subtract(const Duration(seconds: 1)),
          accuracyM: 5.0,
        );
        final sw = Stopwatch()..start();
        final state = engine.update(
          fix: currentFix,
          recordedTrail: [...longTrail, currentFix],
          nowUtc: now,
          isExplicitRequest: iter == 0,
        );
        sw.stop();
        durationsMs.add(sw.elapsedMicroseconds / 1000.0);
        expect(state, isA<GuidanceFollowingTrail>());
      }

      final maxDuration = durationsMs.reduce((a, b) => a > b ? a : b);
      final avgDuration = durationsMs.reduce((a, b) => a + b) / durationsMs.length;

      // Maksimal harus <= 5.0 ms
      expect(maxDuration, lessThan(5.0), reason: 'Maksimal eksekusi harus < 5 ms, didapat ${maxDuration.toStringAsFixed(2)} ms');
      expect(avgDuration, lessThan(2.0), reason: 'Rata-rata eksekusi harus < 2 ms, didapat ${avgDuration.toStringAsFixed(2)} ms');
    });
  });
}
