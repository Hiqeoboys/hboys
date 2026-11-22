import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Mengelola pengaturan bisu notifikasi per ruang obrolan (`chat_notification_mutes`),
/// mendukung bisu 1 hari, 1 minggu, selamanya (`9999-12-31T23:59:59Z`), atau aktif (`null`).
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
  static final DateTime foreverMutedAtUtc = DateTime.utc(9999, 12, 31, 23, 59, 59);
  static const String _prefsKey = 'hiqeo_chat_mutes_v1';

  final MutePrefsLoader _prefsLoader;
  final MuteUserIdProvider _userIdProvider;
  final MuteRemoteUpsert _remoteUpsert;
  final MuteRemoteFetchAll _remoteFetchAll;

  final Map<String, DateTime?> _mutes = <String, DateTime?>{};
  bool _loadedLocal = false;

  static String? _defaultUserId() =>
      SupabaseServices.clientOrNull?.auth.currentUser?.id;

  static String _roomKey(String roomType, String roomId) => '$roomType:$roomId';

  DateTime? mutedUntil(String roomType, String roomId) =>
      _mutes[_roomKey(roomType, roomId)];

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

  Future<void> loadAll({bool forceRemote = false}) async {
    await _ensureLocalLoaded();
    final uid = _userIdProvider();
    if (uid == null || uid.isEmpty) return;
    if (!forceRemote && _mutes.isNotEmpty) {
      unawaited(_refreshFromServer(uid));
      return;
    }
    await _refreshFromServer(uid);
  }

  Future<void> _ensureLocalLoaded() async {
    if (_loadedLocal) return;
    _loadedLocal = true;
    try {
      final prefs = await _prefsLoader();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final val = entry.value?.toString();
        _mutes[entry.key.toString()] =
            val != null ? DateTime.tryParse(val)?.toUtc() : null;
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _refreshFromServer(String uid) async {
    try {
      final rows = await _remoteFetchAll(uid);
      final next = <String, DateTime?>{};
      for (final r in rows) {
        final rt = r['room_type']?.toString() ?? '';
        final rid = r['room_id']?.toString() ?? '';
        if (rt.isEmpty || rid.isEmpty) continue;
        final rawUntil = r['muted_until']?.toString();
        next[_roomKey(rt, rid)] =
            rawUntil != null ? DateTime.tryParse(rawUntil)?.toUtc() : null;
      }
      _mutes
        ..clear()
        ..addAll(next);
      await _persistLocal();
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
    await _ensureLocalLoaded();
    final key = _roomKey(roomType, roomId);
    final normalized = mutedUntilUtc?.toUtc();
    if (normalized == null) {
      _mutes.remove(key);
    } else {
      _mutes[key] = normalized;
    }
    notifyListeners();
    await _persistLocal();

    final uid = _userIdProvider();
    if (uid != null && uid.isNotEmpty) {
      try {
        await _remoteUpsert(uid, roomType, roomId, normalized);
      } catch (_) {}
    }
  }

  Future<void> _persistLocal() async {
    try {
      final prefs = await _prefsLoader();
      final map = <String, String?>{
        for (final e in _mutes.entries)
          if (e.value != null) e.key: e.value!.toUtc().toIso8601String(),
      };
      await prefs.setString(_prefsKey, jsonEncode(map));
    } catch (_) {}
  }

  Future<void> clearLocal() async {
    _mutes.clear();
    _loadedLocal = false;
    notifyListeners();
    try {
      final prefs = await _prefsLoader();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> _defaultRemoteFetchAll(
    String userId,
  ) async {
    final client = SupabaseServices.clientOrNull;
    if (client == null) return const <Map<String, dynamic>>[];
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
    await client.from('chat_notification_mutes').upsert(
      <String, dynamic>{
        'user_id': userId,
        'room_type': roomType,
        'room_id': roomId,
        'muted_until': mutedUntilUtc?.toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'user_id,room_type,room_id',
    );
  }
}
