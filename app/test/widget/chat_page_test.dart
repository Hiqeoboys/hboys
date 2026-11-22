import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/widgets/nav_bar_visibility.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/chat/domain/chat_message.dart';
import 'package:nama_app/features/chat/domain/chat_repository.dart';
import 'package:nama_app/features/chat/domain/group_chat_models.dart';
import 'package:nama_app/features/chat/domain/group_chat_remote_service.dart';
import 'package:nama_app/features/chat/domain/media_attachment.dart';
import 'package:nama_app/features/chat/presentation/chat_page.dart';
import 'package:nama_app/features/chat/presentation/last_location_view.dart';
import 'package:nama_app/features/groups/application/group_selection.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/groups/domain/group_repository.dart';
import 'package:nama_app/features/safety/domain/payloads.dart';

import '../support/account_fakes.dart';

class _FakeChatRepository implements ChatRepository {
  final List<ChatMessage> messages = <ChatMessage>[];
  final Map<String, StreamController<List<ChatMessage>>> _controllers =
      <String, StreamController<List<ChatMessage>>>{};

  List<ChatMessage> _snapshot(String groupId) =>
      messages.where((m) => m.groupId == groupId).toList(growable: false)
        ..sort((a, b) => a.sentAtUtc.compareTo(b.sentAtUtc));

  StreamController<List<ChatMessage>> _controllerFor(String groupId) =>
      _controllers.putIfAbsent(
        groupId,
        () => StreamController<List<ChatMessage>>.broadcast(),
      );

  @override
  Future<void> saveMessage(ChatMessage message) async {
    messages.add(message);
    _controllerFor(message.groupId).add(_snapshot(message.groupId));
  }

  @override
  Future<ChatMessage?> findMessage(String messageId) async {
    for (final message in messages) {
      if (message.messageId == messageId) return message;
    }
    return null;
  }

  @override
  Future<List<ChatMessage>> recentMessages(
    String groupId, {
    int limit = 50,
    DateTime? beforeUtc,
  }) async {
    final snapshot = _snapshot(groupId)
        .where((m) => beforeUtc == null || m.sentAtUtc.isBefore(beforeUtc))
        .toList(growable: false);
    return snapshot.length <= limit
        ? snapshot
        : snapshot.sublist(snapshot.length - limit);
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String groupId,
      {int limit = 50}) async* {
    yield _snapshot(groupId);
    yield* _controllerFor(groupId).stream;
  }

  @override
  Future<int> nextSeq({
    required String groupId,
    required String authorId,
  }) async {
    var max = 0;
    for (final message in messages) {
      if (message.groupId == groupId && message.authorId == authorId) {
        if (message.seq > max) max = message.seq;
      }
    }
    return max + 1;
  }

  @override
  Future<void> saveMedia(MediaAttachment media) async {}

  @override
  Future<List<MediaAttachment>> mediaForMessage(String messageId) async =>
      const <MediaAttachment>[];
}

class _FakeGroupRepository implements GroupRepository {
  final List<Group> groups = <Group>[];
  final List<GroupMember> members = <GroupMember>[];
  final StreamController<List<Group>> _groupsCtrl =
      StreamController<List<Group>>.broadcast();
  final StreamController<List<GroupMember>> _membersCtrl =
      StreamController<List<GroupMember>>.broadcast();

  @override
  Future<void> saveGroup(Group group) async {
    groups.removeWhere((g) => g.id == group.id);
    groups.add(group);
    _groupsCtrl.add(List<Group>.unmodifiable(groups));
  }

