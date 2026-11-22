import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/background/page_background.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/features/map/application/map_track_source.dart';
import 'package:nama_app/features/map/application/offline_map_service.dart';
import 'package:nama_app/features/map/domain/map_package.dart';
import 'package:nama_app/features/map/presentation/map_page.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';

class _FakeOfflineService implements OfflineMapService {
  OfflineRegionStatus statusResult = OfflineRegionStatus.missing;
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

class _StaticTrackSource implements MapTrackSource {
  _StaticTrackSource(this.snapshots);

  final List<MapTrackSnapshot> snapshots;
  int calls = 0;

  @override
  Future<MapTrackSnapshot> load() async {
    final index = calls < snapshots.length ? calls : snapshots.length - 1;
    calls++;
    return snapshots[index];
  }
}

MountainMapPackage _package({
  String name = 'Gunung Uji',
  bool verified = false,
  DateTime? verifiedAtUtc,
  int maxTiles = 5000,
}) {
  return MountainMapPackage(
    id: 'gunung_uji',
    name: name,
    version: 2,
    dataDateUtc: DateTime.utc(2026, 10, 1),
    verified: verified,
    verifiedAtUtc: verifiedAtUtc,
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
        verifiedAtUtc: verifiedAtUtc,
        verifiedBy: verified ? 'Tim uji' : null,
        distanceM: 4400,
        elevationGainM: 1101,
        maxElevationM: 3078,
        points: const <LatLng>[LatLng(-7.5, 110.4), LatLng(-7.49, 110.41)],
      ),
    ],
  );
}

MapTrackSnapshot _snapshot(List<TrackPoint> points) => MapTrackSnapshot(
      points: points,
      latestPoint: points.isEmpty ? null : points.last,
    );

Widget _app(MapPage page, {ThemeData? theme}) =>
    MaterialApp(theme: theme ?? hiqeoLightTheme, home: page);

void _setPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _setPhoneWithInsets(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
  tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
}

void main() {
  test('peredup peta hanya aktif di mode gelap', () {
    expect(mapDimOpacityFor(Brightness.light), 0);
    expect(mapDimOpacityFor(Brightness.dark), 0.35);
  });

  testWidgets('mode gelap tanpa peta tidak menambah peredup di atas latar',
      (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_app(
      MapPage(
        catalogLoader: () async =>
            MapPackageCatalog(const <MountainMapPackage>[]),
        offlineService: _FakeOfflineService(),
        trackSource: _StaticTrackSource(<MapTrackSnapshot>[_snapshot(const [])]),
      ),
      theme: hiqeoDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('map-dark-dim')), findsNothing);
    expect(find.text('Peta belum tersedia'), findsOneWidget);
  });

  testWidgets('top bar menampilkan tombol kembali, judul gunung, dan status chip',
      (tester) async {
    _setPhone(tester);
    final package = _package(name: 'Gunung Ciremai');
    await tester.pumpWidget(_app(MapPage(
      initialPackage: package,
      catalogLoader: () async => MapPackageCatalog(<MountainMapPackage>[package]),
      offlineService: _FakeOfflineService(),
      trackSource: _StaticTrackSource(<MapTrackSnapshot>[_snapshot(const [])]),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Gunung Ciremai'), findsOneWidget);
    expect(find.byKey(const ValueKey('map-back-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('map-status-chip')), findsOneWidget);
  });

  testWidgets('panel bawah menampilkan statistik dan tombol mulai tracking',
      (tester) async {
    _setPhone(tester);
    final package = _package(name: 'Gunung Ciremai');
    await tester.pumpWidget(_app(MapPage(
      initialPackage: package,
      catalogLoader: () async => MapPackageCatalog(<MountainMapPackage>[package]),
      offlineService: _FakeOfflineService(),
      trackSource: _StaticTrackSource(<MapTrackSnapshot>[_snapshot(const [])]),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Jarak'), findsOneWidget);
    expect(find.text('Tanjakan'), findsOneWidget);
    expect(find.text('Elevasi maks'), findsOneWidget);
    expect(find.text('Mulai tracking'), findsOneWidget);
  });

  testWidgets('tombol kompas mereset arah peta ke utara', (tester) async {
    _setPhone(tester);
    var compassResetCalls = 0;
    await tester.pumpWidget(_app(MapPage(
      catalogLoader: () async => MapPackageCatalog(const <MountainMapPackage>[]),
      offlineService: _FakeOfflineService(),
      trackSource: _StaticTrackSource(<MapTrackSnapshot>[_snapshot(const [])]),
      onCompassReset: () => compassResetCalls++,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('map-compass-button')));
    await tester.pumpAndSettle();
    expect(compassResetCalls, 1);
  });

  test('panel dan atribusi peta dinaikkan di atas navbar mengambang', () {
    expect(HiqeoMetrics.floatingBottomInset(0), 76);
    expect(mapOrnamentBottomMargin(0), 84);
    expect(mapSheetBottomOffset(0), 120);

    expect(mapOrnamentBottomMargin(24), 108);
    expect(mapSheetBottomOffset(24), 144);
    expect(
      mapSheetBottomOffset(24),
      mapOrnamentBottomMargin(24) + mapAttributionInset - mapOrnamentGap,
    );
  });

  testWidgets('peta kosong memakai latar penuh tanpa pita',
      (tester) async {
    _setPhoneWithInsets(tester);
    await tester.pumpWidget(_app(MapPage(
      catalogLoader: () async => MapPackageCatalog(const <MountainMapPackage>[]),
      offlineService: _FakeOfflineService(),
      trackSource: _StaticTrackSource(<MapTrackSnapshot>[_snapshot(const [])]),
    )));
    await tester.pumpAndSettle();

    // Latar rata memakai warna token, bukan blob halaman.
    expect(find.byType(PageBackground), findsNothing);
    final root = tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(MapPage),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(root.color, HiqeoColors.light.background);

    final map = tester.getRect(find.byType(MapPage));
    expect(map.top, 0);
    expect(map.bottom, 844);
  });
}
