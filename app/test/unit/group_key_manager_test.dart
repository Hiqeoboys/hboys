import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/groups/application/group_key_manager.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/domain/group_key_store.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/groups/domain/invitation.dart';
import 'package:nama_app/infrastructure/crypto/crypto_interfaces.dart';
import 'package:nama_app/infrastructure/crypto/cryptography_identity_service.dart';

class MemoryGroupKeyStore implements GroupKeyStore {
  final Map<String, Uint8List> keys = {};
  final Map<String, String> signatures = {};

  String _key(String groupId, int version) => '$groupId:v$version';

  @override
  Future<Uint8List?> readGroupKey(String groupId, int keyVersion) async =>
      keys[_key(groupId, keyVersion)];

  @override
  Future<void> writeGroupKey(
    String groupId,
    int keyVersion,
    Uint8List groupKey,
  ) async {
    keys[_key(groupId, keyVersion)] = Uint8List.fromList(groupKey);
  }

  @override
  Future<void> deleteGroupKey(String groupId, int keyVersion) async {
    keys.remove(_key(groupId, keyVersion));
  }

  @override
  Future<String?> readDistributionSignature(
    String groupId,
    int keyVersion,
  ) async =>
      signatures[_key(groupId, keyVersion)];

  @override
  Future<void> writeDistributionSignature(
    String groupId,
    int keyVersion,
    String signature,
  ) async {
    signatures[_key(groupId, keyVersion)] = signature;
  }

  @override
  Future<void> deleteDistributionSignature(
    String groupId,
    int keyVersion,
  ) async {
    signatures.remove(_key(groupId, keyVersion));
  }
}

class PublishCall {
  PublishCall(this.version, this.keys);

  final int version;
  final Map<String, String> keys;
}

class FakeGroupRemote implements GroupRemoteService {
  FakeGroupRemote(this.group, this.members);

  Group group;
  List<MemberDirectoryEntry> members;
  String viewerId = 'owner-1';
  final Map<String, Map<int, String>> wrappedByUser = {};
  final List<PublishCall> publishes = [];
  int membersOfCalls = 0;
  int removeCalls = 0;

  @override
  Future<List<RemoteGroup>> myGroups() async => [
        RemoteGroup(
          group: group,
          role: viewerId == group.ownerId ? GroupRole.owner : GroupRole.member,
        ),
      ];

  @override
  Future<List<MemberDirectoryEntry>> membersOf(String groupId) async {
    membersOfCalls++;
    return members;
  }

  @override
  Future<void> publishWrappedKeys({
    required String groupId,
    required int keyVersion,
    required Map<String, String> wrappedKeys,
  }) async {
    publishes.add(PublishCall(keyVersion, Map.of(wrappedKeys)));
    for (final entry in wrappedKeys.entries) {
      wrappedByUser.putIfAbsent(entry.key, () => {})[keyVersion] = entry.value;
    }
  }

  @override
  Future<String?> fetchOwnWrappedKey({
    required String groupId,
    required int keyVersion,
  }) async =>
      wrappedByUser[viewerId]?[keyVersion];

