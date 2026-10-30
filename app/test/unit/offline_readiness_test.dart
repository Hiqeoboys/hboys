import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:nama_app/features/map/application/offline_map_service.dart';
import 'package:nama_app/features/map/application/offline_readiness.dart';
import 'package:nama_app/features/map/domain/map_package.dart';

class _FakeService implements OfflineMapService {
  _FakeService(this.status);

  final OfflineRegionStatus status;
  int statusCalls = 0;

  @override
  Future<OfflineRegionStatus> regionStatus(MountainMapPackage package) async {
    statusCalls++;
    return status;
  }

  @override
  Future<OfflineEstimate> estimate(MountainMapPackage package) async =>
      throw StateError('estimasi tidak diharapkan');

  @override
  Future<void> download(
    MountainMapPackage package, {
    required void Function(OfflineProgress progress) onProgress,
  }) async =>
      throw StateError('unduhan tidak diharapkan');
}

MountainMapPackage _package(String name) => MountainMapPackage(
      id: 'gunung_uji',
      name: name,
      version: 1,
      dataDateUtc: DateTime.utc(2026, 10, 1),
      verified: false,
      offline: const OfflineConfig(
        bounds: GeoBounds(
          south: -7.55,
          west: 110.35,
          north: -7.45,
          east: 110.45,
        ),
        minZoom: 10,
        maxZoom: 14,
        maxAreaKm2: 250,
        maxTiles: 5000,
      ),
      trails: <MapTrail>[
        MapTrail(
          id: 'utama',
          name: 'Jalur Utama',
          source: 'uji',
          verified: false,
          points: const <LatLng>[LatLng(-7.5, 110.4), LatLng(-7.49, 110.41)],
        ),
      ],
    );

void main() {
  final ready = const OfflineRegionStatus(
    completedResources: 10,
    requiredResources: 10,
    completedBytes: 1000,
    styleReady: true,
  );

  test('siap hanya bila nama cocok dan region SDK lengkap', () async {
    final service = _FakeService(ready);
    final result = await defaultOfflineMapReady(
      'gunung uji',
      catalog: MapPackageCatalog(<MountainMapPackage>[_package('Gunung Uji')]),
      offlineService: service,
    );
    expect(result, isTrue);
    expect(service.statusCalls, 1);
  });

  test('nama tanpa paket cocok tidak diklaim siap', () async {
    final service = _FakeService(ready);
    final result = await defaultOfflineMapReady(
      'Gunung Lain',
      catalog: MapPackageCatalog(<MountainMapPackage>[_package('Gunung Uji')]),
      offlineService: service,
    );
    expect(result, isFalse);
    expect(service.statusCalls, 0);
  });

  test('nama kosong atau null tidak diklaim siap', () async {
    final service = _FakeService(ready);
    final catalog = MapPackageCatalog(<MountainMapPackage>[_package('Gunung Uji')]);
    expect(
      await defaultOfflineMapReady('  ',
          catalog: catalog, offlineService: service),
      isFalse,
    );
    expect(
      await defaultOfflineMapReady(null,
          catalog: catalog, offlineService: service),
      isFalse,
    );
    expect(service.statusCalls, 0);
  });

  test('region belum lengkap atau style belum siap dianggap belum siap', () async {
    const partial = OfflineRegionStatus(
      completedResources: 4,
      requiredResources: 10,
      completedBytes: 400,
      styleReady: true,
    );
    expect(
      await defaultOfflineMapReady(
        'Gunung Uji',
        catalog: MapPackageCatalog(<MountainMapPackage>[_package('Gunung Uji')]),
        offlineService: _FakeService(partial),
      ),
      isFalse,
    );
    const noStyle = OfflineRegionStatus(
      completedResources: 10,
      requiredResources: 10,
      completedBytes: 1000,
      styleReady: false,
    );
    expect(
      await defaultOfflineMapReady(
        'Gunung Uji',
        catalog: MapPackageCatalog(<MountainMapPackage>[_package('Gunung Uji')]),
        offlineService: _FakeService(noStyle),
      ),
      isFalse,
    );
  });
}
