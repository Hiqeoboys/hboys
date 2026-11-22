import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/widgets/nav_bar_visibility.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/chat/domain/chat_message.dart';
import 'package:nama_app/features/chat/domain/chat_repository.dart';
import 'package:nama_app/features/chat/domain/group_chat_models.dart';
import 'package:nama_app/features/chat/domain/media_attachment.dart';
import 'package:nama_app/features/chat/presentation/chat_page.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/groups/domain/group_repository.dart';
import 'package:nama_app/features/preparation/application/packing_list_store.dart';
import 'package:nama_app/features/social/data/chat_mute_service.dart';
import 'package:nama_app/features/social/data/community_service.dart';
import 'package:nama_app/features/social/data/social_unread_store.dart';
import 'package:nama_app/features/social/presentation/community_chat_page.dart';
import 'package:nama_app/infrastructure/offgrid/mesh_packet_codec.dart';
import 'package:nama_app/infrastructure/offgrid/mesh_router_service.dart';
import 'package:nama_app/infrastructure/offgrid/off_grid_chat_local_store.dart';
import 'package:nama_app/infrastructure/offgrid/off_grid_transport_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/account_fakes.dart';

class _MemChatRepo implements ChatRepository {
  _MemChatRepo([List<ChatMessage>? seed])
      : messages = List<ChatMessage>.of(seed ?? const <ChatMessage>[]);

  final List<ChatMessage> messages;
  final Map<String, StreamController<List<ChatMessage>>> _controllers =
      <String, StreamController<List<ChatMessage>>>{};

  @override
  Future<void> saveMessage(ChatMessage message) async {
    messages.add(message);
    _controllers[message.groupId]?.add(
      messages.where((m) => m.groupId == message.groupId).toList(growable: false),
    );
  }

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
  Stream<List<ChatMessage>> watchMessages(String groupId, {int limit = 50}) {
    final ctrl = _controllers.putIfAbsent(
      groupId,
      () => StreamController<List<ChatMessage>>.broadcast(),
    );
    return Stream<List<ChatMessage>>.multi((sink) {
      sink.add(messages.where((m) => m.groupId == groupId).toList(growable: false));
      final sub = ctrl.stream.listen(sink.add);
      sink.onCancel = sub.cancel;
    });
  }

  @override
  Future<int> nextSeq({
    required String groupId,
    required String authorId,
  }) async =>
      messages.where((m) => m.groupId == groupId && m.authorId == authorId).length + 1;

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
  _StubAccount({
    this.stubGroups = const <RemoteGroup>[],
    this.stubMembers = const <MemberDirectoryEntry>[],
  }) : super(
          authService: FakeAuthService(
            currentUser: const AuthUser(id: 'u-me', displayName: 'Aku'),
          ),
          profileRepository: FakeProfileRepository(),
          keyDirectory: FakeKeyDirectory(),
          identity: FakeIdentity(Uint8List(32)),
        );

  final List<RemoteGroup> stubGroups;
  final List<MemberDirectoryEntry> stubMembers;

  @override
  void initialize() {}

  @override
  AuthUser? get user => const AuthUser(id: 'u-me', displayName: 'Aku');

  @override
  List<RemoteGroup> get groups => stubGroups;

  @override
  int memberCountFor(String groupId) => stubMembers.length;

  @override
  Future<List<MemberDirectoryEntry>> membersOf(String groupId) async =>
      stubMembers;
}

