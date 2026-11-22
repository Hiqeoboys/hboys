import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/widgets/hiqeo_back_button.dart';
import 'package:nama_app/design/widgets/nav_bar_visibility.dart';
import 'package:nama_app/design/widgets/persistent_avatar_image.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/chat/domain/chat_message.dart';
import 'package:nama_app/features/chat/domain/chat_repository.dart';
import 'package:nama_app/features/chat/domain/media_attachment.dart';
import 'package:nama_app/features/chat/presentation/chat_page.dart';
import 'package:nama_app/features/chat/presentation/chat_room_chrome.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/groups/domain/group_repository.dart';
import 'package:nama_app/features/preparation/application/packing_list_store.dart';
import 'package:nama_app/features/shell/hiqeo_shell.dart';
import 'package:nama_app/features/social/data/community_service.dart';
import 'package:nama_app/features/social/presentation/community_chat_page.dart';
import 'package:nama_app/features/tracking/application/tracking_runtime.dart';
import 'package:nama_app/infrastructure/notifications/fcm_notification_service.dart';
import 'package:nama_app/infrastructure/power/power_profile_controller.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/account_fakes.dart';

class _MemChatRepo implements ChatRepository {
  _MemChatRepo(this.messages);

  final List<ChatMessage> messages;

  @override
  Future<void> saveMessage(ChatMessage message) async => messages.add(message);

  @override
  Future<ChatMessage?> findMessage(String messageId) async => null;

  @override
  Future<List<ChatMessage>> recentMessages(
    String groupId, {
    int limit = 50,
    DateTime? beforeUtc,
  }) async =>
      messages;

  @override
  Stream<List<ChatMessage>> watchMessages(String groupId, {int limit = 50}) =>
      Stream<List<ChatMessage>>.value(List<ChatMessage>.of(messages));

  @override
  Future<int> nextSeq({
    required String groupId,
    required String authorId,
  }) async =>
      messages.length + 1;

  @override
  Future<void> saveMedia(MediaAttachment media) async {}

  @override
  Future<List<MediaAttachment>> mediaForMessage(String messageId) async =>
      const <MediaAttachment>[];
}

class _MemGroupRepo implements GroupRepository {
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

class _StubAccount extends AccountController {
  _StubAccount()
      : super(
          authService: FakeAuthService(
            currentUser: const AuthUser(id: 'user-b', displayName: 'Budi'),
          ),
          profileRepository: FakeProfileRepository(),
          keyDirectory: FakeKeyDirectory(),
          identity: FakeIdentity(Uint8List(32)),
        );

  @override
  void initialize() {}

  @override
  AuthUser? get user => const AuthUser(id: 'user-b', displayName: 'Budi');

  @override
  bool get groupsEnabled => true;

  @override
  List<RemoteGroup> get groups => <RemoteGroup>[
        RemoteGroup(
          group: Group(
            id: 'g-ciremai',
            name: 'Tim Ciremai',
            ownerId: 'user-a',
            mountain: 'Gunung Ciremai',
            createdAtUtc: DateTime.utc(2026, 11, 1),
          ),
          role: GroupRole.member,
        ),
      ];

