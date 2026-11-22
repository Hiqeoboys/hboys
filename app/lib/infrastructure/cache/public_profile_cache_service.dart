import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../features/chat/domain/group_chat_models.dart';
import '../database/app_database.dart';
import '../database/database_connection.dart';
import '../storage/media_url_normalizer.dart';
import '../supabase/supabase_services.dart';
import 'avatar_disk_cache.dart';

@immutable
class PublicProfile {
  const PublicProfile({
    required this.userId,
    this.username,
    this.fullName,
    this.avatarUrl,
    this.lastSeenAtUtc,
    this.updatedAtUtc,
  });

  final String userId;
  final String? username;
  final String? fullName;
  final String? avatarUrl;
  final DateTime? lastSeenAtUtc;
  final DateTime? updatedAtUtc;

  String get displayName {
    final full = fullName?.trim();
    if (full != null && full.isNotEmpty) return full;
    final user = username?.trim().replaceFirst(RegExp(r'^@+'), '');
    if (user != null && user.isNotEmpty) return user;
    return 'Pendaki';
  }
}

typedef PublicProfileRemoteFetcher = Future<List<PublicProfile>> Function(
  List<String> userIds,
);

/// Cache profil publik reaktif (in-memory + SQLite `cached_public_profiles`)
/// agar perubahan nama/foto profil langsung tercermin di seluruh pesan lama
/// maupun baru tanpa bergantung pada snapshot statis di baris pesan.
class PublicProfileCacheService extends ChangeNotifier {
  PublicProfileCacheService({
    AppDatabase? database,
    PublicProfileRemoteFetcher? remoteFetcher,
    void Function(String url)? onEvictImageUrl,
  })  : _injectedDb = database,
        _remoteFetcher = remoteFetcher ?? _defaultRemoteFetcher,
        _onEvictImageUrl = onEvictImageUrl ?? evictAvatarFromImageCache;

  static final PublicProfileCacheService instance = PublicProfileCacheService();

  final AppDatabase? _injectedDb;
  final PublicProfileRemoteFetcher _remoteFetcher;
  final void Function(String url) _onEvictImageUrl;

  final Map<String, PublicProfile> _memory = <String, PublicProfile>{};
  AppDatabase? _openedDb;
  Completer<AppDatabase?>? _openCompleter;

  static void evictAvatarFromImageCache(String? url) {
    final normalized = MediaUrlNormalizer.normalize(url);
    if (normalized == null || normalized.isEmpty) return;
    try {
      final base = NetworkImage(normalized);
      unawaited(base.evict());
      unawaited(ResizeImage(base, width: 128).evict());
      unawaited(ResizeImage(base, width: 160).evict());
      unawaited(ResizeImage(base, width: 256).evict());
    } catch (_) {}
  }

  PublicProfile? getCached(String userId) => _memory[userId];

  String? resolveAvatarUrl(String userId, {String? fallback}) {
    final live = _memory[userId]?.avatarUrl;
    if (live != null && live.trim().isNotEmpty) {
      return MediaUrlNormalizer.normalize(live);
    }
    return MediaUrlNormalizer.normalize(fallback);
  }

  String resolveDisplayName(String userId, {String fallback = 'Pendaki'}) {
    final cached = _memory[userId];
    if (cached != null) {
      final full = cached.fullName?.trim();
      if (full != null && full.isNotEmpty) return full;
      final uname = cached.username?.trim();
      if (uname != null && uname.isNotEmpty) return uname;
    }
    final cleanFallback = fallback.trim();
    return cleanFallback.isNotEmpty ? cleanFallback : 'Pendaki';
  }

  String? resolveUsername(String userId, {String? fallback}) {
    final cached = _memory[userId]?.username?.trim();
    if (cached != null && cached.isNotEmpty) return cached;
    final cleanFallback = fallback?.trim();
    return (cleanFallback != null && cleanFallback.isNotEmpty)
        ? cleanFallback
        : null;
  }

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

