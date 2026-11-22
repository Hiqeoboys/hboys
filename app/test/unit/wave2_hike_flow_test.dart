import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/chat/domain/group_chat_models.dart';
import 'package:nama_app/features/groups/application/group_selection.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/map/application/group_hike_member_tracker.dart';
import 'package:nama_app/features/map/application/map_track_source.dart';
import 'package:nama_app/features/map/application/offline_map_service.dart';
import 'package:nama_app/features/map/domain/map_package.dart';
import 'package:nama_app/features/map/domain/mountain_pack_data.dart';
import 'package:nama_app/features/map/domain/track_geojson.dart';
import 'package:nama_app/features/map/presentation/map_page.dart';
import 'package:nama_app/features/map/presentation/widgets/trail_map_bottom_panel.dart';
import 'package:nama_app/features/onboarding/permission_service.dart';
import 'package:nama_app/features/preparation/application/packing_list_store.dart';
import 'package:nama_app/features/preparation/presentation/siap_naik_page.dart';
import 'package:nama_app/features/tracking/application/tracking_controller.dart';
import 'package:nama_app/features/tracking/application/tracking_runtime.dart'
    show TrackingAccess;
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/trails/domain/track_route.dart';
import 'package:nama_app/infrastructure/location/shared_location_service.dart';
import 'package:nama_app/infrastructure/notifications/push_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/account_fakes.dart';

class _FakeClock implements Clock {
  _FakeClock(this.now);
  DateTime now;

  @override
  DateTime nowUtc() => now;
}

class _TestPermissionService extends PermissionService {
  _TestPermissionService({
    this.gpsEnabled = true,
    this.whileInUse = true,
    this.always = true,
  });

  bool gpsEnabled;
  bool whileInUse;
  bool always;
  int requestCoreCalls = 0;
  int openLocationSettingsCalls = 0;

  @override
  Future<PermissionReport> check() async => PermissionReport(
        notificationGranted: true,
        locationWhileInUse: whileInUse,
        locationAlways: always,
        locationServiceEnabled: gpsEnabled,
        preciseLocation: whileInUse || always,
        ignoringBatteryOptimizations: true,
      );

  @override
  Future<PermissionReport> requestCore() async {
    requestCoreCalls++;
    whileInUse = true;
    return check();
  }

  @override
  Future<bool> openLocationSettings() async {
    openLocationSettingsCalls++;
    gpsEnabled = true;
    return true;
  }
}

class _FakeOfflineMapService implements OfflineMapService {
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

class _EmptyTrackSource implements MapTrackSource {
  @override
  Future<MapTrackSnapshot> load() async => const MapTrackSnapshot(
        points: <TrackPoint>[],
        latestPoint: null,
      );
}

class _InMemoryForegroundBackend implements ForegroundLocationBackend {
  final StreamController<TrackPoint> _ctrl =
      StreamController<TrackPoint>.broadcast();

  @override
  Future<TrackingAccess> checkAccess() async => TrackingAccess.whileInUse;

  @override
  Future<TrackingAccess> requestAccess() async => TrackingAccess.whileInUse;

  @override
  Stream<TrackPoint> positions() => _ctrl.stream;

  @override
  Future<bool> openLocationSettings() async => true;

  @override
  Future<bool> openAppSettings() async => true;

  void dispose() => unawaited(_ctrl.close());
}

class _NoopRecordingFeed implements RecordingLocationFeed {
  @override
  bool get isRecording => false;

  @override
  Listenable get changes => ValueNotifier<int>(0);

  @override
  Future<TrackPoint?> latestPoint() async => null;
}

class _FixedAccountController extends AccountController {
  _FixedAccountController({required this.fixedGroup})
      : super(
          authService: FakeAuthService(
            currentUser: const AuthUser(id: 'u-1'),
          ),
          profileRepository: FakeProfileRepository(),
          keyDirectory: FakeKeyDirectory(),
          identity: FakeIdentity(Uint8List(32)),
        );

  final RemoteGroup fixedGroup;

  @override
  void initialize() {}

  @override
  UserProfile? get profile => const UserProfile(
        userId: 'u-1',
        username: 'rani',
        publicKeyBase64: 'pk',
      );

