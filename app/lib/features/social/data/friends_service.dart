import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../infrastructure/cache/avatar_disk_cache.dart';
import '../../../infrastructure/cache/public_profile_cache_service.dart';
import '../../../infrastructure/storage/media_url_normalizer.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../../plus/domain/plus_entitlement.dart';

@immutable
class FriendRecord {
  const FriendRecord({
    required this.friendshipId,
    required this.userId,
    required this.username,
    this.displayName,
    this.avatarUrl,
    required this.status,
    required this.isIncoming,
    required this.createdAt,
    this.isOfficial = false,
  });

  final String friendshipId;
  final String userId;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final String status; // pending | accepted
  final bool isIncoming;
  final DateTime createdAt;
  final bool isOfficial;

  String get label {
    final full = displayName?.trim();
    if (full != null && full.isNotEmpty) return full;
    final cleanUname = username.trim().replaceFirst(RegExp(r'^@+'), '');
    if (cleanUname.isNotEmpty) return '@$cleanUname';
    return 'Pendaki';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'friendship_id': friendshipId,
        'user_id': userId,
        'username': username,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'status': status,
        'is_incoming': isIncoming,
        'created_at': createdAt.toUtc().toIso8601String(),
        'is_official': isOfficial,
      };

  static FriendRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final fid = raw['friendship_id']?.toString() ?? '';
    final uid = raw['user_id']?.toString() ?? '';
    if (fid.isEmpty || uid.isEmpty) return null;
    return FriendRecord(
      friendshipId: fid,
      userId: uid,
      username: raw['username']?.toString() ?? '',
      displayName: raw['display_name']?.toString(),
      avatarUrl: MediaUrlNormalizer.normalize(raw['avatar_url']?.toString()),
      status: raw['status']?.toString() ?? 'accepted',
      isIncoming: raw['is_incoming'] == true,
      createdAt:
          DateTime.tryParse(raw['created_at']?.toString() ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
      isOfficial: raw['is_official'] == true,
    );
  }
}

@immutable
class UserSearchResult {
  const UserSearchResult({
    required this.userId,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.isOfficial = false,
  });

  final String userId;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final bool isOfficial;

  String get label =>
      (displayName != null && displayName!.trim().isNotEmpty)
          ? displayName!.trim()
          : '@$username';
}

@immutable
class OtherUserProfileData {
  const OtherUserProfileData({
    required this.userId,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.isPlus = false,
    this.plusPlanId,
    this.isUltima = false,
    this.isOfficial = false,
    this.mountainsClimbed = 0,
    this.totalDistanceM = 0,
    this.totalMovingSeconds = 0,
  });

  final String userId;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final bool isPlus;
  final String? plusPlanId;
  final bool isUltima;
  final bool isOfficial;
  final int mountainsClimbed;
  final double totalDistanceM;
  final int totalMovingSeconds;

  /// Lencana Hiqeo Plus hanya muncul bila berlangganan Paket Mahasiswa / Tahunan.
  bool get showPlusBadge =>
      isPlus &&
      !isUltima &&
      (plusPlanId == null || PlusAccess.isFullSocialPlan(plusPlanId));

  String get label =>
      (displayName != null && displayName!.trim().isNotEmpty)
          ? displayName!.trim()
          : '@$username';
}

/// Layanan daftar teman, permintaan pertemanan, notifikasi in-app Realtime,
/// dan profil ringkas pengguna lain via Supabase.
class FriendsService extends ChangeNotifier {
  FriendsService._();

  static final FriendsService instance = FriendsService._();

  final StreamController<FriendRecord> _incomingRequestController =
      StreamController<FriendRecord>.broadcast();

  Stream<FriendRecord> get onIncomingFriendRequest =>
      _incomingRequestController.stream;

  static const String _cachePrefix = 'hiqeo_friends_cache_v1_';

  List<FriendRecord> _friends = const <FriendRecord>[];
  List<FriendRecord> _incomingRequests = const <FriendRecord>[];
  List<FriendRecord> _outgoingRequests = const <FriendRecord>[];
  bool _loading = false;
  String? _error;
  String? _cachedForUserId;
  RealtimeChannel? _channel;
  String? _subscribedUserId;