  Future<void> hydrateFromDisk(Iterable<String> userIds) async {
    final ids = userIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return;

    final db = await _db();
    if (db == null) return;

    try {
      final placeholders = List<String>.filled(ids.length, '?').join(', ');
      final rows = await db.customSelect(
        'SELECT * FROM cached_public_profiles WHERE user_id IN ($placeholders)',
        variables: <Variable<Object>>[
          for (final id in ids) Variable<String>(id),
        ],
      ).get();

      var changed = false;
      for (final r in rows) {
        final d = r.data;
        final uid = d['user_id']?.toString() ?? '';
        if (uid.isEmpty || _memory.containsKey(uid)) continue;
        final rawLastSeen = d['last_seen_at']?.toString();
        final rawUpdated = (d['updated_at'] as num?)?.toInt();
        _memory[uid] = PublicProfile(
          userId: uid,
          username: d['username']?.toString(),
          fullName: d['full_name']?.toString(),
          avatarUrl: MediaUrlNormalizer.normalize(d['avatar_url']?.toString()),
          lastSeenAtUtc:
              rawLastSeen != null ? DateTime.tryParse(rawLastSeen)?.toUtc() : null,
          updatedAtUtc: rawUpdated != null
              ? DateTime.fromMillisecondsSinceEpoch(rawUpdated, isUtc: true)
              : null,
        );
        changed = true;
      }
      if (changed) notifyListeners();
    } catch (_) {}
  }

  Future<void> putAll(
    Iterable<PublicProfile> profiles, {
    bool persistToDisk = true,
  }) async {
    final incomingList = profiles.toList(growable: false);
    if (incomingList.isEmpty) return;

    var changed = false;
    final toPersist = <PublicProfile>[];
    final nowUtc = DateTime.now().toUtc();

    for (final raw in incomingList) {
      if (raw.userId.trim().isEmpty) continue;
      final existing = _memory[raw.userId];
      final normalizedAvatar = MediaUrlNormalizer.normalize(raw.avatarUrl);
      final oldAvatar = existing?.avatarUrl;
      if (oldAvatar != null &&
          oldAvatar.isNotEmpty &&
          normalizedAvatar != null &&
          normalizedAvatar != oldAvatar) {
        _onEvictImageUrl(oldAvatar);
      }

      final next = PublicProfile(
        userId: raw.userId,
        username: raw.username ?? existing?.username,
        fullName: (raw.fullName?.trim().isNotEmpty == true)
            ? raw.fullName!.trim()
            : existing?.fullName,
        avatarUrl: normalizedAvatar ?? existing?.avatarUrl,
        lastSeenAtUtc: raw.lastSeenAtUtc ?? existing?.lastSeenAtUtc,
        updatedAtUtc: raw.updatedAtUtc ?? nowUtc,
      );

      if (existing == null ||
          existing.username != next.username ||
          existing.fullName != next.fullName ||
          existing.avatarUrl != next.avatarUrl ||
          existing.lastSeenAtUtc != next.lastSeenAtUtc) {
        changed = true;
      }
      _memory[raw.userId] = next;
      toPersist.add(next);
      if (next.avatarUrl != null && next.avatarUrl!.isNotEmpty) {
        unawaited(AvatarDiskCache.instance.ensureCached(next.userId, next.avatarUrl));
      }
    }

    if (changed) {
      notifyListeners();
    }

    if (!persistToDisk || toPersist.isEmpty) return;
    final db = await _db();
    if (db == null) return;
    try {
      await db.transaction(() async {
        for (final p in toPersist) {
          await db.customInsert(
            '''
            INSERT INTO cached_public_profiles (
              user_id, username, full_name, avatar_url, last_seen_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(user_id) DO UPDATE SET
              username = COALESCE(excluded.username, cached_public_profiles.username),
              full_name = COALESCE(excluded.full_name, cached_public_profiles.full_name),
              avatar_url = COALESCE(excluded.avatar_url, cached_public_profiles.avatar_url),
              last_seen_at = COALESCE(excluded.last_seen_at, cached_public_profiles.last_seen_at),
              updated_at = excluded.updated_at
            ''',
            variables: <Variable<Object>>[
              Variable<String>(p.userId),
              _nullableText(p.username),
              _nullableText(p.fullName),
              _nullableText(p.avatarUrl),
              _nullableText(p.lastSeenAtUtc?.toUtc().toIso8601String()),
              Variable<int>(
                (p.updatedAtUtc ?? nowUtc).toUtc().millisecondsSinceEpoch,
              ),
            ],
          );
        }
      });
    } catch (_) {}
  }

