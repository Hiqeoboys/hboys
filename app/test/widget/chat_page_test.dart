import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/chat/domain/chat_message.dart';
import 'package:nama_app/features/chat/domain/chat_repository.dart';
import 'package:nama_app/features/chat/domain/media_attachment.dart';
import 'package:nama_app/features/chat/presentation/chat_page.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/safety/domain/payloads.dart';

import '../support/account_fakes.dart';

class _FakeChatRepository implements ChatRepository {
  final List<ChatMessage> messages = <ChatMessage>[];
  final Map<String, StreamController<List<ChatMessage>>> _controllers =
      <String, StreamController<List<ChatMessage>>>{};

  List<ChatMessage> _snapshot(String groupId) => messages
      .where((m) => m.groupId == groupId)
      .toList(growable: false)
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
  Stream<List<ChatMessage>> watchMessages(String groupId, {int limit = 50}) async* {
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

RemoteGroup _remoteGroup(String id, String name, DateTime createdAtUtc) =>
    RemoteGroup(
      group: Group(
        id: id,
        name: name,
        ownerId: 'user-1',
        mountain: 'Gunung Gede',
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
    required this.fixedGroups,
    required this.fixedMembers,
  }) : super(
          authService: FakeAuthService(
            currentUser: const AuthUser(id: 'user-1'),
          ),
          profileRepository: FakeProfileRepository(),
          keyDirectory: FakeKeyDirectory(),
          identity: FakeIdentity(Uint8List(32)),
        );

  final List<RemoteGroup> fixedGroups;
  final List<MemberDirectoryEntry> fixedMembers;
  bool membersFail = false;

  @override
  void initialize() {}

  @override
  AuthUser? get user => const AuthUser(id: 'user-1');

  @override
  bool get isLoading => false;

  @override
  bool get groupsEnabled => true;

  @override
  List<RemoteGroup> get groups => fixedGroups;

  @override
  Future<List<MemberDirectoryEntry>> membersOf(String groupId) async {
    if (membersFail) throw StateError('jaringan mati');
    return fixedMembers;
  }
}

AccountController _guest() => AccountController(
      authService: FakeAuthService(isConfigured: false),
      profileRepository: FakeProfileRepository(),
      keyDirectory: FakeKeyDirectory(),
      identity: FakeIdentity(Uint8List(32)),
    );

AccountController _signedOut() => AccountController(
      authService: FakeAuthService(isConfigured: true),
      profileRepository: FakeProfileRepository(),
      keyDirectory: FakeKeyDirectory(),
      identity: FakeIdentity(Uint8List(32)),
    );

void _setTallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<_FakeChatRepository> _pump(
  WidgetTester tester,
  AccountController account, {
  _FakeChatRepository? repository,
}) async {
  _setTallPhone(tester);
  final repo = repository ?? _FakeChatRepository();
  await tester.pumpWidget(
    MaterialApp(
      theme: hiqeoLightTheme,
      home: Scaffold(
        body: ChatPage(accountController: account, chatRepository: repo),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

_FixedAccount _account({List<MemberDirectoryEntry>? members}) => _FixedAccount(
      fixedGroups: <RemoteGroup>[
        _remoteGroup('g1', 'Rombongan Lama', DateTime.utc(2026, 10, 10)),
        _remoteGroup('g2', 'Rombongan Sabtu', DateTime.utc(2026, 10, 20)),
      ],
      fixedMembers: members ??
          <MemberDirectoryEntry>[
            _member('user-1', 'dimas'),
            _member('user-2', 'sari'),
            _member('user-3', 'bayu'),
          ],
    );

ChatMessage _incomingText(String text) => ChatMessage(
      authorId: 'user-3',
      seq: 1,
      groupId: 'g2',
      type: PacketType.text,
      sentAtUtc: DateTime.utc(2026, 10, 25, 8),
      receivedAtUtc: DateTime.utc(2026, 10, 25, 8),
      payload: Uint8List.fromList(utf8.encode(text)),
    );

ChatMessage _incomingLocation() => ChatMessage(
      authorId: 'user-3',
      seq: 2,
      groupId: 'g2',
      type: PacketType.location,
      sentAtUtc: DateTime.utc(2026, 10, 25, 8, 1),
      receivedAtUtc: DateTime.utc(2026, 10, 25, 8, 1),
      payload: const LocationPayload(
        lat: -6.795,
        lon: 106.985,
        accuracyM: 12,
        batteryPercent: 45,
      ).toBytes(),
    );

void main() {
  testWidgets('tanpa sambungan menampilkan keadaan offline yang jujur',
      (tester) async {
    await _pump(tester, _guest());

    expect(find.text('Grup Chat'), findsOneWidget);
    expect(find.text('Aplikasi berjalan offline'), findsOneWidget);
    expect(
      find.textContaining('Pesan lokal tetap tersimpan di perangkat ini'),
      findsOneWidget,
    );
    expect(find.text('Tulis pesan'), findsNothing);
  });

  testWidgets('terhubung tetapi belum masuk meminta masuk lewat Profil',
      (tester) async {
    await _pump(tester, _signedOut());

    expect(find.text('Belum masuk'), findsOneWidget);
    expect(
      find.text('Masuk lewat Profil untuk memakai grup dan pesan.'),
      findsOneWidget,
    );
    expect(find.text('Tulis pesan'), findsNothing);
  });

  testWidgets('sudah masuk tanpa grup menampilkan keadaan kosong',
      (tester) async {
    final account = _FixedAccount(
      fixedGroups: const <RemoteGroup>[],
      fixedMembers: const <MemberDirectoryEntry>[],
    );
    await _pump(tester, account);

    expect(find.text('Belum ada grup'), findsOneWidget);
    expect(
      find.text('Grup yang kamu ikuti akan muncul di sini.'),
      findsOneWidget,
    );
  });

  testWidgets('grup terbaru tampil dengan anggota nyata', (tester) async {
    await _pump(tester, _account());

    expect(find.text('Rombongan Sabtu'), findsOneWidget);
    expect(find.text('Rombongan Lama'), findsNothing);
    expect(
      find.text('3 anggota · pesan lokal di perangkat ini'),
      findsOneWidget,
    );
    expect(find.text('dimas'), findsOneWidget);
    expect(find.text('sari'), findsOneWidget);
    expect(find.text('bayu'), findsOneWidget);
    expect(find.text('Perangkat ini'), findsOneWidget);
    expect(find.text('Lokasi belum dibagikan'), findsNWidgets(2));
    expect(find.text('Belum ada pesan'), findsOneWidget);
    expect(
      find.textContaining('Pengiriman ke anggota grup belum aktif'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chat-input')), findsOneWidget);
  });

  testWidgets('mengirim pesan menyimpan teks lokal dengan status jujur',
      (tester) async {
    final repo = await _pump(tester, _account());

    await tester.enterText(
      find.byKey(const ValueKey('chat-input')),
      'Aku sudah di Pos 1, nunggu ya',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pumpAndSettle();

    expect(find.text('Aku sudah di Pos 1, nunggu ya'), findsOneWidget);
    expect(find.text('Tersimpan di HP · belum terkirim'), findsOneWidget);
    expect(repo.messages, hasLength(1));
    final saved = repo.messages.single;
    expect(saved.groupId, 'g2');
    expect(saved.authorId, 'user-1');
    expect(saved.isOutgoing, isTrue);
    expect(saved.seq, 1);
    expect(utf8.decode(saved.payload), 'Aku sudah di Pos 1, nunggu ya');
    expect(find.text('Tulis pesan'), findsOneWidget);
  });

  testWidgets('pesan kosong tidak dapat dikirim', (tester) async {
    final repo = await _pump(tester, _account());

    await tester.enterText(find.byKey(const ValueKey('chat-input')), '   ');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pumpAndSettle();

    expect(repo.messages, isEmpty);
  });

  testWidgets('pesan masuk dan kartu lokasi dibaca dari database lokal',
      (tester) async {
    final repo = _FakeChatRepository();
    repo.messages.addAll(<ChatMessage>[
      _incomingText('Halo dari Pos 1'),
      _incomingLocation(),
    ]);
    await _pump(tester, _account(), repository: repo);

    expect(find.text('Halo dari Pos 1'), findsOneWidget);
    expect(find.text('bayu membagikan lokasi'), findsOneWidget);
    expect(
      find.textContaining('±12 m'),
      findsOneWidget,
    );
    expect(find.text('Tersimpan di HP · belum terkirim'), findsNothing);
  });

  testWidgets('daftar anggota gagal dimuat menawarkan coba lagi', (tester) async {
    final account = _account()..membersFail = true;
    await _pump(tester, account);

    expect(find.text('Daftar anggota belum dapat dimuat.'), findsOneWidget);
    expect(find.text('Coba lagi'), findsOneWidget);

    account.membersFail = false;
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();

    expect(find.text('sari'), findsOneWidget);
    expect(find.text('3 anggota · pesan lokal di perangkat ini'),
        findsOneWidget);
  });
}
