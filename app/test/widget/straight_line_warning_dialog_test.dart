import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/map/application/map_track_source.dart';
import 'package:nama_app/features/map/domain/map_package.dart';
import 'package:nama_app/features/map/presentation/map_page.dart';
import 'package:nama_app/features/safety/presentation/sos_page.dart';
import 'package:nama_app/features/tracking/application/tracking_controller.dart';
import 'package:nama_app/features/tracking/application/tracking_runtime.dart'
    show TrackingAccess;
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/trails/application/recovery_guidance_service.dart';
import 'package:nama_app/features/trails/domain/guidance_config.dart';
import 'package:nama_app/features/trails/domain/recovery_guidance_engine.dart';
import 'package:nama_app/features/trails/domain/straight_line_guidance_texts.dart';
import 'package:nama_app/features/trails/domain/track_route.dart';
import 'package:nama_app/infrastructure/location/shared_location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/location_fakes.dart';

class _EmptyTrackSource implements MapTrackSource {
  @override
  Future<MapTrackSnapshot> load() async =>
      const MapTrackSnapshot(points: <TrackPoint>[], latestPoint: null);
}

final DateTime _now = DateTime.utc(2026, 11, 9, 8);

TrackRoute _route() => TrackRoute.fromPoints(
      id: 'uji',
      name: 'Jalur uji',
      points: const <TrackRoutePoint>[
        TrackRoutePoint(lat: -7.5000, lon: 110.4000),
        TrackRoutePoint(lat: -7.5100, lon: 110.4000),
      ],
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TrackingController.instance.startOverride = null;
    TrackingController.instance.setRecordingForTesting(recording: false);
  });

  tearDown(() {
    TrackingController.instance.startOverride = null;
    TrackingController.instance.setRecordingForTesting(recording: false);
  });

  testWidgets(
      'mode garis lurus langsung membuka panel dengan Peringatan penting terlipat, '
      'dapat diperluas dan diminimalkan, serta tombol SOS membuka SosPage', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final backend = FakeForegroundBackend(access: TrackingAccess.whileInUse);
    final feed = FakeRecordingFeed();
    final locationService = SharedLocationService(
      backend: backend,
      recordingFeed: feed,
      clock: FakeClock(_now),
    );
    addTearDown(locationService.dispose);

    // Titik awal 100 m di luar jalur (lat: -7.5050, lon: 110.3991)
    final offRouteFix = TrackPoint(
      lat: -7.5050,
      lon: 110.3991,
      accuracyM: 5.0,
      timestampUtc: _now,
    );

    final engine = RecoveryGuidanceEngine(
      config: const GuidanceConfig(
        offRouteMinM: 40.0,
        offRouteDwell: Duration.zero,
      ),
    );

    final guidanceService = RecoveryGuidanceService(
      locationService: locationService,
      trailPointsProvider: () async => const <TrackPoint>[],
      engine: engine,
      clock: FakeClock(_now),
    );
    addTearDown(guidanceService.dispose);

    TrackingController.instance.setRecordingForTesting(recording: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: MapPage(
          catalogLoader: () async =>
              MapPackageCatalog(const <MountainMapPackage>[]),
          gpxRouteLoader: () async => _route(),
          trackSource: _EmptyTrackSource(),
          locationService: locationService,
          guidanceService: guidanceService,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    backend.emit(offRouteFix);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    await tester.tap(find.byKey(const ValueKey('map-directions-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    // Pertama kali masuk mode garis lurus dalam satu sesi:
    // tanpa dialog modal pemblokir; peringatan penting terbuka otomatis di
    // tempat dengan tombol "Mengerti".
    expect(find.byKey(const ValueKey('straight-line-warning-dialog')), findsNothing);
    expect(find.text(StraightLineGuidanceTexts.modeLabel), findsOneWidget);
    expect(find.byKey(const ValueKey('straight-line-warning-card')), findsOneWidget);
    expect(find.text(StraightLineGuidanceTexts.warningCardText), findsOneWidget);
    expect(find.byKey(const ValueKey('straight-line-warning-ack')), findsOneWidget);
    expect(find.text('Mengerti'), findsOneWidget);

    // Ketuk "Mengerti" -> peringatan terlipat kembali menjadi "Baca".
    await tester.tap(find.byKey(const ValueKey('straight-line-warning-ack')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Baca'), findsOneWidget);
    expect(find.text(StraightLineGuidanceTexts.warningCardText), findsNothing);

    // Perluas kotak Peringatan penting secara manual.
    await tester.tap(find.byKey(const ValueKey('straight-line-warning-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Tutup'), findsOneWidget);
    expect(find.text(StraightLineGuidanceTexts.warningCardText), findsOneWidget);

    // Tombol SOS membuka SosPage.
    final sosButton = find.byKey(const ValueKey('straight-line-panel-sos-button'));
    expect(sosButton, findsOneWidget);
    await tester.tap(sosButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.byType(SosPage), findsOneWidget);
  });

  testWidgets('tombol Tutup di panel menutup panel garis lurus dan menghentikan layanan',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final backend = FakeForegroundBackend(access: TrackingAccess.whileInUse);
    final feed = FakeRecordingFeed();
    final locationService = SharedLocationService(
      backend: backend,
      recordingFeed: feed,
      clock: FakeClock(_now),
    );
    addTearDown(locationService.dispose);

    final engine = RecoveryGuidanceEngine(
      config: const GuidanceConfig(
        offRouteMinM: 40.0,
        offRouteDwell: Duration.zero,
      ),
    );

    final guidanceService = RecoveryGuidanceService(
      locationService: locationService,
      trailPointsProvider: () async => const <TrackPoint>[],
      engine: engine,
      clock: FakeClock(_now),
    );
    addTearDown(guidanceService.dispose);

    TrackingController.instance.setRecordingForTesting(recording: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: MapPage(
          catalogLoader: () async =>
              MapPackageCatalog(const <MountainMapPackage>[]),
          gpxRouteLoader: () async => _route(),
          trackSource: _EmptyTrackSource(),
          locationService: locationService,
          guidanceService: guidanceService,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    backend.emit(TrackPoint(
      lat: -7.5050,
      lon: 110.3991,
      accuracyM: 5.0,
      timestampUtc: _now,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    await tester.tap(find.byKey(const ValueKey('map-directions-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.byKey(const ValueKey('map-directions-panel')), findsOneWidget);
    expect(guidanceService.isRunning, isTrue);

    await tester.tap(find.byKey(const ValueKey('map-directions-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    expect(find.byKey(const ValueKey('map-directions-panel')), findsNothing);
    expect(guidanceService.isRunning, isFalse);
  });

  testWidgets('kasus khusus: jarak > 1000 m dan akurasi > 30 m menampilkan peringatan ekstra saat diperluas',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final backend = FakeForegroundBackend(access: TrackingAccess.whileInUse);
    final feed = FakeRecordingFeed();
    final locationService = SharedLocationService(
      backend: backend,
      recordingFeed: feed,
      clock: FakeClock(_now),
    );
    addTearDown(locationService.dispose);

    final engine = RecoveryGuidanceEngine(
      config: const GuidanceConfig(
        offRouteMinM: 40.0,
        offRouteDwell: Duration.zero,
      ),
    );

    final guidanceService = RecoveryGuidanceService(
      locationService: locationService,
      trailPointsProvider: () async => const <TrackPoint>[],
      engine: engine,
      clock: FakeClock(_now),
    );
    addTearDown(guidanceService.dispose);

    TrackingController.instance.setRecordingForTesting(recording: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: MapPage(
          catalogLoader: () async =>
              MapPackageCatalog(const <MountainMapPackage>[]),
          gpxRouteLoader: () async => _route(),
          trackSource: _EmptyTrackSource(),
          locationService: locationService,
          guidanceService: guidanceService,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    // Jarak ~1.500 m di barat rute (lon 110.3860), akurasi 40 m
    backend.emit(TrackPoint(
      lat: -7.5050,
      lon: 110.3860,
      accuracyM: 40.0,
      timestampUtc: _now,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    await tester.tap(find.byKey(const ValueKey('map-directions-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    // Peringatan jarak > 1.000 m dan akurasi > 30 m langsung tampil sebagai
    // teks satu baris di bawah jarak tanpa memperbesar panel secara drastis.
    expect(find.text(StraightLineGuidanceTexts.farFromRouteWarning), findsOneWidget);
    expect(find.text(StraightLineGuidanceTexts.lowAccuracyWarning), findsOneWidget);
  });
}