  /// Mengambil profil terbaru dari server untuk [userIds], memperbarui cache
  /// memori + disk, dan memicu pembaruan UI secara reaktif.
  Future<Map<String, PublicProfile>> fetchProfiles(
    Iterable<String> userIds, {
    bool forceRefresh = false,
  }) async {
    final requested = userIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (requested.isEmpty) return const <String, PublicProfile>{};

    await hydrateFromDisk(requested);

    final validUuids = requested.where(isValidUuid).toList(growable: false);
    final toFetch = forceRefresh
        ? validUuids
        : validUuids.where((id) {
            final existing = _memory[id];
            if (existing == null) return true;
            final updated = existing.updatedAtUtc;
            if (updated == null) return true;
            return DateTime.now().toUtc().difference(updated).inMinutes >= 2;
          }).toList(growable: false);

    if (toFetch.isNotEmpty) {
      try {
        final fetched = await _remoteFetcher(toFetch);
        await putAll(fetched);
      } catch (_) {}
    }

    return <String, PublicProfile>{
      for (final id in requested)
        if (_memory[id] != null) id: _memory[id]!,
    };
  }

  static Future<List<PublicProfile>> _defaultRemoteFetcher(
    List<String> userIds,
  ) async {
    final client = SupabaseServices.clientOrNull;
    if (client == null || client.auth.currentUser == null || userIds.isEmpty) {
      return const <PublicProfile>[];
    }
    try {
      final raw = await client.rpc(
        'get_public_profiles',
        params: <String, dynamic>{'p_user_ids': userIds},
      );
      if (raw is List) {
        return raw.whereType<Map>().map((row) {
          final r = Map<String, dynamic>.from(row);
          final rawLastSeen = r['last_seen_at']?.toString();
          return PublicProfile(
            userId: r['id']?.toString() ?? '',
            username: r['username']?.toString(),
            fullName: r['full_name']?.toString(),
            avatarUrl: MediaUrlNormalizer.normalize(r['avatar_url']?.toString()),
            lastSeenAtUtc: rawLastSeen != null
                ? DateTime.tryParse(rawLastSeen)?.toUtc()
                : null,
            updatedAtUtc: DateTime.now().toUtc(),
          );
        }).where((p) => p.userId.isNotEmpty).toList(growable: false);
      }
    } catch (_) {
      // Fallback bila RPC belum dimigrasi: hanya membaca profil yang diizinkan RLS.
      final rows = await client
          .from('profiles')
          .select('id, username, full_name, avatar_url, last_seen_at')
          .inFilter('id', userIds);
      return rows.map((r) {
        final rawLastSeen = r['last_seen_at']?.toString();
        return PublicProfile(
          userId: r['id']?.toString() ?? '',
          username: r['username']?.toString(),
          fullName: r['full_name']?.toString(),
          avatarUrl: MediaUrlNormalizer.normalize(r['avatar_url']?.toString()),
          lastSeenAtUtc: rawLastSeen != null
              ? DateTime.tryParse(rawLastSeen)?.toUtc()
              : null,
          updatedAtUtc: DateTime.now().toUtc(),
        );
      }).where((p) => p.userId.isNotEmpty).toList(growable: false);
    }
    return const <PublicProfile>[];
  }

  void clearMemory() {
    _memory.clear();
    notifyListeners();
  }
}
