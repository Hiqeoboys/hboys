import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/features/auth/application/account_controller.dart';
import 'package:nama_app/features/auth/domain/auth_service.dart';
import 'package:nama_app/features/auth/domain/profile_repository.dart';
import 'package:nama_app/features/groups/application/group_key_manager.dart';
import 'package:nama_app/features/groups/domain/group.dart';
import 'package:nama_app/features/groups/domain/group_key_store.dart';
import 'package:nama_app/features/groups/domain/group_remote_service.dart';
import 'package:nama_app/features/groups/domain/invitation.dart';
import 'package:nama_app/infrastructure/crypto/crypto_interfaces.dart';

import '../support/account_fakes.dart';

final DateTime now = DateTime.utc(2027, 5, 1);
final AuthUser testUser =
    const AuthUser(id: 'user-1', email: 'budi@example.com');
final Uint8List identityKey =
    Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
final Uint8List otherKey =
    Uint8List.fromList(List<int>.generate(32, (i) => 200 - i));

UserProfile profileWith({Uint8List? key}) => UserProfile(
      userId: 'user-1',
      username: 'budi_99',
      publicKeyBase64: base64Encode(key ?? identityKey),
    );

RemoteGroup ownerGroup() => RemoteGroup(
      group: Group(
        id: 'g1',
        name: 'Tim Gunung',
        ownerId: 'user-1',
        createdAtUtc: now,
      ),
      role: GroupRole.owner,
    );

IncomingInvitation invitation() => IncomingInvitation(
      id: 'inv-1',
      groupId: 'g1',
      groupName: 'Tim Gunung',
      inviterUsername: 'pemilik',
      createdAtUtc: now,
      expiresAtUtc: now.add(const Duration(days: 7)),
    );

class _UnusedCrypto implements GroupKeyService {
  @override
  Future<Uint8List> generateGroupKey() =>
      throw UnsupportedError('tidak dipakai di tes ini');

  @override
  Future<Uint8List> unwrap({
    required Uint8List wrappedKey,
    required Uint8List associatedData,
  }) =>
      throw UnsupportedError('tidak dipakai di tes ini');

  @override
  Future<Uint8List> wrapForMember({
    required Uint8List groupKey,
    required Uint8List memberPublicKey,
    required Uint8List associatedData,
  }) =>
      throw UnsupportedError('tidak dipakai di tes ini');
}

class _UnusedGroupKeyStore implements GroupKeyStore {
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
  Future<Uint8List?> readGroupKey(String groupId, int keyVersion) async =>
      null;

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

class _StubGroupKeyManager extends GroupKeyManager {
  _StubGroupKeyManager(GroupRemoteService remote)
      : super(
          remote: remote,
          crypto: _UnusedCrypto(),
          store: _UnusedGroupKeyStore(),
        );

  int ownedCalls = 0;
  int membershipCalls = 0;

  @override
  Future<GroupKeyStatus> ensureOwnedGroupKey(RemoteGroup group) async {
    ownedCalls++;
    return GroupKeyStatus(
      availability: GroupKeyAvailability.ready,
      keyVersion: group.group.keyVersion,
      memberCount: 1,
    );
  }

  @override
  Future<GroupKeyStatus> ensureMembershipKey(RemoteGroup group) async {
    membershipCalls++;
    return GroupKeyStatus(
      availability: GroupKeyAvailability.ready,
      keyVersion: group.group.keyVersion,
    );
  }
}

class _FakeGroupRemote implements GroupRemoteService {
  final List<RemoteGroup> groups = [];
  final List<IncomingInvitation> invitations = [];
  final List<MemberDirectoryEntry> members = [];
  final List<({String groupId, String username})> inviteCalls = [];
  final List<({String invitationId, bool accept})> responses = [];
  int membersOfCalls = 0;

  @override
  Future<List<RemoteGroup>> myGroups() async => List.of(groups);

  @override
  Future<RemoteGroup> createGroup({
    required String name,
    String? mountain,
  }) async {
    final created = RemoteGroup(
      group: Group(
        id: 'g-${groups.length + 1}',
        name: name,
        ownerId: testUser.id,
        mountain: mountain,
        createdAtUtc: now,
      ),
      role: GroupRole.owner,
    );
    groups.add(created);
    return created;
  }

  @override
  Future<void> inviteByUsername({
    required String groupId,
    required String username,
  }) async {
    inviteCalls.add((groupId: groupId, username: username));
  }

  @override
  Future<List<IncomingInvitation>> pendingInvitations(DateTime nowUtc) async =>
      List.of(invitations);

  @override
  Future<InvitationStatus> respondToInvitation({
    required String invitationId,
    required bool accept,
    required DateTime nowUtc,
  }) async {
    responses.add((invitationId: invitationId, accept: accept));
    invitations.removeWhere((item) => item.id == invitationId);
    return accept ? InvitationStatus.accepted : InvitationStatus.rejected;
  }

  @override
  Future<List<MemberDirectoryEntry>> membersOf(String groupId) async {
    membersOfCalls++;
    return List.of(members);
  }

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
  Future<void> deleteGroup(String groupId) async {
    groups.removeWhere((g) => g.group.id == groupId);
  }

  @override
  Future<void> leaveGroup(String groupId) async {
    groups.removeWhere((g) => g.group.id == groupId);
  }
}

class _Harness {
  _Harness({
    required this.auth,
    required this.profiles,
    required this.directory,
    required this.identity,
    required this.remote,
    required this.manager,
    required this.controller,
  });

  final FakeAuthService auth;
  final FakeProfileRepository profiles;
  final FakeKeyDirectory directory;
  final FakeIdentity identity;
  final _FakeGroupRemote remote;
  final _StubGroupKeyManager manager;
  final AccountController controller;

