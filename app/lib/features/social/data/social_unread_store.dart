import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../infrastructure/crypto/flutter_secure_value_store.dart';
import '../../../infrastructure/crypto/secure_group_key_store.dart';
import '../../../infrastructure/notifications/push_notification_service.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../../chat/application/group_chat_crypto.dart';
import '../../chat/domain/group_chat_models.dart';
import '../../preparation/application/packing_list_store.dart';

/// Membandingkan dua ruang obrolan berdasarkan aktivitas/pesan terbaru
/// (`lastMessageAtUtc DESC NULLS LAST`, lalu fallback `createdAtUtc DESC`).
int compareRoomsByLatestActivity({
  required DateTime? aLastMessageAtUtc,
  required DateTime aCreatedAtUtc,
  required DateTime? bLastMessageAtUtc,
  required DateTime bCreatedAtUtc,
  String? aId,
  String? bId,
}) {
  if (aLastMessageAtUtc != null && bLastMessageAtUtc != null) {
    final msgCmp = bLastMessageAtUtc.compareTo(aLastMessageAtUtc);
    if (msgCmp != 0) return msgCmp;
  } else if (aLastMessageAtUtc != null) {
    return -1;
  } else if (bLastMessageAtUtc != null) {
    return 1;
  }
  final createdCmp = bCreatedAtUtc.compareTo(aCreatedAtUtc);
  if (createdCmp != 0) return createdCmp;
  if (aId != null && bId != null) {
    return aId.compareTo(bId);
  }
  return 0;
}

/// Membentuk cuplikan pesan ringkas dari rekaman obrolan grup lokal / Hiqeo Mesh.
String formatGroupPreviewSnippetFromRecord(GroupMessageRecord record) {
  if (record.isDeleted) return 'Pesan telah dihapus';
  if (record.isCancelled) return 'Ajakan pendakian dibatalkan';
  final sender = record.senderName.trim();
  if (record.messageType == GroupMessageType.audio) {
    return sender.isNotEmpty ? '$sender: Pesan suara' : 'Pesan suara';
  }
  final rawText = record.content?.trim() ?? '';
  if (rawText.isEmpty) return 'Pesan baru';
  final invite = GroupHikeInviteMessage.tryDecodeInvite(rawText);
  if (invite != null) return 'Ajakan pendakian: ${invite.mountainName}';
  if (GroupHikeInviteMessage.tryDecodeReady(rawText) != null) {
    return 'Anggota siap naik';
  }
  return sender.isNotEmpty ? '$sender: $rawText' : rawText;
}

@immutable
class SocialLatestPreview {
  const SocialLatestPreview({
    required this.roomKind,
    required this.roomId,
    required this.snippet,
    required this.senderId,
    required this.createdAtUtc,
    required this.hasUnread,
    this.lastMessageId,
  });

  final String roomKind; // 'group' | 'community'
  final String roomId;
  final String snippet;
  final String senderId;
  final DateTime createdAtUtc;
  final bool hasUnread;
  final String? lastMessageId;

  SocialLatestPreview copyWith({bool? hasUnread}) => SocialLatestPreview(
        roomKind: roomKind,
        roomId: roomId,
        snippet: snippet,
        senderId: senderId,
        createdAtUtc: createdAtUtc,
        hasUnread: hasUnread ?? this.hasUnread,
        lastMessageId: lastMessageId,
      );
}

@immutable
class RoomReadCursor {
  const RoomReadCursor({
    this.lastReadAtUtc,
    this.lastReadMessageId,
  });

  final DateTime? lastReadAtUtc;
  final String? lastReadMessageId;

  bool get hasCursor =>
      lastReadAtUtc != null ||
      (lastReadMessageId != null && lastReadMessageId!.isNotEmpty);
}

