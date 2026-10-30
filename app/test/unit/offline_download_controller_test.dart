import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:nama_app/features/map/application/offline_download_controller.dart';
import 'package:nama_app/features/map/application/offline_map_service.dart';
import 'package:nama_app/features/map/domain/map_package.dart';

class FakeOfflineService implements OfflineMapService {
  int estimateCalls = 0;
  int downloadCalls = 0;
  int statusCalls = 0;
  bool failFirstEstimate = false;
  bool failDownload = false;
  bool failStatus = false;
  OfflineRegionStatus statusResult = OfflineRegionStatus.missing;
  Completer<OfflineEstimate>? gate;

  @override
  Future<OfflineRegionStatus> regionStatus(MountainMapPackage package) async {
    statusCalls++;
    if (failStatus) throw StateError('penyimpanan uji gagal');
    return statusResult;
  }

  @override
  Future<OfflineEstimate> estimate(MountainMapPackage package) async {
    estimateCalls++;
    final currentGate = gate;
    if (currentGate != null) return currentGate.future;
    if (failFirstEstimate && estimateCalls == 1) {
      throw StateError('jaringan uji gagal');
    }
    return const OfflineEstimate(
      transferBytes: 1000,
      storageBytes: 2000,
      errorMargin: 0.2,
    );
  }

  @override
  Future<void> download(
    MountainMapPackage package, {
    required void Function(OfflineProgress progress) onProgress,
  }) async {
    downloadCalls++;
    if (failDownload) throw StateError('disk uji penuh');
    onProgress(const OfflineProgress(
      phase: OfflinePhase.tiles,
      completedResources: 1,
      requiredResources: 2,
      completedBytes: 100,
      erroredResources: 0,
    ));
    onProgress(const OfflineProgress(
      phase: OfflinePhase.tiles,
      completedResources: 2,
      requiredResources: 2,
      completedBytes: 200,
      erroredResources: 0,
    ));
  }
}

MountainMapPackage testPackage(String id, {int maxTiles = 5000}) {
  return MountainMapPackage(
    id: id,
    name: 'Gunung $id',
    version: 1,
    dataDateUtc: DateTime.utc(2026, 10, 1),
    verified: false,
    offline: OfflineConfig(
      bounds: const GeoBounds(
        south: -7.55,
        west: 110.35,
        north: -7.45,
        east: 110.45,
      ),
      minZoom: 10,
      maxZoom: 14,
      maxAreaKm2: 250,
      maxTiles: maxTiles,
    ),
    trails: [
      MapTrail(
        id: 'utama',
        name: 'Jalur Utama',
        source: 'uji',
        verified: false,
        points: const [LatLng(-7.5, 110.4), LatLng(-7.49, 110.41)],
      ),
    ],
  );
}

