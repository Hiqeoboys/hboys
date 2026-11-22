import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/groups/application/group_key_manager.dart';
import 'package:nama_app/features/groups/application/group_selection.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/domain/group_key_store.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/groups/domain/invitation.dart';
import 'package:nama_app/features/preparation/application/packing_list_store.dart';
import 'package:nama_app/features/preparation/presentation/siap_naik_page.dart';
import 'package:nama_app/infrastructure/cache/offline_account_cache.dart';
import 'package:nama_app/infrastructure/crypto/crypto_interfaces.dart';
import 'package:nama_app/infrastructure/database/app_database.dart';
import 'package:nama_app/infrastructure/database/repositories/drift_group_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/account_fakes.dart';

final DateTime _now = DateTime.utc(2026, 11, 20, 8, 0);
final Uint8List _keyBytes =
    Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

RemoteGroup _makeGroup(
  String id,
  String name, {
  String ownerId = 'user-1',
  GroupRole role = GroupRole.owner,
}) =>
    RemoteGroup(
      group: Group(
        id: id,
        name: name,
        ownerId: ownerId,
        mountain: 'Gunung Ciremai',
        createdAtUtc: _now,
      ),
      role: role,
    );

MemberDirectoryEntry _member(String userId, String username) =>
    MemberDirectoryEntry(
      userId: userId,
      username: username,
      role: GroupRole.member,
      publicKeyBase64: base64Encode(_keyBytes),
      joinedAtUtc: _now,
    );

class _DummyCrypto implements GroupKeyService {
  @override
  Future<Uint8List> generateGroupKey() async => Uint8List(32);

  @override
  Future<Uint8List> unwrap({
    required Uint8List wrappedKey,
    required Uint8List associatedData,
  }) async =>
      Uint8List(32);

  @override
  Future<Uint8List> wrapForMember({
    required Uint8List groupKey,
    required Uint8List memberPublicKey,
    required Uint8List associatedData,
  }) async =>
      Uint8List(32);
}

class _DummyKeyStore implements GroupKeyStore {
  @override
  Future<void> deleteDistributionSignature(String groupId, int keyVersion) async {}

  @override
  Future<void> deleteGroupKey(String groupId, int keyVersion) async {}

  @override
  Future<String?> readDistributionSignature(
    String groupId,
    int keyVersion,
  ) async =>
      null;

  @override
  Future<Uint8List?> readGroupKey(String groupId, int keyVersion) async => null;

  @override
  Future<void> writeDistributionSignature(
    String groupId,
    int keyVersion,
    String signature,
  ) async {}

  @override
  Future<void> writeGroupKey(
    String groupId,
    int keyVersion,
    Uint8List groupKey,
  ) async {}
}

class _NoopKeyManager extends GroupKeyManager {
  _NoopKeyManager(GroupRemoteService remote)
      : super(
          remote: remote,
          crypto: _DummyCrypto(),
          store: _DummyKeyStore(),
        );

  @override
  Future<GroupKeyStatus> ensureOwnedGroupKey(RemoteGroup group) async =>
      GroupKeyStatus(
        availability: GroupKeyAvailability.ready,
        keyVersion: group.group.keyVersion,
        memberCount: 1,
      );

  @override
  Future<GroupKeyStatus> ensureMembershipKey(RemoteGroup group) async =>
      GroupKeyStatus(
        availability: GroupKeyAvailability.ready,
        keyVersion: group.group.keyVersion,
        memberCount: 1,
      );
}

class _MockGroupRemote implements GroupRemoteService {
  List<RemoteGroup> serverGroups = <RemoteGroup>[];
  bool throwOnInvitations = false;
  final List<String> deletedIds = <String>[];
  final List<String> leftIds = <String>[];
  int myGroupsCalls = 0;

  @override
  Future<List<RemoteGroup>> myGroups() async {
    myGroupsCalls++;
    return List<RemoteGroup>.of(serverGroups);
  }

  @override
  Future<List<IncomingInvitation>> pendingInvitations(DateTime nowUtc) async {
    if (throwOnInvitations) throw StateError('invitations endpoint down');
    return const <IncomingInvitation>[];
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    deletedIds.add(groupId);
    serverGroups.removeWhere((g) => g.group.id == groupId);
  }

  @override
  Future<void> leaveGroup(String groupId) async {
    leftIds.add(groupId);
    serverGroups.removeWhere((g) => g.group.id == groupId);
  }

