import 'dart:convert';
import 'dart:typed_data';

import '../../../infrastructure/crypto/crypto_interfaces.dart';
import '../domain/group_key_store.dart';
import '../domain/group_remote_service.dart';

enum GroupKeyAvailability { ready, waitingForOwner }

class GroupKeyStatus {
  const GroupKeyStatus({
    required this.availability,
    required this.keyVersion,
    this.memberCount = 0,
  });

  final GroupKeyAvailability availability;
  final int keyVersion;
  final int memberCount;
}

class GroupKeyPendingException implements Exception {
  const GroupKeyPendingException(this.groupId, this.keyVersion);

  final String groupId;
  final int keyVersion;

  @override
  String toString() =>
      'Kunci grup versi $keyVersion belum dibagikan oleh pemilik grup.';
}

Uint8List groupKeyAssociatedData(String groupId, int keyVersion) =>
    Uint8List.fromList(utf8.encode('nama.group-key|$groupId|v$keyVersion'));

/// Mengelola kunci grup simetris: pembuatan, pembungkusan untuk tiap anggota,
/// penyimpanan lokal, dan pemuatan kunci yang sudah dibagikan pemilik.
class GroupKeyManager {
  GroupKeyManager({
    required GroupRemoteService remote,
    required GroupKeyService crypto,
    required GroupKeyStore store,
  })  : _remote = remote,
        _crypto = crypto,
        _store = store;

  final GroupRemoteService _remote;
  final GroupKeyService _crypto;
  final GroupKeyStore _store;

  /// Pemilik membuat kunci versi aktif dan membagikannya ke seluruh anggota
  /// saat daftar anggota berubah. Publikasi bersifat idempoten di server.
  Future<GroupKeyStatus> ensureOwnedGroupKey(RemoteGroup group) async {
    if (!group.isOwner) {
      throw const GroupOperationException(
        'OWNER_REQUIRED',
        'Hanya pemilik grup yang dapat membagikan kunci.',
      );
    }
    final members = await _remote.membersOf(group.group.id);
    if (members.isEmpty) {
      throw const GroupOperationException(
        'GROUP_EMPTY',
        'Grup belum memiliki anggota.',
      );
    }
    final publicKeys = <String, Uint8List>{};
    for (final member in members) {
      final key = _decodeKey(member.publicKeyBase64, member.username);
      publicKeys[member.userId] = key;
    }

    final version = group.group.keyVersion;
    var groupKey = await _readValidLocalKey(group.group.id, version) ??
        await _recoverOwnGroupKey(group.group.id, version);
    if (groupKey == null) {
      groupKey = await _crypto.generateGroupKey();
      _requireGroupKeyLength(groupKey);
      await _store.writeGroupKey(group.group.id, version, groupKey);
    }

    final signature = _distributionSignature(version, members);
    final previous =
        await _store.readDistributionSignature(group.group.id, version);
    if (previous != signature) {
      final wrappedKeys = <String, String>{};
      for (final entry in publicKeys.entries) {
        final wrapped = await _crypto.wrapForMember(
          groupKey: groupKey,
          memberPublicKey: entry.value,
          associatedData: groupKeyAssociatedData(group.group.id, version),
        );
        wrappedKeys[entry.key] = base64Encode(wrapped);
      }
      await _remote.publishWrappedKeys(
        groupId: group.group.id,
        keyVersion: version,
        wrappedKeys: wrappedKeys,
      );
      await _store.writeDistributionSignature(
        group.group.id,
        version,
        signature,
      );
    }

    return GroupKeyStatus(
      availability: GroupKeyAvailability.ready,
      keyVersion: version,
      memberCount: members.length,
    );
  }

