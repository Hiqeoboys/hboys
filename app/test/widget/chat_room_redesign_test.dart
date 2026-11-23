import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/glass/hiqeo_liquid_glass.dart';
import 'package:nama_app/design/widgets/nav_bar_visibility.dart';
import 'package:nama_app/design/widgets/persistent_avatar_image.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/chat/domain/chat_message.dart';
import 'package:nama_app/features/chat/domain/chat_repository.dart';
import 'package:nama_app/features/chat/domain/media_attachment.dart';
import 'package:nama_app/features/chat/presentation/chat_page.dart';
import 'package:nama_app/features/chat/presentation/chat_room_chrome.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/groups/domain/group_repository.dart';
import 'package:nama_app/features/preparation/application/packing_list_store.dart';
import 'package:nama_app/features/social/data/community_service.dart';
import 'package:nama_app/features/social/presentation/community_chat_page.dart';
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
      messages.where((m) => m.groupId == groupId).toList(growable: false);

  @override
  Stream<List<ChatMessage>> watchMessages(String groupId, {int limit = 50}) =>
      Stream<List<ChatMessage>>.value(
        messages.where((m) => m.groupId == groupId).toList(growable: false),
      );

  @override
  Future<int> nextSeq(
          {required String groupId, required String authorId}) async =>
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
            currentUser: const AuthUser(id: 'me-1', displayName: 'Budi'),
          ),
          profileRepository: FakeProfileRepository(),
          keyDirectory: FakeKeyDirectory(),
          identity: FakeIdentity(Uint8List(32)),
        );

  @override
  void initialize() {}

  @override
  AuthUser? get user => const AuthUser(id: 'me-1', displayName: 'Budi');

  @override
  UserProfile? get profile => const UserProfile(
        userId: 'me-1',
        username: 'budi_hiker',
        fullName: 'Budi',
        publicKeyBase64: 'pk',
      );

  @override
  List<RemoteGroup> get groups => <RemoteGroup>[
        RemoteGroup(
          group: Group(
            id: 'g-rinjani',
            name: 'Ekspedisi Rinjani 2026',
            ownerId: 'other-1',
            mountain: 'Gunung Rinjani',
            createdAtUtc: DateTime.utc(2026, 11, 1),
          ),
          role: GroupRole.member,
        ),
      ];

  @override
  Future<List<MemberDirectoryEntry>> membersOf(String groupId) async =>
      <MemberDirectoryEntry>[
        MemberDirectoryEntry(
          userId: 'other-1',
          username: 'raka_guide',
          displayName: 'Raka',
          role: GroupRole.owner,
          publicKeyBase64: 'k1',
          joinedAtUtc: DateTime.utc(2026, 11, 1),
        ),
        MemberDirectoryEntry(
          userId: 'me-1',
          username: 'budi_hiker',
          displayName: 'Budi',
          role: GroupRole.member,
          publicKeyBase64: 'k2',
          joinedAtUtc: DateTime.utc(2026, 11, 1),
        ),
      ];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    NavBarVisibilityController.instance.reset();
  });

  tearDown(() async {
    NavBarVisibilityController.instance.reset();
    await GroupHikePlanStore.instance.setPlan(null);
  });

  testWidgets(
      'CommunityChatPage: latar #242B40 topografi, bubble pendek tidak melar, smart grouping, foto 14px + pil waktu, & dropdown kanan-atas >=12px dari header',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final community = CommunitySummary(
      id: 'comm-redesign',
      name: 'Komunitas Pendaki Gunung Nusantara',
      description: 'Sharing jalur & kondisi cuaca',
      ownerId: 'owner-99',
      memberCount: 48,
      isJoined: true,
      createdAt: DateTime.utc(2026, 11, 1),
    );

    final messages = <CommunityMessage>[
      CommunityMessage(
        id: 'm1',
        communityId: community.id,
        senderId: 'user-raka',
        senderName: 'Raka',
        messageType: CommunityMessageType.text,
        content: 'Pagi teman-teman!',
        createdAt: DateTime.utc(2026, 11, 20, 7, 0),
      ),
      CommunityMessage(
        id: 'm2',
        communityId: community.id,
        senderId: 'user-raka',
        senderName: 'Raka',
        messageType: CommunityMessageType.text,
        content: 'Cuaca basecamp cerah banget',
        createdAt: DateTime.utc(2026, 11, 20, 7, 1),
      ),
      CommunityMessage(
        id: 'm3',
        communityId: community.id,
        senderId: 'user-raka',
        senderName: 'Raka',
        messageType: CommunityMessageType.text,
        content: 'Siap berangkat jam 8 ya',
        createdAt: DateTime.utc(2026, 11, 20, 7, 2),
      ),
      CommunityMessage(
        id: 'm4',
        communityId: community.id,
        senderId: 'me-1',
        senderName: 'Budi',
        messageType: CommunityMessageType.text,
        content: 'woi',
        createdAt: DateTime.utc(2026, 11, 20, 7, 3),
      ),
      CommunityMessage(
        id: 'm5',
        communityId: community.id,
        senderId: 'user-sari',
        senderName: 'Sari',
        messageType: CommunityMessageType.image,
        mediaUrl: 'https://example.com/sunrise.webp',
        content: 'Sunrise dari Pos 3!',
        createdAt: DateTime.utc(2026, 11, 20, 7, 4),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 24, bottom: 20),
          ),
          child: CommunityChatPage(
            community: community,
            initialMessages: messages,
            hasFullSocialOverride: true,
            currentUserIdOverride: 'me-1',
            onSendText: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Kanvas gelap #242B40 + kontur topografi
    final canvas = tester.widget<ColoredBox>(
      find.byKey(const ValueKey<String>('chat-room-canvas')),
    );
    expect(canvas.color, const Color(0xFF242B40));
    expect(
      find.byKey(const ValueKey<String>('chat-room-topo-bg')),
      findsOneWidget,
    );

    // 2. Header pill + lencana Komunitas + ikon hamburger seragam (tanpa Online/Offline)
    expect(find.text('Komunitas'), findsOneWidget);
    expect(find.text('48 anggota'), findsOneWidget);
    expect(find.textContaining('Online'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('community-hamburger-button')),
        matching: find.byIcon(Icons.menu_rounded),
      ),
      findsOneWidget,
    );

    // 3. Bubble keluar pendek ("woi") memakai lebar alami (TIDAK melar!) & warna #F2EFE9
    final shortBubbleFinder =
        find.byKey(const ValueKey<String>('community-bubble-m4'));
    expect(shortBubbleFinder, findsOneWidget);
    final shortBubbleSize = tester.getSize(shortBubbleFinder);
    expect(shortBubbleSize.width, lessThan(390 * 0.45));
    final shortDec = tester.widget<DecoratedBox>(shortBubbleFinder).decoration
        as BoxDecoration;
    expect(shortDec.color, const Color(0xFFF2EFE9));
    expect(
      shortDec.borderRadius,
      const BorderRadius.only(
        topLeft: Radius.circular(18),
        topRight: Radius.circular(18),
        bottomLeft: Radius.circular(18),
        bottomRight: Radius.circular(5),
      ),
    );

    // 4. Smart Grouping: 3 pesan berurutan dari Raka -> nama SEKALI (atas), avatar SEKALI (bawah), jarak rapat
    expect(find.text('Raka'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('community-msg-sender-m1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('community-msg-sender-m2')),
        findsNothing);
    expect(find.byKey(const ValueKey<String>('community-msg-sender-m3')),
        findsNothing);
    expect(find.byKey(const ValueKey<String>('community-msg-avatar-m1')),
        findsNothing);
    expect(find.byKey(const ValueKey<String>('community-msg-avatar-m2')),
        findsNothing);
    expect(find.byKey(const ValueKey<String>('community-msg-avatar-m3')),
        findsOneWidget);

    final m1Bottom = tester
        .getBottomLeft(
            find.byKey(const ValueKey<String>('community-bubble-m1')))
        .dy;
    final m2Top = tester
        .getTopLeft(find.byKey(const ValueKey<String>('community-bubble-m2')))
        .dy;
    expect(m2Top - m1Bottom, closeTo(3.5, 1.0));

    // 5. Pesan foto bercaption: sudut atas membulat penuh, caption rapi di bawah, waktu di baris teks (tanpa badge sudut media)
    final photoFrame = tester.widget<ClipRRect>(
      find.byKey(const ValueKey<String>('community-photo-frame-m5')),
    );
    expect(
      photoFrame.borderRadius,
      const BorderRadius.vertical(
        top: Radius.circular(14),
        bottom: Radius.circular(4),
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('community-photo-time-m5')),
      findsNothing,
    );
    expect(find.text('Sunrise dari Pos 3!'), findsOneWidget);

    // 6. Menu dropdown hamburger di KANAN ATAS (bukan bottom sheet) dengan jarak >= 12 px di bawah header
    await tester.tap(find.byKey(const ValueKey('community-hamburger-button')));
    await tester.pumpAndSettle();

    final headerBarRect = tester.getRect(find.byType(ChatRoomHeaderBar));
    final dropdownFinder =
        find.byKey(const ValueKey<String>('community-dropdown-menu'));
    expect(dropdownFinder, findsOneWidget);
    final dropdownRect = tester.getRect(dropdownFinder);
    expect(dropdownRect.top - headerBarRect.bottom, greaterThanOrEqualTo(12.0));
    expect(dropdownRect.right, closeTo(390 - 14, 1.5));
    expect(dropdownRect.width, closeTo(ChatRoomDropdownMenu.width, 1.0));
    final dropdownGlass =
        tester.widget<HiqeoLiquidGlassSurface>(dropdownFinder);
    expect(dropdownGlass.borderRadius, ChatRoomDropdownMenu.borderRadius);
    expect(find.byKey(const ValueKey('community-menu-leave')), findsOneWidget);
  });

  testWidgets(
      'Group Chat Room: latar #242B40 topografi, header E2EE + ikon hamburger seragam, smart grouping, kartu Ajakan Pendakian + progress bar & tombol Saya Siap, dropdown >=12px',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const plan = GroupHikePlan(
      inviteId: 'inv-rinjani',
      groupId: 'g-rinjani',
      groupName: 'Ekspedisi Rinjani 2026',
      mountainId: 'rinjani',
      mountainName: 'Gunung Rinjani',
      trailId: 'sembalun',
      trailName: 'Via Sembalun',
      organizerUserId: 'other-1',
      organizerName: 'Raka',
      readyUserIds: <String>{'other-1'},
      memberCount: 2,
    );

    final repo = _MemChatRepo(<ChatMessage>[
      ChatMessage(
        authorId: 'other-1',
        seq: 1,
        groupId: 'g-rinjani',
        type: PacketType.text,
        sentAtUtc: DateTime.utc(2026, 11, 20, 8, 0),
        receivedAtUtc: DateTime.utc(2026, 11, 20, 8, 0),
        payload: Uint8List.fromList(utf8.encode('Halo tim!')),
      ),
      ChatMessage(
        authorId: 'other-1',
        seq: 2,
        groupId: 'g-rinjani',
        type: PacketType.text,
        sentAtUtc: DateTime.utc(2026, 11, 20, 8, 1),
        receivedAtUtc: DateTime.utc(2026, 11, 20, 8, 1),
        payload:
            Uint8List.fromList(utf8.encode('Cek logistik masing-masing ya')),
      ),
      ChatMessage(
        authorId: 'me-1',
        seq: 3,
        groupId: 'g-rinjani',
        type: PacketType.text,
        sentAtUtc: DateTime.utc(2026, 11, 20, 8, 2),
        receivedAtUtc: DateTime.utc(2026, 11, 20, 8, 2),
        payload: Uint8List.fromList(utf8.encode('Hai')),
        isOutgoing: true,
      ),
      ChatMessage(
        authorId: 'other-1',
        seq: 4,
        groupId: 'g-rinjani',
        type: PacketType.text,
        sentAtUtc: DateTime.utc(2026, 11, 20, 8, 3),
        receivedAtUtc: DateTime.utc(2026, 11, 20, 8, 3),
        payload: Uint8List.fromList(
          utf8.encode(GroupHikeInviteMessage.encodeInvite(plan)),
        ),
      ),
    ]);
    final account = _StubAccount();
    addTearDown(account.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 900),
            padding: EdgeInsets.only(top: 24, bottom: 20),
          ),
          child: Scaffold(
            body: ChatPage(
              accountController: account,
              chatRepository: repo,
              groupRepository: _MemGroupRepo(),
              initialOnline: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey<String>('group-card-g-rinjani')));
    await tester.pumpAndSettle();

    // 1. Kanvas gelap #242B40 + topografi + lencana E2EE + ikon menu_rounded seragam
    final canvas = tester.widget<ColoredBox>(
      find.byKey(const ValueKey<String>('chat-room-canvas')),
    );
    expect(canvas.color, const Color(0xFF242B40));
    expect(find.text('Terenkripsi'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('room-chat-menu-btn')),
        matching: find.byIcon(Icons.menu_rounded),
      ),
      findsOneWidget,
    );

    // 2. Smart Grouping pada 2 pesan berurutan Raka -> nama SEKALI (atas), avatar SEKALI di akhir klaster
    expect(find.text('raka_guide'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ChatSenderAvatarSlot),
        matching: find.byType(PersistentAvatarImage),
      ),
      findsNWidgets(2),
    );
    final avatarSlots = tester
        .widgetList<ChatSenderAvatarSlot>(find.byType(ChatSenderAvatarSlot))
        .toList();
    expect(
        avatarSlots.map((s) => s.visible).toList(), <bool>[false, true, true]);
    final firstRakaBubble = find
        .ancestor(
          of: find.text('Halo tim!'),
          matching: find.byType(DecoratedBox),
        )
        .first;
    final secondRakaBubble = find
        .ancestor(
          of: find.text('Cek logistik masing-masing ya'),
          matching: find.byType(DecoratedBox),
        )
        .first;
    final rakaGap = tester.getTopLeft(secondRakaBubble).dy -
        tester.getBottomLeft(firstRakaBubble).dy;
    expect(rakaGap, closeTo(3.5, 1.0));

    // 3. Bubble keluar pendek ("Hai") memakai lebar alami (tidak melar) & warna #F2EFE9
    final outgoingBubble = find
        .ancestor(
          of: find.text('Hai'),
          matching: find.byType(DecoratedBox),
        )
        .first;
    expect(outgoingBubble, findsOneWidget);
    expect(tester.getSize(outgoingBubble).width, lessThan(390 * 0.45));
    final dec =
        tester.widget<DecoratedBox>(outgoingBubble).decoration as BoxDecoration;
    expect(dec.color, const Color(0xFFF2EFE9));

    // 4. Kartu Ajakan Pendakian modern: progress bar kesiapan + tombol "Saya Siap" -> "Sudah Siap ✓"
    final progressFinder =
        find.byKey(const ValueKey<String>('hike-invite-progress-inv-rinjani'));
    expect(progressFinder, findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(progressFinder).value,
        closeTo(0.5, 0.01));
    expect(find.text('Saya Siap'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('hike-invite-ready-inv-rinjani')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sudah Siap ✓'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(progressFinder).value,
        closeTo(1.0, 0.01));

    // 5. Menu dropdown kanan atas dengan jarak >= 12 px dari header & lebar seragam
    await tester.tap(find.byKey(const ValueKey<String>('room-chat-menu-btn')));
    await tester.pumpAndSettle();

    final headerBarRect = tester.getRect(find.byType(ChatRoomHeaderBar));
    final dropdownFinder =
        find.byKey(const ValueKey<String>('room-chat-dropdown'));
    expect(dropdownFinder, findsOneWidget);
    final dropdownRect = tester.getRect(dropdownFinder);
    expect(dropdownRect.top - headerBarRect.bottom, greaterThanOrEqualTo(12.0));
    expect(dropdownRect.width, closeTo(ChatRoomDropdownMenu.width, 1.0));
  });
}
