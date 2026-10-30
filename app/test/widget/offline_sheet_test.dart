import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/widgets/altracq_button.dart';
import 'package:nama_app/features/map/application/offline_download_controller.dart';
import 'package:nama_app/features/map/application/offline_map_service.dart';
import 'package:nama_app/features/map/domain/map_package.dart';
import 'package:nama_app/features/map/presentation/offline_sheet.dart';

class _FakeOfflineService implements OfflineMapService {
  _FakeOfflineService({this.statusResult = OfflineRegionStatus.missing});

  OfflineRegionStatus statusResult;
  int statusCalls = 0;
  int estimateCalls = 0;
  int downloadCalls = 0;

  @override
  Future<OfflineRegionStatus> regionStatus(MountainMapPackage package) async {
    statusCalls++;
    return statusResult;
  }

  @override
  Future<OfflineEstimate> estimate(MountainMapPackage package) async {
    estimateCalls++;
    return const OfflineEstimate(
      transferBytes: 1536,
      storageBytes: 3072,
      errorMargin: 0.2,
    );
  }

  @override
  Future<void> download(
    MountainMapPackage package, {
    required void Function(OfflineProgress progress) onProgress,
  }) async {
    downloadCalls++;
    onProgress(const OfflineProgress(
      phase: OfflinePhase.tiles,
      completedResources: 1,
      requiredResources: 1,
      completedBytes: 1536,
      erroredResources: 0,
    ));
  }
}

MountainMapPackage _package({
  String id = 'gunung_uji',
  String name = 'Gunung Uji',
  bool verified = false,
  int maxTiles = 5000,
}) {
  return MountainMapPackage(
    id: id,
    name: name,
    version: 2,
    dataDateUtc: DateTime.utc(2026, 10, 1),
    verified: verified,
    verifiedAtUtc: verified ? DateTime.utc(2026, 10, 1) : null,
    verifiedBy: verified ? 'Tim uji' : null,
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
    trails: <MapTrail>[
      MapTrail(
        id: 'utama',
        name: 'Jalur Utama',
        source: 'uji lapangan',
        verified: verified,
        points: const <LatLng>[LatLng(-7.5, 110.4), LatLng(-7.49, 110.41)],
      ),
    ],
  );
}

