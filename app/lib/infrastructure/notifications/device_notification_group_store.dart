import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef NotificationPrefsLoader = Future<SharedPreferences> Function();

@immutable
class PendingRoomNotificationMessage {
  const PendingRoomNotificationMessage({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.text,
    this.senderAvatarUrl,
    required this.timestampUtc,
  });

  final String messageId;
  final String senderId;
  final String senderName;
  final String text;
  final String? senderAvatarUrl;
  final DateTime timestampUtc;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'messageId': messageId,
        'senderId': senderId,
        'senderName': senderName,
        'text': text,
        if (senderAvatarUrl != null && senderAvatarUrl!.isNotEmpty)
          'senderAvatarUrl': senderAvatarUrl,
        'timestampMs': timestampUtc.toUtc().millisecondsSinceEpoch,
      };

  static PendingRoomNotificationMessage? fromJson(Map<String, dynamic> map) {
    final text = map['text']?.toString().trim() ?? '';
    final senderName = map['senderName']?.toString().trim() ?? '';
    if (text.isEmpty || senderName.isEmpty) return null;
    final tsMs = map['timestampMs'] is int
        ? map['timestampMs'] as int
        : int.tryParse(map['timestampMs']?.toString() ?? '') ?? 0;
    return PendingRoomNotificationMessage(
      messageId: map['messageId']?.toString() ?? '',
      senderId: map['senderId']?.toString() ?? '',
      senderName: senderName,
      text: text,
      senderAvatarUrl: map['senderAvatarUrl']?.toString(),
      timestampUtc: tsMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(tsMs, isUtc: true)
          : DateTime.now().toUtc(),
    );
  }
}

@immutable
class RoomNotificationQueueState {
  const RoomNotificationQueueState({
    required this.roomType,
    required this.roomId,
    required this.roomName,
    this.roomAvatarUrl,
    required this.unreadCount,
    required this.recentMessages,
    this.seenMessageIds = const <String>[],
  });

  final String roomType;
  final String roomId;
  final String roomName;
  final String? roomAvatarUrl;
  final int unreadCount;
  final List<PendingRoomNotificationMessage> recentMessages;
  final List<String> seenMessageIds;

  int get notificationId =>
      DeviceNotificationGroupStore.notificationIdForRoom(roomType, roomId);

  String get formattedTitle =>
      DeviceNotificationGroupStore.formatGroupTitle(roomName, unreadCount);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'roomType': roomType,
        'roomId': roomId,
        'roomName': roomName,
        if (roomAvatarUrl != null && roomAvatarUrl!.isNotEmpty)
          'roomAvatarUrl': roomAvatarUrl,
        'unreadCount': unreadCount,
        'recentMessages': recentMessages.map((m) => m.toJson()).toList(),
        'seenMessageIds': seenMessageIds,
      };

  static RoomNotificationQueueState? fromJson(Map<String, dynamic> map) {
    final roomType = map['roomType']?.toString().trim() ?? '';
    final roomId = map['roomId']?.toString().trim() ?? '';
    if (roomType.isEmpty || roomId.isEmpty) return null;
    final unread = map['unreadCount'] is int
        ? map['unreadCount'] as int
        : int.tryParse(map['unreadCount']?.toString() ?? '') ?? 0;
    if (unread <= 0) return null;

    final recent = <PendingRoomNotificationMessage>[];
    final rawMsgs = map['recentMessages'];
    if (rawMsgs is List) {
      for (final item in rawMsgs) {
        if (item is Map) {
          final parsed = PendingRoomNotificationMessage.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (parsed != null) recent.add(parsed);
        }
      }
    }

    final seenIds = <String>[];
    final rawSeen = map['seenMessageIds'];
    if (rawSeen is List) {
      for (final s in rawSeen) {
        final v = s?.toString().trim() ?? '';
        if (v.isNotEmpty) seenIds.add(v);
      }
    }

    return RoomNotificationQueueState(
      roomType: roomType,
      roomId: roomId,
      roomName: map['roomName']?.toString().trim().isNotEmpty == true
          ? map['roomName']!.toString().trim()
          : (roomType == 'community' ? 'Komunitas Hiqeo' : 'Grup Pendakian'),
      roomAvatarUrl: map['roomAvatarUrl']?.toString(),
      unreadCount: unread,
      recentMessages: recent,
      seenMessageIds: seenIds,
    );
  }
}