void main() {
  late FakeOfflineService service;
  late OfflineDownloadController controller;
  var disposedInTest = false;

  setUp(() {
    service = FakeOfflineService();
    controller = OfflineDownloadController(service: service);
    disposedInTest = false;
  });

  tearDown(() {
    if (!disposedInTest) controller.dispose();
  });

  test('memilih paket langsung memperkirakan unduhan', () async {
    controller.select(testPackage('gunung_a'));
    expect(controller.phase, OfflineDownloadPhase.estimating);
    expect(service.estimateCalls, 1);

    await pumpEventQueue();
    expect(controller.phase, OfflineDownloadPhase.estimated);
    expect(controller.estimate!.storageBytes, 2000);
    expect(controller.plan!.canDownload, isTrue);
    expect(controller.plan!.tileCount, greaterThan(0));
    expect(controller.canDownload, isTrue);
  });

  test('unduhan mengirim progres dan selesai', () async {
    controller.select(testPackage('gunung_a'));
    await pumpEventQueue();

    await controller.download();
    expect(service.downloadCalls, 1);
    expect(controller.phase, OfflineDownloadPhase.downloaded);
    expect(controller.progress!.completedResources, 2);
    expect(controller.progress!.fraction, 1);
    expect(controller.canDownload, isFalse);
  });

  test('unduhan mencoba estimasi ulang setelah estimasi gagal', () async {
    service.failFirstEstimate = true;
    controller.select(testPackage('gunung_a'));
    await pumpEventQueue();
    expect(controller.phase, OfflineDownloadPhase.error);
    expect(controller.estimate, isNull);

    await controller.download();
    expect(service.estimateCalls, 2);
    expect(service.downloadCalls, 1);
    expect(controller.phase, OfflineDownloadPhase.downloaded);
  });

  test('kegagalan unduhan dilaporkan', () async {
    service.failDownload = true;
    controller.select(testPackage('gunung_a'));
    await pumpEventQueue();

    await controller.download();
    expect(controller.phase, OfflineDownloadPhase.error);
    expect(controller.error, contains('Unduhan gagal'));
  });

  test('paket yang melanggar batas tidak diunduh', () async {
    controller.select(testPackage('gunung_a', maxTiles: 1));
    await pumpEventQueue();

    expect(controller.plan!.canDownload, isFalse);
    expect(controller.phase, OfflineDownloadPhase.idle);
    expect(service.estimateCalls, 0);
    expect(controller.canDownload, isFalse);

    await controller.download();
    expect(service.downloadCalls, 0);
  });

  test('hasil estimasi paket lama diabaikan setelah ganti paket', () async {
    final gateA = Completer<OfflineEstimate>();
    service.gate = gateA;
    controller.select(testPackage('gunung_a'));

    final gateB = Completer<OfflineEstimate>();
    service.gate = gateB;
    controller.select(testPackage('gunung_b'));

    const estimateB = OfflineEstimate(
      transferBytes: 20,
      storageBytes: 40,
      errorMargin: 0.1,
    );
    gateB.complete(estimateB);
    await pumpEventQueue();
    expect(controller.package!.id, 'gunung_b');
    expect(controller.estimate, same(estimateB));
    expect(controller.phase, OfflineDownloadPhase.estimated);

    gateA.complete(const OfflineEstimate(
      transferBytes: 10,
      storageBytes: 20,
      errorMargin: 0.1,
    ));
    await pumpEventQueue();
    expect(controller.package!.id, 'gunung_b');
    expect(controller.estimate, same(estimateB));
  });

  test('hasil estimasi yang datang setelah dispose diabaikan', () async {
    final gate = Completer<OfflineEstimate>();
    service.gate = gate;
    controller.select(testPackage('gunung_a'));
    controller.dispose();
    disposedInTest = true;

    gate.complete(const OfflineEstimate(
      transferBytes: 10,
      storageBytes: 20,
      errorMargin: 0.1,
    ));
    await pumpEventQueue();
    expect(service.estimateCalls, 1);
  });

  test('status siap dibaca dari penyimpanan SDK', () async {
    service.statusResult = const OfflineRegionStatus(
      completedResources: 40,
      requiredResources: 40,
      completedBytes: 9000,
      styleReady: true,
    );
    controller.select(testPackage('gunung_a'));
    await pumpEventQueue();

    expect(service.statusCalls, 1);
    expect(controller.isReady, isTrue);
    expect(controller.canDownload, isFalse);
  });

  test('region belum lengkap bukan status siap', () async {
    service.statusResult = const OfflineRegionStatus(
      completedResources: 10,
      requiredResources: 40,
      completedBytes: 2000,
      styleReady: true,
    );
    controller.select(testPackage('gunung_a'));
    await pumpEventQueue();

    expect(controller.isReady, isFalse);
    expect(controller.canDownload, isTrue);
  });

  test('status gagal dibaca dianggap belum siap', () async {
    service.failStatus = true;
    controller.select(testPackage('gunung_a'));
    await pumpEventQueue();

    expect(controller.status, isNull);
    expect(controller.isReady, isFalse);
    expect(controller.canDownload, isTrue);
  });
}