/// Menghitung indeks pesan belum dibaca pertama beserta jumlah pesan belum dibaca
/// dari kursor lokal ([cursor]). Jika [cursor] kosong (kunjungan perdana),
/// mengembalikan `(firstUnreadIndex: null, unreadCount: 0)` agar layar langsung
/// bergulir ke pesan terbaru.
({int? firstUnreadIndex, int unreadCount}) computeUnreadMarker<T>({
  required List<T> messages,
  required RoomReadCursor cursor,
  required String currentUserId,
  required String Function(T) idOf,
  required String Function(T) senderIdOf,
  required DateTime Function(T) createdAtOf,
}) {
  if (messages.isEmpty || !cursor.hasCursor) {
    return (firstUnreadIndex: null, unreadCount: 0);
  }

  var startSearchIdx = 0;
  final lastMsgId = cursor.lastReadMessageId;
  if (lastMsgId != null && lastMsgId.isNotEmpty) {
    final idx = messages.indexWhere((m) => idOf(m) == lastMsgId);
    if (idx >= 0) {
      startSearchIdx = idx + 1;
    }
  }

  final lastReadMs = cursor.lastReadAtUtc?.toUtc().millisecondsSinceEpoch ?? 0;
  int? firstIdx;
  var unreadCount = 0;

  for (var i = startSearchIdx; i < messages.length; i++) {
    final m = messages[i];
    final sid = senderIdOf(m);
    final isOwn = sid.isNotEmpty && sid == currentUserId;
    if (startSearchIdx > 0 ||
        createdAtOf(m).toUtc().millisecondsSinceEpoch > lastReadMs) {
      if (!isOwn) {
        firstIdx ??= i;
        unreadCount++;
      }
    }
  }

  return (firstUnreadIndex: firstIdx, unreadCount: unreadCount);
}

typedef SocialLatestFetcher = Future<List<Map<String, dynamic>>> Function();
typedef SocialGroupDecryptor = Future<Map<String, dynamic>> Function({
  required String kind,
  required String groupId,
  required String recordId,
  required int keyVersion,
  required String ciphertextBase64,
});
typedef SocialPrefsLoader = Future<SharedPreferences> Function();
typedef SocialUserIdProvider = String? Function();
typedef SocialRoomReadSyncer = Future<void> Function({
  required String roomKind,
  required String roomId,
  required DateTime lastReadAtUtc,
  String? lastMessageId,
});

/// Menyimpan stempel `last_read_at` & `last_read_message_id` per ruang obrolan
/// secara LOKAL di SharedPreferences dan mensinkronkannya ke server RPC
/// (`mark_room_read`), lalu menggunakan stempel terbesar antara lokal & server
/// saat memuat ulang cuplikan (`social_latest_messages`).
class SocialUnreadStore extends ChangeNotifier {
  SocialUnreadStore({
    SocialLatestFetcher? fetcher,
    SocialGroupDecryptor? decryptor,
    SocialPrefsLoader? prefsLoader,
    SocialUserIdProvider? currentUserIdProvider,
    SocialRoomReadSyncer? roomReadSyncer,
  })  : _fetcher = fetcher ?? _defaultFetcher,
        _decryptor = decryptor ?? _defaultDecryptor,
        _prefsLoader = prefsLoader ?? SharedPreferences.getInstance,
        _currentUserIdProvider = currentUserIdProvider ?? _defaultUserId,
        _roomReadSyncer = roomReadSyncer ?? _defaultRoomReadSyncer;

  static final SocialUnreadStore instance = SocialUnreadStore();

  static const String _groupPrefix = 'hiqeo_last_read_group_';
  static const String _communityPrefix = 'hiqeo_last_read_community_';
  static const String _groupMsgPrefix = 'hiqeo_last_read_msg_group_';
  static const String _communityMsgPrefix = 'hiqeo_last_read_msg_community_';

  final SocialLatestFetcher _fetcher;
  final SocialGroupDecryptor _decryptor;
  final SocialPrefsLoader _prefsLoader;
  final SocialUserIdProvider _currentUserIdProvider;
  final SocialRoomReadSyncer _roomReadSyncer;

  final Map<String, SocialLatestPreview> _groupPreviews =
      <String, SocialLatestPreview>{};
  final Map<String, SocialLatestPreview> _communityPreviews =
      <String, SocialLatestPreview>{};
  final Map<String, int> _localLastReadMs = <String, int>{};
  final Map<String, String> _localLastReadMsgId = <String, String>{};
  bool _refreshing = false;
  RealtimeChannel? _realtimeChannel;
  String? _realtimeUserId;
  Timer? _realtimeRefreshTimer;

