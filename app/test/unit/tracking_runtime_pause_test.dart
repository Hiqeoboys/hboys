import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/features/tracking/application/recording_session.dart';
import 'package:nama_app/features/tracking/application/tracking_runtime.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/infrastructure/database/database_connection.dart';
import 'package:nama_app/infrastructure/database/repositories/drift_tracking_repository.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

final t0 = DateTime.utc(2027, 6, 1, 8);
const metersPerDegLat = 111195.0;

TrackPoint pointAt(int seconds) => TrackPoint(
      lat: -6.9 + (1.2 * seconds) / metersPerDegLat,
      lon: 107.6,
      timestampUtc: t0.add(Duration(seconds: seconds)),
      accuracyM: 5,
      altitudeM: 1000 + seconds * 0.2,
    );

class _FakeLocation implements TrackingLocationSource {
  final StreamController<TrackPoint> controller =
      StreamController<TrackPoint>.broadcast();
  int subscriptions = 0;

  @override
  Future<TrackingAccess> checkAccess() async => TrackingAccess.granted;

  @override
  Stream<TrackPoint> positions(PowerProfileConfig config) {
    subscriptions++;
    return controller.stream;
  }
}

class _FakeBattery implements BatteryReader {
  @override
  Future<int> levelPercent() async => 80;

  @override
  Future<bool> isCharging() async => false;
}

void main() {
  test('jeda menghentikan titik masuk dan lanjut melanjutkan sesi', () async {
    final db = openInMemoryAppDatabase();
    addTearDown(db.close);
    final repository = DriftTrackingRepository(db);
    final recording = await RecordingSession.startNew(
      repository: repository,
      clock: FakeClock(t0),
      id: 'sesi-jeda',
    );

    final location = _FakeLocation();
    addTearDown(location.controller.close);
    final updates = <TrackingRuntimeUpdate>[];
    final runtime = TrackingRuntime(
      recording: recording,
      location: location,
      battery: _FakeBattery(),
      onUpdate: updates.add,
      onError: (error) => fail(error.message),
    );
    await runtime.start();
    expect(runtime.isPaused, isFalse);
    expect(updates.last.isPaused, isFalse);

    location.controller.add(pointAt(0));
    location.controller.add(pointAt(5));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final pointsBeforePause = recording.pointCount;
    expect(pointsBeforePause, greaterThan(0));

    await runtime.pause();
    expect(runtime.isPaused, isTrue);
    expect(updates.last.isPaused, isTrue);
    location.controller.add(pointAt(10));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(recording.pointCount, pointsBeforePause);

    await runtime.resume();
    expect(runtime.isPaused, isFalse);
    expect(updates.last.isPaused, isFalse);
    location.controller.add(pointAt(60));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(recording.pointCount, greaterThan(pointsBeforePause));

    await runtime.stop();
    final saved = await repository.findSession('sesi-jeda');
    expect(saved!.status.name, 'completed');
  });
}
