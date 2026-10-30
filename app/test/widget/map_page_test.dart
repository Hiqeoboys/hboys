import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:nama_app/features/map/application/map_track_source.dart';
import 'package:nama_app/features/map/application/offline_map_service.dart';
import 'package:nama_app/features/map/domain/map_package.dart';
import 'package:nama_app/features/map/presentation/map_page.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';

class _CountingOfflineService implements OfflineMapService {
  int estimateCalls = 0;
  int downloadCalls = 0;

  @override
  Future<OfflineEstimate> estimate(MountainMapPackage package) async {
    estimateCalls++;
    throw StateError('estimasi tidak diharapkan tanpa Mapbox aktif');
  }

  @override
  Future<void> download(
    MountainMapPackage package, {
    required void Function(OfflineProgress progress) onProgress,
  }) async {
    downloadCalls++;
    throw StateError('unduhan tidak diharapkan tanpa Mapbox aktif');
  }
}

class _FakeTrackSource implements MapTrackSource {
  _FakeTrackSource(this.snapshot);

  final MapTrackSnapshot snapshot;

  @override
  Future<MapTrackSnapshot> load() async => snapshot;
}

MountainMapPackage _package() {
  return MountainMapPackage(
    id: 'gunung_uji',
    name: 'Gunung Uji',
    version: 2,
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
    trails: [
      MapTrail(
        id: 'utama',
        name: 'Jalur Utama',
        source: 'uji',
        verified: false,
        points: const [
          LatLng(-7.5, 110.4),
          LatLng(-7.49, 110.41),
        ],
      ),
    ],
  );
}

TrackPoint _latestPoint() {
  return TrackPoint(
    lat: -7.5,
    lon: 110.4,
    timestampUtc: DateTime.utc(2026, 10, 25, 3),
    accuracyM: 5,
  );
}

void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _disposePage(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  testWidgets('tanpa token menampilkan setup dan tidak memanggil Mapbox',
      (tester) async {
    _useTallSurface(tester);
    final service = _CountingOfflineService();

    await tester.pumpWidget(MaterialApp(
      home: MapPage(
        mapboxToken: '',
        catalogLoader: () async => MapPackageCatalog(const []),
        offlineService: service,
        trackSource: _FakeTrackSource(
          const MapTrackSnapshot(points: [], latestPoint: null),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Peta belum dikonfigurasi'), findsOneWidget);
    expect(find.text('Belum ada paket gunung'), findsOneWidget);
    expect(
      find.textContaining('Unduhan offline memerlukan Mapbox yang aktif.'),
      findsOneWidget,
    );
    expect(
      find.text('Pilih paket dan jalur untuk mengaktifkan deteksi.'),
      findsOneWidget,
    );
    expect(service.estimateCalls, 0);
    expect(service.downloadCalls, 0);

    await _disposePage(tester);
  });

  testWidgets('memilih paket menampilkan jalur dan deteksi memakai titik GPS',
      (tester) async {
    _useTallSurface(tester);
    final service = _CountingOfflineService();
    final package = _package();

    await tester.pumpWidget(MaterialApp(
      home: MapPage(
        mapboxToken: '',
        catalogLoader: () async => MapPackageCatalog([package]),
        offlineService: service,
        trackSource: _FakeTrackSource(
          MapTrackSnapshot(
            points: [_latestPoint()],
            latestPoint: _latestPoint(),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gunung Uji').last);
    await tester.pumpAndSettle();

    expect(find.text('Data belum terverifikasi'), findsOneWidget);
    expect(find.text('Jalur Utama'), findsWidgets);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('off-trail-status'))).data,
      'Di jalur',
    );
    expect(
      find.textContaining('Perkiraan tile'),
      findsNothing,
      reason: 'Panel offline tidak boleh aktif tanpa Mapbox.',
    );
    expect(service.estimateCalls, 0);

    await _disposePage(tester);
  });
}
