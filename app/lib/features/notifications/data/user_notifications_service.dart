import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../infrastructure/supabase/supabase_services.dart';

@immutable
class UserNotificationItem {
  const UserNotificationItem({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    this.actorId,
    this.targetId,
    this.roomType,
    this.roomId,
    this.messageId,
    this.data = const <String, String>{},
    required this.isRead,
    this.readAtUtc,
    required this.createdAtUtc,
  });

  final String id;
  final String userId;
  final String type;
  final String title;
  final String body;
  final String? actorId;
  final String? targetId;
  final String? roomType;
  final String? roomId;
  final String? messageId;
  final Map<String, String> data;
  final bool isRead;
  final DateTime? readAtUtc;
  final DateTime createdAtUtc;

  UserNotificationItem copyWith({
    bool? isRead,
    DateTime? readAtUtc,
  }) =>
      UserNotificationItem(
        id: id,
        userId: userId,
        type: type,
        title: title,
        body: body,
        actorId: actorId,
        targetId: targetId,
        roomType: roomType,
        roomId: roomId,
        messageId: messageId,
        data: data,
        isRead: isRead ?? this.isRead,
        readAtUtc: readAtUtc ?? this.readAtUtc,
        createdAtUtc: createdAtUtc,
      );

  static UserNotificationItem fromMap(Map<String, dynamic> row) {
    final rawData = row['data'];
    final dataMap = <String, String>{};
    if (rawData is Map) {
      for (final e in rawData.entries) {
        if (e.value != null) {
          dataMap[e.key.toString()] = e.value.toString();
        }
      }
    }
    return UserNotificationItem(
      id: row['id']?.toString() ?? '',
      userId: row['user_id']?.toString() ?? '',
      type: row['type']?.toString() ?? 'general',
      title: row['title']?.toString() ?? 'Hiqeo',
      body: row['body']?.toString() ?? '',
      actorId: row['actor_id']?.toString(),
      targetId: row['target_id']?.toString(),
      roomType: row['room_type']?.toString(),
      roomId: row['room_id']?.toString(),
      messageId: row['message_id']?.toString(),
      data: dataMap,
      isRead: row['is_read'] == true,
      readAtUtc: row['read_at'] != null
          ? DateTime.tryParse(row['read_at'].toString())?.toUtc()
          : null,
      createdAtUtc: row['created_at'] != null
          ? (DateTime.tryParse(row['created_at'].toString())?.toUtc() ??
              DateTime.now().toUtc())
          : DateTime.now().toUtc(),
    );
  }
}

/// Layanan inbox notifikasi Beranda (`public.user_notifications`) dengan
/// langganan Realtime untuk permintaan teman, undangan grup, ajakan mendaki,
/// `@username` mention komunitas, kontak darurat, dan sinyal SOS.
class UserNotificationsService extends ChangeNotifier {
  UserNotificationsService._({
    List<UserNotificationItem> initialItems = const <UserNotificationItem>[],
    DateTime? badgeSeenAtUtc,
    String? initialLoadError,
    bool isTesting = false,
  })  : _items = _filterInboxItems(initialItems),
        _badgeSeenAtUtc = badgeSeenAtUtc?.toUtc(),
        _loadError = initialLoadError,
        _isTesting = isTesting;

  static final UserNotificationsService instance = UserNotificationsService._();

  @visibleForTesting
  factory UserNotificationsService.createForTesting({
    List<UserNotificationItem> initialItems = const <UserNotificationItem>[],
    DateTime? badgeSeenAtUtc,
    String? initialLoadError,
  }) =>
      UserNotificationsService._(
        initialItems: initialItems,
        badgeSeenAtUtc: badgeSeenAtUtc,
        initialLoadError: initialLoadError,
        isTesting: true,
      );

  /// Pesan obrolan grup/komunitas biasa tidak masuk ke inbox Beranda.
  static const Set<String> excludedChatTypes = <String>{
    'group_chat',
    'group_message',
    'community_chat',
    'community_message',
  };

  static const String _badgeSeenKeyPrefix = 'hiqeo_notif_badge_seen_v1_';

  static List<UserNotificationItem> _filterInboxItems(
    Iterable<UserNotificationItem> source,
  ) =>
      source
          .where((item) => !excludedChatTypes.contains(item.type))
          .toList(growable: false);

  final bool _isTesting;
  List<UserNotificationItem> _items;
  bool _loading = false;
  String? _loadError;
  DateTime? _badgeSeenAtUtc;
  String? _loadedSeenOwnerKey;
  RealtimeChannel? _channel;
  String? _subscribedUserId;

  List<UserNotificationItem> get items => _items;
  DateTime? get badgeSeenAtUtc => _badgeSeenAtUtc;
  int get unreadCount => _items.where((item) => !item.isRead).length;
  String? get loadError => _loadError;

  @visibleForTesting
  void setLoadErrorForTesting(String? error) {
    _loadError = error;
    notifyListeners();
  }

  /// `true` bila ada minimal 1 notifikasi belum dibaca yang lebih baru dari
  /// waktu terakhir pengguna membuka halaman Notifikasi (`badge_seen`).
  bool get hasUnreadNotifications {
    final seenAt = _badgeSeenAtUtc;
    return _items.any((item) {
      if (item.isRead) return false;
      if (seenAt == null) return true;
      return item.createdAtUtc.isAfter(seenAt);
    });
  }