/// Penyimpanan persisten antrean notifikasi perangkat per `(roomType, roomId)`.
///
/// Memastikan jumlah pesan masuk yang belum dibaca tetap akurat lintas
/// background isolate (`FirebaseMessaging.onBackgroundMessage`), tahan terhadap
/// geser-hapus (swipe/dismiss) di panel notifikasi Android, dan hanya kembali ke
/// `0` ketika pengguna benar-benar membuka ruang obrolan tersebut.
class DeviceNotificationGroupStore {
  DeviceNotificationGroupStore({NotificationPrefsLoader? prefsLoader})
      : _customPrefsLoader = prefsLoader;

  static final DeviceNotificationGroupStore instance =
      DeviceNotificationGroupStore();

  static const String _roomPrefix = 'hiqeo_notif_room_';
  static const String _indexKey = 'hiqeo_notif_group_index_v1';
  static const int _maxRecentMessages = 10;
  static const int _maxSeenIds = 40;

  NotificationPrefsLoader? _customPrefsLoader;

  NotificationPrefsLoader get _prefsLoader =>
      _customPrefsLoader ?? SharedPreferences.getInstance;

  @visibleForTesting
  void setPrefsLoaderForTesting(NotificationPrefsLoader? loader) {
    _customPrefsLoader = loader;
  }

  /// Menghasilkan ID notifikasi Android deterministik positif per `(roomType, roomId)`
  /// agar pesan berturut-turut di ruang yang sama memperbarui 1 kartu notifikasi.
  static int notificationIdForRoom(String roomType, String roomId) {
    final key = '${roomType.trim()}:${roomId.trim()}';
    var hash = 0x811c9dc5;
    for (var i = 0; i < key.length; i++) {
      hash ^= key.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return 100000 + (hash % 1800000000);
  }

  /// Judul ringkas notifikasi terkelompok, mis. `"Pendakian Gunung Gede · 3 pesan baru"`.
  static String formatGroupTitle(String roomName, int unreadCount) {
    final cleanName =
        roomName.trim().isNotEmpty ? roomName.trim() : 'Obrolan Hiqeo';
    final count = unreadCount < 1 ? 1 : unreadCount;
    return '$cleanName · $count pesan baru';
  }

  static String _storageKey(String roomType, String roomId) =>
      '$_roomPrefix${roomType.trim()}_${roomId.trim()}';

  static String _fallbackRoomName(String roomType) =>
      roomType.trim() == 'community' ? 'Komunitas Hiqeo' : 'Grup Pendakian';

  static bool _isGenericRoomName(String name) {
    final lower = name.trim().toLowerCase();
    return lower.isEmpty ||
        lower == 'grup pendakian' ||
        lower == 'komunitas hiqeo' ||
        lower == 'obrolan hiqeo';
  }

  Future<SharedPreferences> _openFreshPrefs() async {
    final prefs = await _prefsLoader();
    try {
      await prefs.reload();
    } catch (_) {
      // Aman di SharedPreferences mock test.
    }
    return prefs;
  }

  RoomNotificationQueueState? _decodeFromPrefs(
    SharedPreferences prefs,
    String key,
  ) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return RoomNotificationQueueState.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (_) {}
    return null;
  }

  /// Menambahkan pesan baru ke antrean ruang dan mengembalikan status terbaru
  /// dengan [unreadCount] terakumulasi.
  Future<RoomNotificationQueueState> appendMessage({
    required String roomType,
    required String roomId,
    required String roomName,
    String? roomAvatarUrl,
    required PendingRoomNotificationMessage message,
  }) async {
    final rt = roomType.trim();
    final rid = roomId.trim();
    final key = _storageKey(rt, rid);

    SharedPreferences? prefs;
    RoomNotificationQueueState? existing;
    try {
      prefs = await _openFreshPrefs();
      existing = _decodeFromPrefs(prefs, key);
    } catch (_) {}

    final incomingName = roomName.trim();
    final resolvedRoomName = existing != null &&
            (!_isGenericRoomName(existing.roomName) ||
                _isGenericRoomName(incomingName))
        ? existing.roomName
        : (incomingName.isNotEmpty ? incomingName : _fallbackRoomName(rt));

    final cleanRoomAvatar = roomAvatarUrl?.trim();
    final resolvedRoomAvatar =
        (cleanRoomAvatar != null && cleanRoomAvatar.isNotEmpty)
            ? cleanRoomAvatar
            : existing?.roomAvatarUrl;

    final cleanMsgId = message.messageId.trim();
    if (existing != null &&
        cleanMsgId.isNotEmpty &&
        existing.seenMessageIds.contains(cleanMsgId)) {
      return existing;
    }

    final nextUnread = (existing?.unreadCount ?? 0) + 1;
    final nextMessages = <PendingRoomNotificationMessage>[
      ...?existing?.recentMessages,
      message,
    ];
    while (nextMessages.length > _maxRecentMessages) {
      nextMessages.removeAt(0);
    }

    final nextSeen = <String>[
      ...?existing?.seenMessageIds,
      if (cleanMsgId.isNotEmpty) cleanMsgId,
    ];
    while (nextSeen.length > _maxSeenIds) {
      nextSeen.removeAt(0);
    }

    final nextState = RoomNotificationQueueState(
      roomType: rt,
      roomId: rid,
      roomName: resolvedRoomName,
      roomAvatarUrl: resolvedRoomAvatar,
      unreadCount: nextUnread,
      recentMessages: nextMessages,
      seenMessageIds: nextSeen,
    );

    if (prefs != null) {
      try {
        await prefs.setString(key, jsonEncode(nextState.toJson()));
        final keys = Set<String>.from(prefs.getStringList(_indexKey) ?? <String>[])
          ..add(key);
        await prefs.setStringList(_indexKey, keys.toList(growable: false));
      } catch (_) {}
    }

    return nextState;
  }

