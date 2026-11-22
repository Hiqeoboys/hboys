import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../infrastructure/auth/active_account_scope.dart';
import '../../../infrastructure/supabase/supabase_services.dart';

typedef MutePrefsLoader = Future<SharedPreferences> Function();
typedef MuteUserIdProvider = String? Function();
typedef MuteRemoteUpsert = Future<void> Function(
  String userId,
  String roomType,
  String roomId,
  DateTime? mutedUntilUtc,
);
typedef MuteRemoteFetchAll = Future<List<Map<String, dynamic>>> Function(
  String userId,
);

@immutable
class _MuteEntry {
  const _MuteEntry({
    this.mutedUntilUtc,
    this.pendingSync = false,
  });

  final DateTime? mutedUntilUtc;
  final bool pendingSync;
}

/// Mengelola pengaturan bisu notifikasi per ruang obrolan (`chat_notification_mutes`,
/// `group_members`, & `community_members`) sebagai sumber kebenaran tunggal per `user_id`
/// lintas isolate (foreground, background FCM isolate, dan Hiqeo Mesh offline).
class ChatMuteService extends ChangeNotifier {
  ChatMuteService({
    MutePrefsLoader? prefsLoader,
    MuteUserIdProvider? userIdProvider,
    MuteRemoteUpsert? remoteUpsert,
    MuteRemoteFetchAll? remoteFetchAll,
  })  : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance,
        _userIdProvider = userIdProvider ?? _defaultUserId,
        _remoteUpsert = remoteUpsert ?? _defaultRemoteUpsert,
        _remoteFetchAll = remoteFetchAll ?? _defaultRemoteFetchAll;

  static final ChatMuteService instance = ChatMuteService();

  /// Tanggal konvensi server & klien untuk "bisu selamanya".
  static final DateTime foreverMutedAtUtc =
      DateTime.utc(9999, 12, 31, 23, 59, 59);

  static const String _legacyPrefsKey = 'hiqeo_chat_mutes_v1';
  static const String _activeUidKey = 'hiqeo_chat_mutes_active_uid_v2';
  static const String _scopedMapPrefix = 'hiqeo_chat_mutes_v2_u_';
  static const String _mutedGroupsPrefix = 'muted_group_ids_u_';
  static const String _mutedCommunitiesPrefix = 'muted_community_ids_u_';

  final MutePrefsLoader _prefsLoader;
  final MuteUserIdProvider _userIdProvider;
  final MuteRemoteUpsert _remoteUpsert;
  final MuteRemoteFetchAll _remoteFetchAll;

  final Map<String, _MuteEntry> _entries = <String, _MuteEntry>{};
  bool _loadedLocal = false;
  String? _loadedScope;

  static String? _defaultUserId() {
    final fromSupabase =
        SupabaseServices.clientOrNull?.auth.currentUser?.id.trim();
    if (fromSupabase != null && fromSupabase.isNotEmpty) return fromSupabase;
    final fromScope = ActiveAccountScope.activeUserId.value?.trim();
    if (fromScope != null && fromScope.isNotEmpty) return fromScope;
    return null;
  }

  static String _normType(String roomType) => roomType.trim().toLowerCase();
  static String _normId(String roomId) => roomId.trim().toLowerCase();
  static String _roomKey(String roomType, String roomId) =>
      '${_normType(roomType)}:${_normId(roomId)}';

  String _resolveScopeSync([SharedPreferences? prefs]) {
    final direct = _userIdProvider()?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final fromPrefs = prefs?.getString(_activeUidKey)?.trim();
    if (fromPrefs != null && fromPrefs.isNotEmpty) return fromPrefs;
    return _loadedScope ?? 'guest';
  }

  DateTime? mutedUntil(String roomType, String roomId) =>
      _entries[_roomKey(roomType, roomId)]?.mutedUntilUtc;

  bool isMuted(String roomType, String roomId, {DateTime? nowUtc}) {
    final until = mutedUntil(roomType, roomId);
    if (until == null) return false;
    return until.isAfter((nowUtc ?? DateTime.now()).toUtc());
  }

  bool isMutedForever(String roomType, String roomId) {
    final until = mutedUntil(roomType, roomId);
    if (until == null) return false;
    return until.toUtc().year >= 9999;
  }

