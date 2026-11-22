import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/features/tracking/application/tracking_runtime.dart'
    show TrackingAccess;
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/infrastructure/location/shared_location_service.dart';

import '../support/location_fakes.dart';

final DateTime t0 = DateTime.utc(2026, 11, 9, 8);

TrackPoint point(DateTime at, {double lat = -7.5}) => TrackPoint(
      lat: lat,
      lon: 110.4,
      timestampUtc: at,
      accuracyM: 5,
    );

void main() {
  late FakeForegroundBackend backend;
  late FakeRecordingFeed feed;
  late FakeClock clock;
  late SharedLocationService service;

  setUp(() {
    backend = FakeForegroundBackend();
    feed = FakeRecordingFeed();
    clock = FakeClock(t0);
    service = SharedLocationService(
      backend: backend,
      recordingFeed: feed,
      clock: clock,
    );
  });

  tearDown(() => service.dispose());

  test('aliran GPS hidup selama ada lease dan berhenti saat lease terakhir lepas',
      () async {
    expect(service.hasOwnStream, isFalse);

    final first = service.acquire();
    final second = service.acquire();
    await pumpEventQueue();

    expect(service.leaseCount, 2);
    expect(backend.streamsOpened, 1, reason: 'dua lease berbagi satu aliran');
    expect(backend.activeStreams, 1);
    expect(service.state.status, LiveLocationStatus.searching);

    first.release();
    first.release(); // idempoten
    await pumpEventQueue();
    expect(service.leaseCount, 1);
    expect(backend.activeStreams, 1);

    second.release();
    await pumpEventQueue();
    expect(service.leaseCount, 0);
    expect(backend.activeStreams, 0);
    expect(service.state.status, LiveLocationStatus.idle);
  });

  test('fix dari aliran menjadi posisi aktif dan kedaluwarsa setelah maxFixAge',
      () async {
    final lease = service.acquire();
    await pumpEventQueue();

    backend.emit(point(t0));
    await pumpEventQueue();
    expect(service.state.status, LiveLocationStatus.active);
    expect(service.state.source, LiveLocationSource.ownStream);
    expect(service.freshPoint, isNotNull);

    clock.advance(const Duration(minutes: 3));
    expect(service.freshPoint, isNull);
    lease.release();
  });

  test('titik yang lebih lama tidak menimpa titik yang lebih baru', () async {
    final lease = service.acquire();
    await pumpEventQueue();
    backend.emit(point(t0.add(const Duration(seconds: 10)), lat: -7.4));
    backend.emit(point(t0, lat: -7.9));
    await pumpEventQueue();
    expect(service.state.point!.lat, -7.4);
    lease.release();
  });

  test('selama merekam tidak membuka aliran kedua dan memakai titik rekaman',
      () async {
    feed.recording = true;
    feed.latest = point(t0);

    final lease = service.acquire();
    await pumpEventQueue();

    expect(backend.streamsOpened, 0, reason: 'rekaman memegang satu-satunya GPS');
    expect(service.followsRecording, isTrue);
    expect(service.state.source, LiveLocationSource.recordingSession);
    expect(service.state.point, isNotNull);

    final newer = point(t0.add(const Duration(seconds: 5)), lat: -7.45);
    feed.update(latest: newer);
    await pumpEventQueue();
    expect(service.state.point!.lat, -7.45);

    lease.release();
    await pumpEventQueue();
    expect(service.followsRecording, isFalse);
    expect(backend.streamsOpened, 0);
  });

  test('rekaman mulai mematikan aliran sendiri; rekaman selesai menyalakannya lagi',
      () async {
    final lease = service.acquire();
    await pumpEventQueue();
    expect(backend.activeStreams, 1);

    feed.update(recording: true, latest: point(t0));
    await pumpEventQueue();
    expect(backend.activeStreams, 0);
    expect(service.followsRecording, isTrue);

    feed.update(recording: false);
    await pumpEventQueue();
    expect(service.followsRecording, isFalse);
    expect(backend.activeStreams, 1);
    expect(backend.streamsOpened, 2);
    lease.release();
  });

  test('layanan lokasi mati atau izin ditolak tidak membuka aliran', () async {
    backend.access = TrackingAccess.serviceDisabled;
    final lease = service.acquire();
    await pumpEventQueue();
    expect(service.state.status, LiveLocationStatus.serviceDisabled);
    expect(backend.streamsOpened, 0);

    backend.access = TrackingAccess.denied;
    await service.refresh();
    expect(service.state.status, LiveLocationStatus.permissionDenied);

    backend.access = TrackingAccess.deniedForever;
    await service.refresh();
    expect(service.state.status, LiveLocationStatus.permissionDeniedForever);
    expect(backend.streamsOpened, 0);

    // Pengguna menyalakan lokasi dan memberi izin: aliran terbuka.
    backend.access = TrackingAccess.whileInUse;
    await service.refresh();
    expect(service.state.status, LiveLocationStatus.searching);
    expect(backend.activeStreams, 1);
    lease.release();
  });

  test('requestPermission menyelaraskan status setelah dialog izin', () async {
    backend.access = TrackingAccess.denied;
    backend.accessAfterRequest = TrackingAccess.whileInUse;
    final lease = service.acquire();
    await pumpEventQueue();
    expect(service.state.status, LiveLocationStatus.permissionDenied);

    await service.requestPermission();
    expect(backend.requestCalls, 1);
    expect(service.state.status, LiveLocationStatus.searching);
    expect(backend.activeStreams, 1);
    lease.release();
  });

  test('kesalahan aliran tidak menjatuhkan layanan dan bisa dipulihkan',
      () async {
    final lease = service.acquire();
    await pumpEventQueue();
    backend.controllers.last.addError(StateError('GPS putus'));
    await pumpEventQueue();
    expect(service.state.status, LiveLocationStatus.error);
    expect(backend.activeStreams, 0);

    await service.refresh();
    expect(backend.activeStreams, 1);
    lease.release();
  });
}