RemoteGroup _group(String id, String name) => RemoteGroup(
      group: Group(
        id: id,
        name: name,
        ownerId: 'u-me',
        mountain: 'Gunung Merbabu',
        createdAtUtc: DateTime.utc(2026, 11, 20),
      ),
      role: GroupRole.owner,
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    NavBarVisibilityController.instance.reset();
    GroupHikePlanStore.setInstanceForTesting(GroupHikePlanStore());
    await ChatMuteService.instance.clearLocal();
  });

  tearDown(() async {
    NavBarVisibilityController.instance.reset();
    GroupHikePlanStore.setInstanceForTesting(null);
    await ChatMuteService.instance.clearLocal();
  });

  testWidgets('Kartu daftar grup menampilkan badge kesiapan hanya bila ada undangan aktif', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final account = _StubAccount();
    addTearDown(account.dispose);

    final cards = <GroupCardData>[
      GroupCardData(remote: _group('g-none', 'Grup Tanpa Undangan'), memberCount: 3),
      GroupCardData(
        remote: _group('g-zero', 'Grup 0 Siap'),
        memberCount: 4,
        hasActiveHikeInvite: true,
        readyCount: 0,
      ),
      GroupCardData(
        remote: _group('g-partial', 'Grup Sebagian Siap'),
        memberCount: 5,
        hasActiveHikeInvite: true,
        readyCount: 3,
      ),
      GroupCardData(
        remote: _group('g-all', 'Grup Semua Siap'),
        memberCount: 3,
        hasActiveHikeInvite: true,
        readyCount: 3,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: Scaffold(
          body: ChatPage(
            accountController: account,
            chatRepository: _MemChatRepo(),
            groupRepository: _MemGroupRepo(),
            initialLocalGroups: cards,
            initialOnline: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Grup Tanpa Undangan'), findsOneWidget);
    expect(find.text('Siap naik 1/2'), findsNothing);
    expect(find.text('Belum ada yang siap'), findsOneWidget);
    expect(find.text('Siap naik 3/5'), findsOneWidget);
    expect(find.text('Semua siap'), findsOneWidget);
  });

  testWidgets(
      'GroupChat: kirim offline via Mesh tidak diblokir, undang anggota dikunci saat offline, undangan dibatalkan, hapus pesan sendiri, unread divider & modal mute 4 opsi',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const plan = GroupHikePlan(
      inviteId: 'inv-cancel-1',
      groupId: 'g-room',
      groupName: 'Tim Merbabu',
      mountainId: 'merbabu',
      mountainName: 'Gunung Merbabu',
      organizerUserId: 'u-other',
      organizerName: 'Raka',
      readyUserIds: <String>{'u-other'},
      memberCount: 2,
    );
    GroupHikePlanStore.instance.markInviteCancelledLocally(
      'inv-cancel-1',
      groupId: 'g-room',
    );

    final t1 = DateTime.utc(2026, 11, 20, 8, 0);
    final t2 = DateTime.utc(2026, 11, 20, 8, 5);
    final t3 = DateTime.utc(2026, 11, 20, 8, 10);
    final msgRead = ChatMessage(
      authorId: 'u-me',
      seq: 1,
      groupId: 'g-room',
      type: PacketType.text,
      sentAtUtc: t1,
      receivedAtUtc: t1,
      payload: Uint8List.fromList(utf8.encode('Pesan lamaku')),
      isOutgoing: true,
    );
    final msgUnread1 = ChatMessage(
      authorId: 'u-other',
      seq: 2,
      groupId: 'g-room',
      type: PacketType.text,
      sentAtUtc: t2,
      receivedAtUtc: t2,
      payload: Uint8List.fromList(utf8.encode('Pesan baru 1')),
    );
    final msgUnreadInvite = ChatMessage(
      authorId: 'u-other',
      seq: 3,
      groupId: 'g-room',
      type: PacketType.text,
      sentAtUtc: t3,
      receivedAtUtc: t3,
      payload: Uint8List.fromList(
        utf8.encode(GroupHikeInviteMessage.encodeInvite(plan)),
      ),
    );

    await SocialUnreadStore.instance.markGroupRead(
      'g-room',
      at: t1,
      lastMessageId: msgRead.messageId,
    );

    final localStore = OffGridChatLocalStore();
    final meshRouter = MeshRouterService(
      adapter: InMemoryOffGridTransportAdapter(),
      codec: MeshPacketCodec(),
      localStore: localStore,
    );
    final repo = _MemChatRepo(<ChatMessage>[msgRead, msgUnread1, msgUnreadInvite]);
    final account = _StubAccount(
      stubGroups: <RemoteGroup>[_group('g-room', 'Tim Merbabu')],
      stubMembers: <MemberDirectoryEntry>[
        MemberDirectoryEntry(
          userId: 'u-me',
          username: 'aku',
          role: GroupRole.owner,
          publicKeyBase64: '',
          joinedAtUtc: t1,
        ),
        MemberDirectoryEntry(
          userId: 'u-other',
          username: 'raka',
          role: GroupRole.member,
          publicKeyBase64: '',
          joinedAtUtc: t1,
        ),
      ],
    );
    addTearDown(account.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: Scaffold(
          body: ChatPage(
            accountController: account,
            chatRepository: repo,
            groupRepository: _MemGroupRepo(),
            localStore: localStore,
            meshRouter: meshRouter,
            initialOnline: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('group-card-g-room')));
    await tester.pumpAndSettle();

    // 1. Unread divider tampil untuk 2 pesan baru
    expect(
      find.byKey(const ValueKey<String>('chat-unread-divider-pill')),
      findsOneWidget,
    );
    expect(find.text('2 pesan belum dibaca'), findsOneWidget);

    // 2. Undangan yang dibatalkan tampil dengan status "Undangan dibatalkan" tanpa tombol "Saya Siap"
    expect(
      find.byKey(const ValueKey<String>('hike-invite-cancelled-inv-cancel-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('hike-invite-ready-inv-cancel-1')),
      findsNothing,
    );
    expect(find.text('Saya Siap'), findsNothing);

    // 3. Offline via Mesh tidak memblokir kirim pesan
    await tester.enterText(
      find.byKey(const ValueKey<String>('chat-input')),
      'Pesan offline via Hiqeo Mesh',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('chat-send')));
    await tester.pumpAndSettle();
    expect(find.text('Pesan offline via Hiqeo Mesh'), findsOneWidget);

    // 4. Long-press pesan sendiri -> Hapus pesan -> konfirmasi -> "Pesan telah dihapus"
    await tester.longPress(find.text('Pesan offline via Hiqeo Mesh'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('group-msg-action-delete')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('group-msg-delete-confirm-btn')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pesan telah dihapus'), findsOneWidget);

    // 5. Menu Tambah anggota terkunci saat offline + Bisukan notifikasi 4 opsi
    await tester.tap(find.byKey(const ValueKey<String>('room-chat-menu-btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-add-member')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Fitur undang teman ke grup hanya bisa digunakan saat terhubung ke internet.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('room-chat-menu-btn')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('menu-mute-notifications')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mati'), findsOneWidget);
    expect(find.text('1 hari'), findsOneWidget);
    expect(find.text('1 minggu'), findsOneWidget);
    expect(find.text('Selamanya'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('mute-option-1d')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('chat-header-muted-icon')),
      findsOneWidget,
    );
  });

  testWidgets(
      'CommunityChat: header tanpa Online, info pembuat & tanggal penuh, mention @username anggota, swipe-to-reply, hapus pesan sendiri, unread divider, modal mute 4 opsi, & kompensasi keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final muteService = ChatMuteService();
    final t1 = DateTime.utc(2026, 11, 14, 7, 0);
    final t2 = DateTime.utc(2026, 11, 14, 7, 5);
    final t3 = DateTime.utc(2026, 11, 14, 7, 10);

    final community = CommunitySummary(
      id: 'comm-w2',
      name: 'Merbabu Hikers',
      description: 'Komunitas jalur Selo',
      ownerId: 'u-raka',
      createdBy: 'u-raka',
      creatorName: 'Raka Pratama',
      creatorUsername: 'raka_mount',
      memberCount: 48,
      isJoined: true,
      createdAt: DateTime(2026, 11, 14),
    );
    final members = <CommunityMemberEntry>[
      CommunityMemberEntry(
        userId: 'u-me',
        username: 'saya',
        fullName: 'Saya Sendiri',
        role: 'member',
        joinedAt: t1,
      ),
      CommunityMemberEntry(
        userId: 'u-raka',
        username: 'raka_mount',
        fullName: 'Raka Pratama',
        role: 'admin',
        joinedAt: t1,
      ),
      CommunityMemberEntry(
        userId: 'u-sari',
        username: 'sari_id',
        fullName: 'Sari Dewi',
        role: 'member',
        joinedAt: t1,
      ),
    ];
    final messages = <CommunityMessage>[
      CommunityMessage(
        id: 'cm-1',
        communityId: 'comm-w2',
        senderId: 'u-me',
        senderName: 'Saya Sendiri',
        messageType: CommunityMessageType.text,
        content: 'Pesan lamaku untuk dihapus',
        createdAt: t1,
      ),
      CommunityMessage(
        id: 'cm-2',
        communityId: 'comm-w2',
        senderId: 'u-raka',
        senderName: 'Raka Pratama',
        messageType: CommunityMessageType.text,
        content: 'Cuaca cerah hari ini!',
        createdAt: t2,
      ),
      CommunityMessage(
        id: 'cm-3',
        communityId: 'comm-w2',
        senderId: 'u-sari',
        senderName: 'Sari Dewi',
        messageType: CommunityMessageType.text,
        content: 'Siap nanjak bareng @raka_mount!',
        createdAt: t3,
      ),
    ];

    await SocialUnreadStore.instance.markCommunityRead(
      'comm-w2',
      at: t1,
      lastMessageId: 'cm-1',
    );

    ({String text, String? replyTo, List<String> mentions})? sentMeta;
    String? deletedMsgId;

    Widget buildRoom({double keyboardBottom = 0.0}) => MaterialApp(
          theme: hiqeoDarkTheme,
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              viewInsets: EdgeInsets.only(bottom: keyboardBottom),
            ),
            child: CommunityChatPage(
              community: community,
              initialMessages: messages,
              initialMembers: members,
              hasFullSocialOverride: true,
              currentUserIdOverride: 'u-me',
              muteService: muteService,
              onSendTextWithMeta: ({
                required text,
                replyToMessageId,
                mentionedUserIds = const <String>[],
              }) async {
                sentMeta = (
                  text: text,
                  replyTo: replyToMessageId,
                  mentions: mentionedUserIds,
                );
              },
              onDeleteMessage: (id) async {
                deletedMsgId = id;
              },
            ),
          ),
        );

    await tester.pumpWidget(buildRoom());
    await tester.pumpAndSettle();

    // 1. Header tanpa "Online"/"Offline" + unread divider "2 pesan belum dibaca"
    expect(find.text('48 anggota'), findsOneWidget);
    expect(find.textContaining('Online'), findsNothing);
    expect(find.text('2 pesan belum dibaca'), findsOneWidget);

    // 2. Community Info menampilkan pembuat + @username + tanggal penuh Indonesia
    await tester.tap(find.byKey(const ValueKey<String>('community-header-info-btn')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Raka Pratama (@raka_mount)'), findsOneWidget);
    expect(find.textContaining('14 November 2026'), findsOneWidget);
    Navigator.of(tester.element(find.byKey(const ValueKey<String>('community-info-sheet')))).pop();
    await tester.pumpAndSettle();

    // 3. Swipe-to-reply pada pesan cm-2
    await tester.drag(
      find.byKey(const ValueKey<String>('community-bubble-cm-2')),
      const Offset(90, 0),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('community-reply-preview-bar')),
      findsOneWidget,
    );
    expect(find.text('Membalas Raka Pratama'), findsOneWidget);

    // 4. Mention @rak -> popup anggota tergabung saja, ketuk item, lalu kirim
    await tester.enterText(
      find.byKey(const ValueKey<String>('community-input')),
      'Siap ikut @rak',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('community-mention-suggestions')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('community-mention-item-raka_mount')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('community-mention-item-sari_id')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('community-mention-item-raka_mount')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('community-send-button')));
    await tester.pumpAndSettle();

    expect(sentMeta?.text, 'Siap ikut @raka_mount');
    expect(sentMeta?.replyTo, 'cm-2');
    expect(sentMeta?.mentions, <String>['u-raka']);

    // 5. Hapus pesan sendiri -> "Pesan telah dihapus"
    await tester.longPress(
      find.byKey(const ValueKey<String>('community-bubble-cm-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('community-msg-action-delete')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('community-msg-delete-confirm-btn')),
    );
    await tester.pumpAndSettle();
    expect(deletedMsgId, 'cm-1');
    expect(find.text('Pesan telah dihapus'), findsOneWidget);

    // 6. Keyboard muncul -> pesan terbaru tidak tertutup oleh bilah input
    await tester.pumpWidget(buildRoom(keyboardBottom: 300));
    await tester.pumpAndSettle();
    final composerRect = tester.getRect(
      find.byKey(const ValueKey<String>('community-composer-position')),
    );
    final lastBubbleRect = tester.getRect(
      find.byKey(const ValueKey<String>('community-bubble-cm-3')),
    );
    expect(lastBubbleRect.bottom, lessThanOrEqualTo(composerRect.top + 2));

    // 7. Modal Mute 4 opsi -> Selamanya -> ikon lonceng dicoret muncul di header
    await tester.pumpWidget(buildRoom(keyboardBottom: 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('community-hamburger-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('community-menu-mute')));
    await tester.pumpAndSettle();
    expect(find.text('Mati'), findsOneWidget);
    expect(find.text('1 hari'), findsOneWidget);
    expect(find.text('1 minggu'), findsOneWidget);
    expect(find.text('Selamanya'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('mute-option-forever')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('chat-header-muted-icon')),
      findsOneWidget,
    );
  });
}