Future<OfflineDownloadController> _pump(
  WidgetTester tester, {
  MapPackageCatalog? catalog,
  bool loading = false,
  String? error,
  bool mapAvailable = true,
  OfflineMapService? service,
  VoidCallback? onRetry,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final resolvedService = service ?? _FakeOfflineService();
  final controller = OfflineDownloadController(service: resolvedService);
  addTearDown(controller.dispose);
  await tester.pumpWidget(MaterialApp(
    theme: altracqLightTheme,
    home: Scaffold(
      body: OfflineSheetBody(
        catalog: catalog,
        loading: loading,
        error: error,
        controller: controller,
        mapAvailable: mapAvailable,
        onSelect: controller.select,
        onRetry: onRetry ?? () {},
      ),
    ),
  ));
  if (loading) {
    // Spinner katalog beranimasi terus sehingga pumpAndSettle tidak selesai.
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
  return controller;
}

void main() {
  testWidgets('katalog kosong menampilkan keadaan jujur tanpa estimasi',
      (tester) async {
    final service = _FakeOfflineService();
    await _pump(
      tester,
      catalog: MapPackageCatalog(const <MountainMapPackage>[]),
      mapAvailable: false,
      service: service,
    );

    expect(find.text('Peta offline'), findsOneWidget);
    expect(find.text('Belum ada paket gunung'), findsOneWidget);
    expect(find.text('PAKET TERSEDIA'), findsNothing);
    expect(
      find.textContaining('tidak membundel data gunung fiktif'),
      findsOneWidget,
    );
    expect(find.text('Mapbox belum aktif'), findsOneWidget);
    expect(service.estimateCalls, 0);
    expect(service.statusCalls, 0);
  });

  testWidgets('memilih paket menampilkan status simpan dan estimasi SDK',
      (tester) async {
    final service = _FakeOfflineService();
    await _pump(
      tester,
      catalog: MapPackageCatalog(<MountainMapPackage>[
        _package(verified: true),
        _package(id: 'gunung_lain', name: 'Gunung Lain'),
      ]),
      service: service,
    );

    expect(find.text('PAKET TERSEDIA'), findsOneWidget);
    expect(find.text('Gunung Uji'), findsOneWidget);
    expect(find.text('Gunung Lain'), findsOneWidget);
    expect(find.text('Terverifikasi'), findsOneWidget);
    expect(find.text('Belum terverifikasi'), findsOneWidget);
    expect(find.textContaining('Versi 2 · data 1 Okt 2026'), findsNWidgets(2));

    await tester.tap(find.text('Gunung Uji'));
    await tester.pumpAndSettle();

    expect(service.statusCalls, 1);
    expect(service.estimateCalls, 1);
    expect(find.text('Belum diunduh di perangkat ini.'), findsOneWidget);
    expect(
      find.text(
        'Perkiraan SDK: transfer 1,5 KB, penyimpanan 3,0 KB (margin ±20%).',
      ),
      findsOneWidget,
    );
    expect(tester.widget<AltracqButton>(find.byType(AltracqButton)).onPressed,
        isNotNull);
  });

  testWidgets('unduhan selesai memakai label jujur dari SDK', (tester) async {
    final service = _FakeOfflineService();
    await _pump(
      tester,
      catalog: MapPackageCatalog(<MountainMapPackage>[_package()]),
      service: service,
    );

    await tester.tap(find.text('Gunung Uji'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unduh paket'));
    await tester.pumpAndSettle();

    expect(service.downloadCalls, 1);
    expect(find.text('Selesai diunduh'), findsOneWidget);
    expect(
      find.textContaining(
        'SDK melaporkan unduhan selesai pada sesi ini. Aplikasi belum '
        'memverifikasi ulang seluruh tile.',
      ),
      findsOneWidget,
    );
    expect(tester.widget<AltracqButton>(find.byType(AltracqButton)).onPressed,
        isNull);
  });

  testWidgets('region siap dari penyimpanan SDK menonaktifkan unduhan',
      (tester) async {
    final service = _FakeOfflineService(
      statusResult: const OfflineRegionStatus(
        completedResources: 10,
        requiredResources: 10,
        completedBytes: 2048,
        styleReady: true,
      ),
    );
    await _pump(
      tester,
      catalog: MapPackageCatalog(<MountainMapPackage>[_package()]),
      service: service,
    );

    await tester.tap(find.text('Gunung Uji'));
    await tester.pumpAndSettle();

    expect(
      find.text('Siap dipakai offline · 10/10 aset tersimpan.'),
      findsOneWidget,
    );
    expect(tester.widget<AltracqButton>(find.byType(AltracqButton)).onPressed,
        isNull);

    await tester.tap(find.text('Unduh paket'));
    await tester.pumpAndSettle();
    expect(service.downloadCalls, 0);
  });

  testWidgets('paket melewati batas tile menampilkan pelanggaran dan tombol mati',
      (tester) async {
    final service = _FakeOfflineService();
    await _pump(
      tester,
      catalog: MapPackageCatalog(<MountainMapPackage>[_package(maxTiles: 1)]),
      service: service,
    );

    await tester.tap(find.text('Gunung Uji'));
    await tester.pumpAndSettle();

    expect(find.textContaining('melebihi batas paket 1'), findsOneWidget);
    expect(service.estimateCalls, 0);
    expect(tester.widget<AltracqButton>(find.byType(AltracqButton)).onPressed,
        isNull);

    await tester.tap(find.text('Unduh paket'));
    await tester.pumpAndSettle();
    expect(service.downloadCalls, 0);
  });

  testWidgets('catatan kaki menyebut batas tile pack dan atribusi',
      (tester) async {
    await _pump(
      tester,
      catalog: MapPackageCatalog(<MountainMapPackage>[_package()]),
    );

    await tester.scrollUntilVisible(
      find.textContaining('750 tile pack'),
      160,
      scrollable: find.byType(Scrollable),
    );
    expect(
      find.textContaining(
        'Logo dan atribusi Mapbox/OpenStreetMap wajib tetap terlihat',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Data offline tidak diperbarui otomatis'),
      findsWidgets,
    );
  });

  testWidgets('katalog yang gagal dimuat bisa dicoba ulang', (tester) async {
    var retries = 0;
    await _pump(tester, loading: true);
    expect(find.text('Memuat katalog paket…'), findsOneWidget);

    await _pump(
      tester,
      error: 'Berkas katalog rusak.',
      onRetry: () => retries++,
    );
    expect(find.text('Katalog paket tidak terbaca'), findsOneWidget);
    expect(find.text('Berkas katalog rusak.'), findsOneWidget);

    await tester.tap(find.text('Muat ulang'));
    await tester.pumpAndSettle();
    expect(retries, 1);
  });
}
