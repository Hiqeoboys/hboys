import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/map/application/map_track_source.dart';
import 'package:nama_app/features/map/application/offline_map_service.dart';
import 'package:nama_app/features/map/domain/map_package.dart';
import 'package:nama_app/features/map/domain/mountain_pack_data.dart';
import 'package:nama_app/features/map/presentation/map_page.dart';
import 'package:nama_app/features/tracking/application/tracking_controller.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/real_font.dart';

class _FakeOfflineService implements OfflineMapService {
  @override
  Future<OfflineRegionStatus> regionStatus(MountainMapPackage package) async =>
      OfflineRegionStatus.missing;

  @override
  Future<OfflineEstimate> estimate(MountainMapPackage package) async =>
      const OfflineEstimate(
        transferBytes: 1024,
        storageBytes: 2048,
        errorMargin: 0.1,
      );

  @override
  Future<void> download(
    MountainMapPackage package, {
    required void Function(OfflineProgress progress) onProgress,
  }) async {}
}

class _StaticTrackSource implements MapTrackSource {
  @override
  Future<MapTrackSnapshot> load() async => const MapTrackSnapshot(
        points: <TrackPoint>[],
        latestPoint: null,
      );
}

Widget _buildGoldenMapHarness({
  required ThemeData theme,
  required MountainMapPackage package,
}) {
  return MaterialApp(
    theme: theme,
    debugShowCheckedModeBanner: false,
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(390, 844),
        padding: EdgeInsets.only(top: 44, bottom: 34),
        disableAnimations: true,
      ),
      child: Scaffold(
        body: MapPage(
          initialPackage: package,
          initialTrail: package.trails.first,
          catalogLoader: () async => MapPackageCatalog([package]),
          offlineService: _FakeOfflineService(),
          trackSource: _StaticTrackSource(),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TrackingController.instance.startOverride = null;
    TrackingController.instance.setRecordingForTesting(recording: false);
  });

  tearDown(() {
    TrackingController.instance.startOverride = null;
    TrackingController.instance.setRecordingForTesting(recording: false);
  });

  MountainMapPackage getCiremai() {
    final packs = MountainPackData.createDefaultPacks();
    return packs.firstWhere((p) => p.id == 'ciremai').package;
  }

  group('Golden Tests Peta Jalur (Trail Map)', () {
    for (final (themeName, theme) in [
      ('light', hiqeoLightTheme),
      ('dark', hiqeoDarkTheme),
    ]) {
      testWidgets('Golden trail map $themeName - state 1: initial', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await loadPlusJakartaSans(tester);

        final package = getCiremai();
        await tester.pumpWidget(_buildGoldenMapHarness(
          theme: theme,
          package: package,
        ));
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(MapPage),
          matchesGoldenFile('goldens/trail_map_${themeName}_initial.png'),
        );
      });

      testWidgets('Golden trail map $themeName - state 2: selection open',
          (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await loadPlusJakartaSans(tester);

        final package = getCiremai();
        await tester.pumpWidget(_buildGoldenMapHarness(
          theme: theme,
          package: package,
        ));
        await tester.pumpAndSettle();

        // Buka pilihan jalur
        await tester.tap(find.text('Via Apuy'));
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(MapPage),
          matchesGoldenFile('goldens/trail_map_${themeName}_selection_open.png'),
        );
      });

      testWidgets('Golden trail map $themeName - state 3: tracking active',
          (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await loadPlusJakartaSans(tester);

        final package = getCiremai();
        await tester.pumpWidget(_buildGoldenMapHarness(
          theme: theme,
          package: package,
        ));
        await tester.pumpAndSettle();

        // Aktifkan rekaman tracking
        TrackingController.instance.setRecordingForTesting(recording: true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        await expectLater(
          find.byType(MapPage),
          matchesGoldenFile('goldens/trail_map_${themeName}_tracking_active.png'),
        );
      });
    }
  });
}