  @override
  Future<List<MemberDirectoryEntry>> membersOf(String groupId) async =>
      <MemberDirectoryEntry>[
        MemberDirectoryEntry(
          userId: 'user-a',
          username: 'andi_leader',
          displayName: 'Andi',
          role: GroupRole.owner,
          publicKeyBase64: 'k1',
          joinedAtUtc: DateTime.utc(2026, 11, 1),
        ),
        MemberDirectoryEntry(
          userId: 'user-b',
          username: 'budi_hiker',
          displayName: 'Budi',
          role: GroupRole.member,
          publicKeyBase64: 'k2',
          joinedAtUtc: DateTime.utc(2026, 11, 1),
        ),
      ];
}

class _FixedBattery implements BatteryReader {
  const _FixedBattery();
  @override
  Future<int> levelPercent() async => 80;
  @override
  Future<bool> isCharging() async => false;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    NavBarVisibilityController.instance.reset();
    FcmNotificationService.instance.activeRoomKey = null;
  });

  tearDown(() async {
    NavBarVisibilityController.instance.reset();
    await GroupHikePlanStore.instance.setPlan(null);
  });

  testWidgets(
      'Group Chat Room: pil header kaca, modal pengirim (Tambah Teman + Laporkan), dan tombol Siap anti-duplikasi',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const plan = GroupHikePlan(
      inviteId: 'inv-ciremai',
      groupId: 'g-ciremai',
      groupName: 'Tim Ciremai',
      mountainId: 'ciremai',
      mountainName: 'Gunung Ciremai',
      trailId: 'apuy',
      trailName: 'Via Apuy',
      organizerUserId: 'user-a',
      organizerName: 'Andi',
      readyUserIds: <String>{'user-a'},
      memberCount: 2,
    );
    final incomingText = ChatMessage(
      authorId: 'user-a',
      seq: 1,
      groupId: 'g-ciremai',
      type: PacketType.text,
      sentAtUtc: DateTime.utc(2026, 11, 20, 7, 0),
      receivedAtUtc: DateTime.utc(2026, 11, 20, 7, 0),
      payload: Uint8List.fromList(utf8.encode('Kumpul jam 5 ya!')),
    );
    final inviteMsg = ChatMessage(
      authorId: 'user-a',
      seq: 2,
      groupId: 'g-ciremai',
      type: PacketType.text,
      sentAtUtc: DateTime.utc(2026, 11, 20, 7, 1),
      receivedAtUtc: DateTime.utc(2026, 11, 20, 7, 1),
      payload: Uint8List.fromList(
        utf8.encode(GroupHikeInviteMessage.encodeInvite(plan)),
      ),
    );
    final repo = _MemChatRepo(<ChatMessage>[incomingText, inviteMsg]);
    final account = _StubAccount();
    addTearDown(account.dispose);

    final friendRequests = <String>[];
    final reports = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: Scaffold(
          body: ChatPage(
            accountController: account,
            chatRepository: repo,
            groupRepository: _MemGroupRepo(),
            initialOnline: true,
            onSendFriendRequest: (uid) async => friendRequests.add(uid),
            onSubmitMessageReport: ({
              required String groupId,
              required String messageId,
              required String reportedUserId,
              required String reason,
              String? details,
              String? excerpt,
            }) async {
              reports.add('$groupId:$messageId:$reportedUserId:$reason');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('group-card-g-ciremai')));
    await tester.pumpAndSettle();

    // 2.1 & 2.2: Pil header kaca melayang & tidak ada tombol Bagikan lokasi ke grup di chat room
    expect(
      find.byKey(const ValueKey<String>('room-chat-header-pill')),
      findsOneWidget,
    );
    expect(find.text('Bagikan lokasi ke grup'), findsNothing);
    expect(find.text('Kamu membagikan lokasi'), findsNothing);

    // 2.3: Ketuk nama pengirim -> modal dengan "Tambahkan teman" & "Laporkan pesan"
    await tester.tap(find.text('andi_leader').first);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('group-sender-action-sheet')),
      findsOneWidget,
    );
    expect(find.text('Tambahkan teman'), findsOneWidget);
    expect(find.text('Laporkan pesan'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('group-sender-add-friend')),
    );
    await tester.pumpAndSettle();
    expect(friendRequests, <String>['user-a']);

    // Ketuk avatar pengirim -> Laporkan pesan
    await tester.tap(
      find
          .descendant(
            of: find.byType(ChatSenderAvatarSlot),
            matching: find.byType(PersistentAvatarImage),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('group-sender-report-message')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('group-report-submit-btn')),
    );
    await tester.pumpAndSettle();
    expect(reports, hasLength(1));

    // 2.4: Ketuk tombol "Siap" -> memperbarui store & TIDAK mengirim pesan duplikat
    final msgCountBefore = repo.messages.length;
    await tester.tap(
      find.byKey(const ValueKey<String>('hike-invite-ready-inv-ciremai')),
    );
    await tester.pumpAndSettle();

    expect(GroupHikePlanStore.instance.activePlan?.mountainId, 'ciremai');
    expect(
      GroupHikePlanStore.instance.activePlan?.readyUserIds,
      containsAll(<String>['user-a', 'user-b']),
    );
    expect(find.text('Sudah Siap ✓'), findsOneWidget);
    expect(repo.messages.length, msgCountBefore);
  });

  testWidgets(
      'CommunityChatPage: tidak double keyboard inset & toast galat tampil di atas',
      (tester) async {
    tester.view.physicalSize = const Size(400, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final community = CommunitySummary(
      id: 'comm-1',
      name: 'Pendaki Nusantara',
      description: 'Diskusi gunung',
      ownerId: 'owner-1',
      memberCount: 12,
      isJoined: true,
      createdAt: DateTime.utc(2026, 11, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(400, 844),
            padding: EdgeInsets.only(top: 24, bottom: 20),
            viewInsets: EdgeInsets.only(bottom: 300),
          ),
          child: CommunityChatPage(
            community: community,
            initialMessages: const <CommunityMessage>[],
            hasFullSocialOverride: true,
            onSendText: (_) async => throw StateError('Jaringan terputus'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Back button seragam + header kaca melayang
    expect(find.byType(HiqeoBackButton), findsOneWidget);
    expect(find.byKey(const ValueKey('community-glass-header')), findsOneWidget);

    // Posisi composer hanya 1x inset keyboard (300 + 10 = 310), tidak 600+
    final pos = tester.widget<Positioned>(
      find.byKey(const ValueKey<String>('community-composer-position')),
    );
    expect(pos.bottom, 310.0);

    // Galat kirim pesan muncul sebagai toast melayang di bagian atas layar
    await tester.enterText(find.byKey(const ValueKey('community-input')), 'Halo');
    await tester.tap(find.byKey(const ValueKey('community-send-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final toastFinder = find.byKey(const ValueKey<String>('community-top-toast'));
    expect(toastFinder, findsOneWidget);
    expect(tester.getTopLeft(toastFinder).dy, lessThan(180));
  });

  testWidgets(
      'HiqeoShell menampilkan banner notifikasi FCM foreground dan menavigasi saat diketuk',
      (tester) async {
    tester.view.physicalSize = const Size(400, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final power = PowerProfileController(
      reader: const _FixedBattery(),
      manager: PowerProfileManager(),
    );
    await power.refresh();
    addTearDown(power.dispose);

    final router = GoRouter(
      initialLocation: '/beranda',
      routes: <RouteBase>[
        GoRoute(
          path: '/teman',
          builder: (_, __) => const Scaffold(body: Center(child: Text('Halaman Teman'))),
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => HiqeoShell(
            navigationShell: shell,
            powerController: power,
          ),
          branches: <StatefulShellBranch>[
            for (final path in const <String>[
              '/beranda',
              '/peta',
              '/lacak',
              '/grup',
              '/profil',
            ])
              StatefulShellBranch(
                routes: <RouteBase>[
                  GoRoute(
                    path: path,
                    builder: (_, __) => Scaffold(body: Center(child: Text(path))),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: hiqeoLightTheme, routerConfig: router),
    );
    await tester.pumpAndSettle();

    final notif = InAppPushNotification.fromRemoteData(
      title: 'Permintaan Pertemanan',
      body: 'Rani ingin berteman denganmu.',
      data: <String, dynamic>{'kind': 'friend_request', 'route': '/teman'},
    );
    FcmNotificationService.instance.emitForegroundForTesting(notif);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey<String>('in-app-fcm-banner')), findsNothing);
    expect(NavBarVisibilityController.instance.isHidden, isFalse);

    FcmNotificationService.instance.emitTapForTesting(notif);
    await tester.pumpAndSettle();
    expect(find.text('Halaman Teman'), findsOneWidget);
    expect(NavBarVisibilityController.instance.isHidden, isFalse);
  });
}