  bool get isLoading => _loading;

  String _currentSeenKey() {
    if (_isTesting) return '${_badgeSeenKeyPrefix}test';
    final uid = SupabaseServices.clientOrNull?.auth.currentUser?.id;
    return '$_badgeSeenKeyPrefix${uid ?? 'local'}';
  }

  /// Memuat stempel waktu `seen_at` lokal agar titik merah tidak muncul ulang
  /// setelah aplikasi dibuka kembali bila pengguna sudah masuk ke halaman Notifikasi.
  Future<void> loadBadgeSeenState() async {
    if (_isTesting) return;
    final key = _currentSeenKey();
    if (_loadedSeenOwnerKey == key && _badgeSeenAtUtc != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      _loadedSeenOwnerKey = key;
      final parsed = raw != null ? DateTime.tryParse(raw)?.toUtc() : null;
      if (parsed != null && parsed != _badgeSeenAtUtc) {
        _badgeSeenAtUtc = parsed;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Menghilangkan titik merah di Beranda seketika saat pengguna mengetuk
  /// tombol lonceng / masuk ke halaman Notifikasi (`badge_seen`).
  Future<void> markBadgeSeen() async {
    var seenAt = DateTime.now().toUtc();
    for (final item in _items) {
      if (item.createdAtUtc.isAfter(seenAt)) {
        seenAt = item.createdAtUtc;
      }
    }
    _badgeSeenAtUtc = seenAt;
    notifyListeners();

    if (_isTesting) return;
    final key = _currentSeenKey();
    _loadedSeenOwnerKey = key;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, seenAt.toIso8601String());
    } catch (_) {}
  }

  static bool _isOfflineError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('connection refused') ||
        text.contains('connection closed') ||
        text.contains('clientexception') ||
        text.contains('xmlhttprequest error');
  }

  static const Duration _timeout = Duration(seconds: 9);

  Future<void> loadNotifications({int limit = 50}) async {
    await loadBadgeSeenState();
    if (_isTesting) {
      if (_loadError != null) {
        _loadError = null;
        notifyListeners();
      }
      return;
    }
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      _items = const <UserNotificationItem>[];
      _loadError = null;
      notifyListeners();
      return;
    }

    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      final rows = await client
          .from('user_notifications')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(limit.clamp(1, 100))
          .timeout(_timeout);
      _items = _filterInboxItems(
        rows.map<UserNotificationItem>(
          (r) => UserNotificationItem.fromMap(Map<String, dynamic>.from(r)),
        ),
      );
      _loadError = null;
    } catch (e) {
      // Tetap aman saat offline; ekspos state galat hanya pada kegagalan online saat cache kosong.
      if (_items.isEmpty && !_isOfflineError(e)) {
        _loadError =
            'Notifikasi belum dapat dimuat dari server. Periksa koneksi lalu coba lagi.';
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void ensureRealtimeSubscribed() {
    if (_isTesting) return;
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    if (_subscribedUserId == user.id && _channel != null) return;

    unawaited(disposeChannel());
    _subscribedUserId = user.id;
    _channel = client
        .channel('hiqeo_user_notifications_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (_) => unawaited(loadNotifications()),
        )
        .subscribe();
  }

  Future<void> markAsRead(String notificationId) async {
    final nowUtc = DateTime.now().toUtc();
    _items = _items
        .map(
          (item) => item.id == notificationId && !item.isRead
              ? item.copyWith(isRead: true, readAtUtc: nowUtc)
              : item,
        )
        .toList(growable: false);
    notifyListeners();

    if (_isTesting) return;
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    try {
      await client
          .from('user_notifications')
          .update(<String, dynamic>{
            'is_read': true,
            'read_at': nowUtc.toIso8601String(),
          })
          .eq('id', notificationId)
          .eq('user_id', user.id)
          .timeout(_timeout);
    } catch (_) {}
  }

  Future<void> markAllAsRead() async {
    final nowUtc = DateTime.now().toUtc();
    _items = _items
        .map(
          (item) => item.isRead
              ? item
              : item.copyWith(isRead: true, readAtUtc: nowUtc),
        )
        .toList(growable: false);
    await markBadgeSeen();

    if (_isTesting) return;
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    try {
      await client.rpc('mark_all_notifications_read').timeout(_timeout);
    } catch (_) {
      try {
        await client
            .from('user_notifications')
            .update(<String, dynamic>{
              'is_read': true,
              'read_at': nowUtc.toIso8601String(),
            })
            .eq('user_id', user.id)
            .eq('is_read', false)
            .timeout(_timeout);
      } catch (_) {}
    }
  }

  Future<void> disposeChannel() async {
    final ch = _channel;
    _channel = null;
    _subscribedUserId = null;
    if (ch != null) {
      try {
        await SupabaseServices.clientOrNull?.removeChannel(ch);
      } catch (_) {}
    }
  }

  void clear() {
    unawaited(disposeChannel());
    _items = const <UserNotificationItem>[];
    _loadError = null;
    _badgeSeenAtUtc = null;
    _loadedSeenOwnerKey = null;
    notifyListeners();
  }
}
