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
  const RemoteGroup({
    required this.group,
    required this.role,
    this.joinedAtUtc,
  });

  final Group group;
  final GroupRole role;
  final DateTime? joinedAtUtc;

  bool get isOwner => role == GroupRole.owner;

  RemoteGroup copyWith({
    Group? group,
    GroupRole? role,
    DateTime? joinedAtUtc,
  }) =>
      RemoteGroup(
        group: group ?? this.group,
        role: role ?? this.role,
        joinedAtUtc: joinedAtUtc ?? this.joinedAtUtc,
      );
}

/// Kontrak opsional untuk memperbarui foto profil grup (`groups.avatar_url`).
abstract interface class GroupAvatarUpdater {
  Future<void> updateGroupAvatar({
    required String groupId,
    required String avatarUrl,
  });
}

class MemberDirectoryEntry {
  const MemberDirectoryEntry({
    required this.userId,
    required this.username,
    required this.role,
    required this.publicKeyBase64,
    required this.joinedAtUtc,
    this.displayName,
    this.avatarUrl,
    this.lastSeenAtUtc,
    this.isOfficial = false,
  });

  final String userId;
  final String username;
  final GroupRole role;
  final String publicKeyBase64;
  final DateTime joinedAtUtc;
  final String? displayName;
  final String? avatarUrl;
  final DateTime? lastSeenAtUtc;
  final bool isOfficial;

  String get effectiveDisplayName {
    final trimmed = displayName?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    if (username.trim().isNotEmpty) return username.trim();
    return 'Anggota';
  }
}

/// Jenis perubahan Realtime pada tabel keanggotaan, undangan, atau kunci grup.
enum GroupRealtimeEventKind {
  membershipChanged,
  invitationChanged,
  groupKeyPublished,
}

class GroupRealtimeEvent {
  const GroupRealtimeEvent({
    required this.kind,
    this.groupId,
    this.userId,
    this.invitationId,
    this.keyVersion,
    this.wrappedKeyBase64,
  });

  final GroupRealtimeEventKind kind;
  final String? groupId;
  final String? userId;
  final String? invitationId;
  final int? keyVersion;
  final String? wrappedKeyBase64;
}

/// Kontrak opsional untuk mengambil daftar anggota aktif yang belum memiliki
/// `group_key_blobs` pada versi kunci tertentu agar pemegang kunci mana pun
/// bisa segera mengirimkan kunci terbungkus ke mereka.
abstract interface class GroupMissingKeyProvider {
  Future<List<MemberDirectoryEntry>> membersMissingGroupKey({
    required String groupId,
    int? keyVersion,
  });
}

/// Kontrak opsional untuk berlangganan perubahan Realtime Supabase pada
/// `group_members`, `invitations`, dan `group_key_blobs`.
abstract interface class GroupRealtimeService {
  Stream<GroupRealtimeEvent> subscribe({
    required String userId,
    required List<String> groupIds,
  });

  Future<void> unsubscribe();
}

/// Kontrak opsional untuk mengambil jumlah anggota beberapa grup sekaligus.
abstract interface class GroupMemberCountProvider {
  Future<Map<String, int>> fetchMemberCounts(List<String> groupIds);
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

  /// Menghapus grup beserta seluruh pesan & lokasinya (khusus pemilik grup).
  Future<void> deleteGroup(String groupId);

  /// Keluar dari grup (khusus anggota non-pemilik).
  Future<void> leaveGroup(String groupId);
}