  Set<String> get mutedGroupIds {
    final now = DateTime.now().toUtc();
    return <String>{
      for (final e in _entries.entries)
        if (e.key.startsWith('group:') &&
            e.value.mutedUntilUtc != null &&
            e.value.mutedUntilUtc!.isAfter(now))
          e.key.substring('group:'.length),
    };
  }

  Set<String> get mutedCommunityIds {
    final now = DateTime.now().toUtc();
    return <String>{
      for (final e in _entries.entries)
        if (e.key.startsWith('community:') &&
            e.value.mutedUntilUtc != null &&
            e.value.mutedUntilUtc!.isAfter(now))
          e.key.substring('community:'.length),
    };
  }

  /// Memperbarui pengguna aktif di layanan mute dan memuat cache lokalnya.
  Future<void> setActiveUser(String? userId) async {
    final clean = userId?.trim();
    try {
      final prefs = await _prefsLoader();
      if (clean != null && clean.isNotEmpty) {
        await prefs.setString(_activeUidKey, clean);
      } else {
        await prefs.remove(_activeUidKey);
      }
    } catch (_) {}
    await ensureLoaded(forceReload: true);
  }

  /// Memastikan preferensi mute lokal (termasuk lintas background isolate)
  /// sudah dimuat untuk `user_id` aktif sebelum memeriksa notifikasi masuk.
  Future<void> ensureLoaded({bool forceReload = false}) async {
    try {
      final prefs = await _prefsLoader();
      if (forceReload) {
        try {
          await prefs.reload();
        } catch (_) {}
      }
      final directUid = _userIdProvider()?.trim();
      if (directUid != null && directUid.isNotEmpty) {
        if (prefs.getString(_activeUidKey) != directUid) {
          unawaited(prefs.setString(_activeUidKey, directUid));
        }
      }
      final scope = _resolveScopeSync(prefs);
      if (_loadedLocal && !forceReload && _loadedScope == scope) {
        return;
      }
      _loadFromPrefs(prefs, scope);
    } catch (_) {
      _loadedLocal = true;
    }
  }

