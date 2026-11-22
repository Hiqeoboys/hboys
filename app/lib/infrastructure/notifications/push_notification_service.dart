import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../features/chat/domain/group_chat_models.dart';
import '../../features/notifications/data/user_notifications_service.dart';
import '../../features/preparation/application/packing_list_store.dart';
import '../../features/social/data/chat_mute_service.dart';
import '../../features/social/data/social_unread_store.dart';
import '../storage/media_url_normalizer.dart';
import '../supabase/supabase_services.dart';
import 'device_notification_group_store.dart';
import 'notification_avatar_helper.dart';

/// Warna aksen notifikasi Android merek Hiqeo (`#242B40`) & peringatan SOS.
const Color kHiqeoNotificationAccentColor = Color(0xFF242B40);
const Color kHiqeoSosNotificationColor = Color(0xFFB3412F);

/// 5 saluran notifikasi Android terpisah & rapi.
const String kHiqeoGroupMessagesChannelId = 'hiqeo_group_messages';
const String kHiqeoCommunityMessagesChannelId = 'hiqeo_community_messages';
const String kHiqeoMentionsChannelId = 'hiqeo_mentions';
const String kHiqeoSocialPrepChannelId = 'hiqeo_social_prep';
const String kHiqeoSosChannelId = 'hiqeo_sos_urgent';

/// Alias kompatibilitas dengan pemanggil lama.
const String kHiqeoMessagesChannelId = kHiqeoGroupMessagesChannelId;

/// Handler latar belakang top-level wajib untuk Firebase Cloud Messaging.
/// Dijalankan di background isolate saat aplikasi berada di background / mati.
@pragma('vm:entry-point')
Future<void> hiqeoFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
  } catch (_) {}
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('FCM background Firebase.initializeApp skipped: $e');
    }
  }
  await PushNotificationService.instance.handleBackgroundRemoteMessage(message);
}

/// Niat navigasi langsung ke ruang obrolan / lokasi SOS saat notifikasi diketuk.
enum SocialNavigationTargetKind {
  groupRoom,
  communityRoom,
  groupLastLocation,
}

@immutable
class SocialNavigationIntent {
  const SocialNavigationIntent({
    required this.kind,
    required this.targetId,
    required this.nonce,
    this.messageId,
  });

  final SocialNavigationTargetKind kind;
  final String targetId;
  final int nonce;
  final String? messageId;
}

