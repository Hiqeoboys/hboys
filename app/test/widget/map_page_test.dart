import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/compass/domain/compass_calibration.dart';
import 'package:nama_app/features/map/application/map_track_source.dart';
import 'package:nama_app/features/map/application/offline_map_service.dart';
import 'package:nama_app/features/map/domain/map_package.dart';
import 'package:nama_app/features/map/presentation/map_page.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';

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

/// Sumber yang diam sampai diaktifkan, lalu melaporkan satu titik baru setiap
/// pembacaan. Dipakai untuk menguji histeresis detektor tanpa bergantung pada
/// waktu pemilihan paket.
class _ArmedTrackSource implements MapTrackSource {
  _ArmedTrackSource(this.points);

  final List<TrackPoint> points;
  bool armed = false;
  int _index = 0;

  @override
  Future<MapTrackSnapshot> load() async {
    if (!armed) {
      return const MapTrackSnapshot(
        points: <TrackPoint>[],
        latestPoint: null,
      );
    }
    final index = _index < points.length ? _index : points.length - 1;
    final point = points[index];
    if (_index < points.length - 1) _index++;
    return MapTrackSnapshot(points: <TrackPoint>[point], latestPoint: point);
  }
}

class _FakeCompassStore implements CompassOffsetStore {
  double offset = 0;
  int writes = 0;

  @override
  Future<double> readOffsetDegrees() async => offset;

  @override
  Future<void> writeOffsetDegrees(double offsetDegrees) async {
    offset = offsetDegrees;
    writes++;
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
        points: const <LatLng>[LatLng(-7.5, 110.4), LatLng(-7.49, 110.41)],
      ),
    ],
  );
}

TrackPoint _point({
  double lat = -7.5,
  double lon = 110.4,
  int second = 0,
}) {
  return TrackPoint(
    lat: lat,
    lon: lon,
    timestampUtc: DateTime.utc(2026, 10, 25, 3, 0, second),
    accuracyM: 5,
  );
}

MapTrackSnapshot _snapshot(List<TrackPoint> points) => MapTrackSnapshot(
      points: points,
      latestPoint: points.isEmpty ? null : points.last,
    );

Widget _app(MapPage page, {ThemeData? theme}) =>
    MaterialApp(theme: theme ?? altracqLightTheme, home: page);

void _setPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _openOfflineSheet(WidgetTester tester) async {
  await tester.tap(find.text('Kelola peta offline'));
  await tester.pumpAndSettle();
}

