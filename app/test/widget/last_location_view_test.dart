import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/widgets/nav_bar_visibility.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/chat/domain/chat_message.dart';
import 'package:nama_app/features/chat/domain/chat_repository.dart';
import 'package:nama_app/features/chat/domain/group_chat_models.dart';
import 'package:nama_app/features/chat/domain/media_attachment.dart';
import 'package:nama_app/features/chat/presentation/chat_page.dart';
import 'package:nama_app/features/chat/presentation/last_location_view.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/groups/domain/group_repository.dart';
import 'package:nama_app/features/map/domain/mountain_pack.dart';
import 'package:nama_app/features/map/domain/mountain_pack_data.dart';
import 'package:nama_app/features/tracking/application/tracking_runtime.dart'
    show TrackingAccess;
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/infrastructure/location/shared_location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/account_fakes.dart';

class _EmptyChatRepo implements ChatRepository {
  @override
  Future<void> saveMessage(ChatMessage message) async {}

  @override
  Future<ChatMessage?> findMessage(String messageId) async => null;

  @override
  Future<List<ChatMessage>> recentMessages(
    String groupId, {
    int limit = 50,
    DateTime? beforeUtc,
  }) async =>
      const <ChatMessage>[];

  @override
  Stream<List<ChatMessage>> watchMessages(String groupId, {int limit = 50}) =>
      Stream<List<ChatMessage>>.value(const <ChatMessage>[]);

  @override
  Future<int> nextSeq({
    required String groupId,
    required String authorId,
  }) async =>
      1;

  @override
  Future<void> saveMedia(MediaAttachment media) async {}

  @override
  Future<List<MediaAttachment>> mediaForMessage(String messageId) async =>
      const <MediaAttachment>[];
}

class _EmptyGroupRepo implements GroupRepository {
  @override
  Future<void> saveGroup(Group group) async {}

  @override
  Future<Group?> findGroup(String id) async => null;

  @override
  Stream<List<Group>> watchGroups() =>
      Stream<List<Group>>.value(const <Group>[]);

  @override
  Future<void> deleteGroup(String id) async {}

  @override
  Future<void> saveMember(GroupMember member) async {}

  @override
  Future<List<GroupMember>> membersOf(String groupId) async =>
      const <GroupMember>[];

  @override
  Stream<List<GroupMember>> watchMembers(String groupId) =>
      Stream<List<GroupMember>>.value(const <GroupMember>[]);

  @override
  Future<void> removeMember(String groupId, String userId) async {}
}

class _FakeLocationBackend implements ForegroundLocationBackend {
  final StreamController<TrackPoint> controller =
      StreamController<TrackPoint>.broadcast();

  @override
  Future<TrackingAccess> checkAccess() async => TrackingAccess.whileInUse;

  @override
  Future<TrackingAccess> requestAccess() async => TrackingAccess.whileInUse;

  @override
  Stream<TrackPoint> positions() => controller.stream;

  @override
  Future<bool> openLocationSettings() async => true;

  @override
  Future<bool> openAppSettings() async => true;

  Future<void> close() => controller.close();
}

class _TestAccount extends AccountController {
  _TestAccount()
      : super(
          authService: FakeAuthService(
            currentUser: const AuthUser(id: 'me'),
          ),
          profileRepository: FakeProfileRepository(),
          keyDirectory: FakeKeyDirectory(),
          identity: FakeIdentity(Uint8List(32)),
        );

  @override
  UserProfile? get profile => const UserProfile(
        userId: 'me',
        username: 'Kallopsia',
        publicKeyBase64: 'kunci',
      );

  @override
  List<RemoteGroup> get groups => <RemoteGroup>[
        RemoteGroup(
          group: Group(
            id: 'g-gede',
            name: 'Pendakian Gunung Gede',
            ownerId: 'me',
            createdAtUtc: DateTime.utc(2026, 11, 20),
            mountain: 'Gunung Gede',
          ),
          role: GroupRole.owner,
        ),
      ];