  @override
  Future<RemoteGroup> createGroup({
    required String name,
    String? mountain,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> inviteByUsername({
    required String groupId,
    required String username,
  }) async {}

  @override
  Future<List<MemberDirectoryEntry>> membersOf(String groupId) async =>
      <MemberDirectoryEntry>[_member('user-1', 'budi')];

  @override
  Future<void> publishWrappedKeys({
    required String groupId,
    required int keyVersion,
    required Map<String, String> wrappedKeys,
  }) async {}

  @override
  Future<String?> fetchOwnWrappedKey({
    required String groupId,
    required int keyVersion,
  }) async =>
      null;

  @override
  Future<void> removeMember({
    required String groupId,
    required String userId,
  }) async {}

  @override
  Future<InvitationStatus> respondToInvitation({
    required String invitationId,
    required bool accept,
    required DateTime nowUtc,
  }) async =>
      InvitationStatus.accepted;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SocialGroupsStore.setInstanceForTesting(null);
    await GroupHikePlanStore.instance.setPlan(null);
  });

  tearDown(() async {
    SocialGroupsStore.setInstanceForTesting(null);
    await GroupHikePlanStore.instance.setPlan(null);
  });

  test(
      'SocialGroupsStore.load memigrasi tombstone lama hiqeo_deleted_group_ids_v1 dan membersihkan kunci lama',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SocialGroupsStore.legacyDeletedGroupsPrefsKey: <String>[
        'ghost-1',
        'ghost-2',
      ],
    });

    final store = SocialGroupsStore();
    await store.load();

    expect(store.deletedGroupIds, containsAll(<String>['ghost-1', 'ghost-2']));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(SocialGroupsStore.legacyDeletedGroupsPrefsKey),
        isNull);
    expect(
      prefs.getStringList(SocialGroupsStore.deletedGroupsPrefsKey),
      containsAll(<String>['ghost-1', 'ghost-2']),
    );
  });

  test(
      'SqliteOfflineAccountCache.writeGroups melakukan full replace & memangkas anggota yatim serta grup UUID basi',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cache = SqliteOfflineAccountCache(database: db);
    final repo = DriftGroupRepository(db);

    final active1 = _makeGroup('11111111-1111-1111-1111-111111111111', 'Aktif 1');
    final active2 = _makeGroup('22222222-2222-2222-2222-222222222222', 'Aktif 2');
    final ghost1 = _makeGroup('33333333-3333-3333-3333-333333333333', 'Hantu 1');
    final ghost2 = _makeGroup('44444444-4444-4444-4444-444444444444', 'Hantu 2');
    final localUnsynced = Group(
      id: 'grup-lokal-123456',
      name: 'Grup Offline Baru',
      ownerId: 'user-1',
      createdAtUtc: _now,
    );

    await cache.writeGroups('user-1', <CachedGroupEntry>[
      CachedGroupEntry(remote: active1, memberCount: 2),
      CachedGroupEntry(remote: active2, memberCount: 1),
      CachedGroupEntry(remote: ghost1, memberCount: 3),
      CachedGroupEntry(remote: ghost2, memberCount: 2),
    ]);
    await cache.writeMembers(ghost1.group.id, <MemberDirectoryEntry>[
      _member('user-1', 'budi'),
    ]);
    await repo.saveGroup(ghost1.group);
    await repo.saveGroup(localUnsynced);

    // Full replace dengan hanya 2 grup aktif dari server
    await cache.writeGroups('user-1', <CachedGroupEntry>[
      CachedGroupEntry(remote: active1, memberCount: 2),
      CachedGroupEntry(remote: active2, memberCount: 1),
    ]);

    final remainingCached = await cache.readGroups('user-1');
    expect(
      remainingCached.map((e) => e.remote.group.id).toList(),
      <String>[active1.group.id, active2.group.id],
    );
    expect(await cache.readMembers(ghost1.group.id), isEmpty);
    expect(await repo.findGroup(ghost1.group.id), isNull);
    expect(await repo.findGroup(localUnsynced.id), isNotNull);
  });

  test(
      'AccountController membersihkan grup hantu di cache saat startup, tetap rekonsiliasi walau invitations gagal, dan membersihkan di server jika perlu',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SocialGroupsStore.legacyDeletedGroupsPrefsKey: <String>['ghost-1'],
    });

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cache = SqliteOfflineAccountCache(database: db);
    final store = SocialGroupsStore();

    final active1 = _makeGroup('active-1', 'Pendakian Gunung Gede Tersesat');
    final active2 = _makeGroup('active-2', 'Testing');
    final ghost1 = _makeGroup('ghost-1', 'Grup Terhapus Lama 1');
    final staleCached = _makeGroup('stale-cached-2', 'Grup Terhapus Lama 2');

    // Cache SQLite masih berisi 4 grup (2 aktif + 2 grup hantu lama)
    await cache.writeGroups('user-1', <CachedGroupEntry>[
      CachedGroupEntry(remote: active1, memberCount: 2),
      CachedGroupEntry(remote: active2, memberCount: 1),
      CachedGroupEntry(remote: ghost1, memberCount: 4),
      CachedGroupEntry(remote: staleCached, memberCount: 3),
    ]);

    final auth = FakeAuthService(
      currentUser: const AuthUser(id: 'user-1', email: 'budi@example.com'),
    );
    final remote = _MockGroupRemote()
      ..throwOnInvitations = true
      // Server sempat masih mengembalikan ghost1 tapi sudah tidak ada staleCached
      ..serverGroups = <RemoteGroup>[active1, active2, ghost1];

    final controller = AccountController(
      authService: auth,
      profileRepository: FakeProfileRepository()
        ..current = UserProfile(
          userId: 'user-1',
          username: 'budi',
          publicKeyBase64: base64Encode(_keyBytes),
        ),
      keyDirectory: FakeKeyDirectory(),
      identity: FakeIdentity(_keyBytes),
      groupRemote: remote,
      groupKeyManager: _NoopKeyManager(remote),
      cache: cache,
      groupsStore: store,
      clock: FakeClock(_now),
    );
    addTearDown(() async {
      controller.dispose();
      await auth.close();
    });

    controller.initialize();
    await pumpEventQueue();

    // Meski pendingInvitations() melempar error, daftar grup tetap direkonsiliasi 100%!
    expect(controller.hasSyncedGroupsFromServer, isTrue);
    expect(
      controller.groups.map((g) => g.group.id).toList(),
      <String>['active-1', 'active-2'],
    );
    expect(remote.deletedIds, contains('ghost-1'));
    // Cache SQLite hanya menyisakan tepat 2 grup aktif (grup hantu terhapus permanen)
    final persisted = await cache.readGroups('user-1');
    expect(
      persisted.map((e) => e.remote.group.id).toList(),
      <String>['active-1', 'active-2'],
    );
    // Tombstone dibersihkan setelah server terkonfirmasi bebas dari ghost
    expect(store.deletedGroupIds, isEmpty);
  });

  testWidgets(
      'SiapNaikPage memuat ulang dari server saat dibuka dan hanya menampilkan 2 grup aktif (grup terhapus di cache hilang permanen)',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cache = SqliteOfflineAccountCache(database: db);
    final store = SocialGroupsStore();

    final active1 = _makeGroup('g-aktif-1', 'Pendakian Gunung Gede Tersesat');
    final active2 = _makeGroup('g-aktif-2', 'Testing');
    final ghost1 = _makeGroup('g-hantu-1', 'Grup Hantu Lama A');
    final ghost2 = _makeGroup('g-hantu-2', 'Grup Hantu Lama B');

    await cache.writeGroups('user-1', <CachedGroupEntry>[
      CachedGroupEntry(remote: active1, memberCount: 2),
      CachedGroupEntry(remote: active2, memberCount: 1),
      CachedGroupEntry(remote: ghost1, memberCount: 2),
      CachedGroupEntry(remote: ghost2, memberCount: 2),
    ]);

    final auth = FakeAuthService(
      currentUser: const AuthUser(id: 'user-1', email: 'budi@example.com'),
    );
    final remote = _MockGroupRemote()
      ..serverGroups = <RemoteGroup>[active1, active2];
    final controller = AccountController(
      authService: auth,
      profileRepository: FakeProfileRepository()
        ..current = UserProfile(
          userId: 'user-1',
          username: 'budi',
          publicKeyBase64: base64Encode(_keyBytes),
        ),
      keyDirectory: FakeKeyDirectory(),
      identity: FakeIdentity(_keyBytes),
      groupRemote: remote,
      groupKeyManager: _NoopKeyManager(remote),
      cache: cache,
      groupsStore: store,
      clock: FakeClock(_now),
    );
    addTearDown(() async {
      controller.dispose();
      await auth.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoDarkTheme,
        home: SiapNaikPage(
          accountController: controller,
          socialGroupsStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pendakian Gunung Gede Tersesat'), findsOneWidget);
    expect(find.text('Testing'), findsOneWidget);
    expect(find.text('Grup Hantu Lama A'), findsNothing);
    expect(find.text('Grup Hantu Lama B'), findsNothing);
    expect(remote.myGroupsCalls, greaterThanOrEqualTo(1));

    final persisted = await cache.readGroups('user-1');
    expect(persisted.map((e) => e.remote.group.id).toList(),
        <String>['g-aktif-1', 'g-aktif-2']);
  });
}