  @override
  Future<Group?> findGroup(String id) async {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  @override
  Stream<List<Group>> watchGroups() async* {
    yield List<Group>.unmodifiable(groups);
    yield* _groupsCtrl.stream;
  }

  @override
  Future<void> deleteGroup(String id) async {
    groups.removeWhere((g) => g.id == id);
    members.removeWhere((m) => m.groupId == id);
    _groupsCtrl.add(List<Group>.unmodifiable(groups));
  }

  @override
  Future<void> saveMember(GroupMember member) async {
    members.removeWhere(
      (m) => m.groupId == member.groupId && m.userId == member.userId,
    );
    members.add(member);
    _membersCtrl.add(
      members.where((m) => m.groupId == member.groupId).toList(growable: false),
    );
  }

  @override
  Future<List<GroupMember>> membersOf(String groupId) async =>
      members.where((m) => m.groupId == groupId).toList(growable: false);

  @override
  Stream<List<GroupMember>> watchMembers(String groupId) async* {
    yield await membersOf(groupId);
    yield* _membersCtrl.stream.map(
      (all) => all.where((m) => m.groupId == groupId).toList(growable: false),
    );
  }

  @override
  Future<void> removeMember(String groupId, String userId) async {
    members.removeWhere((m) => m.groupId == groupId && m.userId == userId);
  }
}

RemoteGroup _remoteGroup(
  String id,
  String name,
  DateTime createdAtUtc, {
  String mountain = 'Gunung Gede',
}) =>
    RemoteGroup(
      group: Group(
        id: id,
        name: name,
        ownerId: 'user-1',
        mountain: mountain,
        createdAtUtc: createdAtUtc,
      ),
      role: GroupRole.owner,
    );

MemberDirectoryEntry _member(String id, String username) =>
    MemberDirectoryEntry(
      userId: id,
      username: username,
      role: id == 'user-1' ? GroupRole.owner : GroupRole.member,
      publicKeyBase64: 'kunci',
      joinedAtUtc: DateTime.utc(2026, 10, 20),
    );

class _FixedAccount extends AccountController {
  _FixedAccount({
    required List<RemoteGroup> fixedGroups,
    required List<MemberDirectoryEntry> fixedMembers,
    List<IncomingInvitation> fixedInvitations = const <IncomingInvitation>[],
  })  : fixedGroups = List<RemoteGroup>.of(fixedGroups),
        fixedMembers = List<MemberDirectoryEntry>.of(fixedMembers),
        fixedInvitations = List<IncomingInvitation>.of(fixedInvitations),
        super(
          authService: FakeAuthService(
            currentUser: const AuthUser(id: 'user-1', displayName: 'Dimas'),
          ),
          profileRepository: FakeProfileRepository(),
          keyDirectory: FakeKeyDirectory(),
          identity: FakeIdentity(Uint8List(32)),
        );

  final List<RemoteGroup> fixedGroups;
  final List<MemberDirectoryEntry> fixedMembers;
  final List<IncomingInvitation> fixedInvitations;
  bool membersFail = false;

  @override
  void initialize() {}

  @override
  AuthUser? get user => const AuthUser(id: 'user-1', displayName: 'Dimas');

  @override
  bool get isLoading => false;

  @override
  bool get groupsEnabled => true;

  @override
  List<RemoteGroup> get groups => List<RemoteGroup>.unmodifiable(fixedGroups);

  @override
  List<IncomingInvitation> get invitations =>
      List<IncomingInvitation>.unmodifiable(fixedInvitations);

  @override
  Future<List<MemberDirectoryEntry>> membersOf(String groupId) async {
    if (membersFail) throw StateError('jaringan mati');
    return List<MemberDirectoryEntry>.unmodifiable(fixedMembers);
  }

  @override
  Future<bool> createGroup(String name, {String? mountain}) async {
    final now = DateTime.utc(2026, 10, 26, 10);
    fixedGroups.add(
      _remoteGroup(
        'grup-${fixedGroups.length + 1}',
        name,
        now,
        mountain: mountain ?? 'Gunung Ciremai',
      ),
    );
    notifyListeners();
    return true;
  }

  @override
  Future<void> respondToInvitation(
    IncomingInvitation invitation, {
    required bool accept,
  }) async {
    fixedInvitations.removeWhere((i) => i.id == invitation.id);
    if (accept) {
      fixedGroups.add(
        _remoteGroup(
          invitation.groupId,
          invitation.groupName,
          invitation.createdAtUtc,
        ),
      );
    }
    notifyListeners();
  }

