import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/auth/domain/profile_repository.dart';
import '../../features/groups/domain/group.dart';
import '../../features/groups/domain/group_remote_service.dart';
import '../database/app_database.dart';
import '../database/database_connection.dart';
import 'hiqeo_media_cache_service.dart';

/// Entri grup yang disimpan di cache lokal beserta jumlah anggota terakhir.
class CachedGroupEntry {
  const CachedGroupEntry({
    required this.remote,
    required this.memberCount,
  });

  final RemoteGroup remote;
  final int memberCount;
}

/// Kontrak penyimpanan cache lokal offline-first untuk profil pengguna, avatar
/// file lokal, daftar grup, daftar anggota grup, dan undangan masuk.
abstract interface class OfflineAccountCache {
  Future<UserProfile?> readProfile(String userId);
  Future<void> writeProfile(UserProfile profile);
  Future<void> deleteProfile(String userId);

  Future<List<CachedGroupEntry>> readGroups(String userId);
  Future<void> writeGroups(String userId, List<CachedGroupEntry> groups);

  Future<List<IncomingInvitation>> readInvitations(String userId);
  Future<void> writeInvitations(
    String userId,
    List<IncomingInvitation> invitations,
  );

  Future<List<MemberDirectoryEntry>> readMembers(String groupId);
  Future<void> writeMembers(
    String groupId,
    List<MemberDirectoryEntry> members,
  );

  /// Mengunduh & menyimpan foto avatar ke penyimpanan lokal perangkat agar
  /// tetap tampil tanpa jaringan. Mengembalikan path lokal jika tersedia.
  Future<String?> cacheAvatarFile({
    required String userId,
    required String avatarUrl,
  });

  /// Menyimpan byte avatar hasil pemotongan/kompresi langsung ke cache lokal.
  Future<String?> saveAvatarBytes({
    required String userId,
    required String avatarUrl,
    required Uint8List bytes,
  });

  Future<void> clearUser(String userId);
}

/// Kontrak opsional untuk membersihkan seluruh cache lokal sebuah grup saat
/// grup dihapus atau pengguna keluar dari grup.
abstract interface class GroupCachePurger {
  Future<void> purgeGroup(String userId, String groupId);
}