  List<FriendRecord> get friends => _friends;
  List<FriendRecord> get incomingRequests => _incomingRequests;
  List<FriendRecord> get outgoingRequests => _outgoingRequests;
  int get incomingCount => _incomingRequests.length;
  bool get isLoading => _loading;
  String? get error => _error;

  void ensureRealtimeSubscribed() {
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    if (_subscribedUserId == user.id && _channel != null) return;
    _subscribedUserId = user.id;
    _channel?.unsubscribe();

    _channel = client
        .channel('hiqeo_friendships_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'friendships',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'addressee_id',
            value: user.id,
          ),
          callback: (payload) async {
            await refresh();
            final newRow = payload.newRecord;
            final id = newRow['id']?.toString();
            if (id != null) {
              for (final req in _incomingRequests) {
                if (req.friendshipId == id) {
                  _incomingRequestController.add(req);
                  break;
                }
              }
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'friendships',
          callback: (_) => unawaited(refresh()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'friendships',
          callback: (_) => unawaited(refresh()),
        )
        .subscribe();
  }

  Future<void> loadCached({String? userIdOverride}) async {
    final uid = userIdOverride ?? SupabaseServices.clientOrNull?.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;
    if (_cachedForUserId == uid &&
        (_friends.isNotEmpty ||
            _incomingRequests.isNotEmpty ||
            _outgoingRequests.isNotEmpty)) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_cachePrefix$uid');
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      List<FriendRecord> decodeList(Object? rawList) {
        if (rawList is! List) return const <FriendRecord>[];
        return rawList
            .map(FriendRecord.fromJson)
            .whereType<FriendRecord>()
            .toList(growable: false);
      }

      var accepted = decodeList(decoded['friends']);
      var incoming = decodeList(decoded['incoming']);
      var outgoing = decodeList(decoded['outgoing']);

      final allIds = <String>{
        for (final r in accepted) r.userId,
        for (final r in incoming) r.userId,
        for (final r in outgoing) r.userId,
      };
      if (allIds.isNotEmpty) {
        await PublicProfileCacheService.instance.hydrateFromDisk(allIds);
      }

      FriendRecord enrich(FriendRecord item) {
        final prof = PublicProfileCacheService.instance.getCached(item.userId);
        if (prof == null) return item;
        final uname = (prof.username?.trim().isNotEmpty == true)
            ? prof.username!.trim()
            : item.username;
        final dname = (prof.fullName?.trim().isNotEmpty == true)
            ? prof.fullName!.trim()
            : item.displayName;
        final av = MediaUrlNormalizer.normalize(prof.avatarUrl) ?? item.avatarUrl;
        return FriendRecord(
          friendshipId: item.friendshipId,
          userId: item.userId,
          username: uname,
          displayName: dname,
          avatarUrl: av,
          status: item.status,
          isIncoming: item.isIncoming,
          createdAt: item.createdAt,
          isOfficial: prof.isOfficial || item.isOfficial,
        );
      }

      _friends = accepted.map(enrich).toList(growable: false);
      _incomingRequests = incoming.map(enrich).toList(growable: false);
      _outgoingRequests = outgoing.map(enrich).toList(growable: false);
      _cachedForUserId = uid;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persistCache(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_cachePrefix$uid',
        jsonEncode(<String, Object?>{
          'friends': _friends.map((e) => e.toJson()).toList(growable: false),
          'incoming':
              _incomingRequests.map((e) => e.toJson()).toList(growable: false),
          'outgoing':
              _outgoingRequests.map((e) => e.toJson()).toList(growable: false),
        }),
      );
      _cachedForUserId = uid;
    } catch (_) {}
  }

  void clear() {
    _friends = const <FriendRecord>[];
    _incomingRequests = const <FriendRecord>[];
    _outgoingRequests = const <FriendRecord>[];
    _cachedForUserId = null;
    _error = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      await loadCached();
      return;
    }

    if (_friends.isEmpty &&
        _incomingRequests.isEmpty &&
        _outgoingRequests.isEmpty) {
      await loadCached(userIdOverride: user.id);
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final rows = await client
          .from('friendships')
          .select('id, requester_id, addressee_id, status, created_at')
          .or('requester_id.eq.${user.id},addressee_id.eq.${user.id}')
          .order('created_at', ascending: false);

      final otherIds = <String>{};
      for (final r in rows) {
        final reqId = r['requester_id']?.toString() ?? '';
        final addId = r['addressee_id']?.toString() ?? '';
        final other = reqId == user.id ? addId : reqId;
        if (other.isNotEmpty) otherIds.add(other);
      }

      final prevByUserId = <String, FriendRecord>{
        for (final r in _friends) r.userId: r,
        for (final r in _incomingRequests) r.userId: r,
        for (final r in _outgoingRequests) r.userId: r,
      };

      final profilesById = <String, PublicProfile>{
        if (otherIds.isNotEmpty)
          ...await PublicProfileCacheService.instance.fetchProfiles(
            otherIds,
            forceRefresh: true,
          ),
      };

      // Fallback RPC user_public_profile bila get_public_profiles belum terdeploy
      // atau mengembalikan baris profil yang belum lengkap.
      final unresolvedIds = otherIds.where((id) {
        final p = profilesById[id];
        if (p == null) return true;
        final hasName = p.fullName != null && p.fullName!.trim().isNotEmpty;
        final hasUname = p.username != null && p.username!.trim().isNotEmpty;
        return !hasName && !hasUname;
      }).toList(growable: false);

      if (unresolvedIds.isNotEmpty) {
        final fallbackProfiles = <PublicProfile>[];
        for (final uid in unresolvedIds) {
          try {
            final res = await client.rpc(
              'user_public_profile',
              params: <String, dynamic>{'p_user_id': uid},
            );
            if (res is List && res.isNotEmpty && res.first is Map) {
              final r = Map<String, dynamic>.from(res.first as Map);
              final prof = PublicProfile(
                userId: uid,
                username: r['username']?.toString(),
                fullName: (r['full_name'] ?? r['display_name'])?.toString(),
                avatarUrl:
                    MediaUrlNormalizer.normalize(r['avatar_url']?.toString()),
                isOfficial: r['is_official'] == true,
                updatedAtUtc: DateTime.now().toUtc(),
              );
              profilesById[uid] = prof;
              fallbackProfiles.add(prof);
            }
          } catch (_) {}
        }
        if (fallbackProfiles.isNotEmpty) {
          unawaited(
            PublicProfileCacheService.instance.putAll(fallbackProfiles),
          );
        }
      }

      final accepted = <FriendRecord>[];
      final incoming = <FriendRecord>[];
      final outgoing = <FriendRecord>[];
      final avatarsToWarm = <String, String?>{};

      for (final r in rows) {
        final id = r['id']?.toString() ?? '';
        final reqId = r['requester_id']?.toString() ?? '';
        final addId = r['addressee_id']?.toString() ?? '';
        final status = r['status']?.toString() ?? 'pending';
        final createdAt =
            DateTime.tryParse(r['created_at']?.toString() ?? '') ??
                DateTime.now().toUtc();
        final isIncoming = addId == user.id;
        final otherId = isIncoming ? reqId : addId;
        final prof = profilesById[otherId];
        final prev = prevByUserId[otherId];

        final resolvedUsername =
            (prof?.username?.trim().isNotEmpty == true)
                ? prof!.username!.trim()
                : ((prev?.username.trim().isNotEmpty == true &&
                        prev!.username != 'pendaki')
                    ? prev.username.trim()
                    : '');
        final resolvedDisplayName =
            (prof?.fullName?.trim().isNotEmpty == true)
                ? prof!.fullName!.trim()
                : ((prev?.displayName?.trim().isNotEmpty == true)
                    ? prev!.displayName!.trim()
                    : null);
        final resolvedAvatar =
            MediaUrlNormalizer.normalize(prof?.avatarUrl) ?? prev?.avatarUrl;

        avatarsToWarm[otherId] = resolvedAvatar;

        final record = FriendRecord(
          friendshipId: id,
          userId: otherId,
          username: resolvedUsername,
          displayName: resolvedDisplayName,
          avatarUrl: resolvedAvatar,
          status: status,
          isIncoming: isIncoming,
          createdAt: createdAt,
          isOfficial: (prof?.isOfficial ?? false) || (prev?.isOfficial ?? false),
        );
        if (status == 'accepted') {
          accepted.add(record);
        } else if (status == 'pending') {
          if (isIncoming) {
            incoming.add(record);
          } else {
            outgoing.add(record);
          }
        }
      }

      _friends = accepted;
      _incomingRequests = incoming;
      _outgoingRequests = outgoing;
      _loading = false;
      notifyListeners();
      unawaited(_persistCache(user.id));
      unawaited(AvatarDiskCache.instance.warmAll(avatarsToWarm));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FriendsService.refresh failed: $e');
      }
      _loading = false;
      // Offline-first: pertahankan daftar teman tersimpan bila sudah ada cache.
      if (_friends.isEmpty && _incomingRequests.isEmpty) {
        _error =
            'Belum bisa memuat daftar teman. Periksa sinyal lalu coba lagi.';
      }
      notifyListeners();
    }
  }

  /// Mengembalikan status relasi saat ini: `'friend'`, `'outgoing'`, `'incoming'`, atau `null`.
  String? relationshipStatusFor(String userId) {
    if (_friends.any((f) => f.userId == userId)) return 'friend';
    if (_outgoingRequests.any((f) => f.userId == userId)) return 'outgoing';
    if (_incomingRequests.any((f) => f.userId == userId)) return 'incoming';
    return null;
  }

  FriendRecord? incomingRequestFrom(String userId) {
    for (final req in _incomingRequests) {
      if (req.userId == userId) return req;
    }
    return null;
  }

  /// Pencarian prefix username (`ILIKE 'kata%'`, LIMIT maks 15) untuk halaman
  /// Daftar Teman maupun pencarian akun Hiqeo di Kontak Darurat.
  Future<List<UserSearchResult>> searchUsersByUsername(
    String rawQuery, {
    int limit = 15,
  }) async {
    final clean = rawQuery.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase();
    if (clean.isEmpty) return const <UserSearchResult>[];
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      throw StateError('Masuk akun dan sambungkan internet untuk mencari.');
    }
    final safeLimit = limit.clamp(1, 15);
    try {
      final raw = await client.rpc(
        'search_users_by_username',
        params: <String, dynamic>{'p_query': clean, 'p_limit': safeLimit},
      );
      if (raw is List) {
        return raw.whereType<Map>().map((row) {
          final r = Map<String, dynamic>.from(row);
          return UserSearchResult(
            userId: r['id']?.toString() ?? '',
            username: r['username']?.toString() ?? '',
            displayName: r['full_name']?.toString(),
            avatarUrl: r['avatar_url']?.toString(),
            isOfficial: r['is_official'] == true,
          );
        }).where((u) => u.userId.isNotEmpty && u.username.isNotEmpty).toList();
      }
    } catch (_) {
      // Fallback prefix query langsung saat fungsi RPC belum dimigrasi.
    }

    final escaped = clean
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final rows = await client
        .from('profiles')
        .select('id, username, full_name, avatar_url, is_official')
        .neq('id', user.id)
        .ilike('username', '$escaped%')
        .order('username', ascending: true)
        .limit(safeLimit);
    return rows
        .map<UserSearchResult>(
          (r) => UserSearchResult(
            userId: r['id']?.toString() ?? '',
            username: r['username']?.toString() ?? '',
            displayName:
                (r['full_name'] ?? r['display_name'])?.toString(),
            avatarUrl: r['avatar_url']?.toString(),
            isOfficial: r['is_official'] == true,
          ),
        )
        .where((u) => u.userId.isNotEmpty && u.username.isNotEmpty)
        .toList();
  }

  /// Mengirim permintaan pertemanan (khusus Plus Mahasiswa & Tahunan).
  Future<void> sendFriendRequest(String targetUserId) async {
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      throw StateError('Masuk akun terlebih dahulu untuk menambah teman.');
    }
    if (targetUserId == user.id) {
      throw StateError('Tidak dapat menambahkan diri sendiri sebagai teman.');
    }
    final existing = await client
        .from('friendships')
        .select('id, status')
        .or(
          'and(requester_id.eq.${user.id},addressee_id.eq.$targetUserId),'
          'and(requester_id.eq.$targetUserId,addressee_id.eq.${user.id})',
        )
        .maybeSingle();
    if (existing != null) {
      final st = existing['status']?.toString();
      if (st == 'accepted') {
        throw StateError('Kalian sudah berteman.');
      }
      if (st == 'pending') {
        throw StateError('Permintaan pertemanan sudah dikirim.');
      }
      await client.from('friendships').delete().eq('id', existing['id']);
    }

    await client.from('friendships').insert(<String, dynamic>{
      'requester_id': user.id,
      'addressee_id': targetUserId,
      'status': 'pending',
    });
    await refresh();
  }

  Future<void> respondToRequest(
    String friendshipId, {
    required bool accept,
  }) async {
    final client = SupabaseServices.clientOrNull;
    if (client == null) return;
    if (accept) {
      await client
          .from('friendships')
          .update(<String, dynamic>{'status': 'accepted'})
          .eq('id', friendshipId);
    } else {
      await client.from('friendships').delete().eq('id', friendshipId);
    }
    await refresh();
  }

  Future<void> removeFriend(String friendshipId) async {
    final client = SupabaseServices.clientOrNull;
    if (client == null) return;
    await client.from('friendships').delete().eq('id', friendshipId);
    await refresh();
  }

  Future<OtherUserProfileData> fetchUserProfile(String userId) async {
    final client = SupabaseServices.clientOrNull;
    if (client == null) {
      throw StateError('Koneksi Supabase tidak tersedia.');
    }
    try {
      final rows = await client.rpc(
        'user_public_profile',
        params: <String, dynamic>{'p_user_id': userId},
      );
      if (rows is List && rows.isNotEmpty && rows.first is Map) {
        final r = Map<String, dynamic>.from(rows.first as Map);
        final isPlus = r['has_plus_badge'] == true || r['is_plus'] == true;
        final planId = r['plus_plan_id']?.toString();
        final isUltima = r['is_ultima'] == true ||
            (isPlus && PlusAccess.isLifetimePlanId(planId));
        return OtherUserProfileData(
          userId: r['user_id']?.toString() ?? userId,
          username: r['username']?.toString() ?? 'pendaki',
          displayName: (r['full_name'] ?? r['display_name'])?.toString(),
          avatarUrl: r['avatar_url']?.toString(),
          isPlus: isPlus,
          plusPlanId: planId,
          isUltima: isUltima,
          isOfficial: r['is_official'] == true,
          mountainsClimbed: (r['mountains_climbed'] as num?)?.toInt() ?? 0,
          totalDistanceM: (r['total_distance_m'] as num?)?.toDouble() ?? 0,
          totalMovingSeconds: (r['total_moving_seconds'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (_) {
      // Fallback baca langsung tabel profiles + hike_sessions.
    }

    final prof = await client
        .from('profiles')
        .select(
          'id, username, full_name, avatar_url, is_plus, plus_plan_id, plus_expires_at, is_official',
        )
        .eq('id', userId)
        .maybeSingle();
    final sessions = await client
        .from('hike_sessions')
        .select('activity_type, mountain_name, distance_m, moving_seconds')
        .eq('user_id', userId);
    final mountains = <String>{};
    var dist = 0.0;
    var secs = 0;
    for (final s in sessions) {
      if (s['activity_type']?.toString() == 'jogging') continue;
      final m = s['mountain_name']?.toString().trim();
      if (m != null && m.isNotEmpty) mountains.add(m.toLowerCase());
      dist += (s['distance_m'] as num?)?.toDouble() ?? 0;
      secs += (s['moving_seconds'] as num?)?.toInt() ?? 0;
    }

    final isPlus = prof?['is_plus'] == true;
    final planId = prof?['plus_plan_id']?.toString();
    final expiresRaw = prof?['plus_expires_at']?.toString();
    final isUltima = isPlus &&
        (expiresRaw == null ||
            expiresRaw.isEmpty ||
            PlusAccess.isLifetimePlanId(planId));

    return OtherUserProfileData(
      userId: userId,
      username: prof?['username']?.toString() ?? 'pendaki',
      displayName: (prof?['full_name'] ?? prof?['display_name'])?.toString(),
      avatarUrl: prof?['avatar_url']?.toString(),
      isPlus: isPlus,
      plusPlanId: planId,
      isUltima: isUltima,
      isOfficial: prof?['is_official'] == true,
      mountainsClimbed: mountains.length,
      totalDistanceM: dist,
      totalMovingSeconds: secs,
    );
  }
}