  @override
  Future<void> removeMember({
    required String groupId,
    required String userId,
  }) async {
    removeCalls++;
    members = members.where((m) => m.userId != userId).toList(growable: false);
    wrappedByUser.remove(userId);
    group = Group(
      id: group.id,
      name: group.name,
      ownerId: group.ownerId,
      createdAtUtc: group.createdAtUtc,
      mountain: group.mountain,
      keyVersion: group.keyVersion + 1,
    );
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
  }) =>
      throw UnimplementedError();

  @override
  Future<List<IncomingInvitation>> pendingInvitations(DateTime nowUtc) async =>
      const [];

  @override
  Future<InvitationStatus> respondToInvitation({
    required String invitationId,
    required bool accept,
    required DateTime nowUtc,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteGroup(String groupId) async {}

  @override
  Future<void> leaveGroup(String groupId) async {}
}

class Harness {
  Harness({
    required this.remote,
    required this.ownerStore,
    required this.memberStore,
    required this.ownerCrypto,
    required this.memberCrypto,
    required this.ownerManager,
    required this.memberManager,
    required this.ownerGroup,
    required this.memberGroup,
  });

  final FakeGroupRemote remote;
  final MemoryGroupKeyStore ownerStore;
  final MemoryGroupKeyStore memberStore;
  final CryptographyIdentityService ownerCrypto;
  final CryptographyIdentityService memberCrypto;
  final GroupKeyManager ownerManager;
  final GroupKeyManager memberManager;
  final RemoteGroup ownerGroup;
  final RemoteGroup memberGroup;
}

Future<Harness> buildHarness() async {
  final ownerStore = MemoryGroupKeyStore();
  final memberStore = MemoryGroupKeyStore();
  final ownerCrypto = CryptographyIdentityService(
    store: _MemorySecretStore(),
  );
  final memberCrypto = CryptographyIdentityService(
    store: _MemorySecretStore(),
  );
  final t0 = DateTime.utc(2027, 5, 1);
  final group = Group(
    id: 'g1',
    name: 'Tim Gunung',
    ownerId: 'owner-1',
    createdAtUtc: t0,
  );
  final members = [
    MemberDirectoryEntry(
      userId: 'owner-1',
      username: 'pemilik',
      role: GroupRole.owner,
      publicKeyBase64: base64Encode(await ownerCrypto.publicKey()),
      joinedAtUtc: t0,
    ),
    MemberDirectoryEntry(
      userId: 'member-1',
      username: 'anggota',
      role: GroupRole.member,
      publicKeyBase64: base64Encode(await memberCrypto.publicKey()),
      joinedAtUtc: t0,
    ),
  ];
  final remote = FakeGroupRemote(group, members);
  return Harness(
    remote: remote,
    ownerStore: ownerStore,
    memberStore: memberStore,
    ownerCrypto: ownerCrypto,
    memberCrypto: memberCrypto,
    ownerManager: GroupKeyManager(
      remote: remote,
      crypto: ownerCrypto,
      store: ownerStore,
    ),
    memberManager: GroupKeyManager(
      remote: remote,
      crypto: memberCrypto,
      store: memberStore,
    ),
    ownerGroup: RemoteGroup(group: group, role: GroupRole.owner),
    memberGroup: RemoteGroup(group: group, role: GroupRole.member),
  );
}

class _MemorySecretStore implements SecretValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  test('pemilik membagikan kunci ke semua anggota dan idempoten', () async {
    final h = await buildHarness();

    final status = await h.ownerManager.ensureOwnedGroupKey(h.ownerGroup);
    expect(status.availability, GroupKeyAvailability.ready);
    expect(status.keyVersion, 1);
    expect(status.memberCount, 2);
    expect(h.remote.publishes, hasLength(1));
    expect(
      h.remote.publishes.single.keys.keys.toSet(),
      {'owner-1', 'member-1'},
    );

    await h.ownerManager.ensureOwnedGroupKey(h.ownerGroup);
    expect(h.remote.publishes, hasLength(1));
  });

  test('anggota menunggu kunci bila pemilik belum membagikan', () async {
    final h = await buildHarness();
    h.remote.viewerId = 'member-1';

    expect(
      () => h.memberManager.ensureMembershipKey(h.memberGroup),
      throwsA(isA<GroupKeyPendingException>()),
    );
  });

  test('anggota membuka kunci yang dibungkus pemilik', () async {
    final h = await buildHarness();
    await h.ownerManager.ensureOwnedGroupKey(h.ownerGroup);
    h.remote.viewerId = 'member-1';

    final status = await h.memberManager.ensureMembershipKey(h.memberGroup);
    final ownerKey = await h.ownerStore.readGroupKey('g1', 1);
    final memberKey = await h.memberStore.readGroupKey('g1', 1);

    expect(status.availability, GroupKeyAvailability.ready);
    expect(ownerKey, isNotNull);
    expect(memberKey, ownerKey);
  });

  test('anggota baru memicu pembagian ulang pada versi yang sama', () async {
    final h = await buildHarness();
    await h.ownerManager.ensureOwnedGroupKey(h.ownerGroup);

    final thirdCrypto = CryptographyIdentityService(
      store: _MemorySecretStore(),
    );
    h.remote.members = [
      ...h.remote.members,
      MemberDirectoryEntry(
        userId: 'member-2',
        username: 'anggota2',
        role: GroupRole.member,
        publicKeyBase64: base64Encode(await thirdCrypto.publicKey()),
        joinedAtUtc: DateTime.utc(2027, 5, 2),
      ),
    ];

    final status = await h.ownerManager.ensureOwnedGroupKey(h.ownerGroup);
    expect(status.memberCount, 3);
    expect(h.remote.publishes, hasLength(2));
    expect(h.remote.publishes.last.version, 1);
    expect(
      h.remote.publishes.last.keys.keys.toSet(),
      {'owner-1', 'member-1', 'member-2'},
    );
  });

  test('pemilik memulihkan kunci lokal dari blob sendiri, bukan membuat baru',
      () async {
    final h = await buildHarness();
    await h.ownerManager.ensureOwnedGroupKey(h.ownerGroup);
    final original = await h.ownerStore.readGroupKey('g1', 1);

    await h.ownerStore.deleteGroupKey('g1', 1);
    final status = await h.ownerManager.ensureOwnedGroupKey(h.ownerGroup);
    final recovered = await h.ownerStore.readGroupKey('g1', 1);

    expect(status.availability, GroupKeyAvailability.ready);
    expect(recovered, original);
    expect(h.remote.publishes, hasLength(1));
  });

  test('penghapusan anggota menaikkan versi dan merotasi kunci', () async {
    final h = await buildHarness();
    await h.ownerManager.ensureOwnedGroupKey(h.ownerGroup);
    final oldKey = await h.ownerStore.readGroupKey('g1', 1);

    final status = await h.ownerManager.removeMemberAndRotate(
      group: h.ownerGroup,
      userId: 'member-1',
    );

    final newKey = await h.ownerStore.readGroupKey('g1', 2);
    expect(h.remote.removeCalls, 1);
    expect(status.keyVersion, 2);
    expect(status.memberCount, 1);
    expect(h.remote.publishes, hasLength(2));
    expect(h.remote.publishes.last.version, 2);
    expect(h.remote.publishes.last.keys.keys.toSet(), {'owner-1'});
    expect(h.remote.wrappedByUser.containsKey('member-1'), isFalse);
    expect(newKey, isNotNull);
    expect(newKey, isNot(oldKey));
  });
}
