import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../infrastructure/cache/public_profile_cache_service.dart';
import '../../../infrastructure/storage/media_url_normalizer.dart';
import '../../../infrastructure/storage/r2_media_service.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import 'community_media_tools.dart';

/// Urutan fallback `sender_name` wajib untuk `community_messages`:
/// `displayName` -> `username` -> awalan email -> `'Pendaki'`.
String resolveCommunitySenderName({
  String? displayName,
  String? fullName,
  String? username,
  String? email,
}) {
  final d = displayName?.trim();
  if (d != null && d.isNotEmpty) return d;
  final f = fullName?.trim();
  if (f != null && f.isNotEmpty) return f;
  final u = username?.trim().replaceFirst(RegExp(r'^@+'), '');
  if (u != null && u.isNotEmpty) return u;
  final e = email?.trim();
  if (e != null && e.contains('@')) {
    final prefix = e.split('@').first.trim();
    if (prefix.isNotEmpty) return prefix;
  }
  return 'Pendaki';
}

@immutable
class CommunitySummary {
  const CommunitySummary({
    required this.id,
    required this.name,
    required this.description,
    this.avatarUrl,
    required this.ownerId,
    this.createdBy,
    this.creatorName,
    this.creatorUsername,
    this.creatorAvatarUrl,
    required this.memberCount,
    required this.isJoined,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String description;
  final String? avatarUrl;
  final String ownerId;
  final String? createdBy;
  final String? creatorName;
  final String? creatorUsername;
  final String? creatorAvatarUrl;
  final int memberCount;
  final bool isJoined;
  final DateTime createdAt;

  bool isOwner(String? userId) => userId != null && userId == ownerId;

  CommunitySummary copyWith({
    String? name,
    String? description,
    String? avatarUrl,
    String? creatorName,
    String? creatorUsername,
    String? creatorAvatarUrl,
    int? memberCount,
    bool? isJoined,
  }) =>
      CommunitySummary(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        ownerId: ownerId,
        createdBy: createdBy,
        creatorName: creatorName ?? this.creatorName,
        creatorUsername: creatorUsername ?? this.creatorUsername,
        creatorAvatarUrl: creatorAvatarUrl ?? this.creatorAvatarUrl,
        memberCount: memberCount ?? this.memberCount,
        isJoined: isJoined ?? this.isJoined,
        createdAt: createdAt,
      );
}

enum CommunityMessageType { text, image, video }

@immutable
class CommunityMessage {
  const CommunityMessage({
    required this.id,
    required this.communityId,
    required this.senderId,
    required this.senderName,
    this.senderUsername,
    this.senderAvatarUrl,
    required this.messageType,
    this.content,
    this.mediaUrl,
    this.mediaThumbnailUrl,
    this.mediaDurationSec,
    this.isDeleted = false,
    this.deletedAt,
    this.replyToMessageId,
    this.replyToSenderId,
    this.replyToSenderName,
    this.replyToContent,
    this.replyToMessageType,
    this.replyToIsDeleted = false,
    this.mentionedUserIds = const <String>[],
    required this.createdAt,
  });

  final String id;
  final String communityId;
  final String senderId;
  final String senderName;
  final String? senderUsername;
  final String? senderAvatarUrl;
  final CommunityMessageType messageType;
  final String? content;
  final String? mediaUrl;
  final String? mediaThumbnailUrl;
  final int? mediaDurationSec;
  final bool isDeleted;
  final DateTime? deletedAt;
  final String? replyToMessageId;
  final String? replyToSenderId;
  final String? replyToSenderName;
  final String? replyToContent;
  final CommunityMessageType? replyToMessageType;
  final bool replyToIsDeleted;
  final List<String> mentionedUserIds;
  final DateTime createdAt;
}

@immutable
class CommunityMemberEntry {
  const CommunityMemberEntry({
    required this.userId,
    required this.username,
    required this.fullName,
    this.avatarUrl,
    required this.role,
    required this.joinedAt,
    this.lastSeenAt,
  });

  final String userId;
  final String username;
  final String fullName;
  final String? avatarUrl;
  final String role;
  final DateTime joinedAt;
  final DateTime? lastSeenAt;
}

/// Layanan komunitas online-only (Supabase Postgres + Cloudflare R2 Presigned
/// URL untuk avatar & media, dengan fallback bucket `community-media`).
class CommunityService extends ChangeNotifier {
  CommunityService._();

  static final CommunityService instance = CommunityService._();

  static const String mediaBucket = 'community-media';
  static const int maxVideoDurationSec = 60;
  static const Duration _timeout = Duration(seconds: 9);

  List<CommunitySummary> _communities = const <CommunitySummary>[];
  bool _loading = false;
  String? _error;

  List<CommunitySummary> get communities => _communities;
  bool get isLoading => _loading;
  String? get error => _error;

  /// Mengosongkan daftar komunitas dan stempel kunjungan saat berganti akun.
  void clearForAccountChange() {
    _communities = const <CommunitySummary>[];
    _firstEnteredCache.clear();
    _loading = false;
    _error = null;
    notifyListeners();
  }

  Future<void> loadCommunities() async {
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      _communities = const <CommunitySummary>[];
      _error = 'Masuk akun dan sambungkan internet untuk mengakses Komunitas.';
      notifyListeners();
      return;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      List<dynamic> rpcRows = const <dynamic>[];
      var usedRpc = false;
      try {
        final raw =
            await client.rpc('list_communities_with_meta').timeout(_timeout);
        if (raw is List) {
          rpcRows = raw;
          usedRpc = true;
        }
      } on PostgrestException catch (error) {
        final msg = '${error.message} ${error.details ?? ''}';
        if (error.code != 'PGRST202' &&
            error.code != '42883' &&
            !msg.contains('list_communities_with_meta')) {
          rethrow;
        }
      }

      if (usedRpc) {
        final creatorProfiles = <PublicProfile>[];
        _communities = rpcRows.whereType<Map>().map<CommunitySummary>((raw) {
          final r = Map<String, dynamic>.from(raw);
          final id = r['id']?.toString() ?? '';
          final ownerId = r['owner_id']?.toString() ?? '';
          final createdBy = r['created_by']?.toString() ?? ownerId;
          final creatorName = r['creator_name']?.toString();
          final creatorUsername = r['creator_username']?.toString();
          final creatorAvatar =
              MediaUrlNormalizer.normalize(r['creator_avatar_url']?.toString());
          if (createdBy.isNotEmpty) {
            creatorProfiles.add(
              PublicProfile(
                userId: createdBy,
                username: creatorUsername,
                fullName: creatorName,
                avatarUrl: creatorAvatar,
              ),
            );
          }
          return CommunitySummary(
            id: id,
            name: r['name']?.toString() ?? 'Komunitas',
            description: r['description']?.toString() ?? '',
            avatarUrl:
                MediaUrlNormalizer.normalize(r['avatar_url']?.toString()),
            ownerId: ownerId,
            createdBy: createdBy,
            creatorName: creatorName,
            creatorUsername: creatorUsername,
            creatorAvatarUrl: creatorAvatar,
            memberCount:
                ((r['member_count'] as num?)?.toInt() ?? 1).clamp(1, 999999),
            isJoined: r['is_joined'] == true,
            createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '') ??
                DateTime.now().toUtc(),
          );
        }).toList();
        if (creatorProfiles.isNotEmpty) {
          unawaited(PublicProfileCacheService.instance.putAll(creatorProfiles));
        }
      } else {
        final rows = await client
            .from('communities')
            .select('id, name, description, avatar_url, owner_id, created_at')
            .order('created_at', ascending: false)
            .timeout(_timeout);

        final memberships = await client
            .from('community_members')
            .select('community_id, user_id')
            .timeout(_timeout);

        final counts = <String, int>{};
        final joinedIds = <String>{};
        for (final m in memberships) {
          final cid = m['community_id']?.toString() ?? '';
          final uid = m['user_id']?.toString() ?? '';
          if (cid.isEmpty) continue;
          counts[cid] = (counts[cid] ?? 0) + 1;
          if (uid == user.id) joinedIds.add(cid);
        }

        final ownerIds = <String>{
          for (final r in rows)
            if (r['owner_id'] != null) r['owner_id'].toString(),
        };
        final owners = ownerIds.isNotEmpty
            ? await PublicProfileCacheService.instance.fetchProfiles(ownerIds)
            : const <String, PublicProfile>{};

        _communities = rows.map<CommunitySummary>((r) {
          final id = r['id']?.toString() ?? '';
          final ownerId = r['owner_id']?.toString() ?? '';
          final creator = owners[ownerId];
          return CommunitySummary(
            id: id,
            name: r['name']?.toString() ?? 'Komunitas',
            description: r['description']?.toString() ?? '',
            avatarUrl:
                MediaUrlNormalizer.normalize(r['avatar_url']?.toString()),
            ownerId: ownerId,
            createdBy: ownerId,
            creatorName: creator?.displayName,
            creatorUsername: creator?.username,
            creatorAvatarUrl: creator?.avatarUrl,
            memberCount: counts[id] ?? 1,
            isJoined: joinedIds.contains(id),
            createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '') ??
                DateTime.now().toUtc(),
          );
        }).toList();
      }
      _loading = false;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CommunityService.loadCommunities failed: $e');
      }
      _loading = false;
      _error = 'Belum bisa memuat komunitas. Periksa sinyal lalu coba lagi.';
      notifyListeners();
    }
  }

  /// Mengunggah foto profil komunitas (`community-avatars/{communityId}.webp`)
  /// ke Cloudflare R2 lewat [R2MediaService] (tanpa menyentuh Supabase Storage).
  Future<String> _uploadCommunityAvatar(
    File file, {
    required String communityId,
    R2MediaService? mediaService,
  }) async {
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      throw StateError('Sesi akun tidak aktif.');
    }
    return (mediaService ?? R2MediaService.instance).uploadCommunityAvatar(
      file,
      communityId: communityId,
    );
  }

  Future<({String senderName, String? senderAvatar})> _resolveCurrentSender(
    SupabaseClient client,
    User user,
  ) async {
    final cached = SupabaseServices.sharedAccountController?.profile;
    final meta = user.userMetadata ?? const <String, dynamic>{};
    String? fullName = cached?.fullName ??
        meta['full_name']?.toString() ??
        meta['name']?.toString();
    String? username = cached?.username;
    String? avatar = cached?.avatarUrl ?? meta['avatar_url']?.toString();

    if ((fullName == null || fullName.trim().isEmpty) &&
        (username == null || username.trim().isEmpty)) {
      try {
        final prof = await client
            .from('profiles')
            .select('username, full_name, avatar_url')
            .eq('id', user.id)
            .maybeSingle();
        if (prof != null) {
          fullName ??= prof['full_name']?.toString();
          username ??= prof['username']?.toString();
          avatar ??= prof['avatar_url']?.toString();
        }
      } catch (_) {}
    }

    final resolved = resolveCommunitySenderName(
      displayName: fullName,
      username: username,
      email: user.email,
    );
    return (senderName: resolved, senderAvatar: avatar);
  }

  final Map<String, DateTime> _firstEnteredCache = <String, DateTime>{};

  static String _firstEntryPrefKey(String userId, String communityId) =>
      'community_first_entry_${userId}_$communityId';

  Future<CommunitySummary> createCommunity({
    required String name,
    required String description,
    File? avatarFile,
    R2MediaService? mediaService,
  }) async {
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      throw StateError('Masuk akun terlebih dahulu.');
    }
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Nama komunitas tidak boleh kosong.');
    }
    if (trimmedName.length > 80) {
      throw ArgumentError('Nama komunitas maksimal 80 karakter.');
    }

    final trimmedDesc = description.trim();
    final r2 = mediaService ?? R2MediaService.instance;
    final avatarPrepFuture =
        avatarFile != null ? r2.prepareAvatarWebp(avatarFile) : null;
    final insertFuture = client
        .from('communities')
        .insert(<String, dynamic>{
          'name': trimmedName,
          'description': trimmedDesc,
          'avatar_url': null,
          'owner_id': user.id,
        })
        .select('id, name, description, avatar_url, owner_id, created_at')
        .single()
        .timeout(_timeout);

    final row = await insertFuture;
    final communityId = row['id'].toString();
    final nowUtc = DateTime.now().toUtc();
    final nowIso = nowUtc.toIso8601String();
    _firstEnteredCache[communityId] = nowUtc;

    final memberFuture = client.from('community_members').upsert(<String, dynamic>{
      'community_id': communityId,
      'user_id': user.id,
      'role': 'owner',
      'first_entered_at': nowIso,
    }).timeout(_timeout);

    String? avatarUrl;
    if (avatarPrepFuture != null) {
      final webpBytes = await avatarPrepFuture;
      final uploadResults = await Future.wait<dynamic>(<Future<dynamic>>[
        memberFuture,
        r2.uploadPreparedCommunityAvatarWebp(
          webpBytes,
          communityId: communityId,
        ),
      ]);
      avatarUrl = uploadResults[1] as String?;
      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        await client
            .from('communities')
            .update(<String, dynamic>{'avatar_url': avatarUrl})
            .eq('id', communityId)
            .timeout(_timeout);
      }
    } else {
      await memberFuture;
    }

    final created = CommunitySummary(
      id: communityId,
      name: row['name'].toString(),
      description: row['description']?.toString() ?? '',
      avatarUrl: MediaUrlNormalizer.normalize(avatarUrl),
      ownerId: row['owner_id'].toString(),
      createdBy: row['owner_id'].toString(),
      memberCount: 1,
      isJoined: true,
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          nowUtc,
    );
    _communities = <CommunitySummary>[
      created,
      ..._communities.where((c) => c.id != communityId),
    ];
    notifyListeners();
    unawaited(loadCommunities());
    return created;
  }

  Future<CommunitySummary> updateCommunity({
    required CommunitySummary community,
    required String name,
    required String description,
    File? newAvatarFile,
  }) async {
    final client = SupabaseServices.clientOrNull;
    if (client == null) throw StateError('Koneksi tidak tersedia.');
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Nama komunitas tidak boleh kosong.');
    }
    if (trimmedName.length > 80) {
      throw ArgumentError('Nama komunitas maksimal 80 karakter.');
    }

    String? avatarUrl = community.avatarUrl;
    if (newAvatarFile != null) {
      avatarUrl = await _uploadCommunityAvatar(
        newAvatarFile,
        communityId: community.id,
      );
    }

    await client.from('communities').update(<String, dynamic>{
      'name': trimmedName,
      'description': description.trim(),
      'avatar_url': avatarUrl,
    }).eq('id', community.id);

    final updated = community.copyWith(
      name: name.trim(),
      description: description.trim(),
      avatarUrl: avatarUrl,
    );
    _communities =
        _communities.map((c) => c.id == updated.id ? updated : c).toList();
    notifyListeners();
    return updated;
  }

  Future<void> joinCommunity(
    String communityId, {
    bool isOwner = false,
  }) async {
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      throw StateError('Masuk akun terlebih dahulu.');
    }
    final firstEntered = _firstEnteredCache[communityId];
    await client.from('community_members').upsert(<String, dynamic>{
      'community_id': communityId,
      'user_id': user.id,
      'role': isOwner ? 'owner' : 'member',
      if (firstEntered != null)
        'first_entered_at': firstEntered.toUtc().toIso8601String(),
    }).timeout(_timeout);
    _communities = _communities
        .map(
          (c) => c.id == communityId && !c.isJoined
              ? c.copyWith(isJoined: true, memberCount: c.memberCount + 1)
              : c,
        )
        .toList(growable: false);
    notifyListeners();
    unawaited(loadCommunities());
  }

  Future<void> leaveCommunity(String communityId) async {
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    await client
        .from('community_members')
        .delete()
        .eq('community_id', communityId)
        .eq('user_id', user.id)
        .timeout(_timeout);
    _communities = _communities
        .map(
          (c) => c.id == communityId
              ? c.copyWith(
                  isJoined: false,
                  memberCount: (c.memberCount - 1).clamp(0, 999999),
                )
              : c,
        )
        .toList(growable: false);
    notifyListeners();
    unawaited(loadCommunities());
  }

  /// Menghapus komunitas secara permanen dari Supabase (dan state lokal).
  Future<void> deleteCommunity(String communityId) async {
    final client = SupabaseServices.clientOrNull;
    if (client == null) throw StateError('Koneksi tidak tersedia.');
    try {
      await client.rpc(
        'delete_community',
        params: <String, dynamic>{'p_community_id': communityId},
      ).timeout(_timeout);
    } catch (_) {
      await client
          .from('communities')
          .delete()
          .eq('id', communityId)
          .timeout(_timeout);
    }
    _firstEnteredCache.remove(communityId);
    _communities = _communities.where((c) => c.id != communityId).toList();
    notifyListeners();
  }

  /// Mencatat waktu pertama pengguna membuka ruang obrolan komunitas (sebelum
  /// atau saat bergabung) untuk membatasi riwayat pesan lama (#13).
  Future<DateTime?> recordFirstEntry(String communityId) async {
    final cached = _firstEnteredCache[communityId];
    if (cached != null) return cached;

    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    final uid = user?.id ?? 'anon';
    final prefs = await SharedPreferences.getInstance();
    final prefKey = _firstEntryPrefKey(uid, communityId);
    final rawLocal = prefs.getString(prefKey);
    final localParsed =
        rawLocal != null ? DateTime.tryParse(rawLocal)?.toUtc() : null;

    if (client != null && user != null) {
      try {
        final raw = await client.rpc(
          'record_community_first_entry',
          params: <String, dynamic>{'p_community_id': communityId},
        ).timeout(_timeout);
        final parsed =
            raw != null ? DateTime.tryParse(raw.toString())?.toUtc() : null;
        if (parsed != null) {
          _firstEnteredCache[communityId] = parsed;
          unawaited(prefs.setString(prefKey, parsed.toIso8601String()));
          return parsed;
        }
      } on PostgrestException catch (error) {
        final msg = '${error.message} ${error.details ?? ''}';
        if (error.code != 'PGRST202' &&
            error.code != '42883' &&
            !msg.contains('record_community_first_entry')) {
          if (localParsed != null) {
            _firstEnteredCache[communityId] = localParsed;
            return localParsed;
          }
          rethrow;
        }
      } catch (_) {}
    }

    final resolved = localParsed ?? DateTime.now().toUtc();
    _firstEnteredCache[communityId] = resolved;
    unawaited(prefs.setString(prefKey, resolved.toIso8601String()));
    return resolved;
  }

  Future<List<CommunityMessage>> fetchMessages(String communityId) async {
    final page = await fetchMessagesPage(communityId, limit: 40);
    return page.messages;
  }

  Future<({List<CommunityMessage> messages, bool hasMore})> fetchMessagesPage(
    String communityId, {
    int limit = 40,
    DateTime? beforeUtc,
    DateTime? sinceUtc,
  }) async {
    final client = SupabaseServices.clientOrNull;
    if (client == null) {
      return (messages: const <CommunityMessage>[], hasMore: false);
    }
    final effectiveLimit = limit.clamp(1, 200);
    final probeLimit = effectiveLimit + 1;
    final effectiveSince = (sinceUtc ?? await recordFirstEntry(communityId))?.toUtc();

    try {
      final raw = await client.rpc(
        'get_community_messages',
        params: <String, dynamic>{
          'p_community_id': communityId,
          'p_limit': probeLimit,
          if (beforeUtc != null) 'p_before': beforeUtc.toUtc().toIso8601String(),
          if (effectiveSince != null)
            'p_since': effectiveSince.toIso8601String(),
        },
      ).timeout(_timeout);
      if (raw is List) {
        final profilesToSeed = <PublicProfile>[];
        final messages = <CommunityMessage>[];
        for (final item in raw) {
          if (item is! Map) continue;
          final r = Map<String, dynamic>.from(item);
          final sid = r['sender_id']?.toString() ?? '';
          final username = r['sender_username']?.toString();
          final senderAvatar =
              MediaUrlNormalizer.normalize(r['sender_avatar_url']?.toString());
          final senderName = resolveCommunitySenderName(
            displayName: r['sender_name']?.toString(),
            username: username,
          );
          if (sid.isNotEmpty) {
            profilesToSeed.add(
              PublicProfile(
                userId: sid,
                username: username,
                fullName: senderName,
                avatarUrl: senderAvatar,
              ),
            );
          }
          final rawMentions = r['mentioned_user_ids'];
          final mentions = <String>[
            if (rawMentions is List)
              for (final m in rawMentions)
                if (m != null && m.toString().trim().isNotEmpty)
                  m.toString().trim(),
          ];
          final isDeleted = r['is_deleted'] == true || r['deleted_at'] != null;
          messages.add(
            CommunityMessage(
              id: r['id']?.toString() ?? '',
              communityId: communityId,
              senderId: sid,
              senderName: senderName,
              senderUsername: username,
              senderAvatarUrl: senderAvatar,
              messageType: _parseMessageType(r['message_type']?.toString()),
              content: isDeleted ? null : r['content']?.toString(),
              mediaUrl: isDeleted
                  ? null
                  : MediaUrlNormalizer.normalize(r['media_url']?.toString()),
              mediaThumbnailUrl: isDeleted
                  ? null
                  : MediaUrlNormalizer.normalize(
                      r['media_thumbnail_url']?.toString(),
                    ),
              mediaDurationSec:
                  isDeleted ? null : (r['media_duration_sec'] as num?)?.toInt(),
              isDeleted: isDeleted,
              deletedAt: r['deleted_at'] != null
                  ? DateTime.tryParse(r['deleted_at'].toString())?.toUtc()
                  : null,
              replyToMessageId: r['reply_to_message_id']?.toString(),
              replyToSenderId: r['reply_to_sender_id']?.toString(),
              replyToSenderName: r['reply_to_sender_name']?.toString(),
              replyToContent: r['reply_to_content']?.toString(),
              replyToMessageType: r['reply_to_message_type'] != null
                  ? _parseMessageType(r['reply_to_message_type']?.toString())
                  : null,
              replyToIsDeleted: r['reply_to_is_deleted'] == true,
              mentionedUserIds: mentions,
              createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '')
                      ?.toUtc() ??
                  DateTime.now().toUtc(),
            ),
          );
        }
        if (profilesToSeed.isNotEmpty) {
          unawaited(PublicProfileCacheService.instance.putAll(profilesToSeed));
        }
        final hasMore = messages.length > effectiveLimit;
        final trimmed = hasMore
            ? messages.sublist(messages.length - effectiveLimit)
            : messages;
        return (messages: trimmed, hasMore: hasMore);
      }
    } on PostgrestException catch (error) {
      final msg = '${error.message} ${error.details ?? ''}';
      if (error.code != 'PGRST202' &&
          error.code != '42883' &&
          !msg.contains('get_community_messages')) {
        rethrow;
      }
    }

    Future<List<dynamic>> queryFallback(String columns) {
      var q = client
          .from('community_messages')
          .select(columns)
          .eq('community_id', communityId);
      if (effectiveSince != null) {
        q = q.gte('created_at', effectiveSince.toIso8601String());
      }
      if (beforeUtc != null) {
        q = q.lt('created_at', beforeUtc.toUtc().toIso8601String());
      }
      return q
          .order('created_at', ascending: false)
          .limit(probeLimit)
          .timeout(_timeout);
    }

    List<dynamic> rowsDesc;
    try {
      rowsDesc = await queryFallback(
        'id, community_id, sender_id, sender_name, message_type, content, media_url, media_thumbnail_url, media_duration_sec, is_deleted, deleted_at, reply_to_message_id, mentioned_user_ids, created_at',
      );
    } catch (e) {
      final errStr = e.toString();
      if (!errStr.contains('media_thumbnail_url') &&
          !errStr.contains('is_deleted') &&
          !errStr.contains('reply_to_message_id')) {
        rethrow;
      }
      rowsDesc = await queryFallback(
        'id, community_id, sender_id, sender_name, message_type, content, media_url, media_duration_sec, created_at',
      );
    }

    final rows = rowsDesc.reversed.toList(growable: false);
    final senderIds = <String>{
      for (final r in rows)
        if (r['sender_id'] != null) r['sender_id'].toString(),
    };
    final profilesById = senderIds.isNotEmpty
        ? await PublicProfileCacheService.instance.fetchProfiles(
            senderIds,
            forceRefresh: true,
          )
        : const <String, PublicProfile>{};

    final parsed = rows.map<CommunityMessage>((r) {
      final sid = r['sender_id']?.toString() ?? '';
      final prof = profilesById[sid];
      final username = prof?.username;
      final senderName = resolveCommunitySenderName(
        displayName: prof?.fullName,
        fullName: r['sender_name']?.toString(),
        username: username,
      );
      final isDeleted = r['is_deleted'] == true || r['deleted_at'] != null;
      final rawMentions = r['mentioned_user_ids'];
      final mentions = <String>[
        if (rawMentions is List)
          for (final m in rawMentions)
            if (m != null && m.toString().trim().isNotEmpty)
              m.toString().trim(),
      ];
      return CommunityMessage(
        id: r['id']?.toString() ?? '',
        communityId: communityId,
        senderId: sid,
        senderName: senderName,
        senderUsername: username,
        // Never use static `r['sender_avatar']` snapshot — always resolve dynamically from `profiles`.
        senderAvatarUrl: prof?.avatarUrl,
        messageType: _parseMessageType(r['message_type']?.toString()),
        content: isDeleted ? null : r['content']?.toString(),
        mediaUrl: isDeleted
            ? null
            : MediaUrlNormalizer.normalize(r['media_url']?.toString()),
        mediaThumbnailUrl: isDeleted
            ? null
            : MediaUrlNormalizer.normalize(
                r['media_thumbnail_url']?.toString()),
        mediaDurationSec:
            isDeleted ? null : (r['media_duration_sec'] as num?)?.toInt(),
        isDeleted: isDeleted,
        deletedAt: r['deleted_at'] != null
            ? DateTime.tryParse(r['deleted_at'].toString())?.toUtc()
            : null,
        replyToMessageId: r['reply_to_message_id']?.toString(),
        mentionedUserIds: mentions,
        createdAt:
            DateTime.tryParse(r['created_at']?.toString() ?? '')?.toUtc() ??
                DateTime.now().toUtc(),
      );
    }).toList();

    final hasMore = parsed.length > effectiveLimit;
    final trimmed = hasMore
        ? parsed.sublist(parsed.length - effectiveLimit)
        : parsed;
    return (messages: trimmed, hasMore: hasMore);
  }

  static CommunityMessageType _parseMessageType(String? rawType) {
    return switch (rawType) {
      'image' => CommunityMessageType.image,
      'video' => CommunityMessageType.video,
      _ => CommunityMessageType.text,
    };
  }

  Future<List<CommunityMemberEntry>> fetchCommunityMembers(
    String communityId,
  ) async {
    final client = SupabaseServices.clientOrNull;
    if (client == null) return const <CommunityMemberEntry>[];
    try {
      final raw = await client.rpc(
        'list_community_members',
        params: <String, dynamic>{'p_community_id': communityId},
      ).timeout(_timeout);
      if (raw is List) {
        final members = <CommunityMemberEntry>[];
        final profiles = <PublicProfile>[];
        for (final item in raw) {
          if (item is! Map) continue;
          final r = Map<String, dynamic>.from(item);
          final uid = r['user_id']?.toString() ?? '';
          if (uid.isEmpty) continue;
          final username = r['username']?.toString() ?? '';
          final fullName = r['full_name']?.toString() ?? 'Pendaki';
          final avatarUrl =
              MediaUrlNormalizer.normalize(r['avatar_url']?.toString());
          final lastSeen = r['last_seen_at'] != null
              ? DateTime.tryParse(r['last_seen_at'].toString())?.toUtc()
              : null;
          profiles.add(
            PublicProfile(
              userId: uid,
              username: username.isNotEmpty ? username : null,
              fullName: fullName,
              avatarUrl: avatarUrl,
              lastSeenAtUtc: lastSeen,
            ),
          );
          members.add(
            CommunityMemberEntry(
              userId: uid,
              username: username,
              fullName: fullName,
              avatarUrl: avatarUrl,
              role: r['role']?.toString() ?? 'member',
              joinedAt: DateTime.tryParse(r['joined_at']?.toString() ?? '')
                      ?.toUtc() ??
                  DateTime.now().toUtc(),
              lastSeenAt: lastSeen,
            ),
          );
        }
        if (profiles.isNotEmpty) {
          unawaited(PublicProfileCacheService.instance.putAll(profiles));
        }
        return members;
      }
    } catch (_) {}

    try {
      final rows = await client
          .from('community_members')
          .select('user_id, role, joined_at')
          .eq('community_id', communityId)
          .timeout(_timeout);
      final uids = <String>[
        for (final r in rows)
          if (r['user_id'] != null) r['user_id'].toString(),
      ];
      final profs =
          await PublicProfileCacheService.instance.fetchProfiles(uids);
      return rows.map<CommunityMemberEntry>((r) {
        final uid = r['user_id']?.toString() ?? '';
        final p = profs[uid];
        return CommunityMemberEntry(
          userId: uid,
          username: p?.username ?? '',
          fullName: p?.displayName ?? 'Pendaki',
          avatarUrl: p?.avatarUrl,
          role: r['role']?.toString() ?? 'member',
          joinedAt:
              DateTime.tryParse(r['joined_at']?.toString() ?? '')?.toUtc() ??
                  DateTime.now().toUtc(),
          lastSeenAt: p?.lastSeenAtUtc,
        );
      }).toList(growable: false);
    } catch (_) {
      return const <CommunityMemberEntry>[];
    }
  }

  Future<void> deleteMessage(String messageId) async {
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      throw StateError('Masuk akun dan pastikan internet aktif.');
    }
    try {
      await client.rpc(
        'soft_delete_community_message',
        params: <String, dynamic>{'p_message_id': messageId},
      );
    } on PostgrestException catch (error) {
      final msg = '${error.message} ${error.details ?? ''}';
      if (error.code == 'PGRST202' ||
          error.code == '42883' ||
          msg.contains('soft_delete_community_message')) {
        await client
            .from('community_messages')
            .update(<String, dynamic>{
              'is_deleted': true,
              'deleted_at': DateTime.now().toUtc().toIso8601String(),
              'content': null,
              'media_url': null,
              'media_thumbnail_url': null,
              'media_mime': null,
              'media_duration_sec': null,
              'message_type': 'text',
            })
            .eq('id', messageId)
            .eq('sender_id', user.id);
      } else {
        rethrow;
      }
    }
  }

  Future<void> sendTextMessage({
    required String communityId,
    required String text,
    String? replyToMessageId,
    List<String> mentionedUserIds = const <String>[],
  }) async {
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      throw StateError('Masuk akun dan pastikan internet aktif.');
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (trimmed.length > 2000) {
      throw ArgumentError('Pesan maksimal 2000 karakter.');
    }

    final sender = await _resolveCurrentSender(client, user);
    await client.from('community_messages').insert(<String, dynamic>{
      'community_id': communityId,
      'sender_id': user.id,
      'sender_name': sender.senderName,
      if (sender.senderAvatar != null && sender.senderAvatar!.isNotEmpty)
        'sender_avatar': sender.senderAvatar,
      'message_type': 'text',
      'content': trimmed,
      if (replyToMessageId != null && replyToMessageId.isNotEmpty)
        'reply_to_message_id': replyToMessageId,
      if (mentionedUserIds.isNotEmpty) 'mentioned_user_ids': mentionedUserIds,
    });
  }

  Future<void> sendImageMessage({
    required String communityId,
    required File imageFile,
    String? caption,
    String? replyToMessageId,
    List<String> mentionedUserIds = const <String>[],
    R2MediaService? mediaService,
  }) async {
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      throw StateError('Masuk akun dan pastikan internet aktif.');
    }
    final url = await (mediaService ?? R2MediaService.instance)
        .uploadCommunityImage(imageFile, communityId: communityId);
    final sender = await _resolveCurrentSender(client, user);
    await client.from('community_messages').insert(<String, dynamic>{
      'community_id': communityId,
      'sender_id': user.id,
      'sender_name': sender.senderName,
      if (sender.senderAvatar != null && sender.senderAvatar!.isNotEmpty)
        'sender_avatar': sender.senderAvatar,
      'message_type': 'image',
      'media_url': url,
      'media_mime': 'image/webp',
      if (caption != null && caption.trim().isNotEmpty)
        'content': caption.trim(),
      if (replyToMessageId != null && replyToMessageId.isNotEmpty)
        'reply_to_message_id': replyToMessageId,
      if (mentionedUserIds.isNotEmpty) 'mentioned_user_ids': mentionedUserIds,
    });
  }

  /// Mengunggah video maks. 60 detik dan thumbnail WebP frame pertama ke Cloudflare R2.
  Future<void> sendVideoMessage({
    required String communityId,
    required File videoFile,
    required int durationSec,
    String? caption,
    String? replyToMessageId,
    List<String> mentionedUserIds = const <String>[],
    R2MediaService? mediaService,
  }) async {
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      throw StateError('Masuk akun dan pastikan internet aktif.');
    }
    final r2 = mediaService ?? R2MediaService.instance;
    Uint8List? thumbBytes;
    try {
      thumbBytes =
          await CommunityMediaChannel.extractVideoThumbnail(videoFile.path);
    } catch (_) {}

    final uploaded = await r2.uploadCommunityVideo(
      videoFile,
      communityId: communityId,
      durationSec: durationSec,
    );

    String? thumbnailUrl;
    if (thumbBytes != null && thumbBytes.isNotEmpty) {
      await CommunityVideoThumbnailCache.instance.saveBytes(
        uploaded.publicUrl,
        thumbBytes,
      );
      try {
        thumbnailUrl = await r2.uploadCommunityImageBytes(
          thumbBytes,
          communityId: communityId,
        );
      } catch (_) {}
    }

    final sender = await _resolveCurrentSender(client, user);
    final payload = <String, dynamic>{
      'community_id': communityId,
      'sender_id': user.id,
      'sender_name': sender.senderName,
      if (sender.senderAvatar != null && sender.senderAvatar!.isNotEmpty)
        'sender_avatar': sender.senderAvatar,
      'message_type': 'video',
      'media_url': uploaded.publicUrl,
      if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
        'media_thumbnail_url': thumbnailUrl,
      'media_mime': uploaded.contentType,
      'media_duration_sec': uploaded.durationSec,
      if (caption != null && caption.trim().isNotEmpty)
        'content': caption.trim(),
      if (replyToMessageId != null && replyToMessageId.isNotEmpty)
        'reply_to_message_id': replyToMessageId,
      if (mentionedUserIds.isNotEmpty) 'mentioned_user_ids': mentionedUserIds,
    };
    try {
      await client.from('community_messages').insert(payload);
    } catch (e) {
      if (!payload.containsKey('media_thumbnail_url') ||
          !e.toString().contains('media_thumbnail_url')) {
        rethrow;
      }
      final fallback = Map<String, dynamic>.from(payload)
        ..remove('media_thumbnail_url');
      await client.from('community_messages').insert(fallback);
    }
  }

  RealtimeChannel? subscribeMessages({
    required String communityId,
    required VoidCallback onChange,
  }) {
    final client = SupabaseServices.clientOrNull;
    if (client == null) return null;
    return client
        .channel('hiqeo_community_msg_$communityId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'community_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'community_id',
            value: communityId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  Future<File> copyToTempIfNeeded(String path) async {
    final file = File(path);
    if (await file.exists()) return file;
    final dir = await getTemporaryDirectory();
    return File(p.join(dir.path, p.basename(path)));
  }
}
