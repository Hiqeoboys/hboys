import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:nama_app/features/map/application/offline_download_controller.dart';
import 'package:nama_app/features/map/application/offline_map_service.dart';
import 'package:nama_app/features/map/domain/map_package.dart';
import 'package:nama_app/features/map/presentation/offline_package_panel.dart';

class _FakeService implements OfflineMapService {
  int downloadCalls = 0;

  @override
  Future<OfflineEstimate> estimate(MountainMapPackage package) async {
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

MountainMapPackage _package({int maxTiles = 5000}) {
  return MountainMapPackage(
    id: 'gunung_uji',
    name: 'Gunung Uji',
    version: 3,
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
        points: const [
          LatLng(-7.5, 110.4),
          LatLng(-7.49, 110.41),
        ],
      ),
    ],
  );
}

Widget _app(OfflineDownloadController controller) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: OfflinePackagePanel(controller: controller),
      ),
    ),
  );
}

void main() {
  testWidgets('menampilkan estimasi tile dan byte lalu menyelesaikan unduhan',
      (tester) async {
    final service = _FakeService();
    final controller = OfflineDownloadController(service: service);
    final package = _package();

    controller.select(package);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    final plan = OfflinePlan.evaluate(package.offline);
    expect(find.text('Perkiraan tile'), findsOneWidget);
    expect(
      find.textContaining('${plan.tileCount} / batas paket'),
      findsOneWidget,
    );
    expect(find.textContaining('transfer 1.5 KB'), findsOneWidget);
    expect(find.textContaining('bukan jumlah aset unduhan'), findsOneWidget);
    expect(find.text('Unduh paket'), findsOneWidget);

    await tester.tap(find.text('Unduh paket'));
    await tester.pumpAndSettle();

    expect(service.downloadCalls, 1);
    expect(find.text('Selesai diunduh'), findsOneWidget);
    expect(
      find.textContaining('belum memverifikasi ulang seluruh tile'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('pelanggaran batas menonaktifkan tombol unduh', (tester) async {
    final service = _FakeService();
    final controller = OfflineDownloadController(service: service);

    controller.select(_package(maxTiles: 1));
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(find.textContaining('melebihi batas paket'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    expect(button.onPressed, isNull);
    expect(service.downloadCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