  @override
  AuthUser? get user => const AuthUser(id: 'u-1');

  @override
  List<RemoteGroup> get groups => <RemoteGroup>[fixedGroup];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TrackingController.instance.startOverride = null;
    TrackingController.instance.setRecordingForTesting(recording: false);
  });

  tearDown(() {
    TrackingController.instance.startOverride = null;
    TrackingController.instance.setRecordingForTesting(recording: false);
    GroupHikePlanStore.setInstanceForTesting(null);
  });

  testWidgets(
      'Req #1: SiapNaikPage menolak masuk ke peta jalur jika peta gunung belum terunduh & tampilkan dialog Unduh peta',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final planStore = GroupHikePlanStore();
    await planStore.setSoloPlan(
      const SoloHikePlan(
        mountainId: 'prau',
        mountainName: 'Gunung Prau',
        trailId: 'prau_patak_banteng',
        trailName: 'Via Patak Banteng',
      ),
    );
    final groupsStore = SocialGroupsStore();
    final account = _FixedAccountController(
      fixedGroup: RemoteGroup(
        group: Group(
          id: '11111111-1111-4111-8111-111111111111',
          name: 'Tim Prau',
          ownerId: 'u-1',
          mountain: 'Gunung Prau',
          createdAtUtc: DateTime.utc(2026, 11, 20),
        ),
        role: GroupRole.owner,
      ),
    );
    addTearDown(account.dispose);

    var routePushedToMap = false;
    final router = GoRouter(
      initialLocation: '/siap-naik',
      routes: <RouteBase>[
        GoRoute(
          path: '/siap-naik',
          builder: (_, __) => SiapNaikPage(
            accountController: account,
            groupHikePlanStore: planStore,
            socialGroupsStore: groupsStore,
            offlineMapCheck: (_) async => false,
          ),
        ),
        GoRoute(
          path: '/peta/jalur',
          builder: (_, __) {
            routePushedToMap = true;
            return const Scaffold(body: Text('MapOpened'));
          },
        ),
        GoRoute(
          path: '/peta',
          builder: (_, __) {
            routePushedToMap = true;
            return const Scaffold(body: Text('MapList'));
          },
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(
        theme: hiqeoLightTheme,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gunung Prau'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('siap-naik-mulai')));
    await tester.pumpAndSettle();

    expect(routePushedToMap, isFalse);
    expect(
      find.byKey(const ValueKey('siap-naik-download-required-dialog')),
      findsOneWidget,
    );
    expect(find.text('Unduh peta gunung dulu'), findsOneWidget);
    expect(find.byKey(const ValueKey('siap-naik-go-download')), findsOneWidget);
  });

  test('Req #2: GeoJSON jalur GPX mengikuti titik asli tanpa garis lurus sintetis',
      () {
    final gpxRoute = TrackRoute.fromPoints(
      id: 'merbabu_selo',
      name: 'Via Selo',
      points: const <TrackRoutePoint>[
        TrackRoutePoint(lat: -7.4836, lon: 110.4594, ele: 1850),
        TrackRoutePoint(lat: -7.4750, lon: 110.4550, ele: 2100),
        TrackRoutePoint(lat: -7.4680, lon: 110.4500, ele: 2550),
        TrackRoutePoint(lat: -7.4537, lon: 110.4406, ele: 3145),
      ],
    );
    final decoded = jsonDecode(trackRouteLineToGeoJson(gpxRoute)) as Map;
    final features = decoded['features'] as List;
    expect(features.length, 1);
    final coords =
        ((features.first as Map)['geometry'] as Map)['coordinates'] as List;
    expect(coords.length, 4);
  });

  testWidgets(
      'Req #3: Status kesiapan anggota di Siapkan Pendakian berubah dinamis realtime saat member menekan Siap atau batal',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final planStore = GroupHikePlanStore();
    await planStore.setPlan(
      const GroupHikePlan(
        inviteId: 'inv-live-1',
        groupId: '11111111-1111-4111-8111-111111111111',
        groupName: 'Rombongan Merbabu',
        mountainId: 'merbabu',
        mountainName: 'Gunung Merbabu',
        trailId: 'merbabu_selo',
        trailName: 'Via Selo',
        organizerUserId: 'u-1',
        organizerName: 'Rani',
        readyUserIds: <String>{'u-1'},
        memberCount: 3,
      ),
    );
    final account = _FixedAccountController(
      fixedGroup: RemoteGroup(
        group: Group(
          id: '11111111-1111-4111-8111-111111111111',
          name: 'Rombongan Merbabu',
          ownerId: 'u-1',
          mountain: 'Gunung Merbabu',
          createdAtUtc: DateTime.utc(2026, 11, 20),
        ),
        role: GroupRole.owner,
      ),
    );
    addTearDown(account.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: SiapNaikPage(
          accountController: account,
          groupHikePlanStore: planStore,
          socialGroupsStore: SocialGroupsStore(),
          offlineMapCheck: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Siap naik 1/3'), findsOneWidget);

    // Simulasikan Postgres Realtime UPDATE dengan string array literal `{u-1,u-2}`
    await planStore.handlePrepRowForTesting(<String, dynamic>{
      'invite_id': 'inv-live-1',
      'group_id': '11111111-1111-4111-8111-111111111111',
      'mountain_id': 'merbabu',
      'mountain_name': 'Gunung Merbabu',
      'trail_id': 'merbabu_selo',
      'trail_name': 'Via Selo',
      'organizer_user_id': 'u-1',
      'organizer_name': 'Rani',
      'ready_user_ids': '{u-1,"u-2"}',
      'member_count': 3,
      'status': 'active',
    });
    await tester.pumpAndSettle();
    expect(find.text('Siap naik 2/3'), findsOneWidget);

    // Anggota ke-3 menekan Siap -> langsung menjadi Semua siap tanpa keluar layar
    await planStore.handlePrepRowForTesting(<String, dynamic>{
      'invite_id': 'inv-live-1',
      'group_id': '11111111-1111-4111-8111-111111111111',
      'mountain_id': 'merbabu',
      'mountain_name': 'Gunung Merbabu',
      'trail_id': 'merbabu_selo',
      'trail_name': 'Via Selo',
      'organizer_user_id': 'u-1',
      'organizer_name': 'Rani',
      'ready_user_ids': <String>['u-1', 'u-2', 'u-3'],
      'member_count': 3,
      'status': 'active',
    });
    await tester.pumpAndSettle();
    expect(find.text('Semua siap'), findsOneWidget);
  });

  testWidgets(
      'Req #4: MapPage dari tab Peta (allowStartAscent: false) hanya menampilkan Mulai turun + pilih jalur, tanpa Mulai pendakian',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final backend = _InMemoryForegroundBackend();
    addTearDown(backend.dispose);
    final loc = SharedLocationService(
      backend: backend,
      recordingFeed: _NoopRecordingFeed(),
    );
    addTearDown(loc.dispose);

    final merbabu = MountainPackData.createDefaultPacks()
        .firstWhere((p) => p.id == 'merbabu')
        .package;

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: MapPage(
          initialPackage: merbabu,
          initialTrail: merbabu.trails.first,
          allowStartAscent: false,
          mapboxToken: '',
          locationService: loc,
          catalogLoader: () async => MapPackageCatalog(<MountainMapPackage>[merbabu]),
          offlineService: _FakeOfflineMapService(),
          trackSource: _EmptyTrackSource(),
          permissionService: _TestPermissionService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('map-start-tracking-button')),
      findsNothing,
    );
    expect(find.text('Mulai tracking'), findsNothing);
    expect(find.text('Mulai pendakian'), findsNothing);
    expect(
      find.byKey(const ValueKey('map-start-descent-button')),
      findsOneWidget,
    );
    expect(find.text('Mulai turun'), findsOneWidget);
    // Merbabu punya 2 jalur -> pemilih jalur tetap tampil di panel bawah
    expect(
      find.descendant(
        of: find.byType(TrailMapBottomPanel),
        matching: find.text('Via Selo'),
      ),
      findsOneWidget,
    );
  });

  test('Req #5: Event hike_started Realtime & FCM didekode dan di-deduplikasi rapi',
      () async {
    final store = GroupHikePlanStore();
    final emitted = <GroupHikePlan>[];
    final sub = store.onHikeStarted.listen(emitted.add);
    addTearDown(sub.cancel);

    final nowIso = DateTime.now().toUtc().toIso8601String();
    await store.handlePrepRowForTesting(
      <String, dynamic>{
        'invite_id': 'inv-start-1',
        'group_id': '22222222-2222-4222-8222-222222222222',
        'mountain_id': 'merbabu',
        'mountain_name': 'Gunung Merbabu',
        'trail_id': 'merbabu_selo',
        'trail_name': 'Via Selo',
        'organizer_user_id': 'leader-1',
        'organizer_name': 'Raka',
        'ready_user_ids': <String>['leader-1', 'member-2'],
        'member_count': 2,
        'status': 'started',
        'started_at': nowIso,
        'started_by': 'leader-1',
      },
      currentUserIdOverride: 'member-2',
    );
    await Future<void>.delayed(Duration.zero);

    expect(emitted.length, 1);
    expect(emitted.first.mountainId, 'merbabu');
    expect(emitted.first.trailId, 'merbabu_selo');

    // Push duplikat dengan started_at sama tidak memicu navigasi ulang
    store.emitHikeStartedFromPush(
      <String, String>{
        'type': 'hike_started',
        'group_id': '22222222-2222-4222-8222-222222222222',
        'invite_id': 'inv-start-1',
        'mountain_id': 'merbabu',
        'mountain_name': 'Gunung Merbabu',
        'route_id': 'merbabu_selo',
        'started_at': nowIso,
        'started_by': 'leader-1',
      },
      currentUserIdOverride: 'member-2',
    );
    await Future<void>.delayed(Duration.zero);
    expect(emitted.length, 1);

    final pushNotif = InAppPushNotification.fromRemoteData(
      data: <String, dynamic>{
        'type': 'hike_started',
        'group_id': '22222222-2222-4222-8222-222222222222',
        'mountain_id': 'merbabu',
        'route_id': 'merbabu_selo',
        'started_at': nowIso,
      },
    );
    expect(pushNotif.type, 'hike_started');
    expect(pushNotif.route, '/peta/jalur');
  });

  testWidgets(
      'Req #5: Auto-start dengan izin/GPS kurang menampilkan overlay non-dismissible di tempat lalu otomatis mulai tracking saat aktif',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var startedCalls = 0;
    TrackingController.instance.startOverride = () async {
      startedCalls++;
      TrackingController.instance.setRecordingForTesting(recording: true);
      return true;
    };

    final backend = _InMemoryForegroundBackend();
    addTearDown(backend.dispose);
    final loc = SharedLocationService(
      backend: backend,
      recordingFeed: _NoopRecordingFeed(),
    );
    addTearDown(loc.dispose);

    final perm = _TestPermissionService(
      gpsEnabled: false,
      whileInUse: false,
      always: false,
    );
    final pack = MountainPackData.createDefaultPacks().first.package;

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: MapPage(
          initialPackage: pack,
          initialTrail: pack.trails.first,
          allowStartAscent: true,
          autoStartTracking: true,
          mapboxToken: '',
          locationService: loc,
          catalogLoader: () async => MapPackageCatalog(<MountainMapPackage>[pack]),
          offlineService: _FakeOfflineMapService(),
          trackSource: _EmptyTrackSource(),
          permissionService: perm,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Pengguna tetap berada di MapPage dengan kartu peringatan non-dismissible
    expect(
      find.byKey(const ValueKey('map-inplace-permission-overlay')),
      findsOneWidget,
    );
    expect(find.text('Izin lokasi diperlukan untuk tracking'), findsOneWidget);
    expect(startedCalls, 0);

    // Simulasikan izin & GPS diberikan -> poller 1.4s langsung menghilangkan
    // kartu dan memulai perekaman tracking otomatis.
    perm.whileInUse = true;
    perm.gpsEnabled = true;
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byKey(const ValueKey('map-inplace-permission-overlay')),
      findsNothing,
    );
    expect(startedCalls, 1);
    expect(TrackingController.instance.isRecording, isTrue);
  });

  test(
      'Req #6: evaluateGroupMemberFreshness menandai lokasi terakhir saat >= 5 menit tidak ter-update atau GPS mati',
      () {
    final now = DateTime.utc(2026, 11, 22, 10, 0, 0);
    final locations = <MemberLastLocation>[
      MemberLastLocation(
        userId: 'u-fresh',
        displayName: 'Dimas',
        initial: 'D',
        hasSignal: true,
        lat: -7.47,
        lon: 110.44,
        recordedAtUtc: now.subtract(const Duration(minutes: 4, seconds: 59)),
        updatedAtUtc: now.subtract(const Duration(minutes: 4, seconds: 59)),
      ),
      MemberLastLocation(
        userId: 'u-stale-5m',
        displayName: 'Sari',
        initial: 'S',
        hasSignal: true,
        lat: -7.48,
        lon: 110.45,
        recordedAtUtc: now.subtract(const Duration(minutes: 5)),
        updatedAtUtc: now.subtract(const Duration(minutes: 5)),
      ),
      MemberLastLocation(
        userId: 'u-gps-off',
        displayName: 'Budi',
        initial: 'B',
        hasSignal: false,
        lat: -7.49,
        lon: 110.46,
        recordedAtUtc: now.subtract(const Duration(minutes: 1)),
        updatedAtUtc: now.subtract(const Duration(minutes: 1)),
      ),
    ];

    final evaluated = evaluateGroupMemberFreshness(
      rawLocations: locations,
      nowUtc: now,
      currentUserId: 'u-self',
    );
    expect(evaluated.length, 3);
    expect(evaluated[0].isStale, isFalse);
    expect(evaluated[1].isStale, isTrue);
    expect(evaluated[1].lastSeenLabel, '5 mnt lalu');
    expect(evaluated[2].isStale, isTrue);

    final geoJson = jsonDecode(groupMembersToGeoJson(evaluated)) as Map;
    final features = geoJson['features'] as List;
    expect(features.length, 3);
    final sariProps = (features[1] as Map)['properties'] as Map;
    expect(sariProps['stale'], 1);
    expect(sariProps['label'].toString(), contains('Terakhir 5 mnt lalu'));
  });

  testWidgets(
      'Req #6: MapPage menampilkan banner peringatan non-blocking saat anggota grup tidak terdeteksi >= 5 menit',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.utc(2026, 11, 22, 10, 30);
    final clock = _FakeClock(now);
    final locCtrl = StreamController<List<MemberLastLocation>>.broadcast();
    addTearDown(locCtrl.close);
    final tracker = GroupHikeMemberTracker(
      clock: clock,
      locationsOverride: locCtrl.stream,
    );
    addTearDown(tracker.dispose);

    TrackingController.instance.setRecordingForTesting(recording: true);
    final backend = _InMemoryForegroundBackend();
    addTearDown(backend.dispose);
    final loc = SharedLocationService(
      backend: backend,
      recordingFeed: _NoopRecordingFeed(),
    );
    addTearDown(loc.dispose);

    final pack = MountainPackData.createDefaultPacks().first.package;
    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: MapPage(
          initialPackage: pack,
          initialTrail: pack.trails.first,
          allowStartAscent: true,
          activeGroupId: '33333333-3333-4333-8333-333333333333',
          activeGroupName: 'Rombongan Merbabu',
          memberTracker: tracker,
          mapboxToken: '',
          locationService: loc,
          catalogLoader: () async => MapPackageCatalog(<MountainMapPackage>[pack]),
          offlineService: _FakeOfflineMapService(),
          trackSource: _EmptyTrackSource(),
          permissionService: _TestPermissionService(),
        ),
      ),
    );
    await tester.pump();
    locCtrl.add(<MemberLastLocation>[
      MemberLastLocation(
        userId: 'u-2',
        displayName: 'Sari',
        initial: 'S',
        hasSignal: true,
        lat: -7.475,
        lon: 110.445,
        recordedAtUtc: now.subtract(const Duration(minutes: 7)),
        updatedAtUtc: now.subtract(const Duration(minutes: 7)),
      ),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('map-stale-member-banner')),
      findsOneWidget,
    );
    expect(find.textContaining('Sari tidak terdeteksi >7 menit'), findsOneWidget);
    expect(find.text('Lihat lokasi terakhir'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('map-stale-collapse-button')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('map-stale-collapsed-pill')),
      findsOneWidget,
    );
  });
}