  /// Mengganti teks pesan tertentu pada antrean notifikasi aktif menjadi
  /// `"Pesan telah dihapus"` bila ruang tersebut masih memiliki notifikasi
  /// belum dibaca yang mencakup [messageId]. Mengembalikan `null` jika tidak ada.
  Future<RoomNotificationQueueState?> markMessageDeleted({
    required String roomType,
    required String roomId,
    required String messageId,
    String replacementText = 'Pesan telah dihapus',
  }) async {
    final rt = roomType.trim();
    final rid = roomId.trim();
    final mid = messageId.trim();
    final replacement = replacementText.trim().isNotEmpty
        ? replacementText.trim()
        : 'Pesan telah dihapus';
    if (rt.isEmpty || rid.isEmpty || mid.isEmpty) return null;

    final key = _storageKey(rt, rid);
    try {
      final prefs = await _openFreshPrefs();
      final existing = _decodeFromPrefs(prefs, key);
      if (existing == null) return null;

      var matched = false;
      final updatedMessages = existing.recentMessages.map((m) {
        if (m.messageId.trim() == mid) {
          matched = true;
          return PendingRoomNotificationMessage(
            messageId: m.messageId,
            senderId: m.senderId,
            senderName: m.senderName,
            text: replacement,
            senderAvatarUrl: m.senderAvatarUrl,
            timestampUtc: m.timestampUtc,
          );
        }
        return m;
      }).toList(growable: false);

      if (!matched) return null;

      final updatedState = RoomNotificationQueueState(
        roomType: existing.roomType,
        roomId: existing.roomId,
        roomName: existing.roomName,
        roomAvatarUrl: existing.roomAvatarUrl,
        unreadCount: existing.unreadCount,
        recentMessages: updatedMessages,
        seenMessageIds: existing.seenMessageIds,
      );
      await prefs.setString(key, jsonEncode(updatedState.toJson()));
      return updatedState;
    } catch (_) {
      return null;
    }
  }

  /// Membaca antrean tersimpan saat ini (tidak berubah bila notifikasi hanya
  /// digeser/dihapus dari panel notifikasi Android).
  Future<RoomNotificationQueueState?> getRoomState(
    String roomType,
    String roomId,
  ) async {
    try {
      final prefs = await _openFreshPrefs();
      return _decodeFromPrefs(prefs, _storageKey(roomType, roomId));
    } catch (_) {
      return null;
    }
  }

  /// Mengosongkan antrean notifikasi untuk ruang tertentu setelah pengguna masuk
  /// dan membuka halaman obrolan ruang tersebut.
  Future<void> clearRoom({
    required String roomType,
    required String roomId,
  }) async {
    final key = _storageKey(roomType, roomId);
    try {
      final prefs = await _openFreshPrefs();
      await prefs.remove(key);
      final keys = prefs.getStringList(_indexKey);
      if (keys != null && keys.contains(key)) {
        final updated = keys.where((k) => k != key).toList(growable: false);
        if (updated.isEmpty) {
          await prefs.remove(_indexKey);
        } else {
          await prefs.setStringList(_indexKey, updated);
        }
      }
    } catch (_) {}
  }

  /// Menghapus seluruh antrean notifikasi yang tersimpan (mis. saat logout).
  Future<void> clearAll() async {
    try {
      final prefs = await _openFreshPrefs();
      final keys = prefs.getStringList(_indexKey) ?? const <String>[];
      for (final key in keys) {
        await prefs.remove(key);
      }
      await prefs.remove(_indexKey);
    } catch (_) {}
  }
}
