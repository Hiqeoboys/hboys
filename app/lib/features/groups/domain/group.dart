enum GroupRole { owner, member }

class Group {
  const Group({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.createdAtUtc,
    this.mountain,
    this.avatarUrl,
    this.keyVersion = 1,
  });

  final String id;
  final String name;
  final String ownerId;
  final String? mountain;
  final String? avatarUrl;
  final int keyVersion;
  final DateTime createdAtUtc;

  Group copyWith({
    String? name,
    String? mountain,
    String? avatarUrl,
    int? keyVersion,
  }) =>
      Group(
        id: id,
        name: name ?? this.name,
        ownerId: ownerId,
        createdAtUtc: createdAtUtc,
        mountain: mountain ?? this.mountain,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        keyVersion: keyVersion ?? this.keyVersion,
      );
}

/// Anggota rombongan seperti yang dikenal perangkat ini saat offline.
class GroupMember {
  const GroupMember({
    required this.groupId,
    required this.userId,
    required this.username,
    required this.joinedAtUtc,
    this.role = GroupRole.member,
    this.isOfficial = false,
  });

  final String groupId;
  final String userId;
  final String username;
  final GroupRole role;
  final DateTime joinedAtUtc;
  final bool isOfficial;
}