  @override
  Future<bool> invite({
    required String groupId,
    required String username,
  }) async {
    fixedMembers.add(_member('anggota-$username', username));
    notifyListeners();
    return true;
  }
}

void _setTallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<({_FakeChatRepository chat, _FakeGroupRepository group})> _pump(
  WidgetTester tester,
  AccountController account, {
  _FakeChatRepository? chatRepository,
  _FakeGroupRepository? groupRepository,
  bool? initialOnline = true,
  List<IncomingInvitation>? initialInvitations,
  List<GroupCardData>? initialLocalGroups,
}) async {
  _setTallPhone(tester);
  final chatRepo = chatRepository ?? _FakeChatRepository();
  final groupRepo = groupRepository ?? _FakeGroupRepository();
  await tester.pumpWidget(
    MaterialApp(
      theme: hiqeoLightTheme,
      home: Scaffold(
        body: ChatPage(
          accountController: account,
          chatRepository: chatRepo,
          groupRepository: groupRepo,
          initialOnline: initialOnline,
          initialInvitations: initialInvitations,
          initialLocalGroups: initialLocalGroups,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (chat: chatRepo, group: groupRepo);
}

_FixedAccount _account({
  List<MemberDirectoryEntry>? members,
  List<IncomingInvitation> invitations = const <IncomingInvitation>[],
}) =>
    _FixedAccount(
      fixedGroups: <RemoteGroup>[
        _remoteGroup('g1', 'Rombongan Lama', DateTime.utc(2026, 10, 10)),
        _remoteGroup('g2', 'Pendakian Tersesat', DateTime.utc(2026, 10, 20),
            mountain: 'Gunung Kembar'),
      ],
      fixedMembers: members ??
          <MemberDirectoryEntry>[
            _member('user-1', 'dimas'),
            _member('user-2', 'sari'),
            _member('user-3', 'bayu'),
          ],
      fixedInvitations: invitations,
    );

ChatMessage _incomingText(String groupId, String text) => ChatMessage(
      authorId: 'user-3',
      seq: 1,
      groupId: groupId,
      type: PacketType.text,
      sentAtUtc: DateTime.utc(2026, 10, 25, 8),
      receivedAtUtc: DateTime.utc(2026, 10, 25, 8),
      payload: Uint8List.fromList(utf8.encode(text)),
    );

ChatMessage _incomingVoice(String groupId) => ChatMessage(
      authorId: 'user-2',
      seq: 2,
      groupId: groupId,
      type: PacketType.voiceFragment,
      sentAtUtc: DateTime.utc(2026, 10, 25, 8, 5),
      receivedAtUtc: DateTime.utc(2026, 10, 25, 8, 5),
      payload: const VoiceNoteData(
        durationSeconds: 12,
        peaks: VoiceNoteData.defaultPeaks,
      ).toBytes(),
    );

ChatMessage _incomingLocation(String groupId) => ChatMessage(
      authorId: 'user-3',
      seq: 3,
      groupId: groupId,
      type: PacketType.location,
      sentAtUtc: DateTime.utc(2026, 10, 25, 8, 10),
      receivedAtUtc: DateTime.utc(2026, 10, 25, 8, 10),
      payload: const LocationPayload(
        lat: -6.795,
        lon: 106.985,
        accuracyM: 12,
        batteryPercent: 45,
      ).toBytes(),
    );

class _FakeGroupChatRemoteService implements GroupChatRemoteService {
  final List<GroupMessageRecord> remoteMessages = <GroupMessageRecord>[];
  final List<MemberLastLocation> remoteLocations = <MemberLastLocation>[];
  final List<String> uploadedVoicePaths = <String>[];
  int syncOfflineMessagesCalls = 0;
  int syncOfflineLocationsCalls = 0;

  final StreamController<List<GroupMessageRecord>> _messagesCtrl =
      StreamController<List<GroupMessageRecord>>.broadcast();
  final StreamController<List<MemberLastLocation>> _locationsCtrl =
      StreamController<List<MemberLastLocation>>.broadcast();

  void emitMessages() {
    _messagesCtrl.add(List<GroupMessageRecord>.unmodifiable(remoteMessages));
  }

  void emitLocations() {
    _locationsCtrl.add(List<MemberLastLocation>.unmodifiable(remoteLocations));
  }

  @override
  Future<List<GroupMessageRecord>> fetchMessages(
    String groupId, {
    int limit = 50,
    DateTime? beforeCreatedAtUtc,
  }) async =>
      remoteMessages.where((m) => m.groupId == groupId).toList(growable: false);

  @override
  Stream<List<GroupMessageRecord>> watchMessages(String groupId) async* {
    yield await fetchMessages(groupId);
    yield* _messagesCtrl.stream.map(
      (all) => all.where((m) => m.groupId == groupId).toList(growable: false),
    );
  }

  @override
  Future<void> upsertMessage(GroupMessageRecord message) async {
    remoteMessages.removeWhere((m) => m.clientMsgId == message.clientMsgId);
    remoteMessages.add(message);
    emitMessages();
  }

  @override
  Future<int> syncOfflineMessages(List<GroupMessageRecord> messages) async {
    syncOfflineMessagesCalls++;
    for (final m in messages) {
      remoteMessages.removeWhere((e) => e.clientMsgId == m.clientMsgId);
      remoteMessages.add(m);
    }
    emitMessages();
    return messages.length;
  }

  @override
  Future<void> softDeleteMessage({
    required String groupId,
    required String clientMsgId,
  }) async {}

  @override
  Future<void> cancelHikeInviteMessage({
    required String groupId,
    required String clientMsgId,
  }) async {}

  @override
  Future<String> uploadVoiceNote({
    required String groupId,
    required String clientMsgId,
    required Uint8List audioBytes,
    int keyVersion = 1,
  }) async {
    final path = '$groupId/$clientMsgId.enc';
    uploadedVoicePaths.add(path);
    return path;
  }

  @override
  Future<Uint8List?> downloadVoiceNote({
    required String groupId,
    required String clientMsgId,
    required String storagePath,
    int keyVersion = 1,
  }) async =>
      null;

  @override
  Future<String> resolveVoiceNotePlayUrl(String storagePathOrUrl) async =>
      'https://example.supabase.co/storage/v1/object/sign/group-voice/$storagePathOrUrl';

  @override
  Future<List<MemberLastLocation>> fetchMemberLocations(
    String groupId, {
    required String currentUserId,
  }) async =>
      List<MemberLastLocation>.unmodifiable(remoteLocations);

  @override
  Stream<List<MemberLastLocation>> watchMemberLocations(
    String groupId, {
    required String currentUserId,
  }) async* {
    yield await fetchMemberLocations(groupId, currentUserId: currentUserId);
    yield* _locationsCtrl.stream;
  }

  @override
  Future<void> upsertMemberLocation({
    required String groupId,
    required MemberLastLocation location,
    int keyVersion = 1,
  }) async {
    remoteLocations.removeWhere((l) => l.userId == location.userId);
    remoteLocations.add(location);
    emitLocations();
  }

  @override
  Future<int> syncOfflineMemberLocations({
    required String groupId,
    required List<MemberLastLocation> locations,
    int keyVersion = 1,
  }) async {
    syncOfflineLocationsCalls++;
    for (final loc in locations) {
      remoteLocations.removeWhere((l) => l.userId == loc.userId);
      remoteLocations.add(loc);
    }
    emitLocations();
    return locations.length;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    NavBarVisibilityController.instance.reset();
    SocialGroupsStore.setInstanceForTesting(SocialGroupsStore());
  });
  tearDown(() {
    NavBarVisibilityController.instance.reset();
    SocialGroupsStore.setInstanceForTesting(null);
  });

  testWidgets(
      'halaman utama tanpa grup menampilkan keadaan kosong dan tombol buat grup',
      (tester) async {
    final account = _FixedAccount(
      fixedGroups: const <RemoteGroup>[],
      fixedMembers: const <MemberDirectoryEntry>[],
    );
    await _pump(tester, account, initialOnline: true);

    expect(find.text('Grup'), findsOneWidget);
    expect(
        find.text('Rencanakan dan ngobrol bersama rombongan'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('grup-create-header-btn')),
        findsOneWidget);
    expect(find.text('Belum ada grup'), findsOneWidget);
    expect(find.text('Buat grup untuk mengundang teman pendakianmu.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('grup-create-empty-btn')),
        findsOneWidget);
    expect(NavBarVisibilityController.instance.isHidden, isFalse);
  });

  testWidgets(
      'daftar grup menampilkan Undangan masuk dan Grup saya lalu terima undangan',
      (tester) async {
    final inv = IncomingInvitation(
      id: 'inv-1',
      groupId: 'g-merbabu',
      groupName: 'Merbabu Weekend',
      inviterUsername: 'raka',
      createdAtUtc: DateTime.utc(2026, 10, 25),
      expiresAtUtc: DateTime.utc(2026, 11, 2),
    );
    final account = _account(invitations: <IncomingInvitation>[inv]);
    await _pump(tester, account);

    expect(find.text('Undangan masuk'), findsOneWidget);
    expect(find.text('Merbabu Weekend'), findsOneWidget);
    expect(find.text('Diundang oleh @raka'), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('inv-reject-inv-1')), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('inv-accept-inv-1')), findsOneWidget);

    expect(find.text('Grup saya'), findsOneWidget);
    expect(find.text('Pendakian Tersesat'), findsOneWidget);
    expect(find.text('1 anggota'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey<String>('inv-accept-inv-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('group-card-g-merbabu')),
        findsOneWidget);
    expect(find.text('Undangan masuk'), findsNothing);
  });

  testWidgets(
      'modal Buat grup baru membuat grup lokal offline dan membuka ruang obrolan',
      (tester) async {
    final account = _FixedAccount(
      fixedGroups: const <RemoteGroup>[],
      fixedMembers: const <MemberDirectoryEntry>[],
    );
    final repos = await _pump(tester, account, initialOnline: false);

    await tester
        .tap(find.byKey(const ValueKey<String>('grup-create-empty-btn')));
    await tester.pumpAndSettle();

    expect(find.text('Buat grup baru'), findsWidgets);
    expect(find.text('Nama grup'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('create-group-avatar-picker')),
      findsOneWidget,
    );
    expect(find.text('Pilih gunung tujuan'), findsNothing);
    expect(find.text('Pilih tanggal pendakian'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey<String>('create-group-name-input')),
      'Tim Semeru Offline',
    );
    await tester
        .tap(find.byKey(const ValueKey<String>('create-group-submit-btn')));
    await tester.pumpAndSettle();

    // Grup baru tersimpan lokal dan muncul di daftar Grup saya
    expect(NavBarVisibilityController.instance.isHidden, isFalse);
    expect(find.text('Tim Semeru Offline'), findsOneWidget);
    expect(find.text('Tersimpan lokal'), findsOneWidget);
    expect(
        repos.group.groups.map((g) => g.name), contains('Tim Semeru Offline'));

    // Buka ruang obrolan dari kartu grup -> navbar otomatis disembunyikan
    await tester.tap(find.text('Tim Semeru Offline'));
    await tester.pumpAndSettle();
    expect(NavBarVisibilityController.instance.isHidden, isTrue);
    expect(
      find.text('Offline · 0 perangkat sekitar'),
      findsOneWidget,
    );

    // Kembali ke daftar grup memulihkan visibilitas navbar
    await tester.tap(find.byKey(const ValueKey<String>('room-chat-back')));
    await tester.pumpAndSettle();
    expect(NavBarVisibilityController.instance.isHidden, isFalse);
    expect(find.text('Tim Semeru Offline'), findsOneWidget);
    expect(find.text('Tersimpan lokal'), findsOneWidget);
  });

  testWidgets(
      'ruang obrolan menyembunyikan navbar, tombol Mikrofon <-> Kirim dinamis, voice note & lokasi',
      (tester) async {
    final chatRepo = _FakeChatRepository();
    chatRepo.messages.addAll(<ChatMessage>[
      _incomingText('g2', 'Besok kumpul di basecamp jam 5 pagi ya.'),
      _incomingVoice('g2'),
      _incomingLocation('g2'),
    ]);
    await _pump(tester, _account(),
        chatRepository: chatRepo, initialOnline: true);

    await tester.tap(find.byKey(const ValueKey<String>('group-card-g2')));
    await tester.pumpAndSettle();

    expect(NavBarVisibilityController.instance.isHidden, isTrue);
    expect(find.text('Online · 3 anggota'), findsOneWidget);
    expect(find.text('25 Okt 2026'), findsOneWidget);
    expect(
        find.text('Besok kumpul di basecamp jam 5 pagi ya.'), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget);
    expect(find.text('bayu membagikan lokasi'), findsOneWidget);

    // Komposer teks aktif dengan tombol Kirim
    expect(find.byKey(const ValueKey<String>('chat-send')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('chat-input')),
      'Siap. Aku bawa power bank dua.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('chat-send')));
    await tester.pumpAndSettle();

    expect(find.text('Siap. Aku bawa power bank dua.'), findsOneWidget);
    expect(chatRepo.messages.where((m) => m.type == PacketType.text),
        hasLength(2));
  });

  testWidgets(
      'menu dropdown membuka Tambah anggota, Bagikan grup, Lokasi terakhir, dan Hapus grup',
      (tester) async {
    await _pump(tester, _account(), initialOnline: true);

    await tester.tap(find.byKey(const ValueKey<String>('group-card-g2')));
    await tester.pumpAndSettle();

    // Buka menu dropdown ⋮
    await tester.tap(find.byKey(const ValueKey<String>('room-chat-menu-btn')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('room-chat-dropdown')),
        findsOneWidget);
    expect(find.text('Tambah anggota'), findsOneWidget);
    expect(find.text('Bagikan grup'), findsOneWidget);
    expect(find.text('Lokasi terakhir'), findsOneWidget);
    expect(find.text('Hapus grup'), findsOneWidget);

    // 1. Tambah anggota
    await tester.tap(find.byKey(const ValueKey<String>('menu-add-member')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('add-member-username-input')),
      'raka',
    );
    await tester
        .tap(find.byKey(const ValueKey<String>('add-member-confirm-btn')));
    await tester.pumpAndSettle();

    // 2. Bagikan grup
    await tester.tap(find.byKey(const ValueKey<String>('room-chat-menu-btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-share-group')));
    await tester.pumpAndSettle();
    expect(find.textContaining('HIQEO-'), findsOneWidget);
    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();

    // 3. Lokasi terakhir -> layar peta topografi
    await tester.tap(find.byKey(const ValueKey<String>('room-chat-menu-btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-last-location')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LastLocationView), findsOneWidget);
    expect(find.text('Lokasi terakhir'), findsOneWidget);
    expect(NavBarVisibilityController.instance.isHidden, isTrue);

    await tester.tap(find.byKey(const ValueKey<String>('last-location-back')));
    await tester.pumpAndSettle();
    expect(find.byType(LastLocationView), findsNothing);

    // 4. Hapus grup (konfirmasi dua langkah untuk pemilik)
    await tester.tap(find.byKey(const ValueKey<String>('room-chat-menu-btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-delete-group')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('delete-group-step1-next')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('delete-group-step2-confirm')),
    );
    await tester.pumpAndSettle();

    expect(NavBarVisibilityController.instance.isHidden, isFalse);
    expect(find.byKey(const ValueKey<String>('group-card-g2')), findsNothing);
    expect(find.byKey(const ValueKey<String>('group-card-g1')), findsOneWidget);
  });

  testWidgets(
      'gagal memuat anggota remote tetap fallback ke anggota lokal dan pulih saat online kembali',
      (tester) async {
    final account = _account()..membersFail = true;
    await _pump(tester, account, initialOnline: true);

    await tester.tap(find.byKey(const ValueKey<String>('group-card-g2')));
    await tester.pumpAndSettle();

    expect(find.text('Online · 1 anggota'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('chat-input')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('room-chat-back')));
    await tester.pumpAndSettle();

    account.membersFail = false;
    await tester.tap(find.byKey(const ValueKey<String>('group-card-g2')));
    await tester.pumpAndSettle();

    expect(find.text('Online · 3 anggota'), findsOneWidget);
  });

  testWidgets(
      'sinkronisasi Supabase group_messages, chat-voice-notes, member_locations, dan antrean offline',
      (tester) async {
    const groupUuid = '11111111-2222-4333-8444-555555555555';
    const peerUuid = 'bbbbbbbb-cccc-4ddd-8eee-ffffffffffff';
    const clientMsgUuid = '22222222-3333-4444-8555-666666666666';

    final account = _FixedAccount(
      fixedGroups: <RemoteGroup>[
        _remoteGroup(
          groupUuid,
          'Ekspedisi Ciremai',
          DateTime.utc(2026, 11, 18),
          mountain: 'Gunung Ciremai',
        ),
      ],
      fixedMembers: <MemberDirectoryEntry>[
        _member('user-1', 'dimas'),
        _member(peerUuid, 'sari'),
      ],
    );
    final chatRepo = _FakeChatRepository();
    final groupRepo = _FakeGroupRepository();
    final remoteChat = _FakeGroupChatRemoteService()
      ..remoteLocations.add(
        MemberLastLocation(
          groupId: groupUuid,
          userId: peerUuid,
          displayName: 'Sari',
          initial: 'S',
          hasSignal: true,
          lat: -6.892,
          lon: 108.405,
          altitudeMdpl: 2750,
          batteryPercent: 72,
          sourceTransport: ChatTransportOrigin.bleMesh,
          recordedAtUtc: DateTime.utc(2026, 11, 19, 1),
          updatedAtUtc: DateTime.utc(2026, 11, 19, 1),
        ),
      );

    Widget buildChat({required bool online}) => MaterialApp(
          theme: hiqeoLightTheme,
          home: Scaffold(
            body: ChatPage(
              accountController: account,
              chatRepository: chatRepo,
              groupRepository: groupRepo,
              chatRemoteService: remoteChat,
              initialOnline: online,
            ),
          ),
        );

    _setTallPhone(tester);
    // Mulai dalam kondisi OFFLINE saat mengirim pesan & memperbarui lokasi
    await tester.pumpWidget(buildChat(online: false));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('group-card-$groupUuid')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('chat-input')),
      'Pesan offline lewat BLE Mesh',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('chat-send')));
    await tester.pumpAndSettle();

    // Saat offline, belum mengirim ke Supabase langsung
    expect(remoteChat.remoteMessages, isEmpty);
    expect(
      find.text('Offline · 0 perangkat sekitar'),
      findsOneWidget,
    );

    // Kembali ONLINE -> antrean offline disinkronkan ke group_messages & stream realtime aktif
    await tester.pumpWidget(buildChat(online: true));
    await tester.pumpAndSettle();

    expect(remoteChat.syncOfflineMessagesCalls, 1);
    expect(remoteChat.remoteMessages, hasLength(1));
    expect(remoteChat.remoteMessages.first.content, 'Pesan offline lewat BLE Mesh');
    expect(remoteChat.remoteMessages.first.originTransport, ChatTransportOrigin.bleMesh);
    expect(find.text('Data offline berhasil disinkronkan.'), findsOneWidget);
    expect(find.text('Online · 2 anggota'), findsOneWidget);

    // Tunggu SnackBar selesai tampil sebelum mengetuk tombol composer di kanan bawah
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Pesan realtime masuk dari anggota lain tampil tanpa duplikasi
    remoteChat.remoteMessages.add(
      GroupMessageRecord(
        clientMsgId: clientMsgUuid,
        groupId: groupUuid,
        senderId: peerUuid,
        senderName: 'Sari',
        messageType: GroupMessageType.text,
        content: 'Pesan realtime dari Sari!',
        keyVersion: 1,
        originTransport: ChatTransportOrigin.online,
        clientCreatedAtUtc: DateTime.utc(2026, 11, 19, 2),
      ),
    );
    remoteChat.emitMessages();
    await tester.pumpAndSettle();

    expect(find.text('Pesan realtime dari Sari!'), findsOneWidget);
    expect(find.text('Pesan offline lewat BLE Mesh'), findsOneWidget);

    // Buka Lokasi Terakhir -> menampilkan data Supabase member_locations & tombol Bagikan ulang lokasi
    await tester.tap(find.byKey(const ValueKey<String>('room-chat-menu-btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-last-location')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Sari'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('last-location-share-toggle')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('last-location-reshare-btn')),
      findsOneWidget,
    );

    // Ketuk tombol "Bagikan ulang lokasi"
    await tester.tap(
      find.byKey(const ValueKey<String>('last-location-reshare-btn')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });
}