  SocialLatestPreview? groupPreview(String groupId) => _groupPreviews[groupId];

  SocialLatestPreview? communityPreview(String communityId) =>
      _communityPreviews[communityId];

  bool get hasAnyUnread =>
      _groupPreviews.values.any((e) => e.hasUnread) ||
      _communityPreviews.values.any((e) => e.hasUnread);

  /// Berlangganan Supabase Realtime (`group_messages` & `community_messages`)
  /// untuk akun aktif agar daftar Grup & Komunitas langsung naik ke teratas
  /// begitu pesan baru tiba tanpa harus membuka ruang terlebih dahulu.
  void ensureRealtimeSubscribed() {
    final client = SupabaseServices.clientOrNull;
    final uid = _currentUserIdProvider()?.trim();
    if (client == null || uid == null || uid.isEmpty) return;
    if (_realtimeChannel != null && _realtimeUserId == uid) return;
    unawaited(unsubscribeRealtime());
    _realtimeUserId = uid;
    try {
      final channel = client.channel('hiqeo_social_activity_$uid');
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'group_messages',
            callback: (payload) {
              final r = payload.newRecord;
              final gid = r['group_id']?.toString() ?? '';
              if (gid.isEmpty) return;
              final rawCreated = r['created_at']?.toString() ??
                  r['client_created_at']?.toString() ??
                  '';
              final ts = DateTime.tryParse(rawCreated)?.toUtc() ??
                  DateTime.now().toUtc();
              final senderId = r['sender_id']?.toString() ?? '';
              final msgId =
                  (r['client_id'] ?? r['client_msg_id'] ?? r['id'])?.toString();
              final existing = _groupPreviews[gid];
              recordGroupActivity(
                groupId: gid,
                createdAtUtc: ts,
                snippet: existing?.snippet ?? 'Pesan terenkripsi',
                senderId: senderId,
                messageId: msgId,
                markUnread: senderId.isNotEmpty && senderId != uid,
              );
              _scheduleDebouncedRefresh();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'community_messages',
            callback: (payload) {
              final r = payload.newRecord;
              final cid = r['community_id']?.toString() ?? '';
              if (cid.isEmpty) return;
              final rawCreated = r['created_at']?.toString() ?? '';
              final ts = DateTime.tryParse(rawCreated)?.toUtc() ??
                  DateTime.now().toUtc();
              final senderId = r['sender_id']?.toString() ?? '';
              final msgId = r['id']?.toString();
              recordCommunityActivity(
                communityId: cid,
                createdAtUtc: ts,
                snippet: resolveCommunitySnippetFromRow(r),
                senderId: senderId,
                messageId: msgId,
                markUnread: senderId.isNotEmpty && senderId != uid,
              );
            },
          )
          .subscribe();
      _realtimeChannel = channel;
    } catch (_) {
      _realtimeChannel = null;
      _realtimeUserId = null;
    }
  }