Future<void> _dismissSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(195, 20));
  await tester.pumpAndSettle();
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
      theme: altracqDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('map-dark-dim')), findsNothing);
    expect(find.text('Peta belum tersedia'), findsOneWidget);
  });

  testWidgets('tanpa Mapbox menampilkan setup dan katalog kosong jujur',
      (tester) async {
    _setPhone(tester);
    final service = _FakeOfflineService();
    await tester.pumpWidget(_app(MapPage(
      catalogLoader: () async => MapPackageCatalog(const <MountainMapPackage>[]),
      offlineService: service,
      trackSource: _StaticTrackSource(<MapTrackSnapshot>[_snapshot(const [])]),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Belum ada data jalur'), findsOneWidget);
    expect(
      find.text('Katalog paket kosong · tidak ada data jalur dibundel'),
      findsOneWidget,
    );
    expect(find.text('Peta belum tersedia'), findsOneWidget);
    expect(find.text('Peta offline'), findsOneWidget);
    expect(find.text('Peta offline belum siap'), findsOneWidget);
    expect(find.text('GPS belum aktif'), findsOneWidget);

    await _openOfflineSheet(tester);
    expect(find.text('Belum ada paket gunung'), findsOneWidget);
    expect(find.text('PAKET TERSEDIA'), findsNothing);
    expect(service.estimateCalls, 0);
  });

  testWidgets('memilih paket menampilkan jalur, panduan, dan status offline',
      (tester) async {
    _setPhone(tester);
    final service = _FakeOfflineService();
    final package = _package();
    await tester.pumpWidget(_app(MapPage(
      catalogLoader: () async => MapPackageCatalog(<MountainMapPackage>[package]),
      offlineService: service,
      trackSource: _StaticTrackSource(<MapTrackSnapshot>[
        _snapshot(<TrackPoint>[_point()]),
      ]),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Belum ada jalur dipilih'), findsOneWidget);

    await _openOfflineSheet(tester);
    expect(find.text('PAKET TERSEDIA'), findsOneWidget);
    expect(find.text('Gunung Uji'), findsOneWidget);
    expect(find.textContaining('±'), findsWidgets);

    await tester.tap(find.text('Gunung Uji'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Belum diunduh'), findsOneWidget);
    expect(find.textContaining('Perkiraan SDK'), findsOneWidget);

    await _dismissSheet(tester);

    expect(find.text('Jalur belum terverifikasi'), findsOneWidget);
    expect(find.text('Jalur Utama'), findsOneWidget);
    expect(find.byKey(const ValueKey('map-guidance')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('map-guidance'))).data,
      '0 m · bearing 0°',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('map-trail-state')),
        matching: find.text('Dijalur'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('map-offline-state')),
        matching: find.text('Peta offline belum siap'),
      ),
      findsOneWidget,
    );
    expect(find.text('Kelola peta offline'), findsOneWidget);
  });

  testWidgets('paket terverifikasi menampilkan tanggal verifikasi nyata',
      (tester) async {
    _setPhone(tester);
    final verifiedAt = DateTime.utc(2026, 10, 1);
    final package = _package(
      verified: true,
      verifiedAtUtc: verifiedAt,
    );
    await tester.pumpWidget(_app(MapPage(
      catalogLoader: () async => MapPackageCatalog(<MountainMapPackage>[package]),
      offlineService: _FakeOfflineService(),
      trackSource: _StaticTrackSource(<MapTrackSnapshot>[_snapshot(const [])]),
    )));
    await tester.pumpAndSettle();
    await _openOfflineSheet(tester);
    await tester.tap(find.text('Gunung Uji'));
    await tester.pumpAndSettle();
    await _dismissSheet(tester);

    expect(find.text('Jalur terverifikasi'), findsOneWidget);
    expect(
      find.text('Diverifikasi 1 Okt 2026 · kondisi jalur dapat berubah'),
      findsOneWidget,
    );
  });

  testWidgets('status region SDK siap mengubah pill peta offline',
      (tester) async {
    _setPhone(tester);
    final service = _FakeOfflineService(
      statusResult: const OfflineRegionStatus(
        completedResources: 10,
        requiredResources: 10,
        completedBytes: 2048,
        styleReady: true,
      ),
    );
    await tester.pumpWidget(_app(MapPage(
      catalogLoader: () async =>
          MapPackageCatalog(<MountainMapPackage>[_package()]),
      offlineService: service,
      trackSource: _StaticTrackSource(<MapTrackSnapshot>[
        _snapshot(<TrackPoint>[_point()]),
      ]),
    )));
    await tester.pumpAndSettle();
    await _openOfflineSheet(tester);
    await tester.tap(find.text('Gunung Uji'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Siap dipakai offline'), findsOneWidget);
    await _dismissSheet(tester);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('map-offline-state')),
        matching: find.text('Peta offline'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('tiga titik jauh menampilkan peringatan di luar jalur',
      (tester) async {
    _setPhone(tester);
    final source = _ArmedTrackSource(<TrackPoint>[
      _point(lat: -7.48, second: 1),
      _point(lat: -7.48, second: 2),
      _point(lat: -7.48, second: 3),
    ]);
    await tester.pumpWidget(_app(MapPage(
      catalogLoader: () async =>
          MapPackageCatalog(<MountainMapPackage>[_package()]),
      offlineService: _FakeOfflineService(),
      trackSource: source,
      trackPollInterval: const Duration(milliseconds: 40),
    )));
    await tester.pumpAndSettle();
    await _openOfflineSheet(tester);
    await tester.tap(find.text('Gunung Uji'));
    await tester.pumpAndSettle();
    await _dismissSheet(tester);

    // Detektor butuh tiga titik di luar ambang; setiap pump baru menjalankan
    // satu pembacaan karena sumber jejak dipanggil bergiliran.
    source.armed = true;
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
    }

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('map-trail-state')),
        matching: find.text('Di luar jalur'),
      ),
      findsOneWidget,
    );
    expect(find.text('Kelola peta offline'), findsOneWidget);
  });

  testWidgets('tanpa titik GPS menampilkan status menunggu', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_app(MapPage(
      catalogLoader: () async =>
          MapPackageCatalog(<MountainMapPackage>[_package()]),
      offlineService: _FakeOfflineService(),
      trackSource: _StaticTrackSource(<MapTrackSnapshot>[_snapshot(const [])]),
    )));
    await tester.pumpAndSettle();
    await _openOfflineSheet(tester);
    await tester.tap(find.text('Gunung Uji'));
    await tester.pumpAndSettle();
    await _dismissSheet(tester);

    expect(find.text('Menunggu GPS'), findsOneWidget);
  });

  testWidgets('tombol kompas membuka sheet kompas', (tester) async {
    _setPhone(tester);
    final events = StreamController<CompassEvent>.broadcast();
    addTearDown(events.close);
    final store = _FakeCompassStore();
    await tester.pumpWidget(_app(MapPage(
      catalogLoader: () async => MapPackageCatalog(const <MountainMapPackage>[]),
      offlineService: _FakeOfflineService(),
      trackSource: _StaticTrackSource(<MapTrackSnapshot>[_snapshot(const [])]),
      compassEvents: events.stream,
      compassOffsetStore: store,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Buka kompas'));
    await tester.pumpAndSettle();
    expect(find.text('Koreksi arah manual'), findsOneWidget);

    events.add(CompassEvent.fromList(<double>[350, 0, 10]));
    await tester.pumpAndSettle();
    expect(find.text('350° U'), findsOneWidget);
    expect(find.textContaining('±10° (tinggi)'), findsOneWidget);
  });
}
