import 'group.dart';
import 'invitation.dart';

class GroupOperationException implements Exception {
  const GroupOperationException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class IncomingInvitation {
  const IncomingInvitation({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.inviterUsername,
    required this.createdAtUtc,
    required this.expiresAtUtc,
  });

  final String id;
  final String groupId;
  final String groupName;
  final String inviterUsername;
  final DateTime createdAtUtc;
  final DateTime expiresAtUtc;

  InvitationStatus effectiveStatus(DateTime nowUtc) =>
      nowUtc.isBefore(expiresAtUtc)
          ? InvitationStatus.pending
          : InvitationStatus.expired;
}

class RemoteGroup {
  const RemoteGroup({required this.group, required this.role});

  final Group group;
  final GroupRole role;

  bool get isOwner => role == GroupRole.owner;
}

class MemberDirectoryEntry {
  const MemberDirectoryEntry({
    required this.userId,
    required this.username,
    required this.role,
    required this.publicKeyBase64,
    required this.joinedAtUtc,
  });

  final String userId;
  final String username;
  final GroupRole role;
  final String publicKeyBase64;
  final DateTime joinedAtUtc;
}

/// Operasi grup yang memerlukan server. Perubahan status undangan dan
/// penerbitan kunci dilakukan lewat fungsi server, bukan tulis langsung.
abstract interface class GroupRemoteService {
  Future<List<RemoteGroup>> myGroups();

  Future<RemoteGroup> createGroup({
    required String name,
    String? mountain,
  });

  Future<void> inviteByUsername({
    required String groupId,
    required String username,
  });

  Future<List<IncomingInvitation>> pendingInvitations(DateTime nowUtc);

  Future<InvitationStatus> respondToInvitation({
    required String invitationId,
    required bool accept,
    required DateTime nowUtc,
  });

  Future<List<MemberDirectoryEntry>> membersOf(String groupId);

  Future<void> publishWrappedKeys({
    required String groupId,
    required int keyVersion,
    required Map<String, String> wrappedKeys,
  });

  Future<String?> fetchOwnWrappedKey({
    required String groupId,
    required int keyVersion,
  });

  Future<void> removeMember({
    required String groupId,
    required String userId,
  });
}
