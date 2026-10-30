import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/features/tracking/application/recording_session.dart';
import 'package:nama_app/features/tracking/application/session_recovery.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';
import 'package:nama_app/infrastructure/database/database_connection.dart';
import 'package:nama_app/infrastructure/database/repositories/drift_tracking_repository.dart';

final t0 = DateTime.utc(2027, 6, 1, 8);
const metersPerDegLat = 111195.0;

TrackPoint pointAt(int seconds, {double accuracy = 5}) => TrackPoint(
      lat: -6.9 + (1.2 * seconds) / metersPerDegLat,
      lon: 107.6,
      timestampUtc: t0.add(Duration(seconds: seconds)),
      accuracyM: accuracy,
      altitudeM: 1000 + seconds * 0.2,
    );

void main() {
  late DriftTrackingRepository repository;
  late FakeClock clock;

  setUp(() {
    final db = openInMemoryAppDatabase();
    addTearDown(db.close);
    repository = DriftTrackingRepository(db);
    clock = FakeClock(t0);
  });

  test('memulihkan sesi aktif dan melanjutkan metrik dari titik tersimpan',
      () async {
    final recording = await RecordingSession.startNew(
      repository: repository,
      clock: clock,
      id: 'sesi-1',
      trailId: 'jalur-a',
    );
    for (var s = 0; s <= 60; s += 5) {
      await recording.onFix(pointAt(s));
    }
    final beforeKill = recording.snapshot!;
    expect(recording.pointCount, 13);
    expect(beforeKill.distanceM, closeTo(72, 2));

    // Proses "mati": objek lama dibuang, lalu layanan baru memulihkan dari DB.
    final recovered = await SessionRecovery(repository).recoverActive();
    expect(recovered, isNotNull);
    expect(recovered!.session.id, 'sesi-1');
    expect(recovered.session.trailId, 'jalur-a');
    expect(recovered.points, hasLength(13));
    expect(recovered.lastSnapshot!.distanceM,
        closeTo(beforeKill.distanceM, 0.001));
    expect(
      recovered.lastSnapshot!.movingTime.inSeconds,
      beforeKill.movingTime.inSeconds,
    );

    final resumed = await RecordingSession.resume(
      repository: repository,
      clock: clock,
      recovered: recovered,
    );
    final next = await resumed.onFix(pointAt(65));
    expect(next, isNotNull);
    expect(next!.distanceM, greaterThan(beforeKill.distanceM));
    expect(await repository.points('sesi-1'), hasLength(14));
  });

  test('menyimpan setiap titik yang diterima dan menolak titik buruk',
      () async {
    final recording = await RecordingSession.startNew(
      repository: repository,
      clock: clock,
      id: 'sesi-2',
    );
    await recording.onFix(pointAt(0));
    final rejected = await recording.onFix(pointAt(5, accuracy: 90));
    expect(rejected, isNull);

    final stored = await repository.findSession('sesi-2');
    expect(stored!.distanceM, 0);
    expect(await repository.points('sesi-2'), hasLength(1));
  });

  test('sesi selesai tidak dipulihkan lagi', () async {
    final recording = await RecordingSession.startNew(
      repository: repository,
      clock: clock,
      id: 'sesi-3',
    );
    await recording.onFix(pointAt(0));
    clock.advance(const Duration(minutes: 5));
    final finished = await recording.finish();

    expect(finished.status, TrackingSessionStatus.completed);
    expect(finished.endedAtUtc, t0.add(const Duration(minutes: 5)));
    expect(await SessionRecovery(repository).recoverActive(), isNull);
    expect((await repository.findSession('sesi-3'))!.status,
        TrackingSessionStatus.completed);
  });

  test('memulihkan sesi aktif yang belum punya titik', () async {
    await repository.saveSession(
      TrackingSession(id: 'sesi-4', startedAtUtc: t0, groupId: 'g1'),
    );

    final recovered = await SessionRecovery(repository).recoverActive();
    expect(recovered, isNotNull);
    expect(recovered!.points, isEmpty);
    expect(recovered.lastSnapshot, isNull);

    final resumed = await RecordingSession.resume(
      repository: repository,
      clock: clock,
      recovered: recovered,
    );
    final first = await resumed.onFix(pointAt(0));
    expect(first!.distanceM, 0);
    expect(await repository.points('sesi-4'), hasLength(1));
  });

  test('memilih sesi aktif terbaru jika ada lebih dari satu', () async {
    await repository.saveSession(
      TrackingSession(id: 'lama', startedAtUtc: t0),
    );
    await repository.saveSession(
      TrackingSession(
        id: 'baru',
        startedAtUtc: t0.add(const Duration(minutes: 1)),
      ),
    );
    await repository.saveSession(
      TrackingSession(
        id: 'selesai',
        startedAtUtc: t0.add(const Duration(minutes: 2)),
        status: TrackingSessionStatus.completed,
      ),
    );

    final recovered = await SessionRecovery(repository).recoverActive();
    expect(recovered!.session.id, 'baru');
  });

  test('titik yang tersimpan diputar ulang tanpa ditolak filter', () async {
    final recording = await RecordingSession.startNew(
      repository: repository,
      clock: clock,
      id: 'sesi-5',
    );
    for (var s = 0; s <= 30; s += 5) {
      await recording.onFix(pointAt(s));
    }
    final before = recording.snapshot!;

    final recovered = await SessionRecovery(repository).recoverActive();
    expect(
        recovered!.lastSnapshot!.distanceM, closeTo(before.distanceM, 0.001));
    expect(
      recovered.lastSnapshot!.gainM,
      closeTo(before.gainM, 0.001),
    );
  });
}