  Future<void> dispose() async {
    controller.dispose();
    await auth.close();
  }
}

Future<_Harness> _buildHarness({
  bool signedIn = true,
  UserProfile? profile,
  List<RemoteGroup> groups = const [],
  List<IncomingInvitation> invitations = const [],
}) async {
  final auth = FakeAuthService(currentUser: signedIn ? testUser : null);
  final profiles = FakeProfileRepository()..current = profile;
  final directory = FakeKeyDirectory();
  final identity = FakeIdentity(identityKey);
  final remote = _FakeGroupRemote()
    ..groups.addAll(groups)
    ..invitations.addAll(invitations);
  final manager = _StubGroupKeyManager(remote);
  final controller = AccountController(
    authService: auth,
    profileRepository: profiles,
    keyDirectory: directory,
    identity: identity,
    groupRemote: remote,
    groupKeyManager: manager,
    clock: FakeClock(now),
  );
  controller.initialize();
  await pumpEventQueue();
  return _Harness(
    auth: auth,
    profiles: profiles,
    directory: directory,
    identity: identity,
    remote: remote,
    manager: manager,
    controller: controller,
  );
}

void main() {
  test('memuat profil dan kunci grup untuk pemilik', () async {
    final h = await _buildHarness(
      profile: profileWith(),
      groups: [ownerGroup()],
    );

    expect(h.controller.profile?.username, 'budi_99');
    expect(h.controller.deviceKeyMismatch, isFalse);
    expect(h.manager.ownedCalls, 1);
    expect(
      h.controller.keyStatusFor('g1')?.availability,
      GroupKeyAvailability.ready,
    );

    await h.dispose();
  });

  test('registrasi username menormalkan dan mendaftarkan kunci publik',
      () async {
    final h = await _buildHarness(profile: null);
    expect(h.controller.needsUsername, isTrue);

    await h.controller.registerUsername('  BudI_99 ');

    expect(h.profiles.registrations, hasLength(1));
    expect(h.profiles.registrations.single.username, 'budi_99');
    expect(
      h.profiles.registrations.single.publicKeyBase64,
      base64Encode(identityKey),
    );
    expect(h.controller.profile?.username, 'budi_99');
    expect(h.controller.needsUsername, isFalse);

    await h.dispose();
  });

  test('undangan dengan username tidak dikenal tidak dikirim ke server',
      () async {
    final h = await _buildHarness(profile: profileWith());

    final sent = await h.controller.invite(
      groupId: 'g1',
      username: 'tidak_ada',
    );

    expect(sent, isFalse);
    expect(h.remote.inviteCalls, isEmpty);
    expect(h.controller.error, contains('tidak ditemukan'));

    await h.dispose();
  });

  test('undangan memakai kecocokan persis dan menyatakan masih menunggu',
      () async {
    final h = await _buildHarness(profile: profileWith());
    h.directory.entries['budi_99'] = const DirectoryEntry(
      userId: 'user-2',
      username: 'budi_99',
      publicKeyBase64: 'kunci',
    );

    final sent = await h.controller.invite(
      groupId: 'g1',
      username: '  Budi_99 ',
    );

    expect(sent, isTrue);
    expect(h.remote.inviteCalls.single.username, 'budi_99');
    expect(h.controller.notice, contains('menunggu penerimaan'));

    await h.dispose();
  });

  test('menerima undangan menghapusnya dari daftar dan menunggu kunci',
      () async {
    final pending = invitation();
    final h = await _buildHarness(
      profile: profileWith(),
      invitations: [pending],
    );
    expect(h.controller.invitations, hasLength(1));

    await h.controller.respondToInvitation(pending, accept: true);

    expect(h.remote.responses.single.accept, isTrue);
    expect(h.controller.invitations, isEmpty);
    expect(h.controller.notice, contains('Menunggu pemilik'));

    await h.dispose();
  });

  test('menolak undangan tidak menambahkan grup', () async {
    final pending = invitation();
    final h = await _buildHarness(
      profile: profileWith(),
      invitations: [pending],
    );

    await h.controller.respondToInvitation(pending, accept: false);

    expect(h.remote.responses.single.accept, isFalse);
    expect(h.controller.invitations, isEmpty);
    expect(h.controller.groups, isEmpty);
    expect(h.controller.notice, contains('ditolak'));

    await h.dispose();
  });

  test('kunci grup diblokir saat kunci perangkat berbeda, lalu dipulihkan',
      () async {
    final h = await _buildHarness(
      profile: profileWith(key: otherKey),
      groups: [ownerGroup()],
    );
    expect(h.controller.deviceKeyMismatch, isTrue);
    expect(h.manager.ownedCalls, 0);

    await h.controller.ensureGroupKey('g1');
    expect(h.controller.error, contains('berbeda dari direktori'));
    expect(h.manager.ownedCalls, 0);

    await h.controller.registerCurrentDeviceKey();
    expect(h.controller.deviceKeyMismatch, isFalse);
    expect(h.manager.ownedCalls, 1);
    expect(h.profiles.registrations, hasLength(1));
    expect(
      h.profiles.registrations.single.publicKeyBase64,
      base64Encode(identityKey),
    );

    await h.dispose();
  });

  test('membuat grup memuatnya kembali bersama status kunci', () async {
    final h = await _buildHarness(profile: profileWith());

    final created = await h.controller.createGroup('Tim Gunung');

    expect(created, isTrue);
    expect(h.controller.groups, hasLength(1));
    expect(h.controller.groups.single.group.name, 'Tim Gunung');
    expect(h.controller.notice, contains('dibuat'));

    await h.dispose();
  });
}