  void _scheduleDebouncedRefresh() {
    _realtimeRefreshTimer?.cancel();
    _realtimeRefreshTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(refresh());
    });
  }

  Future<void> unsubscribeRealtime() async {
    _realtimeRefreshTimer?.cancel();
    _realtimeRefreshTimer = null;
    _realtimeUserId = null;
    final ch = _realtimeChannel;
    _realtimeChannel = null;
    if (ch != null) {
      try {
        await SupabaseServices.clientOrNull?.removeChannel(ch);
      } catch (_) {}
    }
  }

  /// Mencatat aktivitas pesan grup terbaru secara langsung di memori (dari pesan
  /// terkirim, Hiqeo Mesh offline, maupun Supabase Realtime) agar grup otomatis
  /// naik ke posisi teratas tanpa menunggu polling server.
  void recordGroupActivity({
    required String groupId,
    required DateTime createdAtUtc,
    String? snippet,
    String? senderId,
    String? messageId,
    bool? markUnread,
  }) {
    _recordRoomActivity(
      roomKind: 'group',
      roomId: groupId,
      cache: _groupPreviews,
      createdAtUtc: createdAtUtc,
      snippet: snippet,
      senderId: senderId,
      messageId: messageId,
      markUnread: markUnread,
    );
  }

  /// Mencatat aktivitas pesan komunitas terbaru secara langsung di memori.
  void recordCommunityActivity({
    required String communityId,
    required DateTime createdAtUtc,
    String? snippet,
    String? senderId,
    String? messageId,
    bool? markUnread,
  }) {
    _recordRoomActivity(
      roomKind: 'community',
      roomId: communityId,
      cache: _communityPreviews,
      createdAtUtc: createdAtUtc,
      snippet: snippet,
      senderId: senderId,
      messageId: messageId,
      markUnread: markUnread,
    );
  }

  void _recordRoomActivity({
    required String roomKind,
    required String roomId,
    required Map<String, SocialLatestPreview> cache,
    required DateTime createdAtUtc,
    String? snippet,
    String? senderId,
    String? messageId,
    bool? markUnread,
  }) {
    if (roomId.isEmpty) return;
    final utc = createdAtUtc.toUtc();
    final existing = cache[roomId];
    if (existing != null && utc.isBefore(existing.createdAtUtc)) {
      return;
    }

    final currentUid = _currentUserIdProvider()?.trim() ?? '';
    final sid = senderId?.trim() ?? existing?.senderId ?? '';
    final isOwn =
        sid.isNotEmpty && currentUid.isNotEmpty && sid == currentUid;
    final isActiveRoom =
        PushNotificationService.instance.activeRoomType == roomKind &&
            PushNotificationService.instance.activeRoomId == roomId;

    final nextUnread = isOwn || isActiveRoom
        ? false
        : (markUnread ?? existing?.hasUnread ?? false);
    final nextSnippet = (snippet != null && snippet.trim().isNotEmpty)
        ? snippet.trim()
        : (existing?.snippet ?? 'Pesan baru');

    cache[roomId] = SocialLatestPreview(
      roomKind: roomKind,
      roomId: roomId,
      snippet: nextSnippet,
      senderId: sid,
      createdAtUtc: utc,
      hasUnread: nextUnread,
      lastMessageId: (messageId != null && messageId.trim().isNotEmpty)
          ? messageId.trim()
          : existing?.lastMessageId,
    );
    notifyListeners();
  }

  static const Duration _timeout = Duration(seconds: 8);
  static final GroupChatCrypto _sharedCrypto = GroupChatCrypto(
    keyStore: const SecureGroupKeyStore(store: FlutterSecureValueStore()),
    allowDeterministicFallback: true,
  );

  static String? _defaultUserId() =>
      SupabaseServices.clientOrNull?.auth.currentUser?.id;

  String _scopedRoomKey(String prefix, String roomId) {
    final uid = _currentUserIdProvider()?.trim();
    if (uid != null && uid.isNotEmpty) {
      return '${prefix}u_${uid}_$roomId';
    }
    return '$prefix$roomId';
  }

  static Future<void> _defaultRoomReadSyncer({
    required String roomKind,
    required String roomId,
    required DateTime lastReadAtUtc,
    String? lastMessageId,
  }) async {
    final client = SupabaseServices.clientOrNull;
    if (client == null || client.auth.currentUser == null) return;
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(roomId)) {
      return;
    }
    try {
      await client.rpc(
        'mark_room_read',
        params: <String, dynamic>{
          'p_room_kind': roomKind,
          'p_room_id': roomId,
          'p_last_read_at': lastReadAtUtc.toUtc().toIso8601String(),
          if (lastMessageId != null && lastMessageId.isNotEmpty)
            'p_last_read_message_id': lastMessageId,
        },
      ).timeout(_timeout);
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> _defaultFetcher() async {
    final client = SupabaseServices.clientOrNull;
    if (client == null || client.auth.currentUser == null) {
      return const <Map<String, dynamic>>[];
    }
    final raw = await client.rpc('social_latest_messages').timeout(_timeout);
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  static Future<Map<String, dynamic>> _defaultDecryptor({
    required String kind,
    required String groupId,
    required String recordId,
    required int keyVersion,
    required String ciphertextBase64,
  }) {
    return _sharedCrypto.decryptJson(
      kind: kind,
      groupId: groupId,
      recordId: recordId,
      keyVersion: keyVersion,
      ciphertextBase64: ciphertextBase64,
    );
  }

  Future<RoomReadCursor> getGroupReadCursor(String groupId) =>
      _getReadCursor(_groupPrefix, _groupMsgPrefix, groupId);

  Future<RoomReadCursor> getCommunityReadCursor(String communityId) =>
      _getReadCursor(_communityPrefix, _communityMsgPrefix, communityId);

  Future<RoomReadCursor> _getReadCursor(
    String timePrefix,
    String msgPrefix,
    String roomId,
  ) async {
    if (roomId.isEmpty) return const RoomReadCursor();
    try {
      final prefs = await _prefsLoader();
      final tsMs = prefs.getInt(_scopedRoomKey(timePrefix, roomId));
      final msgId = prefs.getString(_scopedRoomKey(msgPrefix, roomId));
      return RoomReadCursor(
        lastReadAtUtc: tsMs != null && tsMs > 0
            ? DateTime.fromMillisecondsSinceEpoch(tsMs, isUtc: true)
            : null,
        lastReadMessageId: (msgId != null && msgId.isNotEmpty) ? msgId : null,
      );
    } catch (_) {
      return const RoomReadCursor();
    }
  }

  Future<void> markGroupRead(
    String groupId, {
    DateTime? at,
    String? lastMessageId,
  }) async {
    try {
      await PushNotificationService.instance.clearRoomNotifications(
        type: 'group',
        id: groupId,
      );
    } catch (_) {}
    await _markRead(
      'group',
      _groupPrefix,
      _groupMsgPrefix,
      groupId,
      _groupPreviews,
      at: at,
      lastMessageId: lastMessageId,
    );
  }

  Future<void> markCommunityRead(
    String communityId, {
    DateTime? at,
    String? lastMessageId,
  }) async {
    try {
      await PushNotificationService.instance.clearRoomNotifications(
        type: 'community',
        id: communityId,
      );
    } catch (_) {}
    await _markRead(
      'community',
      _communityPrefix,
      _communityMsgPrefix,
      communityId,
      _communityPreviews,
      at: at,
      lastMessageId: lastMessageId,
    );
  }

  Future<void> _markRead(
    String roomKind,
    String prefix,
    String msgPrefix,
    String roomId,
    Map<String, SocialLatestPreview> cache, {
    DateTime? at,
    String? lastMessageId,
  }) async {
    if (roomId.isEmpty) return;
    final preview = cache[roomId];
    var stampMs = (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    if (preview != null &&
        preview.createdAtUtc.millisecondsSinceEpoch > stampMs) {
      stampMs = preview.createdAtUtc.millisecondsSinceEpoch;
    }
    final memKey = _scopedRoomKey(prefix, roomId);
    final memMsgKey = _scopedRoomKey(msgPrefix, roomId);
    final memPrev = _localLastReadMs[memKey] ?? 0;
    if (memPrev > stampMs) {
      stampMs = memPrev;
    }
    final cleanMsgId =
        (lastMessageId?.trim().isNotEmpty == true)
            ? lastMessageId!.trim()
            : preview?.lastMessageId;

    _localLastReadMs[memKey] = stampMs;
    if (cleanMsgId != null && cleanMsgId.isNotEmpty) {
      _localLastReadMsgId[memMsgKey] = cleanMsgId;
    }

    try {
      final prefs = await _prefsLoader();
      final prev = prefs.getInt(memKey) ?? 0;
      final nextMs = math.max(stampMs, prev);
      _localLastReadMs[memKey] = nextMs;
      stampMs = nextMs;
      await prefs.setInt(memKey, nextMs);
      if (cleanMsgId != null && cleanMsgId.isNotEmpty) {
        await prefs.setString(memMsgKey, cleanMsgId);
      }
    } catch (_) {}

    if (preview != null && preview.hasUnread) {
      cache[roomId] = preview.copyWith(hasUnread: false);
      notifyListeners();
    }

    unawaited(
      _roomReadSyncer(
        roomKind: roomKind,
        roomId: roomId,
        lastReadAtUtc: DateTime.fromMillisecondsSinceEpoch(stampMs, isUtc: true),
        lastMessageId: cleanMsgId,
      ).catchError((_) {}),
    );
  }

  /// Menjalankan 1 kueri ringan untuk memperbarui cuplikan pesan terakhir dan
  /// status titik belum dibaca pada tab Grup & Komunitas.
  Future<void> refresh() async {
    if (_refreshing) return;
    final currentUserId = _currentUserIdProvider();
    if (currentUserId == null || currentUserId.isEmpty) return;

    _refreshing = true;
    try {
      final rows = await _fetcher();
      final prefs = await _prefsLoader();
      final nextGroups = <String, SocialLatestPreview>{};
      final nextCommunities = <String, SocialLatestPreview>{};

      for (final row in rows) {
        final roomKind = row['room_kind']?.toString() ?? '';
        final roomId = row['room_id']?.toString() ?? '';
        final msgId = row['message_id']?.toString() ?? '';
        final senderId = row['sender_id']?.toString() ?? '';
        final rawCreated = row['created_at']?.toString() ?? '';
        final createdAt = DateTime.tryParse(rawCreated)?.toUtc();
        if (roomId.isEmpty || createdAt == null) continue;

        final prefix = roomKind == 'group' ? _groupPrefix : _communityPrefix;
        final msgPrefix =
            roomKind == 'group' ? _groupMsgPrefix : _communityMsgPrefix;
        final scopedTimeKey = _scopedRoomKey(prefix, roomId);
        final scopedMsgKey = _scopedRoomKey(msgPrefix, roomId);
        final localMs = math.max(
          prefs.getInt(scopedTimeKey) ?? 0,
          _localLastReadMs[scopedTimeKey] ?? 0,
        );
        final serverReadAt =
            DateTime.tryParse(row['last_read_at']?.toString() ?? '')?.toUtc();
        final serverMs = serverReadAt?.millisecondsSinceEpoch ?? 0;
        final lastReadMs = math.max(localMs, serverMs);
        if (serverMs > localMs) {
          _localLastReadMs[scopedTimeKey] = lastReadMs;
          try {
            await prefs.setInt(scopedTimeKey, lastReadMs);
          } catch (_) {}
        }

        final localMsgId = _localLastReadMsgId[scopedMsgKey] ??
            prefs.getString(scopedMsgKey);
        final serverMsgId = row['last_read_message_id']?.toString();
        final alreadyReadById = msgId.isNotEmpty &&
            (msgId == localMsgId || msgId == serverMsgId);
        final hasUnread = senderId.isNotEmpty &&
            senderId != currentUserId &&
            !alreadyReadById &&
            createdAt.millisecondsSinceEpoch > lastReadMs;

        if (roomKind == 'group') {
          final snippet = await _resolveGroupSnippet(row, roomId);
          nextGroups[roomId] = SocialLatestPreview(
            roomKind: 'group',
            roomId: roomId,
            snippet: snippet,
            senderId: senderId,
            createdAtUtc: createdAt,
            hasUnread: hasUnread,
            lastMessageId: msgId.isNotEmpty ? msgId : null,
          );
        } else if (roomKind == 'community') {
          final snippet = _resolveCommunitySnippet(row);
          nextCommunities[roomId] = SocialLatestPreview(
            roomKind: 'community',
            roomId: roomId,
            snippet: snippet,
            senderId: senderId,
            createdAtUtc: createdAt,
            hasUnread: hasUnread,
            lastMessageId: msgId.isNotEmpty ? msgId : null,
          );
        }
      }

      for (final entry in _groupPreviews.entries) {
        final incoming = nextGroups[entry.key];
        if (incoming == null ||
            entry.value.createdAtUtc.isAfter(incoming.createdAtUtc)) {
          nextGroups[entry.key] = entry.value;
        }
      }
      for (final entry in _communityPreviews.entries) {
        final incoming = nextCommunities[entry.key];
        if (incoming == null ||
            entry.value.createdAtUtc.isAfter(incoming.createdAtUtc)) {
          nextCommunities[entry.key] = entry.value;
        }
      }

      _groupPreviews
        ..clear()
        ..addAll(nextGroups);
      _communityPreviews
        ..clear()
        ..addAll(nextCommunities);
      notifyListeners();
    } catch (_) {
      // Abaikan bila offline atau RPC belum aktif agar tab Sosial tetap mulus.
    } finally {
      _refreshing = false;
    }
  }

  Future<String> _resolveGroupSnippet(
    Map<String, dynamic> row,
    String groupId,
  ) async {
    if (row['is_deleted'] == true) {
      return 'Pesan telah dihapus';
    }
    if (row['is_cancelled'] == true) {
      return 'Ajakan pendakian dibatalkan';
    }
    final msgType = row['message_type']?.toString() ?? 'text';
    final isVoice = msgType == 'voice' || msgType == 'audio';
    final recordId = row['message_id']?.toString() ?? '';
    final ciphertext = row['ciphertext']?.toString() ?? '';
    final keyVersion = (row['key_version'] as num?)?.toInt() ?? 1;

    if (ciphertext.isEmpty || recordId.isEmpty) {
      return isVoice ? 'Pesan suara' : 'Pesan terenkripsi';
    }
    try {
      final clear = await _decryptor(
        kind: isVoice ? 'voice' : 'text',
        groupId: groupId,
        recordId: recordId,
        keyVersion: keyVersion,
        ciphertextBase64: ciphertext,
      );
      if (isVoice) {
        final sender = clear['sender_name']?.toString().trim();
        return (sender != null && sender.isNotEmpty)
            ? '$sender: Pesan suara'
            : 'Pesan suara';
      }
      final rawText = clear['text']?.toString().trim() ?? '';
      if (rawText.isEmpty) return 'Pesan baru';
      final invite = GroupHikeInviteMessage.tryDecodeInvite(rawText);
      if (invite != null) return 'Ajakan pendakian: ${invite.mountainName}';
      if (GroupHikeInviteMessage.tryDecodeReady(rawText) != null) {
        return 'Anggota siap naik';
      }
      final sender = clear['sender_name']?.toString().trim();
      return (sender != null && sender.isNotEmpty)
          ? '$sender: $rawText'
          : rawText;
    } catch (_) {
      return 'Pesan terenkripsi';
    }
  }

  static String resolveCommunitySnippetFromRow(Map<String, dynamic> row) {
    final sender = row['sender_name']?.toString().trim() ?? '';
    final prefix = sender.isNotEmpty ? '$sender: ' : '';
    if (row['is_deleted'] == true) return '${prefix}Pesan telah dihapus';
    final msgType = row['message_type']?.toString() ?? 'text';
    if (msgType == 'image') return '${prefix}Foto';
    if (msgType == 'video') return '${prefix}Video';
    final text = row['content']?.toString().trim() ?? '';
    if (text.isEmpty) return '${prefix}Pesan baru';
    return '$prefix$text';
  }

  String _resolveCommunitySnippet(Map<String, dynamic> row) =>
      resolveCommunitySnippetFromRow(row);

  Future<void> clearGroup(String groupId) async {
    if (groupId.isEmpty) return;
    _groupPreviews.remove(groupId);
    try {
      final prefs = await _prefsLoader();
      await prefs.remove(_scopedRoomKey(_groupPrefix, groupId));
      await prefs.remove(_scopedRoomKey(_groupMsgPrefix, groupId));
    } catch (_) {}
    notifyListeners();
  }

  void clear() {
    _groupPreviews.clear();
    _communityPreviews.clear();
    notifyListeners();
  }

  /// Mengosongkan seluruh cache unread & kursor baca di memori saat akun berganti.
  void clearForAccountChange() {
    unawaited(unsubscribeRealtime());
    _groupPreviews.clear();
    _communityPreviews.clear();
    _localLastReadMs.clear();
    _localLastReadMsgId.clear();
    _refreshing = false;
    notifyListeners();
  }
}

/// Format jam ringkas (`HH:mm` hari ini atau `dd/MM` hari sebelumnya).
String formatSocialTimeShort(DateTime utc) {
  final local = utc.toLocal();
  final now = DateTime.now();
  final sameDay = local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  if (sameDay) {
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
  final dd = local.day.toString().padLeft(2, '0');
  final mo = local.month.toString().padLeft(2, '0');
  return '$dd/$mo';
}