/// Muatan notifikasi push FCM yang telah dinormalisasi untuk notifikasi OS
/// perangkat, pengelompokan antrean pesan, dan navigasi otomatis saat diketuk.
@immutable
class InAppPushNotification {
  const InAppPushNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.route,
    this.targetId,
    this.groupId,
    this.communityId,
    this.inviteId,
    this.sosId,
    this.messageId,
    this.roomName,
    this.roomAvatarUrl,
    this.senderId,
    this.senderName,
    this.senderAvatarUrl,
    this.messageText,
    this.sentAtUtc,
    this.rawData = const <String, String>{},
  });

  final String id;

  /// Tipe kanonik: `group_chat`, `group_ready`, `group_hike_cancelled`,
  /// `group_invitation`, `community_chat`, `community_mention`,
  /// `friend_request`, `sos`, `emergency_contact_request`, atau `general`.
  final String type;

  /// Alias kompatibilitas dengan kode lama yang membaca `kind`.
  String get kind => type;

  final String title;
  final String body;
  final String route;
  final String? targetId;
  final String? groupId;
  final String? communityId;
  final String? inviteId;
  final String? sosId;
  final String? messageId;
  final String? roomName;
  final String? roomAvatarUrl;
  final String? senderId;
  final String? senderName;
  final String? senderAvatarUrl;
  final String? messageText;
  final DateTime? sentAtUtc;
  final Map<String, String> rawData;

  bool get isUrgent =>
      type == 'sos' || type == 'sos_alert' || type == 'sos_nearby';

  bool get isRoomChatNotification =>
      (type == 'group_chat' ||
          type == 'community_chat' ||
          type == 'community_mention') &&
      roomType != null &&
      roomId != null &&
      roomId!.isNotEmpty;

    String? get roomType {
    if (type == 'group_chat' ||
        type == 'group_ready' ||
        type == 'group_hike_cancelled' ||
        type == 'hike_started' ||
        type == 'group_invitation') {
      return 'group';
    }
    if (type == 'community_chat' ||
        type == 'community_mention' ||
        type == 'community_message_deleted') {
      return 'community';
    }
    if (groupId != null && groupId!.isNotEmpty) return 'group';
    if (communityId != null && communityId!.isNotEmpty) return 'community';
    return null;
  }

  String? get roomId {
    if (roomType == 'group') return groupId ?? targetId;
    if (roomType == 'community') return communityId ?? targetId;
    return null;
  }

  String? get roomKey {
    final rt = roomType;
    final rid = roomId;
    if (rt != null && rid != null && rid.isNotEmpty) return '$rt:$rid';
    return null;
  }

  String toPayloadJson() => jsonEncode(<String, dynamic>{
        'id': id,
        'title': title,
        'body': body,
        'data': rawData,
      });

  static InAppPushNotification? fromPayloadJson(String? payload) {
    if (payload == null || payload.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      final data = decoded['data'] is Map
          ? Map<String, dynamic>.from(decoded['data'] as Map)
          : <String, dynamic>{};
      return fromRemoteData(
        id: decoded['id']?.toString(),
        title: decoded['title']?.toString(),
        body: decoded['body']?.toString(),
        data: data,
      );
    } catch (_) {
      return null;
    }
  }

  static InAppPushNotification fromRemoteData({
    String? id,
    String? title,
    String? body,
    required Map<String, dynamic> data,
  }) {
    final normalized = <String, String>{
      for (final e in data.entries)
        if (e.value != null) e.key: e.value.toString(),
    };

    // Normalisasi `data.type` baru maupun `data.kind` lama.
    final rawType = _nonEmpty(normalized['type']) ??
        _nonEmpty(normalized['kind']) ??
        'general';
    final canonicalType = switch (rawType) {
      'group_chat' || 'group_message' => 'group_chat',
      'group_ready' || 'group_hike_invite' => 'group_ready',
      'group_hike_cancelled' || 'hike_cancelled' => 'group_hike_cancelled',
      'hike_started' || 'group_hike_started' => 'hike_started',
      'group_invitation' => 'group_invitation',
      'community_chat' || 'community_message' => 'community_chat',
      'community_mention' => 'community_mention',
      'community_message_deleted' => 'community_message_deleted',
      'friend_request' => 'friend_request',
      'sos' || 'sos_alert' => 'sos',
      'sos_nearby' => 'sos_nearby',
      'emergency_contact_request' => 'emergency_contact_request',
      _ => rawType,
    };

    final rawTarget = _nonEmpty(normalized['target_id']);
    final groupId = _nonEmpty(normalized['group_id']) ??
        ((canonicalType == 'group_chat' ||
                canonicalType == 'group_ready' ||
                canonicalType == 'group_hike_cancelled' ||
                canonicalType == 'hike_started' ||
                canonicalType == 'group_invitation')
            ? rawTarget
            : null);
    final communityId = _nonEmpty(normalized['community_id']) ??
        ((canonicalType == 'community_chat' ||
                canonicalType == 'community_mention' ||
                canonicalType == 'community_message_deleted')
            ? rawTarget
            : null);
    final inviteId = _nonEmpty(normalized['invite_id']);
    final sosId = _nonEmpty(normalized['sos_id']) ??
        ((canonicalType == 'sos' || canonicalType == 'sos_nearby')
            ? rawTarget
            : null);
    final messageId = _nonEmpty(normalized['message_id']);
    final roomName = _nonEmpty(normalized['room_name']);
    final roomAvatarUrl =
        MediaUrlNormalizer.normalize(_nonEmpty(normalized['room_avatar_url']));
    final senderId = _nonEmpty(normalized['sender_id']);
    final senderName = _nonEmpty(normalized['sender_name']);
    final senderAvatarUrl =
        MediaUrlNormalizer.normalize(_nonEmpty(normalized['sender_avatar_url']));
    final targetId = rawTarget ?? groupId ?? communityId ?? sosId;

    final defaultRoute = switch (canonicalType) {
      'group_chat' => '/grup',
      'group_ready' => groupId != null ? '/grup' : '/siap-naik',
      'group_hike_cancelled' => '/grup',
      'hike_started' => '/peta/jalur',
      'group_invitation' => '/grup',
      'community_chat' ||
      'community_mention' ||
      'community_message_deleted' =>
        '/grup',
      'friend_request' => '/teman',
      'sos' => groupId != null ? '/grup' : '/sos',
      'sos_nearby' => '',
      'emergency_contact_request' => '/profil',
      _ => '/beranda',
    };
    final route = _nonEmpty(normalized['route']) ?? defaultRoute;

    final resolvedTitle = _nonEmpty(title) ??
        _nonEmpty(normalized['title']) ??
        roomName ??
        switch (canonicalType) {
          'group_chat' => 'Grup Pendakian',
          'group_ready' => 'Ajakan Pendakian Grup',
          'group_hike_cancelled' => 'Ajakan Pendakian Dibatalkan',
          'hike_started' => 'Pendakian Grup Dimulai',
          'group_invitation' => 'Undangan Grup Pendakian',
          'community_chat' => 'Komunitas Hiqeo',
          'community_mention' => 'Kamu Disebut di Komunitas',
          'friend_request' => 'Permintaan Pertemanan',
          'sos' => 'DARURAT SOS HIQEO',
          'sos_nearby' => 'DARURAT SOS TERDEKAT',
          'emergency_contact_request' => 'Permintaan Kontak Darurat',
          _ => 'Hiqeo',
        };
    final resolvedBody = _nonEmpty(body) ??
        _nonEmpty(normalized['body']) ??
        'Ketuk untuk membuka.';

    var resolvedMessageText = _nonEmpty(normalized['message_text']);
    if (resolvedMessageText == null) {
      if (senderName != null && resolvedBody.startsWith('$senderName: ')) {
        resolvedMessageText =
            resolvedBody.substring(senderName.length + 2).trim();
      } else {
        resolvedMessageText = resolvedBody;
      }
    }
    final sentAtRaw = _nonEmpty(normalized['sent_at']);
    final sentAtUtc = sentAtRaw != null
        ? DateTime.tryParse(sentAtRaw)?.toUtc()
        : null;

    return InAppPushNotification(
      id: id ??
          messageId ??
          'fcm_${DateTime.now().microsecondsSinceEpoch}',
      type: canonicalType,
      title: resolvedTitle,
      body: resolvedBody,
      route: route,
      targetId: targetId,
      groupId: groupId,
      communityId: communityId,
      inviteId: inviteId,
      sosId: sosId,
      messageId: messageId,
      roomName: roomName ?? resolvedTitle,
      roomAvatarUrl: roomAvatarUrl,
      senderId: senderId,
      senderName: senderName,
      senderAvatarUrl: senderAvatarUrl,
      messageText: resolvedMessageText,
      sentAtUtc: sentAtUtc,
      rawData: normalized,
    );
  }

  static String? _nonEmpty(String? raw) {
    final trimmed = raw?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}

