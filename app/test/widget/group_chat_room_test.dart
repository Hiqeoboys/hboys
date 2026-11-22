import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:nama_app/features/groups/application/group_selection.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/groups/domain/group_repository.dart';
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

class _RoleAccount extends AccountController {
  _RoleAccount({required this.role})
      : super(
          authService: FakeAuthService(
            currentUser: const AuthUser(id: 'me'),
          ),
          profileRepository: FakeProfileRepository(),
          keyDirectory: FakeKeyDirectory(),
          identity: FakeIdentity(Uint8List(32)),
        );

  final GroupRole role;
  int leaveCalls = 0;

  @override
  UserProfile? get profile => const UserProfile(
        userId: 'me',
        username: 'pendaki',
        publicKeyBase64: 'kunci',
      );

  @override
  List<RemoteGroup> get groups => <RemoteGroup>[
        RemoteGroup(
          group: Group(
            id: 'g-merbabu',
            name: 'Tim Merbabu',
            ownerId: role == GroupRole.owner ? 'me' : 'owner-lain',
            createdAtUtc: DateTime.utc(2026, 6, 1),
            mountain: 'Gunung Merbabu',
          ),
          role: role,
        ),
      ];

  @override
  Future<List<MemberDirectoryEntry>> membersOf(String groupId) async =>
      <MemberDirectoryEntry>[
        MemberDirectoryEntry(
          userId: 'me',
          username: 'pendaki',
          role: role,
          joinedAtUtc: DateTime.utc(2026, 6, 1),
          publicKeyBase64: 'k',
        ),
      ];

  @override
  Future<bool> leaveGroup(String groupId) async {
    leaveCalls++;
    return true;
  }

  @override
  void initialize() {}
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
      'menu hamburger menampilkan "Keluar grup" untuk anggota biasa (bukan Hapus grup)',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final account = _RoleAccount(role: GroupRole.member);
    addTearDown(account.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: Scaffold(
          body: ChatPage(
            accountController: account,
            chatRepository: _EmptyChatRepo(),
            groupRepository: _EmptyGroupRepo(),
            initialOnline: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey<String>('group-card-g-merbabu')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('room-chat-menu-btn')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey<String>('menu-leave-group')), findsOneWidget);
    expect(find.text('Keluar grup'), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('menu-delete-group')), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('menu-leave-group')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('leave-group-confirm')));
    await tester.pumpAndSettle();

    expect(NavBarVisibilityController.instance.isHidden, isFalse);
  });

  testWidgets(
      'menu hamburger pembuat grup menampilkan BOTH "Keluar grup" dan "Hapus grup"',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final account = _RoleAccount(role: GroupRole.owner);
    addTearDown(account.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: Scaffold(
          body: ChatPage(
            accountController: account,
            chatRepository: _EmptyChatRepo(),
            groupRepository: _EmptyGroupRepo(),
            initialOnline: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey<String>('group-card-g-merbabu')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('room-chat-menu-btn')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey<String>('menu-leave-group')), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('menu-delete-group')), findsOneWidget);
    expect(find.text('Keluar grup'), findsOneWidget);
    expect(find.text('Hapus grup'), findsOneWidget);
  });

  testWidgets(
      'LastLocationView: sakelar opt-in default NONAKTIF, anggota >15 menit ditandai "Terakhir terlihat", ketuk baris memilih anggota',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.utc(2026, 6, 15, 10, 0);
    var reshared = false;
    MemberLastLocation? selected;

    final members = <MemberLastLocation>[
      MemberLastLocation(
        userId: 'u1',
        displayName: 'Raka',
        initial: 'R',
        hasSignal: true,
        lat: -7.454,
        lon: 110.440,
        altitudeMdpl: 2650,
        batteryPercent: 80,
        recordedAtUtc: now.subtract(const Duration(minutes: 3)),
        updatedAtUtc: now.subtract(const Duration(minutes: 3)),
      ),
      MemberLastLocation(
        userId: 'u2',
        displayName: 'Bayu',
        initial: 'B',
        hasSignal: true,
        lat: -7.456,
        lon: 110.442,
        altitudeMdpl: 2420,
        batteryPercent: 52,
        recordedAtUtc: now.subtract(const Duration(minutes: 25)),
        updatedAtUtc: now.subtract(const Duration(minutes: 25)),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: LastLocationView(
              groupName: 'Tim Merbabu',
              members: members,
              nowUtc: now,
              isOnline: true,
              locationSharingEnabled: true,
              onShareLocation: () async {
                reshared = true;
              },
              onSelectMember: (m) => selected = m,
              onBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Sakelar opt-in lama dihapus dan diganti tombol manual "Bagikan ulang lokasi"
    expect(
      find.byKey(const ValueKey<String>('last-location-share-toggle')),
      findsNothing,
    );
    expect(find.text('Bagikan lokasi ke grup'), findsNothing);
    expect(find.text('Bagikan ulang lokasi'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('last-location-reshare-btn')),
      findsOneWidget,
    );

    // Anggota segar (3 menit lalu) vs stale (>15 menit -> Terakhir terlihat 25 menit lalu)
    expect(find.textContaining('3 menit lalu'), findsOneWidget);
    expect(
        find.textContaining('Terakhir terlihat 25 menit lalu'), findsOneWidget);

    // Ketuk tombol "Bagikan ulang lokasi" -> memanggil onShareLocation
    await tester.tap(
      find.byKey(const ValueKey<String>('last-location-reshare-btn')),
    );
    await tester.pumpAndSettle();
    expect(reshared, isTrue);

    // Ketuk baris anggota -> memanggil onSelectMember untuk pusatkan kamera
    await tester.tap(find.text('Bayu'));
    await tester.pumpAndSettle();
    expect(selected?.userId, 'u2');
  });
}
