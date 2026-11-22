import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/map/application/map_track_source.dart';
import 'package:nama_app/features/map/application/offline_map_service.dart';
import 'package:nama_app/features/map/domain/map_package.dart';
import 'package:nama_app/features/map/domain/mountain_pack_data.dart';
import 'package:nama_app/features/map/presentation/map_page.dart';
import 'package:nama_app/features/onboarding/permission_service.dart';
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
    SharedPreferences.setMockInitialValues({});
    TrackingController.instance.startOverride = null;
    TrackingController.instance.setRecordingForTesting(recording: false);
  });

  tearDown(() {
    TrackingController.instance.startOverride = null;
    TrackingController.instance.setRecordingForTesting(recording: false);
  });

  MountainMapPackage getCiremaiPackage() {
    final packs = MountainPackData.createDefaultPacks();
    return packs.firstWhere((p) => p.id == 'ciremai').package;
  }

  MountainMapPackage getPrauPackage() {
    final packs = MountainPackData.createDefaultPacks();
    return packs.firstWhere((p) => p.id == 'prau').package;
  }

  Widget createSubject({
    required MountainMapPackage package,
    MapTrail? initialTrail,
  }) {
    return MaterialApp(
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
            initialTrail: initialTrail ?? package.trails.first,
            catalogLoader: () async => MapPackageCatalog([package]),
            offlineService: _FakeOfflineService(),
            trackSource: _StaticTrackSource(),
            permissionService: const _FakePermissionService(),
          ),
        ),
      ),
    );
  }

  testWidgets('panel bawah menampilkan 3 kolom statistik: Jarak, Tanjakan, Elevasi maks',
      (tester) async {
    final package = getCiremaiPackage();
    await tester.pumpWidget(createSubject(package: package));
    await tester.pumpAndSettle();

    expect(find.text('Jarak'), findsOneWidget);
    expect(find.text('Tanjakan'), findsOneWidget);
    expect(find.text('Elevasi maks'), findsOneWidget);

    expect(find.text('4,4 km'), findsOneWidget);
    expect(find.text('+1.101 m'), findsOneWidget);
    expect(find.text('3.078 mdpl'), findsOneWidget);
  });

  testWidgets('gunung dengan 1 jalur menyembunyikan tombol Jalur dan memperluas tombol utama',
      (tester) async {
    final package = getPrauPackage();
    await tester.pumpWidget(createSubject(package: package));
    await tester.pumpAndSettle();

    // Tombol pilihan jalur tidak ditampilkan
    expect(find.text('Via Patakbanteng'), findsNothing);
    // Tombol Mulai tracking tetap ada
    expect(find.text('Mulai tracking'), findsOneWidget);
  });

  testWidgets('gunung dengan banyak jalur menampilkan tombol Jalur dan membuka daftar pilihan',
      (tester) async {
    final package = getCiremaiPackage();
    await tester.pumpWidget(createSubject(package: package));
    await tester.pumpAndSettle();

    expect(find.text('Via Apuy'), findsOneWidget);

    // Ketuk tombol Jalur untuk membuka pilihan
    await tester.tap(find.text('Via Apuy'));
    await tester.pumpAndSettle();

    // Sekarang chip Via Linggarjati muncul
    expect(find.text('Via Linggarjati'), findsOneWidget);

    // Pilih Via Linggarjati
    await tester.tap(find.text('Via Linggarjati'));
    await tester.pumpAndSettle();

    // Statistik terbarui ke Via Linggarjati (7,8 km, +2.200 m)
    expect(find.text('7,8 km'), findsOneWidget);
    expect(find.text('+2.200 m'), findsOneWidget);
  });

  testWidgets('tombol Mulai tracking memulai sesi dan memicu mode tracking',
      (tester) async {
    TrackingController.instance.startOverride = () async {
      TrackingController.instance.setRecordingForTesting(recording: true);
      return true;
    };

    final package = getCiremaiPackage();
    await tester.pumpWidget(createSubject(package: package));
    await tester.pumpAndSettle();

    expect(TrackingController.instance.isRecording, isFalse);
    expect(find.byKey(const ValueKey('map-directions-button')), findsNothing);

    await tester.tap(find.text('Mulai tracking'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(TrackingController.instance.isRecording, isTrue);

    // Tombol Petunjuk Arah muncul setelah tracking aktif
    expect(find.byKey(const ValueKey('map-directions-button')), findsOneWidget);
  });

  testWidgets('tombol kembali saat tracking memunculkan dialog konfirmasi',
      (tester) async {
    final package = getCiremaiPackage();
    await tester.pumpWidget(createSubject(package: package));
    await tester.pumpAndSettle();

    // Aktifkan mode tracking
    TrackingController.instance.setRecordingForTesting(recording: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Ketuk tombol kembali di top bar
    await tester.tap(find.byKey(const ValueKey('map-back-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Muncul dialog peringatan
    expect(find.text('Tracking masih berjalan'), findsOneWidget);
    expect(find.text('Tetap di peta'), findsOneWidget);
    expect(find.text('Keluar dari peta'), findsOneWidget);
    expect(find.text('Selesaikan tracking'), findsOneWidget);

    // Pilih Tetap di peta
    await tester.tap(find.text('Tetap di peta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Dialog tertutup dan tracking tetap berjalan
    expect(find.text('Tracking masih berjalan'), findsNothing);
    expect(TrackingController.instance.isRecording, isTrue);
  });
}
