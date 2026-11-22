import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/features/kartu/domain/kartu_data.dart';
import 'package:nama_app/features/tracking/application/recording_session.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_engine.dart';
import 'package:nama_app/features/tracking/presentation/tracking_view_data.dart';
import 'package:nama_app/infrastructure/database/database_connection.dart';
import 'package:nama_app/infrastructure/database/repositories/drift_tracking_repository.dart';
import 'package:nama_app/infrastructure/location/pedometer_step_counter.dart';
import 'package:shared_preferences/shared_preferences.dart';

final DateTime _t0 = DateTime.utc(2026, 11, 21, 7, 0);
const double _metersPerDegLat = 111195.0;

TrackPoint _point({
  required double metersNorth,
  required int sec,
  double accuracyM = 6,
  double? altitudeM,
  double? altitudeAccuracyM,
  double speedMps = 1.2,
}) =>
    TrackPoint(
      lat: -6.9 + metersNorth / _metersPerDegLat,
      lon: 107.6,
      timestampUtc: _t0.add(Duration(seconds: sec)),
      accuracyM: accuracyM,
      speedMps: speedMps,
      altitudeM: altitudeM,
      altitudeAccuracyM: altitudeAccuracyM,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('PedometerStepCounter (TYPE_STEP_COUNTER baseline & pause)', () {
    test('menyimpan initialStepBaseline saat mulai lalu menghitung selisih langkah',
        () async {
      final controller = StreamController<int>();
      addTearDown(controller.close);
      final counter = PedometerStepCounter(
        stepStreamOverride: controller.stream,
        persistBaseline: false,
        calibrationWindow: Duration.zero,
      );
      addTearDown(counter.dispose);

      counter.syncSession(
        sessionId: 'sesi-step-1',
        activityPermissionGranted: true,
      );

      // Android TYPE_STEP_COUNTER selalu mengirim total kumulatif sejak HP menyala.
      controller.add(45000);
      await Future<void>.delayed(Duration.zero);
      expect(counter.initialStepBaseline, 45000);
      expect(counter.sensorSteps, 0);

      controller.add(45185);
      await Future<void>.delayed(Duration.zero);
      expect(counter.sensorSteps, 185);
    });

    test('mengurangi langkah yang terjadi saat sesi dijeda (paused) setelah dilanjutkan',
        () async {
      final controller = StreamController<int>();
      addTearDown(controller.close);
      final counter = PedometerStepCounter(
        stepStreamOverride: controller.stream,
        persistBaseline: false,
        calibrationWindow: Duration.zero,
      );
      addTearDown(counter.dispose);

      counter.syncSession(
        sessionId: 'sesi-step-pause',
        activityPermissionGranted: true,
        isPaused: false,
      );

      controller.add(10000);
      await Future<void>.delayed(Duration.zero);
      controller.add(10250);
      await Future<void>.delayed(Duration.zero);
      expect(counter.sensorSteps, 250);

      // Pengguna menjeda rekaman lalu berjalan 120 langkah saat dijeda.
      counter.syncSession(
        sessionId: 'sesi-step-pause',
        activityPermissionGranted: true,
        isPaused: true,
      );
      controller.add(10370);
      await Future<void>.delayed(Duration.zero);
      expect(counter.sensorSteps, 250);

      // Rekaman dilanjutkan dan pengguna melangkah 80 langkah lagi.
      counter.syncSession(
        sessionId: 'sesi-step-pause',
        activityPermissionGranted: true,
        isPaused: false,
      );
      expect(counter.pausedStepsOffset, 120);
      controller.add(10450);
      await Future<void>.delayed(Duration.zero);
      expect(counter.sensorSteps, 330);
    });

    test('menangani reset penghitung sensor dan fallback jarak saat sensor tidak tersedia',
        () async {
      final controller = StreamController<int>();
      addTearDown(controller.close);
      final counter = PedometerStepCounter(
        stepStreamOverride: controller.stream,
        persistBaseline: false,
        calibrationWindow: Duration.zero,
      );
      addTearDown(counter.dispose);

      counter.syncSession(
        sessionId: 'sesi-reset',
        activityPermissionGranted: true,
      );
      controller.add(50000);
      await Future<void>.delayed(Duration.zero);
      controller.add(50100);
      await Future<void>.delayed(Duration.zero);
      expect(counter.sensorSteps, 100);

      // Misal perangkat restart dan counter kembali dari 15.
      controller.add(15);
      await Future<void>.delayed(Duration.zero);
      expect(counter.sensorSteps, 100);

      controller.add(45);
      await Future<void>.delayed(Duration.zero);
      expect(counter.sensorSteps, 130);

      counter.markSensorUnavailable();
      expect(counter.state, StepSourceState.sensorUnavailable);
      expect(counter.sensorSteps, isNull);
      expect(estimateStepsFromDistance(distanceM: 705.5, heightCm: 170), 1000);
    });
  });

  group('Elevation Gain & Ascent Consistency', () {
    test('menolak noise horizontal > 25 m & vertikal > 25 m dan menjaga tanjakan datar = 0 m',
        () {
      final engine = TrackingEngine();
      TrackingSnapshot? last;

      // Fix awal akurat pada ketinggian 800 m.
      last = engine.onFix(_point(
        metersNorth: 0,
        sec: 0,
        accuracyM: 6,
        altitudeM: 800,
        altitudeAccuracyM: 5,
      ));

      // Fix ber-akurasi buruk 45 m (> 25 m) ditolak langsung di filter GPS -> gainM tetap 0.
      final rejectedBadH = engine.onFix(_point(
        metersNorth: 8,
        sec: 4,
        accuracyM: 45,
        altitudeM: 860,
        altitudeAccuracyM: 8,
      ));
      expect(rejectedBadH, isNull);
      expect(engine.latestSnapshot!.gainM, 0);

      // Fix dengan altitudeAccuracy 32 m (> 25 m) dan ketinggian ngaco +80 m -> altitud ditolak!
      last = engine.onFix(_point(
        metersNorth: 18,
        sec: 10,
        accuracyM: 8,
        altitudeM: 880,
        altitudeAccuracyM: 32,
      )) ??
          last;
      expect(last!.gainM, 0);

      // Jalan datar 300 m dengan noise GPS altitud +/- 9 m berkala (median + moving avg + histeresis 8 m -> 0 m tanjakan palsu).
      for (var s = 22; s <= 320; s += 4) {
        final noisyAlt = 800.0 + math.sin(s * 0.9) * 9.0;
        last = engine.onFix(_point(
              metersNorth: s * 1.1,
              sec: s,
              accuracyM: 8,
              altitudeM: noisyAlt,
              altitudeAccuracyM: 12,
            )) ??
            last;
      }
      expect(last!.gainM, 0);
    });

    test('nilai tanjakan pada layar tracking, database sesi, dan KartuData selalu identik',
        () async {
      final db = openInMemoryAppDatabase();
      final repo = DriftTrackingRepository(db);
      addTearDown(() async {
        repo.disposeDatabaseRegistration();
        await db.close();
      });

      final recording = await RecordingSession.startNew(
        repository: repo,
        clock: FakeClock(_t0),
        id: 'sesi-konsisten',
      );

      for (var s = 0; s <= 240; s += 4) {
        await recording.onFix(_point(
          metersNorth: s * 1.2,
          sec: s,
          accuracyM: 5,
          altitudeM: 1000.0 + s * 0.15, // +36 m konsisten
          altitudeAccuracyM: 4,
        ));
      }

      final liveGain = recording.snapshot!.gainM;
      expect(liveGain, greaterThan(28.0));

      final completed = await recording.finish();
      final points = await repo.points(completed.id);
      final kartu = KartuData.fromSession(completed, points);

      expect(completed.elevationGainM, liveGain);
      expect(kartu, isNotNull);
      expect(kartu!.elevationGainM, liveGain);
      expect(
        formatElevationValue(completed.elevationGainM),
        formatElevationValue(liveGain),
      );
      expect(
        formatElevationValue(kartu.elevationGainM),
        formatElevationValue(liveGain),
      );
    });
  });
}
