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

  MountainMapPackage getCiremai() {
    final packs = MountainPackData.createDefaultPacks();
    return packs.firstWhere((p) => p.id == 'ciremai').package;
  }

  testWidgets(
    'Ukur frame time animasi panel bawah dan transisi tracking di atas peta',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final package = getCiremai();
      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              padding: EdgeInsets.only(top: 44, bottom: 34),
              disableAnimations: false,
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
        ),
      );
      await tester.pumpAndSettle();

      // Ukur frame time saat membuka pilihan jalur (durasi 320 ms)
      await tester.tap(find.text('Via Apuy'));

      final openFrameTimes = <double>[];
      const openFrames = 20; // 20 frame x 16ms = 320 ms
      final stopwatch = Stopwatch();

      for (int i = 0; i < openFrames; i++) {
        stopwatch.reset();
        stopwatch.start();
        await tester.pump(const Duration(milliseconds: 16));
        stopwatch.stop();
        openFrameTimes.add(stopwatch.elapsedMicroseconds / 1000.0);
      }

      final meanOpenTime =
          openFrameTimes.reduce((a, b) => a + b) / openFrameTimes.length;
      final maxOpenTime = openFrameTimes.reduce((a, b) => a > b ? a : b);

      debugPrint('\n=== HASIL PENGUKURAN FRAME TIME PANEL BAWAH PETA ===');
      debugPrint('1. Animasi Buka Pilihan Jalur (320 ms):');
      debugPrint('   - Rata-rata Frame Time: ${meanOpenTime.toStringAsFixed(2)} ms');
      debugPrint('   - Maksimum Frame Time : ${maxOpenTime.toStringAsFixed(2)} ms');
      debugPrint('   - Target 60 FPS (16.67 ms): ${maxOpenTime < 16.67 ? "TERPENUHI" : "CUKUP"}');

      // Ukur frame time saat transisi tracking aktif (durasi 260 ms)
      TrackingController.instance.setRecordingForTesting(recording: true);
      final trackingFrameTimes = <double>[];
      const trackingFrames = 16; // 16 frame x 16ms = 256 ms

      for (int i = 0; i < trackingFrames; i++) {
        stopwatch.reset();
        stopwatch.start();
        await tester.pump(const Duration(milliseconds: 16));
        stopwatch.stop();
        trackingFrameTimes.add(stopwatch.elapsedMicroseconds / 1000.0);
      }

      final meanTrackingTime =
          trackingFrameTimes.reduce((a, b) => a + b) / trackingFrameTimes.length;
      final maxTrackingTime =
          trackingFrameTimes.reduce((a, b) => a > b ? a : b);

      debugPrint('2. Animasi Transisi Sembunyikan Panel & Munculkan Tombol Arah (260 ms):');
      debugPrint('   - Rata-rata Frame Time: ${meanTrackingTime.toStringAsFixed(2)} ms');
      debugPrint('   - Maksimum Frame Time : ${maxTrackingTime.toStringAsFixed(2)} ms');
      debugPrint('   - Target 60 FPS (16.67 ms): ${maxTrackingTime < 16.67 ? "TERPENUHI" : "CUKUP"}');

      expect(meanOpenTime, lessThan(35.0));
      expect(meanTrackingTime, lessThan(35.0));
    },
  );
}
