import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/features/map/application/map_track_source.dart';
import 'package:nama_app/features/map/application/offline_map_service.dart';
import 'package:nama_app/features/map/domain/map_package.dart';
import 'package:nama_app/features/map/domain/mountain_pack.dart';
import 'package:nama_app/features/map/domain/mountain_pack_data.dart';
import 'package:nama_app/features/map/presentation/map_page.dart';
import 'package:nama_app/features/map/presentation/mountain_detail_page.dart';
import 'package:nama_app/features/onboarding/permission_service.dart';
import 'package:nama_app/features/preparation/application/packing_list_store.dart';
import 'package:nama_app/features/tracking/application/tracking_controller.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePermissionService extends PermissionService {
  const _FakePermissionService();

  @override
  Future<PermissionReport> check() async => const PermissionReport(
        notificationGranted: true,
        locationWhileInUse: true,
        locationAlways: true,
        locationServiceEnabled: true,
        preciseLocation: true,
        ignoringBatteryOptimizations: true,
      );
}

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
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TrackingController.instance.startOverride = null;
    TrackingController.instance.setRecordingForTesting(recording: false);
  });

  tearDown(() {
    TrackingController.instance.startOverride = null;
    TrackingController.instance.setRecordingForTesting(recording: false);
  });

  testWidgets(
      'MountainDetailPage membersihkan angka jarak/elevasi dari JALUR PENDAKIAN, menampilkan nama lengkap tanpa terpotong, dan memberi padding bawah lega',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const longTrailName = 'Via Suwanting Magelang Timur Basecamp';
    const secondTrailName = 'Via Selo Boyolali Utama';
    final customPack = MountainPack(
      id: 'merbabu-test',
      name: 'Gunung Merbabu',
      province: 'Jawa Tengah',
      elevationM: 3145,
      trailCount: 2,
      sizeMb: 28,
      status: MountainDownloadStatus.notDownloaded,
      package: MountainMapPackage(
        id: 'merbabu-test',
        name: 'Gunung Merbabu',
        version: 1,
        dataDateUtc: DateTime.utc(2026, 1, 1),
        verified: true,
        offline: const OfflineConfig(
          bounds: GeoBounds(
            south: -7.5,
            west: 110.4,
            north: -7.4,
            east: 110.5,
          ),
          minZoom: 10,
          maxZoom: 16,
          maxAreaKm2: 120,
          maxTiles: 500,
        ),
        trails: <MapTrail>[
          MapTrail(
            id: 'suwanting',
            name: longTrailName,
            source: 'gpx',
            verified: true,
            points: const <LatLng>[LatLng(-7.48, 110.42), LatLng(-7.45, 110.44)],
            distanceM: 5300,
            elevationGainM: 1294.5433333333333,
          ),
          MapTrail(
            id: 'selo',
            name: secondTrailName,
            source: 'gpx',
            verified: true,
            points: const <LatLng>[LatLng(-7.49, 110.45), LatLng(-7.45, 110.44)],
            distanceM: 6100,
            elevationGainM: 1380.123456789,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: const <ThemeExtension<dynamic>>[HiqeoColors.light],
        ),
        home: MountainDetailPage(pack: customPack),
      ),
    );
    await tester.pumpAndSettle();

    // Nama lengkap jalur tampil utuh tanpa ellipsis dan tanpa angka mentah jarak/elevasi.
    final firstTrailText = tester.widget<Text>(find.text(longTrailName));
    expect(firstTrailText.overflow, isNull);
    expect(find.text(secondTrailName), findsOneWidget);
    expect(find.textContaining('5.3 km'), findsNothing);
    expect(find.textContaining('1294'), findsNothing);
    expect(find.textContaining('6.1 km'), findsNothing);
    expect(find.byIcon(Icons.terrain_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

    // Spacer bawah memberi ruang gulir yang lebih tinggi dari Floating Bottom Navbar.
    final spacer = tester.widget<SizedBox>(
      find.byKey(const ValueKey('mountain-detail-bottom-spacer')),
    );
    expect(
      spacer.height,
      greaterThanOrEqualTo(
        HiqeoMetrics.navbarHeight + HiqeoMetrics.navbarBottomMargin + 56,
      ),
    );
  });

  testWidgets(
      'MapPage mengunci tombol Mulai tracking saat anggota grup belum semua menekan Siap, lalu membuka setelah semua siap',
      (tester) async {
    var startedCount = 0;
    TrackingController.instance.startOverride = () async {
      startedCount++;
      TrackingController.instance.setRecordingForTesting(recording: true);
      return true;
    };

    final planStore = GroupHikePlanStore();
    await planStore.setPlan(
      const GroupHikePlan(
        inviteId: 'inv-1',
        groupId: 'grp-local-1',
        groupName: 'Tim Puncak',
        mountainId: 'ciremai',
        mountainName: 'Gunung Ciremai',
        organizerUserId: 'u-1',
        organizerName: 'Raka',
        readyUserIds: <String>{'u-1'},
        memberCount: 3,
      ),
    );

    final package = MountainPackData.createDefaultPacks()
        .firstWhere((p) => p.id == 'ciremai')
        .package;

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
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
              catalogLoader: () async => MapPackageCatalog(<MountainMapPackage>[package]),
              offlineService: _FakeOfflineService(),
              trackSource: _StaticTrackSource(),
              permissionService: const _FakePermissionService(),
              groupHikePlanStore: planStore,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Terkunci: catatan menunggu tampil, ikon kunci muncul, tap tidak memulai tracking.
    expect(find.byKey(const ValueKey('map-tracking-lock-note')), findsOneWidget);
    expect(
      find.text('Menunggu anggota grup lain menekan Siap (1/3 siap)'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('map-start-tracking-button')));
    await tester.pumpAndSettle();
    expect(startedCount, 0);
    expect(TrackingController.instance.isRecording, isFalse);

    // Semua anggota menekan Siap -> kunci terbuka otomatis.
    await planStore.markUserReady('inv-1', 'u-2');
    await planStore.markUserReady('inv-1', 'u-3');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('map-tracking-lock-note')), findsNothing);
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);

    await tester.tap(find.byKey(const ValueKey('map-start-tracking-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(startedCount, 1);
    expect(TrackingController.instance.isRecording, isTrue);
  });
}