  /// Anggota memuat kunci yang sudah dibungkus untuk kunci publiknya. Bila
  /// pemilik belum membagikannya, hasilnya [GroupKeyPendingException].
  Future<GroupKeyStatus> ensureMembershipKey(RemoteGroup group) async {
    final version = group.group.keyVersion;
    final local = await _readValidLocalKey(group.group.id, version);
    if (local != null) {
      return GroupKeyStatus(
        availability: GroupKeyAvailability.ready,
        keyVersion: version,
      );
    }

    final wrappedBase64 = await _remote.fetchOwnWrappedKey(
      groupId: group.group.id,
      keyVersion: version,
    );
    if (wrappedBase64 == null || wrappedBase64.isEmpty) {
      throw GroupKeyPendingException(group.group.id, version);
    }
    final unwrapped = await _crypto.unwrap(
      wrappedKey: Uint8List.fromList(base64Decode(wrappedBase64)),
      associatedData: groupKeyAssociatedData(group.group.id, version),
    );
    _requireGroupKeyLength(unwrapped);
    await _store.writeGroupKey(group.group.id, version, unwrapped);
    return GroupKeyStatus(
      availability: GroupKeyAvailability.ready,
      keyVersion: version,
    );
  }

  /// Menghapus anggota dan memicu rotasi. Server menaikkan versi kunci; pemilik
  /// lalu membuat kunci baru untuk anggota yang tersisa.
  Future<GroupKeyStatus> removeMemberAndRotate({
    required RemoteGroup group,
    required String userId,
  }) async {
    await _remote.removeMember(groupId: group.group.id, userId: userId);
    final groups = await _remote.myGroups();
    final refreshed = groups.where((g) => g.group.id == group.group.id);
    if (refreshed.isEmpty) {
      throw const GroupOperationException(
        'GROUP_NOT_FOUND',
        'Grup tidak ditemukan setelah perubahan anggota.',
      );
    }
    return ensureOwnedGroupKey(refreshed.first);
  }

  Future<Uint8List?> _readValidLocalKey(String groupId, int keyVersion) async {
    final key = await _store.readGroupKey(groupId, keyVersion);
    if (key == null) return null;
    if (key.length != 32) {
      await _store.deleteGroupKey(groupId, keyVersion);
      return null;
    }
    return key;
  }

  /// Pemilik juga menerima blob untuk dirinya sendiri. Bila cache lokal hilang
  /// tetapi kunci identitas masih sama, kunci grup dipulihkan dari blob itu
  /// agar tidak membuat kunci baru di versi yang sama (yang akan memecah grup).
  Future<Uint8List?> _recoverOwnGroupKey(
    String groupId,
    int keyVersion,
  ) async {
    final wrappedBase64 = await _remote.fetchOwnWrappedKey(
      groupId: groupId,
      keyVersion: keyVersion,
    );
    if (wrappedBase64 == null || wrappedBase64.isEmpty) return null;

    final Uint8List wrapped;
    try {
      wrapped = Uint8List.fromList(base64Decode(wrappedBase64));
    } on FormatException {
      throw const GroupOperationException(
        'GROUP_KEY_UNREADABLE',
        'Kunci grup tersimpan di server rusak. Rotasi kunci diperlukan.',
      );
    }
    final recovered = await _crypto.unwrap(
      wrappedKey: wrapped,
      associatedData: groupKeyAssociatedData(groupId, keyVersion),
    );
    _requireGroupKeyLength(recovered);
    await _store.writeGroupKey(groupId, keyVersion, recovered);
    return recovered;
  }

  Uint8List _decodeKey(String base64Key, String username) {
    try {
      final decoded = base64Decode(base64Key);
      if (decoded.length != 32) throw const FormatException('panjang kunci');
      return decoded;
    } on FormatException {
      throw GroupOperationException(
        'PUBLIC_KEY_INVALID',
        'Kunci publik $username tidak valid.',
      );
    }
  }

  void _requireGroupKeyLength(Uint8List key) {
    if (key.length != 32) {
      throw const GroupOperationException(
        'GROUP_KEY_INVALID',
        'Kunci grup tidak valid.',
      );
    }
  }

  String _distributionSignature(
    int version,
    List<MemberDirectoryEntry> members,
  ) {
    final entries = members
        .map((m) => '${m.userId}:${m.publicKeyBase64}')
        .toList()
      ..sort();
    return 'v$version|${entries.join(',')}';
  }
}