class _NotificationChannelSpec {
  const _NotificationChannelSpec({
    required this.id,
    required this.name,
    required this.description,
    this.importance = Importance.high,
  });

  final String id;
  final String name;
  final String description;
  final Importance importance;
}

/// Mengelola Firebase Cloud Messaging (FCM), `flutter_local_notifications`
/// (5 channel Android rapi, ikon monokrom `ic_stat_hiqeo`, aksen `#242B40`,
/// `MessagingStyleInformation` berkelompok per ruang dengan penghitung persisten),
/// serta deep-link router saat notifikasi perangkat diketuk.
class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  static const String _smallIconDrawable = 'ic_stat_hiqeo';
  static const Person _selfPerson = Person(name: 'Kamu', key: 'hiqeo_self');

  static const List<_NotificationChannelSpec> _channelSpecs =
      <_NotificationChannelSpec>[
    _NotificationChannelSpec(
      id: kHiqeoGroupMessagesChannelId,
      name: 'Pesan Grup',
      description: 'Notifikasi obrolan grup pendakian.',
    ),
    _NotificationChannelSpec(
      id: kHiqeoCommunityMessagesChannelId,
      name: 'Pesan Komunitas',
      description: 'Notifikasi obrolan komunitas pendaki.',
    ),
    _NotificationChannelSpec(
      id: kHiqeoMentionsChannelId,
      name: 'Sebutan @username',
      description: 'Pemberitahuan saat kamu disebut langsung di komunitas.',
    ),
    _NotificationChannelSpec(
      id: kHiqeoSocialPrepChannelId,
      name: 'Sosial & Persiapan',
      description:
          'Permintaan teman, undangan grup, kontak darurat, dan ajakan mendaki.',
    ),
    _NotificationChannelSpec(
      id: kHiqeoSosChannelId,
      name: 'Darurat SOS Hiqeo',
      description:
          'Peringatan darurat SOS prioritas maksimum dari rombongan atau kontak darurat.',
      importance: Importance.max,
    ),
  ];

  static String resolveChannelId(InAppPushNotification notif) =>
      switch (notif.type) {
        'sos' || 'sos_alert' || 'sos_nearby' => kHiqeoSosChannelId,
        'group_chat' => kHiqeoGroupMessagesChannelId,
        'community_chat' => kHiqeoCommunityMessagesChannelId,
        'community_mention' => kHiqeoMentionsChannelId,
        _ => kHiqeoSocialPrepChannelId,
      };

  static _NotificationChannelSpec _specForChannel(String channelId) {
    for (final spec in _channelSpecs) {
      if (spec.id == channelId) return spec;
    }
    return _channelSpecs.first;
  }

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final StreamController<InAppPushNotification> _foregroundCtrl =
      StreamController<InAppPushNotification>.broadcast();
  final StreamController<InAppPushNotification> _tapCtrl =
      StreamController<InAppPushNotification>.broadcast();

  /// Hook opsional untuk uji unit tanpa kanal platform Android.
  @visibleForTesting
  Future<void> Function({
    required int id,
    required String title,
    required String body,
    required NotificationDetails details,
    required String payload,
  })? showNotificationForTesting;

  /// Hook opsional untuk uji unit penghapusan notifikasi saat masuk ruang chat.
  @visibleForTesting
  Future<void> Function(int id)? cancelNotificationForTesting;

  /// Sinyal navigasi mendalam ke [ChatPage] (buka ruang obrolan grup,
  /// komunitas, atau layar Lokasi Terakhir SOS secara otomatis).
  final ValueNotifier<SocialNavigationIntent?> pendingSocialIntent =
      ValueNotifier<SocialNavigationIntent?>(null);

  Stream<InAppPushNotification> get onForegroundMessage =>
      _foregroundCtrl.stream;
  Stream<InAppPushNotification> get onNotificationTap => _tapCtrl.stream;

  bool _firebaseInitialized = false;
  bool _messagingWired = false;
  bool _localNotifReady = false;
  String? _currentToken;
  InAppPushNotification? _pendingInitialTap;
  int _intentNonce = 0;

  /// Ruang obrolan yang sedang dibuka user saat ini (`'group'` / `'community'`)
  /// untuk mencegah notifikasi muncul di ruang yang sama.
  String? activeRoomType;
  String? activeRoomId;

  bool get isFirebaseReady => _firebaseInitialized;

  void setActiveRoom({required String type, required String id}) {
    activeRoomType = type;
    activeRoomId = id;
    unawaited(clearRoomNotifications(type: type, id: id));
  }

  void clearActiveRoom({required String type, required String id}) {
    if (activeRoomType == type && activeRoomId == id) {
      activeRoomType = null;
      activeRoomId = null;
    }
  }

  /// Menghapus notifikasi perangkat OS untuk ruang `(type, id)` sekaligus
  /// mereset penghitung pesan belum dibaca ke 0 saat ruang obrolan dibuka.
  Future<void> clearRoomNotifications({
    required String type,
    required String id,
  }) async {
    final cleanType = type.trim();
    final cleanId = id.trim();
    if (cleanType.isEmpty || cleanId.isEmpty) return;
    await DeviceNotificationGroupStore.instance.clearRoom(
      roomType: cleanType,
      roomId: cleanId,
    );
    final nid = DeviceNotificationGroupStore.notificationIdForRoom(
      cleanType,
      cleanId,
    );
    if (cancelNotificationForTesting != null) {
      await cancelNotificationForTesting!(nid);
      return;
    }
    try {
      await _localNotifications.cancel(id: nid);
    } catch (_) {}
  }

  /// Properti kompatibilitas format `<type>:<id>` (mis. `group:uuid`).
  String? get activeRoomKey {
    final t = activeRoomType;
    final id = activeRoomId;
    if (t == null || id == null || t.isEmpty || id.isEmpty) return null;
    return '$t:$id';
  }

  set activeRoomKey(String? value) {
    if (value == null || value.trim().isEmpty) {
      activeRoomType = null;
      activeRoomId = null;
      return;
    }
    final idx = value.indexOf(':');
    if (idx <= 0 || idx >= value.length - 1) {
      activeRoomType = null;
      activeRoomId = value.trim();
      return;
    }
    activeRoomType = value.substring(0, idx).trim();
    activeRoomId = value.substring(idx + 1).trim();
  }

  InAppPushNotification? takePendingInitialTap() {
    final pending = _pendingInitialTap;
    _pendingInitialTap = null;
    return pending;
  }

  void queueSocialIntent(
    SocialNavigationTargetKind kind,
    String targetId, {
    String? messageId,
  }) {
    if (targetId.trim().isEmpty) return;
    pendingSocialIntent.value = SocialNavigationIntent(
      kind: kind,
      targetId: targetId.trim(),
      nonce: ++_intentNonce,
      messageId: messageId?.trim().isNotEmpty == true ? messageId!.trim() : null,
    );
  }

  SocialNavigationIntent? consumeSocialIntent() {
    final current = pendingSocialIntent.value;
    if (current != null) {
      pendingSocialIntent.value = null;
    }
    return current;
  }

  /// Menginisialisasi Firebase dan mendaftarkan background message handler
  /// top-level secara lokal (tanpa panggilan jaringan server).
  Future<void> initializeFirebase() async {
    if (_firebaseInitialized) return;
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _firebaseInitialized = true;
      FirebaseMessaging.onBackgroundMessage(
        hiqeoFirebaseMessagingBackgroundHandler,
      );
    } catch (e) {
      // Aman bila konfigurasi Firebase belum terpasang pada lingkungan uji/dev.
      if (kDebugMode) {
        debugPrint('FCM Firebase.initializeApp skipped: $e');
      }
    }
  }

  /// Menyiapkan channel notifikasi lokal secara offline-safe saat startup.
  Future<void> initializeLocalNotifications() => _initLocalNotifications();

  /// Menginisialisasi channel notifikasi lokal, listener FCM foreground/tap,
  /// serta memeriksa pesan awal saat aplikasi dibuka dari kondisi mati.
  Future<void> initialize() async {
    await initializeFirebase();
    if (!_firebaseInitialized || _messagingWired) return;
    _messagingWired = true;

    await _initLocalNotifications();

    try {
      final messaging = FirebaseMessaging.instance;
      // Nonaktifkan alert/badge/sound bawaan iOS di foreground agar Flutter
      // selalu memeriksa status mute ruang & ruang aktif terlebih dahulu.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );

      FirebaseMessaging.onMessage.listen(
        (msg) => unawaited(_handleForegroundRemoteMessage(msg)),
      );
      FirebaseMessaging.onMessageOpenedApp.listen(_handleTapRemoteMessage);
      messaging.onTokenRefresh.listen((token) {
        _currentToken = token;
        unawaited(_persistToken(token));
      });

      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        final notif = _toNotification(initial);
        _pendingInitialTap = notif;
        if (!_tapCtrl.isClosed) _tapCtrl.add(notif);
      }

      if (SupabaseServices.clientOrNull?.auth.currentUser != null) {
        await registerForCurrentUser();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FCM listener setup failed: $e');
      }
    }
  }

  Future<void> _initLocalNotifications() async {
    if (_localNotifReady) return;
    try {
      const androidInit = AndroidInitializationSettings(_smallIconDrawable);
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _localNotifications.initialize(
        settings: const InitializationSettings(
          android: androidInit,
          iOS: darwinInit,
        ),
        onDidReceiveNotificationResponse: (response) {
          final notif =
              InAppPushNotification.fromPayloadJson(response.payload);
          if (notif != null && !_tapCtrl.isClosed) {
            _tapCtrl.add(notif);
          }
        },
      );

      final androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        for (final spec in _channelSpecs) {
          await androidPlugin.createNotificationChannel(
            AndroidNotificationChannel(
              spec.id,
              spec.name,
              description: spec.description,
              importance: spec.importance,
              playSound: true,
              enableVibration: true,
            ),
          );
        }
      }

      final launchDetails =
          await _localNotifications.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        final notif = InAppPushNotification.fromPayloadJson(
          launchDetails?.notificationResponse?.payload,
        );
        if (notif != null) {
          _pendingInitialTap ??= notif;
        }
      }
      _localNotifReady = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Local notifications init skipped: $e');
      }
    }
  }

  /// Dipanggil setelah pengguna berhasil login: meminta izin notifikasi,
  /// mengambil token FCM, dan menyimpannya ke `profiles.fcm_token` +
  /// `user_fcm_tokens`.
  Future<void> registerForCurrentUser() async {
    await initialize();
    if (!_firebaseInitialized) return;
    final client = SupabaseServices.clientOrNull;
    if (client == null || client.auth.currentUser == null) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final token = _currentToken ?? await messaging.getToken();
      if (token == null || token.isEmpty) return;
      _currentToken = token;
      await _persistToken(token);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FCM registerForCurrentUser skipped: $e');
      }
    }
  }

  /// Alias kompatibilitas dengan pemanggil lama.
  Future<void> syncTokenForCurrentUser() => registerForCurrentUser();

  /// Menghapus / mengosongkan `profiles.fcm_token` menjadi `null` dan menghapus
  /// token perangkat di `user_fcm_tokens` saat pengguna logout / hapus akun.
  Future<void> clearTokenForCurrentUser() async {
    unawaited(DeviceNotificationGroupStore.instance.clearAll());
    final token = _currentToken;
    _currentToken = null;
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    try {
      await client
          .from('profiles')
          .update(<String, dynamic>{'fcm_token': null})
          .eq('id', user.id);
    } catch (_) {}
    if (token != null && token.isNotEmpty) {
      try {
        await client
            .from('user_fcm_tokens')
            .delete()
            .eq('user_id', user.id)
            .eq('token', token);
      } catch (_) {}
    }
  }

  /// Alias kompatibilitas dengan pemanggil lama.
  Future<void> removeCurrentToken() => clearTokenForCurrentUser();

  Future<void> _persistToken(String token) async {
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    final platform = Platform.isIOS ? 'ios' : 'android';
    try {
      await client
          .from('profiles')
          .update(<String, dynamic>{'fcm_token': token})
          .eq('id', user.id);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('profiles.fcm_token update skipped: $e');
      }
    }
    try {
      await client.from('user_fcm_tokens').upsert(
        <String, dynamic>{
          'user_id': user.id,
          'token': token,
          'platform': platform,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,token',
      );
    } catch (_) {}
  }

  Future<void> _handleForegroundRemoteMessage(RemoteMessage message) async {
    final notif = _toNotification(message);
    if (notif.type == 'community_message_deleted') {
      await handleRemoteMessageDeleted(notif);
      unawaited(UserNotificationsService.instance.loadNotifications());
      return;
    }
    if (notif.type == 'hike_started') {
      GroupHikePlanStore.instance.emitHikeStartedFromPush(notif.rawData);
      unawaited(UserNotificationsService.instance.loadNotifications());
    }
    if (notif.type == 'group_chat' ||
        notif.type == 'group_ready' ||
        notif.type == 'group_hike_cancelled' ||
        notif.type == 'community_chat' ||
        notif.type == 'community_mention') {
      // Tetap perbarui daftar obrolan secara senyap tanpa pop-up/suara bila bisu.
      unawaited(SocialUnreadStore.instance.refresh());
    }
    if (notif.type == 'community_mention' ||
        notif.type == 'friend_request' ||
        notif.type == 'group_invitation' ||
        notif.type == 'group_ready' ||
        notif.type == 'group_hike_cancelled' ||
        notif.type == 'emergency_contact_request' ||
        notif.isUrgent) {
      unawaited(UserNotificationsService.instance.loadNotifications());
    }
    await ChatMuteService.instance.ensureLoaded();
    if (shouldShowForegroundBanner(notif)) {
      if (!_foregroundCtrl.isClosed) _foregroundCtrl.add(notif);
      await showLocalNotification(notif);
    }
  }

  /// Dipanggil di background isolate FCM saat notifikasi data-only tiba.
  Future<void> handleBackgroundRemoteMessage(RemoteMessage message) async {
    await ChatMuteService.instance.ensureLoaded(forceReload: true);
    final notif = _toNotification(message);
    if (await isSuppressedByMuteAsync(notif, forceReloadPrefs: true)) {
      return;
    }
    await _initLocalNotifications();
    if (notif.type == 'community_message_deleted') {
      await handleRemoteMessageDeleted(notif);
      return;
    }
    await showLocalNotification(notif);
  }

  /// Menyelaraskan notifikasi perangkat aktif secara senyap saat pesan
  /// komunitas dihapus oleh pengirimnya (tidak memunculkan notifikasi baru bila
  /// tidak ada antrean aktif atau ruang sedang dibisukan).
  Future<bool> handleRemoteMessageDeleted(InAppPushNotification notif) async {
    if (await isSuppressedByMuteAsync(notif)) return false;
    final roomType = notif.roomType ?? 'community';
    final roomId = notif.roomId?.trim() ?? '';
    final messageId = notif.messageId?.trim() ?? '';
    if (roomId.isEmpty || messageId.isEmpty) return false;

    final rawReplacement = notif.rawData['replacement_text']?.trim();
    final updated = await DeviceNotificationGroupStore.instance.markMessageDeleted(
      roomType: roomType,
      roomId: roomId,
      messageId: messageId,
      replacementText: (rawReplacement != null && rawReplacement.isNotEmpty)
          ? rawReplacement
          : 'Pesan telah dihapus',
    );
    if (updated == null) return false;

    if (!_localNotifReady && showNotificationForTesting == null) {
      await _initLocalNotifications();
    }
    if (!_localNotifReady && showNotificationForTesting == null) return false;

    await _renderRoomChatNotification(
      state: updated,
      notif: notif,
      channelId: kHiqeoCommunityMessagesChannelId,
      silentUpdate: true,
    );
    return true;
  }

  void _handleTapRemoteMessage(RemoteMessage message) {
    final notif = _toNotification(message);
    if (!_tapCtrl.isClosed) _tapCtrl.add(notif);
  }

  String _formatRoomMessageText(InAppPushNotification notif) {
    final raw = (notif.messageText ?? notif.body).trim();
    if (notif.type == 'group_chat' &&
        (raw.isEmpty || raw.toLowerCase().contains('terenkripsi'))) {
      final rawHandle =
          (notif.rawData['sender_username'] ?? notif.senderName ?? '')
              .trim()
              .replaceFirst(RegExp(r'^@+'), '');
      final handle = rawHandle.isNotEmpty ? rawHandle : 'anggota';
      return 'Ada pesan baru dari $handle';
    }
    return raw.isNotEmpty ? raw : notif.body;
  }

  Future<void> _renderRoomChatNotification({
    required RoomNotificationQueueState state,
    required InAppPushNotification notif,
    required String channelId,
    required bool silentUpdate,
  }) async {
    final channelSpec = _specForChannel(channelId);
    final darwinDetails = DarwinNotificationDetails(
      presentAlert: !silentUpdate,
      presentBadge: true,
      presentSound: !silentUpdate,
    );

    final senderIconBytesByKey = <String, Uint8List?>{};
    for (final m in state.recentMessages) {
      final pKey =
          m.senderId.trim().isNotEmpty ? m.senderId.trim() : m.senderName;
      if (senderIconBytesByKey.containsKey(pKey)) continue;
      senderIconBytesByKey[pKey] =
          await NotificationAvatarHelper.resolveCircularAvatarPng(
        cacheKey: m.senderId.trim().isNotEmpty ? m.senderId.trim() : pKey,
        avatarUrl: m.senderAvatarUrl,
        fallbackLabel: m.senderName,
      );
    }

    // `largeIcon` selalu memakai foto profil/monogram Grup atau Komunitas,
    // bukan foto profil pengirim.
    final largeBytes = await NotificationAvatarHelper.resolveCircularAvatarPng(
      cacheKey: '${state.roomType}_${state.roomId}',
      avatarUrl: state.roomAvatarUrl,
      fallbackLabel: state.roomName,
      allowMonogramFallback: true,
    );

    final latest =
        state.recentMessages.isNotEmpty ? state.recentMessages.last : null;

    final messagingStyle = MessagingStyleInformation(
      _selfPerson,
      conversationTitle: state.formattedTitle,
      groupConversation: true,
      messages: state.recentMessages.map((m) {
        final pKey =
            m.senderId.trim().isNotEmpty ? m.senderId.trim() : m.senderName;
        final iconBytes = senderIconBytesByKey[pKey];
        return Message(
          m.text,
          m.timestampUtc.toLocal(),
          Person(
            name: m.senderName,
            key: pKey,
            icon: iconBytes != null ? ByteArrayAndroidIcon(iconBytes) : null,
          ),
        );
      }).toList(growable: false),
    );

    final androidDetails = AndroidNotificationDetails(
      channelSpec.id,
      channelSpec.name,
      channelDescription: channelSpec.description,
      icon: _smallIconDrawable,
      color: kHiqeoNotificationAccentColor,
      importance: channelSpec.importance,
      priority: Priority.high,
      largeIcon: largeBytes != null ? ByteArrayAndroidBitmap(largeBytes) : null,
      styleInformation: messagingStyle,
      subText: '${state.unreadCount} pesan baru',
      number: state.unreadCount,
      groupKey: 'hiqeo_room_${state.roomType}_${state.roomId}',
      silent: silentUpdate,
      onlyAlertOnce: silentUpdate,
      playSound: !silentUpdate,
      enableVibration: !silentUpdate,
      category: AndroidNotificationCategory.message,
    );

    final nid = state.notificationId;
    final title = state.formattedTitle;
    final body = latest == null
        ? notif.body
        : ((state.roomType == 'group' &&
                latest.text.startsWith('Ada pesan baru dari '))
            ? latest.text
            : '${latest.senderName}: ${latest.text}');
    final payload = notif.toPayloadJson();
    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );
    if (showNotificationForTesting != null) {
      await showNotificationForTesting!(
        id: nid,
        title: title,
        body: body,
        details: details,
        payload: payload,
      );
      return;
    }
    try {
      await _localNotifications.show(
        id: nid,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (_) {}
  }

  /// Menampilkan notifikasi sistem OS Android/iOS dengan ikon monokrom putih
  /// (`ic_stat_hiqeo`), aksen `#242B40`, `MessagingStyleInformation`
  /// berkelompok per ruang (`"Nama · N pesan baru"`), dan avatar melingkar.
  Future<void> showLocalNotification(InAppPushNotification notif) async {
    if (await isSuppressedByMuteAsync(notif)) return;
    if (notif.type == 'community_message_deleted') {
      await handleRemoteMessageDeleted(notif);
      return;
    }
    if (!_localNotifReady && showNotificationForTesting == null) {
      await _initLocalNotifications();
    }
    if (!_localNotifReady && showNotificationForTesting == null) return;

    final channelId = resolveChannelId(notif);
    final channelSpec = _specForChannel(channelId);
    final isUrgent = notif.isUrgent;

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    if (notif.isRoomChatNotification) {
      final roomType = notif.roomType!;
      final roomId = notif.roomId!;
      final incomingMsg = PendingRoomNotificationMessage(
        messageId: notif.messageId ?? notif.id,
        senderId: notif.senderId ?? '',
        senderName: notif.senderName ??
            (roomType == 'community' ? 'Pendaki' : 'Anggota'),
        text: _formatRoomMessageText(notif),
        senderAvatarUrl: notif.senderAvatarUrl,
        timestampUtc: notif.sentAtUtc ?? DateTime.now().toUtc(),
      );
      final state = await DeviceNotificationGroupStore.instance.appendMessage(
        roomType: roomType,
        roomId: roomId,
        roomName: notif.roomName ?? notif.title,
        roomAvatarUrl: notif.roomAvatarUrl,
        message: incomingMsg,
      );
      await _renderRoomChatNotification(
        state: state,
        notif: notif,
        channelId: channelId,
        silentUpdate: false,
      );
      return;
    }

    Uint8List? avatarBytes;
    if ((notif.senderAvatarUrl != null && notif.senderAvatarUrl!.isNotEmpty) ||
        (notif.senderId != null && notif.senderId!.isNotEmpty)) {
      avatarBytes = await NotificationAvatarHelper.resolveCircularAvatarPng(
        cacheKey: notif.senderId ?? notif.id,
        avatarUrl: notif.senderAvatarUrl,
        fallbackLabel: notif.senderName ?? notif.title,
        allowMonogramFallback: false,
      );
    }

    final androidDetails = AndroidNotificationDetails(
      channelSpec.id,
      channelSpec.name,
      channelDescription: channelSpec.description,
      icon: _smallIconDrawable,
      color: isUrgent
          ? kHiqeoSosNotificationColor
          : kHiqeoNotificationAccentColor,
      importance: isUrgent ? Importance.max : channelSpec.importance,
      priority: isUrgent ? Priority.max : Priority.high,
      largeIcon:
          avatarBytes != null ? ByteArrayAndroidBitmap(avatarBytes) : null,
      styleInformation: BigTextStyleInformation(
        notif.body,
        contentTitle: notif.title,
      ),
      playSound: true,
      enableVibration: true,
      category: isUrgent
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.social,
    );
    final nid = notif.id.hashCode & 0x7fffffff;
    final payload = notif.toPayloadJson();
    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );
    if (showNotificationForTesting != null) {
      await showNotificationForTesting!(
        id: nid,
        title: notif.title,
        body: notif.body,
        details: details,
        payload: payload,
      );
      return;
    }
    try {
      await _localNotifications.show(
        id: nid,
        title: notif.title,
        body: notif.body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (_) {}
  }

  /// Memeriksa status mute untuk notifikasi obrolan grup atau komunitas secara sinkron.
  /// Pengecualian keselamatan: sinyal darurat SOS (`isUrgent`) & `hike_started` selalu lolos.
  bool isSuppressedByMute(InAppPushNotification notif) {
    if (notif.isUrgent || notif.type == 'hike_started') return false;
    final incomingType = notif.roomType;
    final incomingId = notif.roomId;
    if (incomingType == null || incomingId == null || incomingId.isEmpty) {
      return false;
    }
    if (notif.type == 'group_chat' ||
        notif.type == 'community_chat' ||
        notif.type == 'community_mention' ||
        notif.type == 'group_ready' ||
        notif.type == 'group_hike_cancelled' ||
        notif.type == 'community_message_deleted') {
      return ChatMuteService.instance.isMuted(incomingType, incomingId);
    }
    return false;
  }

  /// Memastikan status mute terhidrasi dari SharedPreferences (penting di
  /// background isolate) lalu memeriksa apakah notifikasi wajib dibatalkan 100%.
  Future<bool> isSuppressedByMuteAsync(
    InAppPushNotification notif, {
    bool forceReloadPrefs = false,
  }) async {
    if (notif.isUrgent || notif.type == 'hike_started') return false;
    await ChatMuteService.instance.ensureLoaded(forceReload: forceReloadPrefs);
    return isSuppressedByMute(notif);
  }

  /// Anti-spam in-app & per-ruang mute (`chat_notification_mutes`):
  /// - Sinyal SOS (`isUrgent`) selalu ditampilkan menembus mute dan ruang aktif.
  /// - Ruang obrolan yang sedang dibuka user tidak memunculkan pop-up.
  /// - Semua pesan obrolan grup & komunitas (termasuk mention) di ruang yang
  ///   dibisukan diblokir 100% dari banner/suara/getar/notifikasi OS.
  bool shouldShowForegroundBanner(InAppPushNotification notif) {
    if (notif.type == 'community_message_deleted') return false;
    if (notif.isUrgent || notif.type == 'hike_started') return true;
    final incomingType = notif.roomType;
    final incomingId = notif.roomId;
    if (incomingType != null &&
        incomingId != null &&
        activeRoomType == incomingType &&
        activeRoomId == incomingId) {
      return false;
    }
    if (isSuppressedByMute(notif)) {
      return false;
    }
    return true;
  }

  /// Menampilkan notifikasi perangkat lokal OS (format & pengelompokan identik
  /// notifikasi online) saat peer terdekat mengirim pesan via Hiqeo Mesh
  /// offline sementara pengguna tidak sedang membuka ruang obrolan tersebut.
  Future<void> showOfflineMeshMessageNotification({
    required GroupMessageRecord record,
    required String groupName,
    String? groupAvatarUrl,
    String? currentUserId,
    bool isSos = false,
  }) async {
    if (currentUserId != null &&
        currentUserId.isNotEmpty &&
        record.senderId == currentUserId) {
      return;
    }
    await ChatMuteService.instance.ensureLoaded();
    final cleanRoomName =
        groupName.trim().isNotEmpty ? groupName.trim() : 'Grup Pendakian';
    final cleanSender =
        record.senderName.trim().isNotEmpty ? record.senderName.trim() : 'Anggota';
    final rawContent = record.messageType == GroupMessageType.audio
        ? 'Pesan suara'
        : (record.content?.trim().isNotEmpty == true
            ? record.content!.trim()
            : 'Pesan baru');
    final type = isSos ? 'sos' : 'group_chat';
    final notif = InAppPushNotification(
      id: 'mesh_${record.clientMsgId}',
      type: type,
      title: isSos ? 'DARURAT SOS HIQEO' : cleanRoomName,
      body: '$cleanSender: $rawContent',
      route: '/grup',
      targetId: record.groupId,
      groupId: record.groupId,
      messageId: record.clientMsgId,
      roomName: cleanRoomName,
      roomAvatarUrl: MediaUrlNormalizer.normalize(groupAvatarUrl),
      senderId: record.senderId,
      senderName: cleanSender,
      messageText: rawContent,
      sentAtUtc: record.clientCreatedAtUtc,
      rawData: <String, String>{
        'type': type,
        'group_id': record.groupId,
        'message_id': record.clientMsgId,
        'room_name': cleanRoomName,
        'sender_id': record.senderId,
        'sender_name': cleanSender,
        'message_text': rawContent,
        'route': '/grup',
      },
    );
    if (!shouldShowForegroundBanner(notif)) return;
    await showLocalNotification(notif);
  }

  InAppPushNotification _toNotification(RemoteMessage message) {
    return InAppPushNotification.fromRemoteData(
      id: message.messageId,
      title: message.notification?.title,
      body: message.notification?.body,
      data: message.data,
    );
  }

  @visibleForTesting
  void emitForegroundForTesting(InAppPushNotification notif) {
    if (!shouldShowForegroundBanner(notif)) return;
    unawaited(showLocalNotification(notif));
    if (!_foregroundCtrl.isClosed) {
      _foregroundCtrl.add(notif);
    }
  }

  @visibleForTesting
  void emitTapForTesting(InAppPushNotification notif) {
    if (!_tapCtrl.isClosed) _tapCtrl.add(notif);
  }
}