/// Implementasi SQLite (via [AppDatabase]) untuk cache profil, avatar, grup,
/// keanggotaan, dan undangan masuk secara offline-first.
class SqliteOfflineAccountCache
    implements OfflineAccountCache, GroupCachePurger {
  SqliteOfflineAccountCache({
    AppDatabase? database,
    Future<Directory> Function()? avatarDirResolver,
    Future<Uint8List?> Function(Uri uri)? httpDownloader,
  })  : _injectedDb = database,
        _avatarDirResolver = avatarDirResolver,
        _httpDownloader = httpDownloader;

  final AppDatabase? _injectedDb;
  final Future<Directory> Function()? _avatarDirResolver;
  final Future<Uint8List?> Function(Uri uri)? _httpDownloader;

  AppDatabase? _openedDb;
  Completer<AppDatabase?>? _openCompleter;

  Future<AppDatabase?> _db() async {
    if (_injectedDb != null) return _injectedDb;
    if (_openedDb != null) return _openedDb;
    if (_openCompleter != null) return _openCompleter!.future;

    final completer = Completer<AppDatabase?>();
    _openCompleter = completer;
    try {
      final file = await defaultAppDatabaseFile();
      final db = openAppDatabase(file);
      _openedDb = db;
      completer.complete(db);
      return db;
    } catch (_) {
      completer.complete(null);
      _openCompleter = null;
      return null;
    }
  }

  Variable<Object> _nullableText(String? value) =>
      value == null ? const Variable<String>(null) : Variable<String>(value);

  @override
  Future<UserProfile?> readProfile(String userId) async {
    final db = await _db();
    if (db == null) return null;
    try {
      final row = await db.customSelect(
        'SELECT * FROM cached_user_profiles WHERE user_id = ? LIMIT 1',
        variables: <Variable<Object>>[Variable<String>(userId)],
      ).getSingleOrNull();
      if (row == null) return null;
      final d = row.data;
      final rawChanged = d['username_changed_at'] as String?;
      final rawPlusExp = d['plus_expires_at'] as String?;
      final localAvatarPath = d['local_avatar_path'] as String?;
      final validLocalAvatar =
          localAvatarPath != null &&
                  localAvatarPath.isNotEmpty &&
                  File(localAvatarPath).existsSync()
              ? localAvatarPath
              : null;
      return UserProfile(
        userId: d['user_id'] as String,
        username: d['username'] as String?,
        fullName: d['display_name'] as String?,
        avatarUrl: d['avatar_url'] as String?,
        localAvatarPath: validLocalAvatar,
        email: d['email'] as String?,
        publicKeyBase64: d['public_key'] as String?,
        usernameChangedAtUtc:
            rawChanged != null ? DateTime.tryParse(rawChanged)?.toUtc() : null,
        isProfileComplete: ((d['is_profile_complete'] as num?)?.toInt() ?? 0) == 1,
        isPlus: ((d['is_plus'] as num?)?.toInt() ?? 0) == 1,
        plusPlanId: d['plus_plan_id'] as String?,
        plusExpiresAtUtc:
            rawPlusExp != null ? DateTime.tryParse(rawPlusExp)?.toUtc() : null,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeProfile(UserProfile profile) async {
    final db = await _db();
    if (db == null) return;
    try {
      await db.customInsert(
        '''
        INSERT INTO cached_user_profiles (
          user_id, username, display_name, avatar_url, local_avatar_path,
          email, public_key, username_changed_at, is_profile_complete,
          is_plus, plus_plan_id, plus_expires_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(user_id) DO UPDATE SET
          username = COALESCE(excluded.username, cached_user_profiles.username),
          display_name = COALESCE(excluded.display_name, cached_user_profiles.display_name),
          avatar_url = COALESCE(excluded.avatar_url, cached_user_profiles.avatar_url),
          local_avatar_path = COALESCE(excluded.local_avatar_path, cached_user_profiles.local_avatar_path),
          email = COALESCE(excluded.email, cached_user_profiles.email),
          public_key = COALESCE(excluded.public_key, cached_user_profiles.public_key),
          username_changed_at = COALESCE(excluded.username_changed_at, cached_user_profiles.username_changed_at),
          is_profile_complete = CASE
            WHEN excluded.is_profile_complete = 1 THEN 1
            ELSE cached_user_profiles.is_profile_complete
          END,
          is_plus = excluded.is_plus,
          plus_plan_id = excluded.plus_plan_id,
          plus_expires_at = excluded.plus_expires_at,
          updated_at = excluded.updated_at
        ''',
        variables: <Variable<Object>>[
          Variable<String>(profile.userId),
          _nullableText(profile.username),
          _nullableText(profile.fullName),
          _nullableText(profile.avatarUrl),
          _nullableText(profile.localAvatarPath),
          _nullableText(profile.email),
          _nullableText(profile.publicKeyBase64),
          _nullableText(profile.usernameChangedAtUtc?.toUtc().toIso8601String()),
          Variable<int>(profile.isProfileComplete ? 1 : 0),
          Variable<int>(profile.isPlus ? 1 : 0),
          _nullableText(profile.plusPlanId),
          _nullableText(profile.plusExpiresAtUtc?.toUtc().toIso8601String()),
          Variable<int>(DateTime.now().toUtc().millisecondsSinceEpoch),
        ],
      );
    } catch (_) {}
  }

  @override
  Future<void> deleteProfile(String userId) async {
    final db = await _db();
    if (db == null) return;
    try {
      await db.customUpdate(
        'DELETE FROM cached_user_profiles WHERE user_id = ?',
        variables: <Variable<Object>>[Variable<String>(userId)],
      );
    } catch (_) {}
  }

  @override
  Future<List<CachedGroupEntry>> readGroups(String userId) async {
    final db = await _db();
    if (db == null) return const <CachedGroupEntry>[];
    try {
      final rows = await db.customSelect(
        'SELECT * FROM cached_remote_groups WHERE owner_user_id = ? '
        'ORDER BY created_at ASC',
        variables: <Variable<Object>>[Variable<String>(userId)],
      ).get();
      return rows.map((row) {
        final d = row.data;
        final role = (d['role'] as String?) == 'owner'
            ? GroupRole.owner
            : GroupRole.member;
        final createdRaw = d['created_at'] as String?;
        final createdAt = createdRaw != null
            ? (DateTime.tryParse(createdRaw)?.toUtc() ?? DateTime.now().toUtc())
            : DateTime.now().toUtc();
        final joinedRaw = d['joined_at'] as String?;
        final joinedAt =
            joinedRaw != null ? DateTime.tryParse(joinedRaw)?.toUtc() : null;
        return CachedGroupEntry(
          remote: RemoteGroup(
            group: Group(
              id: d['group_id'] as String,
              name: d['name'] as String,
              ownerId: d['group_owner_id'] as String,
              mountain: d['mountain'] as String?,
              avatarUrl: d['avatar_url'] as String?,
              keyVersion: (d['key_version'] as num?)?.toInt() ?? 1,
              createdAtUtc: createdAt,
            ),
            role: role,
            joinedAtUtc: joinedAt,
          ),
          memberCount: ((d['member_count'] as num?)?.toInt() ?? 1).clamp(1, 9999),
        );
      }).toList(growable: false);
    } catch (_) {
      return const <CachedGroupEntry>[];
    }
  }

  @override
  Future<void> writeGroups(
    String userId,
    List<CachedGroupEntry> groups,
  ) async {
    final db = await _db();
    if (db == null) return;
    try {
      final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      await db.transaction(() async {
        await db.customUpdate(
          'DELETE FROM cached_remote_groups WHERE owner_user_id = ?',
          variables: <Variable<Object>>[Variable<String>(userId)],
        );
        for (final entry in groups) {
          final g = entry.remote.group;
          await db.customInsert(
            '''
            INSERT OR REPLACE INTO cached_remote_groups (
              owner_user_id, group_id, name, group_owner_id, mountain, avatar_url,
              key_version, role, member_count, created_at, joined_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''',
            variables: <Variable<Object>>[
              Variable<String>(userId),
              Variable<String>(g.id),
              Variable<String>(g.name),
              Variable<String>(g.ownerId),
              _nullableText(g.mountain),
              _nullableText(g.avatarUrl),
              Variable<int>(g.keyVersion),
              Variable<String>(
                entry.remote.role == GroupRole.owner ? 'owner' : 'member',
              ),
              Variable<int>(entry.memberCount < 1 ? 1 : entry.memberCount),
              Variable<String>(g.createdAtUtc.toUtc().toIso8601String()),
              _nullableText(entry.remote.joinedAtUtc?.toUtc().toIso8601String()),
              Variable<int>(nowMs),
            ],
          );
        }
        await db.customUpdate(
          'DELETE FROM cached_group_members '
          'WHERE group_id NOT IN (SELECT group_id FROM cached_remote_groups)',
        );
        try {
          await db.customUpdate(
            "DELETE FROM local_group_messages "
            "WHERE group_id NOT IN (SELECT group_id FROM cached_remote_groups) "
            "AND group_id NOT LIKE 'grup-lokal-%'",
          );
          await db.customUpdate(
            "DELETE FROM local_member_locations "
            "WHERE group_id NOT IN (SELECT group_id FROM cached_remote_groups) "
            "AND group_id NOT LIKE 'grup-lokal-%'",
          );
        } catch (_) {}
        try {
          await db.customUpdate(
            "DELETE FROM groups "
            "WHERE id NOT IN (SELECT group_id FROM cached_remote_groups) "
            "AND id NOT LIKE 'grup-lokal-%'",
          );
        } catch (_) {}
      });
    } catch (_) {}
  }

  @override
  Future<void> purgeGroup(String userId, String groupId) async {
    final db = await _db();
    if (db == null) return;
    try {
      await db.transaction(() async {
        await db.customUpdate(
          'DELETE FROM cached_remote_groups '
          'WHERE owner_user_id = ? AND group_id = ?',
          variables: <Variable<Object>>[
            Variable<String>(userId),
            Variable<String>(groupId),
          ],
        );
        await db.customUpdate(
          'DELETE FROM cached_group_members WHERE group_id = ?',
          variables: <Variable<Object>>[Variable<String>(groupId)],
        );
        await db.customUpdate(
          'DELETE FROM cached_invitations '
          'WHERE owner_user_id = ? AND group_id = ?',
          variables: <Variable<Object>>[
            Variable<String>(userId),
            Variable<String>(groupId),
          ],
        );
        for (final table in const <String>[
          'local_group_messages',
          'local_member_locations',
        ]) {
          try {
            await db.customUpdate(
              'DELETE FROM $table WHERE group_id = ?',
              variables: <Variable<Object>>[Variable<String>(groupId)],
            );
          } catch (_) {}
        }
        try {
          await db.customUpdate(
            'DELETE FROM groups WHERE id = ?',
            variables: <Variable<Object>>[Variable<String>(groupId)],
          );
        } catch (_) {}
      });
    } catch (_) {}
  }

  @override
  Future<List<IncomingInvitation>> readInvitations(String userId) async {
    final db = await _db();
    if (db == null) return const <IncomingInvitation>[];
    try {
      final rows = await db.customSelect(
        'SELECT * FROM cached_invitations WHERE owner_user_id = ? '
        'ORDER BY created_at DESC',
        variables: <Variable<Object>>[Variable<String>(userId)],
      ).get();
      return rows.map((row) {
        final d = row.data;
        return IncomingInvitation(
          id: d['invitation_id'] as String,
          groupId: d['group_id'] as String,
          groupName: d['group_name'] as String,
          inviterUsername: d['inviter_username'] as String,
          createdAtUtc: DateTime.parse(d['created_at'] as String).toUtc(),
          expiresAtUtc: DateTime.parse(d['expires_at'] as String).toUtc(),
        );
      }).toList(growable: false);
    } catch (_) {
      return const <IncomingInvitation>[];
    }
  }

  @override
  Future<void> writeInvitations(
    String userId,
    List<IncomingInvitation> invitations,
  ) async {
    final db = await _db();
    if (db == null) return;
    try {
      await db.transaction(() async {
        await db.customUpdate(
          'DELETE FROM cached_invitations WHERE owner_user_id = ?',
          variables: <Variable<Object>>[Variable<String>(userId)],
        );
        for (final inv in invitations) {
          await db.customInsert(
            '''
            INSERT OR REPLACE INTO cached_invitations (
              owner_user_id, invitation_id, group_id, group_name,
              inviter_username, created_at, expires_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ''',
            variables: <Variable<Object>>[
              Variable<String>(userId),
              Variable<String>(inv.id),
              Variable<String>(inv.groupId),
              Variable<String>(inv.groupName),
              Variable<String>(inv.inviterUsername),
              Variable<String>(inv.createdAtUtc.toUtc().toIso8601String()),
              Variable<String>(inv.expiresAtUtc.toUtc().toIso8601String()),
            ],
          );
        }
      });
    } catch (_) {}
  }

  @override
  Future<List<MemberDirectoryEntry>> readMembers(String groupId) async {
    final db = await _db();
    if (db == null) return const <MemberDirectoryEntry>[];
    try {
      final rows = await db.customSelect(
        'SELECT * FROM cached_group_members WHERE group_id = ? '
        'ORDER BY CASE WHEN role = \'owner\' THEN 0 ELSE 1 END ASC, joined_at ASC',
        variables: <Variable<Object>>[Variable<String>(groupId)],
      ).get();
      return rows.map((row) {
        final d = row.data;
        final rawLastSeen = d['last_seen_at'] as String?;
        return MemberDirectoryEntry(
          userId: d['user_id'] as String,
          username: (d['username'] as String?) ?? '',
          displayName: d['display_name'] as String?,
          avatarUrl: d['avatar_url'] as String?,
          role: (d['role'] as String?) == 'owner'
              ? GroupRole.owner
              : GroupRole.member,
          publicKeyBase64: (d['public_key'] as String?) ?? '',
          joinedAtUtc: DateTime.parse(d['joined_at'] as String).toUtc(),
          lastSeenAtUtc:
              rawLastSeen != null ? DateTime.tryParse(rawLastSeen)?.toUtc() : null,
        );
      }).toList(growable: false);
    } catch (_) {
      return const <MemberDirectoryEntry>[];
    }
  }

  @override
  Future<void> writeMembers(
    String groupId,
    List<MemberDirectoryEntry> members,
  ) async {
    final db = await _db();
    if (db == null) return;
    try {
      await db.transaction(() async {
        await db.customUpdate(
          'DELETE FROM cached_group_members WHERE group_id = ?',
          variables: <Variable<Object>>[Variable<String>(groupId)],
        );
        for (final m in members) {
          await db.customInsert(
            '''
            INSERT OR REPLACE INTO cached_group_members (
              group_id, user_id, username, display_name, avatar_url,
              role, public_key, joined_at, last_seen_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''',
            variables: <Variable<Object>>[
              Variable<String>(groupId),
              Variable<String>(m.userId),
              Variable<String>(m.username),
              _nullableText(m.displayName),
              _nullableText(m.avatarUrl),
              Variable<String>(m.role == GroupRole.owner ? 'owner' : 'member'),
              Variable<String>(m.publicKeyBase64),
              Variable<String>(m.joinedAtUtc.toUtc().toIso8601String()),
              _nullableText(m.lastSeenAtUtc?.toUtc().toIso8601String()),
            ],
          );
        }
      });
    } catch (_) {}
  }

  @override
  Future<String?> cacheAvatarFile({
    required String userId,
    required String avatarUrl,
  }) async {
    final trimmed = avatarUrl.trim();
    if (trimmed.isEmpty || kIsWeb) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }

    try {
      final baseDir = _avatarDirResolver != null
          ? await _avatarDirResolver()
          : await getApplicationSupportDirectory();
      final avatarDir = Directory(
        '${baseDir.path}${Platform.pathSeparator}avatar_cache',
      );
      if (!avatarDir.existsSync()) {
        avatarDir.createSync(recursive: true);
      }

      final safeUser = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final urlHash = _fnv1aHex(trimmed);
      final target = File(
        '${avatarDir.path}${Platform.pathSeparator}${safeUser}_$urlHash.img',
      );
      if (target.existsSync() && target.lengthSync() > 0) {
        return target.path;
      }

      final bytes = _httpDownloader != null
          ? await _httpDownloader(uri)
          : await _downloadBytes(uri);
      if (bytes == null || bytes.isEmpty) return null;

      await target.writeAsBytes(bytes, flush: true);

      // Bersihkan avatar versi lama milik user yang sama agar tidak menumpuk.
      try {
        await for (final entity in avatarDir.list(followLinks: false)) {
          if (entity is File &&
              entity.path != target.path &&
              entity.uri.pathSegments.last.startsWith('${safeUser}_')) {
            await entity.delete();
          }
        }
      } catch (_) {}

      return target.path;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> saveAvatarBytes({
    required String userId,
    required String avatarUrl,
    required Uint8List bytes,
  }) async {
    if (kIsWeb || bytes.isEmpty) return null;
    try {
      final baseDir = _avatarDirResolver != null
          ? await _avatarDirResolver()
          : await getApplicationSupportDirectory();
      final avatarDir = Directory(
        '${baseDir.path}${Platform.pathSeparator}avatar_cache',
      );
      if (!avatarDir.existsSync()) {
        avatarDir.createSync(recursive: true);
      }
      final safeUser = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final urlHash = _fnv1aHex(avatarUrl.trim());
      final target = File(
        '${avatarDir.path}${Platform.pathSeparator}${safeUser}_$urlHash.img',
      );
      await target.writeAsBytes(bytes, flush: true);
      try {
        await for (final entity in avatarDir.list(followLinks: false)) {
          if (entity is File &&
              entity.path != target.path &&
              entity.uri.pathSegments.last.startsWith('${safeUser}_')) {
            await entity.delete();
          }
        }
      } catch (_) {}
      return target.path;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _downloadBytes(Uri uri) =>
      HiqeoMediaCacheService.instance.downloadBytes(uri.toString());

  String _fnv1aHex(String input) {
    var hash = 0x811c9dc5;
    for (final b in utf8.encode(input)) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  @override
  Future<void> clearUser(String userId) async {
    final db = await _db();
    if (db == null) return;
    try {
      await db.transaction(() async {
        await db.customUpdate(
          'DELETE FROM cached_user_profiles WHERE user_id = ?',
          variables: <Variable<Object>>[Variable<String>(userId)],
        );
        await db.customUpdate(
          'DELETE FROM cached_remote_groups WHERE owner_user_id = ?',
          variables: <Variable<Object>>[Variable<String>(userId)],
        );
        await db.customUpdate(
          'DELETE FROM cached_group_members '
          'WHERE group_id NOT IN (SELECT group_id FROM cached_remote_groups)',
        );
        await db.customUpdate(
          'DELETE FROM cached_invitations WHERE owner_user_id = ?',
          variables: <Variable<Object>>[Variable<String>(userId)],
        );
      });
    } catch (_) {}
  }

  Future<void> close() async {
    final db = _openedDb;
    _openedDb = null;
    _openCompleter = null;
    await db?.close();
  }
}

/// Implementasi cache akun dalam memori untuk pengujian unit dan widget.
class InMemoryOfflineAccountCache
    implements OfflineAccountCache, GroupCachePurger {
  final Map<String, UserProfile> profiles = <String, UserProfile>{};
  final Map<String, List<CachedGroupEntry>> groupsByUser =
      <String, List<CachedGroupEntry>>{};
  final Map<String, List<IncomingInvitation>> invitationsByUser =
      <String, List<IncomingInvitation>>{};
  final Map<String, List<MemberDirectoryEntry>> membersByGroup =
      <String, List<MemberDirectoryEntry>>{};
  final Map<String, String> cachedAvatarPaths = <String, String>{};

  @override
  Future<UserProfile?> readProfile(String userId) async => profiles[userId];

  @override
  Future<void> writeProfile(UserProfile profile) async {
    final existing = profiles[profile.userId];
    profiles[profile.userId] = profile.copyWith(
      username: profile.username ?? existing?.username,
      fullName: profile.fullName ?? existing?.fullName,
      avatarUrl: profile.avatarUrl ?? existing?.avatarUrl,
      localAvatarPath: profile.localAvatarPath ?? existing?.localAvatarPath,
      email: profile.email ?? existing?.email,
      publicKeyBase64: profile.publicKeyBase64 ?? existing?.publicKeyBase64,
      usernameChangedAtUtc:
          profile.usernameChangedAtUtc ?? existing?.usernameChangedAtUtc,
      isProfileComplete:
          profile.isProfileComplete || (existing?.isProfileComplete ?? false),
    );
  }

  @override
  Future<void> deleteProfile(String userId) async {
    profiles.remove(userId);
  }

  @override
  Future<List<CachedGroupEntry>> readGroups(String userId) async =>
      List<CachedGroupEntry>.unmodifiable(
        groupsByUser[userId] ?? const <CachedGroupEntry>[],
      );

  @override
  Future<void> writeGroups(
    String userId,
    List<CachedGroupEntry> groups,
  ) async {
    groupsByUser[userId] = List<CachedGroupEntry>.of(groups);
    final allActiveIds = groupsByUser.values
        .expand((list) => list.map((e) => e.remote.group.id))
        .toSet();
    membersByGroup.removeWhere((gid, _) => !allActiveIds.contains(gid));
  }

  @override
  Future<List<IncomingInvitation>> readInvitations(String userId) async =>
      List<IncomingInvitation>.unmodifiable(
        invitationsByUser[userId] ?? const <IncomingInvitation>[],
      );

  @override
  Future<void> writeInvitations(
    String userId,
    List<IncomingInvitation> invitations,
  ) async {
    invitationsByUser[userId] = List<IncomingInvitation>.of(invitations);
  }

  @override
  Future<List<MemberDirectoryEntry>> readMembers(String groupId) async =>
      List<MemberDirectoryEntry>.unmodifiable(
        membersByGroup[groupId] ?? const <MemberDirectoryEntry>[],
      );

  @override
  Future<void> writeMembers(
    String groupId,
    List<MemberDirectoryEntry> members,
  ) async {
    membersByGroup[groupId] = List<MemberDirectoryEntry>.of(members);
  }

  @override
  Future<String?> cacheAvatarFile({
    required String userId,
    required String avatarUrl,
  }) async {
    return cachedAvatarPaths[userId];
  }

  @override
  Future<String?> saveAvatarBytes({
    required String userId,
    required String avatarUrl,
    required Uint8List bytes,
  }) async {
    return cachedAvatarPaths[userId];
  }

  @override
  Future<void> clearUser(String userId) async {
    profiles.remove(userId);
    groupsByUser.remove(userId);
    invitationsByUser.remove(userId);
  }

  @override
  Future<void> purgeGroup(String userId, String groupId) async {
    final existing = groupsByUser[userId];
    if (existing != null) {
      groupsByUser[userId] = existing
          .where((e) => e.remote.group.id != groupId)
          .toList(growable: false);
    }
    membersByGroup.remove(groupId);
    final invites = invitationsByUser[userId];
    if (invites != null) {
      invitationsByUser[userId] = invites
          .where((inv) => inv.groupId != groupId)
          .toList(growable: false);
    }
  }
}
