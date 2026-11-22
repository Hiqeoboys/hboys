import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/plus/domain/cloud_backup_bundle.dart';
import 'package:nama_app/features/profile/domain/profile_summary.dart';
import 'package:nama_app/features/tracking/application/tracking_runtime.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';
import 'package:nama_app/infrastructure/database/database_connection.dart';
import 'package:nama_app/infrastructure/database/repositories/drift_tracking_repository.dart';
import 'package:nama_app/infrastructure/power/power_profile_controller.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

class _FakeBatteryReader implements BatteryReader {
  _FakeBatteryReader({this.level = 30, this.charging = false});

  int level;
  bool charging;

  @override
  Future<int> levelPercent() async => level;

  @override
  Future<bool> isCharging() async => charging;
}

class _FakeOsPowerSaveSource implements OsPowerSaveSource {
  bool active = false;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  void emit(bool value) {
    active = value;
    _changes.add(value);
  }

  @override
  Future<bool> isPowerSaveMode() async => active;

  @override
  Stream<bool> changes() => _changes.stream;

  Future<void> close() => _changes.close();
}

void main() {
  group('PowerProfileController OS power save mode', () {
    test('tidak menyalakan isOsPowerSaveMode saat baterai <40% tapi OS mati, dan langsung bereaksi saat broadcast berubah', () async {
      final battery = _FakeBatteryReader(level: 25, charging: false);
      final osSource = _FakeOsPowerSaveSource();
      addTearDown(osSource.close);
      final controller = PowerProfileController(
        reader: battery,
        osPowerSaveSource: osSource,
      );
      addTearDown(controller.dispose);

      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.refresh();
      expect(controller.profile, PowerProfile.saver);
      expect(controller.isOsPowerSaveMode, isFalse);

      osSource.emit(true);
      await Future<void>.delayed(Duration.zero);
      expect(controller.isOsPowerSaveMode, isTrue);

      osSource.emit(false);
      await Future<void>.delayed(Duration.zero);
      expect(controller.isOsPowerSaveMode, isFalse);
      expect(notifications, greaterThanOrEqualTo(3));
    });
  });

  group('Activity type (hiking vs jogging) persistence & stats separation', () {
    test('DriftTrackingRepository menyimpan dan membaca activity_type jogging', () async {
      final db = openInMemoryAppDatabase();
      final repo = DriftTrackingRepository(db);
      addTearDown(() async {
        repo.disposeDatabaseRegistration();
        await db.close();
      });

      final jogging = TrackingSession(
        id: 'jog-1',
        startedAtUtc: DateTime.utc(2026, 11, 20, 6, 0),
        endedAtUtc: DateTime.utc(2026, 11, 20, 6, 45),
        distanceM: 5200,
        movingSeconds: 2400,
        elevationGainM: 45,
        status: TrackingSessionStatus.completed,
        activityType: TrackingSession.activityJogging,
      );
      await repo.saveSession(jogging);

      final loaded = await repo.findSession('jog-1');
      expect(loaded, isNotNull);
      expect(loaded!.isJogging, isTrue);
      expect(loaded.activityType, TrackingSession.activityJogging);
      expect(loaded.reachedSummit, isFalse);
      expect(loaded.mountainName, isNull);
    });

    test('ProfileSummary memisahkan sesi jogging dari hitungan pendakian', () {
      final summary = ProfileSummary.fromSessions(<TrackingSession>[
        TrackingSession(
          id: 'hike-1',
          startedAtUtc: DateTime.utc(2026, 11, 1),
          distanceM: 10000,
          elevationGainM: 900,
          status: TrackingSessionStatus.completed,
          activityType: TrackingSession.activityHiking,
        ),
        TrackingSession(
          id: 'jog-1',
          startedAtUtc: DateTime.utc(2026, 11, 2),
          distanceM: 5000,
          elevationGainM: 30,
          status: TrackingSessionStatus.completed,
          activityType: TrackingSession.activityJogging,
        ),
      ]);

      expect(summary.hikeCount, 1);
      expect(summary.distanceM, 15000);
      expect(summary.elevationGainM, 930);
    });

    test('encodeSimplifiedRoutePolyline dan bundle menjaga ukuran ~3-8 KB serta melestarikan activity_type', () {
      final start = DateTime.utc(2026, 11, 20, 6, 0);
      final points = List<TrackPoint>.generate(600, (i) {
        final angle = i * 0.04;
        return TrackPoint(
          lat: -6.9 + math.sin(angle) * 0.008 + i * 0.00001,
          lon: 107.6 + math.cos(angle) * 0.008,
          altitudeM: 710 + math.sin(angle) * 15,
          accuracyM: 6,
          timestampUtc: start.add(Duration(seconds: i * 4)),
        );
      });
      final polyline = encodeSimplifiedRoutePolyline(points);
      expect(polyline, isNotNull);
      expect(polyline!.byteLength, lessThan(8192));
      expect(polyline.pointCount, lessThanOrEqualTo(250));

      final session = TrackingSession(
        id: 'jog-bundle',
        startedAtUtc: start,
        endedAtUtc: start.add(const Duration(minutes: 40)),
        distanceM: 6100,
        movingSeconds: 2200,
        elevationGainM: 65,
        status: TrackingSessionStatus.completed,
        activityType: TrackingSession.activityJogging,
      );
      final encoded = encodeSessionBundle(session, points);
      final decoded = decodeSessionBundle(encoded.gzipBase64);
      expect(decoded, isNotNull);
      expect(decoded!.activityType, TrackingSession.activityJogging);
      expect(decoded.session.isJogging, isTrue);
    });
  });
}
