import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/app/router.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/groups/application/group_selection.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/home/beranda_page.dart';
import 'package:nama_app/features/kartu/domain/kartu_data.dart';
import 'package:nama_app/features/preparation/application/packing_list_store.dart';
import 'package:nama_app/features/splash/presentation/startup_gate_screen.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';
import 'package:nama_app/infrastructure/cache/offline_account_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/account_fakes.dart';
import '../support/hiqeo_app_harness.dart';

class _CountingProfileRepo extends FakeProfileRepository {
  int currentProfileCalls = 0;

  @override
  Future<UserProfile?> currentProfile() async {
    currentProfileCalls++;
    return super.currentProfile();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    BerandaPage.setPreloadedLastTripForTesting();
  });

  tearDown(() {
    BerandaPage.setPreloadedLastTripForTesting();
  });

  testWidgets(
      'StartupGateScreen menampilkan logo baru di latar gelap dan menunggu durasi minimum',
      (tester) async {
    var initialized = 0;
    var ready = 0;
    var postSync = 0;

    expect(
      StartupGateScreen.defaultMinimumDuration,
      const Duration(milliseconds: 650),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: StartupGateScreen(
          initializer: () async => initialized++,
          minimumDuration: const Duration(milliseconds: 100),
          onReady: () => ready++,
          onPostEntrySync: () => postSync++,
        ),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, HiqeoColors.dark.background);

    final overlay = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).last,
    );
    expect(overlay.value.statusBarColor, Colors.transparent);
    expect(overlay.value.systemNavigationBarColor, Colors.transparent);
    expect(overlay.value.statusBarIconBrightness, Brightness.light);
    expect(overlay.value.systemNavigationBarIconBrightness, Brightness.light);

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<AssetImage>());
    expect(
      (image.image as AssetImage).assetName,
      StartupGateScreen.logoAssetPath,
    );

    expect(initialized, 1);
    expect(ready, 0);
    expect(postSync, 0);

    await tester.pump(const Duration(milliseconds: 110));
    expect(ready, 1);
    expect(postSync, 1);
  });

  testWidgets('galat inisialisasi offline tidak menahan StartupGateScreen',
      (tester) async {
    var ready = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: StartupGateScreen(
          initializer: () async => throw StateError('offline'),
          minimumDuration: Duration.zero,
          onReady: () => ready++,
        ),
      ),
    );

    await tester.pump();
    expect(ready, 1);
  });

  testWidgets('transisi StartupGateScreen ke Beranda memakai FadeTransition',
      (tester) async {
    final router = buildHiqeoRouter();
    await tester.pumpWidget(buildHiqeoTestApp(router: router));
    expect(find.byType(StartupGateScreen), findsOneWidget);

    router.go('/beranda');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    expect(find.byType(FadeTransition), findsWidgets);

    await tester.pumpAndSettle();
    expect(find.byType(BerandaPage), findsOneWidget);
  });

  test('hydrateLocalCacheOnly memuat profil lokal tanpa panggilan jaringan',
      () async {
    final cache = InMemoryOfflineAccountCache();
    await cache.writeProfile(
      const UserProfile(
        userId: 'u-1',
        username: 'pendaki_gunung',
        fullName: 'Alya',
        isProfileComplete: true,
      ),
    );
    await cache.writeGroups('u-1', <CachedGroupEntry>[
      CachedGroupEntry(
        remote: RemoteGroup(
          group: Group(
            id: 'g-deleted',
            name: 'Grup Lama',
            ownerId: 'u-1',
            createdAtUtc: DateTime.utc(2026, 1, 1),
          ),
          role: GroupRole.owner,
        ),
        memberCount: 2,
      ),
      CachedGroupEntry(
        remote: RemoteGroup(
          group: Group(
            id: 'g-active',
            name: 'Tim Rinjani',
            ownerId: 'u-1',
            createdAtUtc: DateTime.utc(2026, 2, 1),
          ),
          role: GroupRole.owner,
        ),
        memberCount: 3,
      ),
    ]);

    final groupsStore = SocialGroupsStore();
    await groupsStore.markGroupDeleted('g-deleted');
    final profileRepo = _CountingProfileRepo();

    final controller = AccountController(
      authService: FakeAuthService(
        currentUser: const AuthUser(id: 'u-1'),
      ),
      profileRepository: profileRepo,
      keyDirectory: FakeKeyDirectory(),
      identity: FakeIdentity(Uint8List(32)),
      cache: cache,
      groupsStore: groupsStore,
      connectivityStream: const Stream<bool>.empty(),
    );
    addTearDown(controller.dispose);

    await controller.hydrateLocalCacheOnly();

    expect(profileRepo.currentProfileCalls, 0);
    expect(controller.profile?.fullName, 'Alya');
    expect(controller.groups.map((g) => g.group.id), <String>['g-active']);
  });

  test('pruneDeletedGroups menghapus rencana aktif milik grup terhapus',
      () async {
    final planStore = GroupHikePlanStore();
    await planStore.setPlan(
      const GroupHikePlan(
        inviteId: 'inv-1',
        groupId: 'g-deleted',
        groupName: 'Grup Lama',
        mountainId: 'merbabu',
        mountainName: 'Gunung Merbabu',
        organizerUserId: 'u-1',
        organizerName: 'Alya',
        readyUserIds: <String>{'u-1', 'u-2'},
        memberCount: 2,
      ),
    );
    expect(planStore.activePlan, isNotNull);

    await planStore.pruneDeletedGroups(const <String>{'g-deleted'});
    expect(planStore.activePlan, isNull);
  });

  testWidgets(
      'BerandaPage langsung menampilkan data Pendakian Terakhir dari preload pada frame pertama',
      (tester) async {
    final session = TrackingSession(
      id: 'sess-1',
      startedAtUtc: DateTime.utc(2026, 6, 10, 1),
      endedAtUtc: DateTime.utc(2026, 6, 10, 5),
      distanceM: 7400,
      movingSeconds: 10800,
      elevationGainM: 920,
      elevationLossM: 900,
      status: TrackingSessionStatus.completed,
      mountainName: 'Gunung Prau',
    );
    final data = KartuData.fromSession(session, <TrackPoint>[
      TrackPoint(
        timestampUtc: DateTime.utc(2026, 6, 10, 1),
        lat: -7.186,
        lon: 109.922,
        altitudeM: 1850,
        accuracyM: 5,
      ),
      TrackPoint(
        timestampUtc: DateTime.utc(2026, 6, 10, 5),
        lat: -7.190,
        lon: 109.925,
        altitudeM: 2565,
        accuracyM: 5,
      ),
    ]);
    BerandaPage.setPreloadedLastTripForTesting(session: session, data: data);

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: Scaffold(
          body: BerandaPage(
            now: () => DateTime(2026, 6, 11, 8),
          ),
        ),
      ),
    );

    // Frame pertama (tanpa pumpAndSettle): langsung terisi tanpa teks kosong.
    expect(find.text('Gunung Prau'), findsOneWidget);
    expect(find.text('Belum ada riwayat pendakian'), findsNothing);
    await tester.pumpAndSettle();
  });
}
