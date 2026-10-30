enum GroupRole { owner, member }

class Group {
  const Group({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.createdAtUtc,
    this.mountain,
    this.keyVersion = 1,
  });

  final String id;
  final String name;
  final String ownerId;
  final String? mountain;
  final int keyVersion;
  final DateTime createdAtUtc;
}

/// Anggota rombongan seperti yang dikenal perangkat ini saat offline.
class GroupMember {
  const GroupMember({
    required this.groupId,
    required this.userId,
    required this.username,
    required this.joinedAtUtc,
    this.role = GroupRole.member,
  });

  final String groupId;
  final String userId;
  final String username;
  final GroupRole role;
  final DateTime joinedAtUtc;
}