  @override
  Future<List<MemberDirectoryEntry>> membersOf(String groupId) async =>
      <MemberDirectoryEntry>[
        MemberDirectoryEntry(
          userId: 'me',
          username: 'Kallopsia',
          role: GroupRole.owner,
          joinedAtUtc: DateTime.utc(2026, 11, 20),
          publicKeyBase64: 'kunci',
        ),
      ];

  @override
  void initialize() {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    NavBarVisibilityController.instance.reset();
  });

  tearDown(() => NavBarVisibilityController.instance.reset());

  group('resolveLastLocationMapDecision & helpers', () {
    final downloadedMerbabu = MountainPackData.createDefaultPacks(
      downloadedIds: const <String>{'merbabu'},
    ).where((p) => p.id == 'merbabu').toList();

    test('online dengan GPS nyata memusat tepat ke GPS perangkat (tanpa Ciremai)', () {
      const jakarta = LatLng(-6.2088, 106.8456);
      final decision = resolveLastLocationMapDecision(
        isOnline: true,
        userPosition: jakarta,
        isLockingGps: false,
        members: const <MemberLastLocation>[],
        downloadedPacks: const <MountainPack>[],
      );
      expect(decision.mode, LastLocationMapMode.onlineMap);
      expect(decision.cameraTarget, jakarta);
    });

    test('online saat mengunci GPS memasuki mode lockingGps', () {
      final decision = resolveLastLocationMapDecision(
        isOnline: true,
        userPosition: null,
        isLockingGps: true,
        members: const <MemberLastLocation>[],
        downloadedPacks: const <MountainPack>[],
      );
      expect(decision.mode, LastLocationMapMode.lockingGps);
      expect(decision.cameraTarget, isNull);
    });

    test('Skenario B: offline di dalam bounding box gunung terunduh memakai peta offline', () {
      const merbabuPos = LatLng(-7.470, 110.440);
      final decision = resolveLastLocationMapDecision(
        isOnline: false,
        userPosition: merbabuPos,
        isLockingGps: false,
        members: const <MemberLastLocation>[],
        downloadedPacks: downloadedMerbabu,
      );
      expect(
        decision.mode,
        LastLocationMapMode.offlineDownloadedMountain,
      );
      expect(decision.matchedOfflinePack?.id, 'merbabu');
      expect(decision.cameraTarget, merbabuPos);
    });

    test('Skenario C: offline di luar area unduhan menampilkan status tidak tersedia', () {
      const bandungPos = LatLng(-6.9175, 107.6191);
      final decision = resolveLastLocationMapDecision(
        isOnline: false,
        userPosition: bandungPos,
        isLockingGps: false,
        members: const <MemberLastLocation>[],
        downloadedPacks: downloadedMerbabu,
      );
      expect(decision.mode, LastLocationMapMode.offlineUnavailable);
      expect(decision.cameraTarget, isNull);
    });

    test('Skenario C: offline tanpa peta terunduh menampilkan status tidak tersedia', () {
      const anyPos = LatLng(-6.2088, 106.8456);
      final decision = resolveLastLocationMapDecision(
        isOnline: false,
        userPosition: anyPos,
        isLockingGps: false,
        members: const <MemberLastLocation>[],
        downloadedPacks: const <MountainPack>[],
      );
      expect(decision.mode, LastLocationMapMode.offlineUnavailable);
    });

    test('margin atas scale bar selalu berada di bawah status bar + pil header', () {
      expect(lastLocationScaleBarTopMargin(36.0), 112.0);
    });
  });

  group('LastLocationView UI', () {
    final now = DateTime.utc(2026, 11, 21, 10, 0);

    testWidgets('menampilkan indikator mengunci GPS saat belum ada fix',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoDarkTheme,
          home: Scaffold(
            body: LastLocationView(
              groupName: 'Pendakian Gede',
              members: const <MemberLastLocation>[],
              nowUtc: now,
              isOnline: true,
              userLocation: null,
              isLockingGps: true,
              locationStatus: LiveLocationStatus.searching,
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('last-location-gps-loading')),
        findsOneWidget,
      );
      expect(find.text('Mencari sinyal GPS akurat…'), findsOneWidget);
      expect(find.text('Mencari GPS'), findsOneWidget);
    });

    testWidgets('Skenario B (offline dalam gunung terunduh) menampilkan badge Peta Offline',
        (tester) async {
      final downloadedMerbabu = MountainPackData.createDefaultPacks(
        downloadedIds: const <String>{'merbabu'},
      ).where((p) => p.id == 'merbabu').toList();

      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoDarkTheme,
          home: Scaffold(
            body: LastLocationView(
              groupName: 'Tim Merbabu',
              members: <MemberLastLocation>[
                MemberLastLocation(
                  userId: 'me',
                  displayName: 'Kamu',
                  initial: 'K',
                  hasSignal: true,
                  accuracyM: 9,
                  lat: -7.470,
                  lon: 110.440,
                  recordedAtUtc: now,
                  updatedAtUtc: now,
                ),
              ],
              nowUtc: now,
              isOnline: false,
              userLocation: const LatLng(-7.470, 110.440),
              downloadedPacks: downloadedMerbabu,
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Peta Offline'), findsOneWidget);
      expect(
        find.text('Tim Merbabu · Offline (Gunung Merbabu)'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('last-location-offline-unavailable')),
        findsNothing,
      );
    });

    testWidgets(
        'Skenario C (offline di luar area unduhan) menampilkan pesan resmi & pintasan unduh peta',
        (tester) async {
      var openedMaps = false;
      final downloadedMerbabu = MountainPackData.createDefaultPacks(
        downloadedIds: const <String>{'merbabu'},
      ).where((p) => p.id == 'merbabu').toList();

      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoDarkTheme,
          home: Scaffold(
            body: LastLocationView(
              groupName: 'Pendakian Gede',
              members: const <MemberLastLocation>[],
              nowUtc: now,
              isOnline: false,
              userLocation: const LatLng(-6.2088, 106.8456),
              downloadedPacks: downloadedMerbabu,
              onOpenOfflineMaps: () => openedMaps = true,
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('last-location-offline-unavailable')),
        findsOneWidget,
      );
      expect(find.text(kOfflineMapUnavailableMessage), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('last-location-open-maps-btn')),
      );
      await tester.pump();
      expect(openedMaps, isTrue);
    });

    testWidgets(
        'ChatPage memakai GPS nyata tanpa koordinat palsu Ciremai saat mengunci lalu menerima fix',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final backend = _FakeLocationBackend();
      addTearDown(backend.close);
      final locationService = SharedLocationService(backend: backend);
      addTearDown(locationService.dispose);

      final account = _TestAccount();
      addTearDown(account.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoDarkTheme,
          home: Scaffold(
            body: ChatPage(
              accountController: account,
              chatRepository: _EmptyChatRepo(),
              groupRepository: _EmptyGroupRepo(),
              locationService: locationService,
              downloadedPacksLoader: () async => const <MountainPack>[],
              initialOnline: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('group-card-g-gede')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('room-chat-menu-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('menu-last-location')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Sebelum GPS terkunci: tampil loading GPS dan TIDAK ada data/koordinat Ciremai.
      expect(
        find.byKey(const ValueKey<String>('last-location-gps-loading')),
        findsOneWidget,
      );
      expect(find.text('Kamu'), findsNothing);

      // Kirim fix GPS nyata di Jakarta (-6.2088, 106.8456, akurasi 8m).
      backend.controller.add(
        TrackPoint(
          lat: -6.2088,
          lon: 106.8456,
          timestampUtc: DateTime.now().toUtc(),
          accuracyM: 8.0,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('last-location-gps-loading')),
        findsNothing,
      );
      expect(find.text('Kamu'), findsOneWidget);
      expect(find.text('Akurasi 8 m'), findsOneWidget);
    });
  });
}