  void _loadFromPrefs(SharedPreferences prefs, String scope) {
    _loadedLocal = true;
    _loadedScope = scope;
    _entries.clear();

    final scopedKey = '$_scopedMapPrefix$scope';
    var raw = prefs.getString(scopedKey);
    var migratedLegacy = false;
    if ((raw == null || raw.isEmpty) && prefs.containsKey(_legacyPrefsKey)) {
      raw = prefs.getString(_legacyPrefsKey);
      migratedLegacy = raw != null && raw.isNotEmpty;
    }

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final keyParts = entry.key.toString().split(':');
            if (keyParts.length < 2) continue;
            final normKey = _roomKey(
              keyParts.first,
              keyParts.sublist(1).join(':'),
            );
            final val = entry.value;
            if (val is Map) {
              final untilStr = val['u']?.toString();
              final pending = val['p'] == true;
              _entries[normKey] = _MuteEntry(
                mutedUntilUtc:
                    untilStr != null ? DateTime.tryParse(untilStr)?.toUtc() : null,
                pendingSync: pending,
              );
            } else if (val != null) {
              _entries[normKey] = _MuteEntry(
                mutedUntilUtc: DateTime.tryParse(val.toString())?.toUtc(),
                pendingSync: false,
              );
            }
          }
        }
      } catch (_) {}
    }

    // Pastikan daftar cepat `muted_group_ids` & `muted_community_ids` juga ikut terhidrasi
    final nowUtc = DateTime.now().toUtc();
    for (final gid in prefs.getStringList('$_mutedGroupsPrefix$scope') ??
        const <String>[]) {
      final k = _roomKey('group', gid);
      _entries.putIfAbsent(
        k,
        () => _MuteEntry(
          mutedUntilUtc: foreverMutedAtUtc,
          pendingSync: false,
        ),
      );
    }
    for (final cid in prefs.getStringList('$_mutedCommunitiesPrefix$scope') ??
        const <String>[]) {
      final k = _roomKey('community', cid);
      _entries.putIfAbsent(
        k,
        () => _MuteEntry(
          mutedUntilUtc: foreverMutedAtUtc,
          pendingSync: false,
        ),
      );
    }

    // Bersihkan entri kadaluarsa yang tidak tertunda sinkronisasinya
    _entries.removeWhere(
      (_, e) =>
          !e.pendingSync &&
          e.mutedUntilUtc != null &&
          !e.mutedUntilUtc!.isAfter(nowUtc),
    );

    if (migratedLegacy) {
      unawaited(_persistLocal(scope: scope));
    }
    notifyListeners();
  }

  Future<void> loadAll({bool forceRemote = false}) async {
    await ensureLoaded(forceReload: forceRemote);
    final uid = _userIdProvider()?.trim();
    if (uid == null || uid.isEmpty) return;
    if (!forceRemote && _entries.isNotEmpty) {
      unawaited(_refreshFromServer(uid));
      return;
    }
    await _refreshFromServer(uid);
  }

  Future<void> _refreshFromServer(String uid) async {
    try {
      // Kirim dulu perubahan lokal yang belum tersinkron (misal saat sebelumnya offline).
      final pendingEntries = <String, _MuteEntry>{
        for (final e in _entries.entries)
          if (e.value.pendingSync) e.key: e.value,
      };
      for (final entry in pendingEntries.entries) {
        final idx = entry.key.indexOf(':');
        if (idx <= 0) continue;
        final rt = entry.key.substring(0, idx);
        final rid = entry.key.substring(idx + 1);
        try {
          await _remoteUpsert(uid, rt, rid, entry.value.mutedUntilUtc);
          _entries[entry.key] = _MuteEntry(
            mutedUntilUtc: entry.value.mutedUntilUtc,
            pendingSync: false,
          );
        } catch (_) {}
      }

      final rows = await _remoteFetchAll(uid);
      final next = <String, _MuteEntry>{};
      final nowUtc = DateTime.now().toUtc();
      for (final r in rows) {
        final rt = _normType(r['room_type']?.toString() ?? '');
        final rid = _normId(r['room_id']?.toString() ?? '');
        if (rt.isEmpty || rid.isEmpty) continue;
        final isFlagMuted = r['is_muted'] == true;
        final rawUntil = r['muted_until']?.toString();
        DateTime? untilUtc =
            rawUntil != null ? DateTime.tryParse(rawUntil)?.toUtc() : null;
        if (untilUtc == null && isFlagMuted) {
          untilUtc = foreverMutedAtUtc;
        }
        if (untilUtc != null && untilUtc.isAfter(nowUtc)) {
          next[_roomKey(rt, rid)] = _MuteEntry(mutedUntilUtc: untilUtc);
        }
      }

      // Pertahankan entri lokal yang masih pending agar aksi offline tidak tertimpa.
      for (final e in _entries.entries) {
        if (e.value.pendingSync) {
          if (e.value.mutedUntilUtc == null) {
            next.remove(e.key);
          } else {
            next[e.key] = e.value;
          }
        }
      }

      _entries
        ..clear()
        ..addAll(next);
      await _persistLocal(scope: uid);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> muteFor(
    String roomType,
    String roomId,
    Duration duration, {
    DateTime? nowUtc,
  }) {
    final target = (nowUtc ?? DateTime.now()).toUtc().add(duration);
    return setMutedUntil(roomType, roomId, target);
  }

  Future<void> muteForever(String roomType, String roomId) =>
      setMutedUntil(roomType, roomId, foreverMutedAtUtc);

  Future<void> unmute(String roomType, String roomId) =>
      setMutedUntil(roomType, roomId, null);

  Future<void> setMutedUntil(
    String roomType,
    String roomId,
    DateTime? mutedUntilUtc,
  ) async {
    await ensureLoaded();
    final cleanType = _normType(roomType);
    final cleanId = _normId(roomId);
    final key = _roomKey(cleanType, cleanId);
    final normalized = mutedUntilUtc?.toUtc();

    final uid = _userIdProvider()?.trim();
    final scope = (uid != null && uid.isNotEmpty) ? uid : _resolveScopeSync();

    _entries[key] = _MuteEntry(
      mutedUntilUtc: normalized,
      pendingSync: true,
    );
    notifyListeners();
    await _persistLocal(scope: scope);

    if (uid != null && uid.isNotEmpty) {
      try {
        await _remoteUpsert(uid, cleanType, cleanId, normalized);
        if (normalized == null) {
          _entries.remove(key);
        } else {
          _entries[key] = _MuteEntry(
            mutedUntilUtc: normalized,
            pendingSync: false,
          );
        }
        await _persistLocal(scope: uid);
      } catch (_) {
        // Tetap tandai `pendingSync = true` agar sinkronisasi ulang mengirimnya saat online.
      }
    } else if (normalized == null) {
      _entries.remove(key);
      await _persistLocal(scope: scope);
    }
  }

  Future<void> _persistLocal({String? scope}) async {
    try {
      final prefs = await _prefsLoader();
      final resolvedScope = scope ?? _resolveScopeSync(prefs);
      final map = <String, Map<String, dynamic>>{
        for (final e in _entries.entries)
          if (e.value.mutedUntilUtc != null || e.value.pendingSync)
            e.key: <String, dynamic>{
              'u': e.value.mutedUntilUtc?.toUtc().toIso8601String(),
              if (e.value.pendingSync) 'p': true,
            },
      };
      await prefs.setString('$_scopedMapPrefix$resolvedScope', jsonEncode(map));
      await prefs.setStringList(
        '$_mutedGroupsPrefix$resolvedScope',
        mutedGroupIds.toList(growable: false),
      );
      await prefs.setStringList(
        '$_mutedCommunitiesPrefix$resolvedScope',
        mutedCommunityIds.toList(growable: false),
      );
      if (resolvedScope != 'guest') {
        await prefs.setString(_activeUidKey, resolvedScope);
      }
    } catch (_) {}
  }

  Future<void> clearLocal({String? userId}) async {
    final targetScope = userId?.trim();
    _entries.clear();
    _loadedLocal = false;
    _loadedScope = null;
    notifyListeners();
    try {
      final prefs = await _prefsLoader();
      final scopeToDelete = (targetScope != null && targetScope.isNotEmpty)
          ? targetScope
          : _resolveScopeSync(prefs);
      await prefs.remove(_legacyPrefsKey);
      await prefs.remove('$_scopedMapPrefix$scopeToDelete');
      await prefs.remove('$_mutedGroupsPrefix$scopeToDelete');
      await prefs.remove('$_mutedCommunitiesPrefix$scopeToDelete');
      if (targetScope == null) {
        await prefs.remove(_activeUidKey);
      }
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> _defaultRemoteFetchAll(
    String userId,
  ) async {
    final client = SupabaseServices.clientOrNull;
    if (client == null) return const <Map<String, dynamic>>[];
    try {
      final rpcRows = await client.rpc('my_chat_mutes');
      if (rpcRows is List) {
        return rpcRows
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
            .toList(growable: false);
      }
    } catch (_) {
      // Fallback ke select tabel langsung bila RPC belum dimigrasi.
    }
    final rows = await client
        .from('chat_notification_mutes')
        .select('room_type, room_id, muted_until')
        .eq('user_id', userId);
    return rows
        .map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r))
        .toList(growable: false);
  }

  static Future<void> _defaultRemoteUpsert(
    String userId,
    String roomType,
    String roomId,
    DateTime? mutedUntilUtc,
  ) async {
    final client = SupabaseServices.clientOrNull;
    if (client == null) return;
    final cleanType = _normType(roomType);
    final cleanId = _normId(roomId);
    final isoUntil = mutedUntilUtc?.toUtc().toIso8601String();
    try {
      await client.rpc(
        'set_room_mute',
        params: <String, dynamic>{
          'p_room_type': cleanType,
          'p_room_id': cleanId,
          'p_is_muted': mutedUntilUtc != null,
          'p_muted_until': isoUntil,
        },
      );
      return;
    } catch (_) {
      // Fallback ke upsert tabel langsung bila RPC belum dimigrasi.
    }
    await client.from('chat_notification_mutes').upsert(
      <String, dynamic>{
        'user_id': userId,
        'room_type': cleanType,
        'room_id': cleanId,
        'muted_until': isoUntil,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'user_id,room_type,room_id',
    );
  }
}
