import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/clock.dart';
import '../../../design/glass/glass_surface.dart';
import '../../../design/glass/hiqeo_liquid_glass.dart';
import '../../../design/gooey/gooey_selector.dart';
import '../../../design/layout.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/hiqeo_state_view.dart';
import '../../../design/widgets/line_icons.dart';
import '../../../design/widgets/nav_bar_visibility.dart';
import '../../../design/widgets/persistent_avatar_image.dart';
import '../../../infrastructure/cache/public_profile_cache_service.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_connection.dart';
import '../../../infrastructure/database/repositories/drift_chat_repository.dart';
import '../../../infrastructure/database/repositories/drift_group_repository.dart';
import '../../../infrastructure/location/shared_location_service.dart';
import '../../../infrastructure/notifications/fcm_notification_service.dart';
import '../../../infrastructure/notifications/push_notification_overlay.dart';
import '../../../infrastructure/offgrid/android_off_grid_adapter.dart';
import '../../../infrastructure/offgrid/global_off_grid_outbox_service.dart';
import '../../../infrastructure/offgrid/mesh_packet_codec.dart';
import '../../../infrastructure/offgrid/mesh_router_service.dart';
import '../../../infrastructure/offgrid/off_grid_chat_local_store.dart';
import '../../../infrastructure/offgrid/off_grid_supabase_sync_service.dart';
import '../../../infrastructure/offgrid/off_grid_transport_adapter.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../../auth/application/account_controller.dart';
import '../../groups/application/group_key_manager.dart';
import '../../groups/application/group_selection.dart';
import '../../groups/domain/group.dart';
import '../../groups/domain/group_remote_service.dart';
import '../../groups/domain/group_repository.dart';
import '../../map/application/offline_pack_service.dart';
import '../../map/domain/mountain_pack.dart';
import '../../map/domain/mountain_pack_data.dart';
import '../../preparation/application/packing_list_store.dart';
import '../../safety/domain/payloads.dart';
import '../../social/data/chat_mute_service.dart';
import '../../social/data/community_service.dart';
import '../../social/data/friends_service.dart';
import '../../social/data/moderation_service.dart';
import '../../social/data/social_unread_store.dart';
import '../../social/presentation/community_chat_page.dart';
import '../../social/presentation/social_community_tab.dart';
import '../../social/presentation/social_leaderboard_tab.dart';
import '../../tracking/application/tracking_controller.dart';
import '../../tracking/domain/track_point.dart';
import '../application/group_location_consent_store.dart';
import '../domain/chat_message.dart';
import '../domain/chat_repository.dart';
import '../domain/group_chat_models.dart';
import '../domain/group_chat_remote_service.dart';
import 'chat_mute_sheet.dart';
import 'chat_room_chrome.dart';
import 'group_members_sheet.dart';
import 'last_location_view.dart';

/// Label lencana kesiapan pendakian pada kartu grup.
/// Mengembalikan `null` jika tidak ada undangan pendakian aktif.
String? formatGroupReadinessBadge({
  required bool hasActiveInvite,
  required int readyCount,
  required int memberCount,
}) {
  if (!hasActiveInvite) return null;
  final total = math.max(1, memberCount);
  final ready = readyCount.clamp(0, total);
  if (ready <= 0) return 'Belum ada yang siap';
  if (ready >= total) return 'Semua siap';
  return 'Siap naik $ready/$total';
}

enum _GroupViewMode { list, room, lastLocation }

enum _SocialTab { grup, komunitas, leaderboard }

/// Menentukan apakah lokasi anggota perlu di-UPSERT (1 baris per pengguna di
/// `member_locations`): hanya saat sesi aktif tiap 10–15 detik atau berpindah
/// >= 10 meter (atau pembaruan awal layar Lokasi Terakhir).
bool shouldUploadMemberLocation({
  DateTime? lastUploadedAt,
  LatLng? lastPosition,
  required DateTime nowUtc,
  required LatLng currentPosition,
  required bool isActiveSession,
  bool force = false,
}) {
  if (force) return true;
  if (!isActiveSession) return false;
  if (lastUploadedAt == null || lastPosition == null) return true;
  if (distanceMeters(lastPosition, currentPosition) >= 10.0) return true;
  return nowUtc.difference(lastUploadedAt) >= const Duration(seconds: 12);
}

/// Layar Grup & Ruang Obrolan (Online & Offline-First).
///
/// Menampilkan:
/// 1. Daftar grup & undangan masuk (+ tombol "+ Buat grup" dan daftar kosong).
/// 2. Ruang obrolan rombongan (navbar disembunyikan, tombol Mikrofon <-> Kirim
///    dinamis, voice note player, dan menu dropdown ⋮).
/// 3. Layar Lokasi terakhir anggota dengan panel mengambang `glassFillMap`.
class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    this.accountController,
    this.chatRepository,
    this.groupRepository,
    this.chatRemoteService,
    this.localStore,
    this.meshRouter,
    this.syncService,
    this.clock = const SystemClock(),
    this.initialOnline,
    this.initialInvitations,
    this.initialLocalGroups,
    this.onSendFriendRequest,
    this.onSubmitMessageReport,
    this.locationService,
    this.downloadedPacksLoader,
    this.onOpenOfflineMaps,
  });

  /// Disuntikkan untuk uji; produksi memakai layanan yang tersedia.
  final AccountController? accountController;
  final ChatRepository? chatRepository;
  final GroupRepository? groupRepository;
  final GroupChatRemoteService? chatRemoteService;
  final OffGridChatLocalStore? localStore;
  final MeshRouterService? meshRouter;
  final OffGridSupabaseSyncService? syncService;
  final Clock clock;

  /// Disuntikkan untuk uji mode Online / Offline secara deterministik.
  final bool? initialOnline;

  /// Opsional untuk skenario uji daftar undangan / grup lokal awal.
  final List<IncomingInvitation>? initialInvitations;
  final List<GroupCardData>? initialLocalGroups;

  /// Disuntikkan untuk uji aksi Tambah Teman & Laporkan Pesan dari bubble grup.
  final Future<void> Function(String targetUserId)? onSendFriendRequest;
  final Future<void> Function({
    required String groupId,
    required String messageId,
    required String reportedUserId,
    required String reason,
    String? details,
    String? excerpt,
  })? onSubmitMessageReport;

  /// Opsional untuk uji GPS nyata & peta offline pada Lokasi Terakhir.
  final SharedLocationService? locationService;
  final Future<List<MountainPack>> Function()? downloadedPacksLoader;
  final VoidCallback? onOpenOfflineMaps;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final AccountController _account;
  late final bool _ownsAccount;

  AppDatabase? _database;
  ChatRepository? _chat;
  GroupRepository? _groupRepo;
  GroupChatRemoteService? _chatRemote;
  OffGridChatLocalStore? _localStore;
  OffGridTransportAdapter? _transportAdapter;
  MeshRouterService? _meshRouter;
  OffGridSupabaseSyncService? _syncService;
  bool _ownsDb = false;
  bool _ownsLocalStore = false;
  bool _ownsMeshRouter = false;
  bool _ownsSyncService = false;

  _GroupViewMode _viewMode = _GroupViewMode.list;
  _SocialTab _socialTab = _SocialTab.grup;
  bool _menuOpen = false;
  bool _isOnline = true;
  int _meshConnectedPeers = 0;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  LocationLease? _lastLocationLease;

  // Data daftar grup & undangan (gabungan server + cache lokal + antrean offline)
  final List<GroupCardData> _localCreatedGroups = <GroupCardData>[];
  final List<IncomingInvitation> _localAcceptedInvitations =
      <IncomingInvitation>[];
  final Set<String> _dismissedInvitationIds = <String>{};
  final Map<String, int> _unreadOverrides = <String, int>{};
  final Map<String, List<MemberDirectoryEntry>> _localExtraMembers =
      <String, List<MemberDirectoryEntry>>{};
  final Map<String, List<MemberLastLocation>> _groupMemberLocations =
      <String, List<MemberLastLocation>>{};

  // Penyimpanan tunggal & cache pesan/lokasi grup
  final Map<String, List<ChatMessage>> _memoryMessages =
      <String, List<ChatMessage>>{};
  final Map<String, List<ChatMessage>> _localMessagesByGroup =
      <String, List<ChatMessage>>{};
  final Map<String, List<GroupMessageRecord>> _storeMessagesByGroup =
      <String, List<GroupMessageRecord>>{};
  final Map<String, String> _remoteSenderNames = <String, String>{};
  final Set<String> _pendingSyncMessageIds = <String>{};
  final Set<String> _deletedMessageIds = <String>{};
  final Set<String> _cancelledMessageIds = <String>{};
  final Map<String, ChatSyncStatus> _messageSyncStatusById =
      <String, ChatSyncStatus>{};
  final Map<String, String> _clientMsgIdByMessageId = <String, String>{};
  final Set<String> _bridgedRepoMessageIds = <String>{};

  // Grup aktif yang sedang dibuka di Ruang Obrolan
  GroupCardData? _activeGroup;
  List<MemberDirectoryEntry> _members = const <MemberDirectoryEntry>[];
  List<ChatMessage> _messages = const <ChatMessage>[];
  bool _messagesLoading = false;
  String? _messagesError;
  StreamSubscription<List<ChatMessage>>? _messageSubscription;
  StreamSubscription<List<GroupMessageRecord>>? _localStoreMsgSub;
  StreamSubscription<List<MemberLastLocation>>? _localStoreLocSub;
  StreamSubscription<int>? _meshPeersSub;
  StreamSubscription<GroupMessageRecord>? _meshIncomingMsgSub;
  StreamSubscription<String>? _groupKeyReadySub;
  Timer? _keyDecryptRetryTimer;
  Timer? _roomSyncTimeoutTimer;
  int _keyDecryptRetryCount = 0;
  String? _keyVerifiedForRoomId;
  int _messageGeneration = 0;

  // Input teks, rekam pesan suara (.m4a), dan pemutar audio lokal/online
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  AudioRecorder? _audioRecorder;
  AudioPlayer? _audioPlayer;
  bool _sending = false;
  Timer? _recordingTimer;

  // Pemutar voice note aktif & paginasi riwayat + pembaruan lokasi berkala
  String? _playingMessageId;
  double _playingProgress = 0.0;
  Timer? _playbackTimer;
  Timer? _locationShareTimer;
  Timer? _lastLocationPollTimer;
  DateTime? _lastLocationUploadAt;
  LatLng? _lastLocationUploadPos;
  bool _loadingOlderMessages = false;
  bool _hasMoreOlderMessages = false;
  RoomReadCursor? _roomInitialReadCursor;
  int? _roomFirstUnreadIndex;
  int _roomUnreadDividerCount = 0;
  bool _roomInitialScrollDone = false;
  final GlobalKey _roomUnreadDividerKey = GlobalKey();
  double _lastRoomKeyboardInset = 0.0;
  double _lastRoomViewportHeight = 0.0;
  final GroupLocationConsentStore _locationConsent =
      GroupLocationConsentStore.instance;
  late final SharedLocationService _locationService =
      widget.locationService ?? SharedLocationService.instance;
  TrackPoint? _directGpsFix;
  bool _fetchingDirectGps = false;
  bool _pendingLocationShare = false;
  List<MountainPack> _downloadedMountainPacks = const <MountainPack>[];
  bool _loadingDownloadedPacks = false;

  String get _effectiveUserId => _account.user?.id ?? 'pendaki-lokal';

  String get _effectiveUserDisplayName {
    final full = _account.profile?.fullName?.trim();
    if (full != null && full.isNotEmpty) return full;
    final display = _account.user?.displayName?.trim();
    if (display != null && display.isNotEmpty) return display;
    final uname = _account.profile?.username?.trim();
    if (uname != null && uname.isNotEmpty) return uname;
    return 'Kamu';
  }

  @override
  void initState() {
    super.initState();
    final shared = widget.accountController == null
        ? SupabaseServices.sharedAccountController
        : null;
    _ownsAccount = widget.accountController == null && shared == null;
    _account = widget.accountController ??
        shared ??
        SupabaseServices.createAccountController();
    _account.initialize();
    _account.addListener(_onAccountChanged);
    _groupKeyReadySub = _account.onGroupKeyReady.listen(_handleGroupKeyReady);
    _locationConsent.addListener(_onLocationConsentChanged);
    _locationService.addListener(_onLiveLocationChanged);
    SocialUnreadStore.instance.addListener(_onSocialUnreadChanged);
    SocialGroupsStore.instance.addListener(_onSocialUnreadChanged);
    GroupHikePlanStore.instance.addListener(_onSocialUnreadChanged);
    GroupHikePlanStore.instance.ensureRealtimeSubscribed(
      groupNamesById: <String, String>{
        for (final g in _account.groups) g.group.id: g.group.name,
      },
    );
    if (_isOnline && _account.groups.isNotEmpty) {
      unawaited(
        GroupHikePlanStore.instance.refreshForGroups(
          <String>[for (final g in _account.groups) g.group.id],
          groupNamesById: <String, String>{
            for (final g in _account.groups) g.group.id: g.group.name,
          },
        ),
      );
    }
    FcmNotificationService.instance.pendingSocialIntent
        .addListener(_handlePendingSocialIntent);
    _input.addListener(_onInputChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handlePendingSocialIntent();
    });

    if (widget.initialOnline != null) {
      _isOnline = widget.initialOnline!;
    } else {
      unawaited(_initConnectivity());
    }
    if (_isOnline) {
      unawaited(SocialUnreadStore.instance.refresh());
    }

    if (widget.initialLocalGroups != null) {
      _localCreatedGroups.addAll(widget.initialLocalGroups!);
    }

    _chat = widget.chatRepository;
    _groupRepo = widget.groupRepository;
    _chatRemote = widget.chatRemoteService ??
        SupabaseServices.createGroupChatRemoteService();

    _initOffGridStack();
    unawaited(SocialGroupsStore.instance.load());

    if (_chat == null || _groupRepo == null) {
      unawaited(_openLocalDatabase());
    } else {
      unawaited(_loadPersistedGroups());
    }
  }

  Future<void> _persistDeletedGroupTombstone(
    String groupId, {
    bool cancelRemotePlan = true,
  }) async {
    await SocialGroupsStore.instance.markGroupDeleted(groupId);
    if (cancelRemotePlan &&
        GroupHikePlanStore.instance.activePlan?.groupId == groupId) {
      unawaited(GroupHikePlanStore.instance.cancelActivePlanRemote());
    }
  }

  RemoteGroup? _findGroupMeta(String groupId) {
    final active = _activeGroup;
    if (active != null && active.group.id == groupId) {
      return active.remote;
    }
    for (final g in _account.groups) {
      if (g.group.id == groupId) return g;
    }
    for (final local in _localCreatedGroups) {
      if (local.group.id == groupId) return local.remote;
    }
    return null;
  }

  void _initOffGridStack({AppDatabase? database}) {
    if (widget.localStore != null) {
      _localStore = widget.localStore;
    } else if (_localStore == null || database != null) {
      if (_ownsLocalStore) unawaited(_localStore?.dispose());
      final sharedStore = GlobalOffGridOutboxService.instance.sharedLocalStore;
      if (sharedStore != null && widget.chatRepository == null) {
        _localStore = sharedStore;
        _ownsLocalStore = false;
      } else {
        _localStore = OffGridChatLocalStore(database: database);
        _ownsLocalStore = true;
      }
    }

    if (widget.meshRouter != null) {
      _meshRouter = widget.meshRouter;
    } else if (_meshRouter == null || database != null) {
      final wasStarted = _meshRouter?.isStarted ?? false;
      final prevGroupId = _meshRouter?.activeGroupId;
      if (_ownsMeshRouter) {
        // Jangan hancurkan EventChannel sink; cukup lepaskan router lama.
        unawaited(_meshRouter?.stop());
      }
      // Gunakan ulang satu adapter transport agar EventChannel Android tidak
      // pernah membatalkan `packetSink` secara asinkron saat DB dibuka.
      _transportAdapter ??= (!kIsWeb && Platform.isAndroid)
          ? AndroidOffGridAdapter()
          : InMemoryOffGridTransportAdapter();
      _meshRouter = MeshRouterService(
        adapter: _transportAdapter!,
        codec: MeshPacketCodec(),
        localStore: _localStore!,
      );
      _ownsMeshRouter = true;
      if (wasStarted && prevGroupId != null && !_isOnline) {
        unawaited(
          _meshRouter!.start(
            groupId: prevGroupId,
            keyVersion: _activeGroup?.group.keyVersion ?? 1,
            highDuty: true,
            useForegroundService: true,
          ),
        );
      }
    }

    unawaited(_meshPeersSub?.cancel());
    _meshConnectedPeers = _meshRouter!.connectedPeersCount;
    _meshPeersSub = _meshRouter!.onConnectedPeersChanged.listen((count) {
      if (!mounted || _meshConnectedPeers == count) return;
      setState(() => _meshConnectedPeers = count);
    });

    unawaited(_meshIncomingMsgSub?.cancel());
    _meshIncomingMsgSub = _meshRouter!.onIncomingMessage.listen((record) {
      final meta = _findGroupMeta(record.groupId);
      unawaited(
        PushNotificationService.instance.showOfflineMeshMessageNotification(
          record: record,
          groupName: meta?.group.name ?? 'Grup Pendakian',
          groupAvatarUrl: meta?.group.avatarUrl,
          currentUserId: _effectiveUserId,
        ),
      );
    });

    if (widget.syncService != null) {
      _syncService = widget.syncService;
    } else if (_syncService == null || database != null) {
      if (_ownsSyncService) unawaited(_syncService?.dispose());
      _syncService = OffGridSupabaseSyncService(
        localStore: _localStore!,
        remoteService: _chatRemote,
        meshRouter: _meshRouter,
      );
      _ownsSyncService = true;
    }
  }

  @override
  void didUpdateWidget(covariant ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialOnline != null && widget.initialOnline != _isOnline) {
      final online = widget.initialOnline!;
      setState(() => _isOnline = online);
      _syncMeshLifecycleForConnectivity(online);
      if (online) {
        unawaited(_syncPendingOfflineQueue());
      }
    }
  }

  @override
  void dispose() {
    NavBarVisibilityController.instance.setRoomChatOpen(false);
    unawaited(_connectivitySub?.cancel());
    _recordingTimer?.cancel();
    _playbackTimer?.cancel();
    _locationShareTimer?.cancel();
    _lastLocationPollTimer?.cancel();
    _keyDecryptRetryTimer?.cancel();
    _roomSyncTimeoutTimer?.cancel();
    _locationService.removeListener(_onLiveLocationChanged);
    _lastLocationLease?.release();
    _lastLocationLease = null;
    _account.removeListener(_onAccountChanged);
    unawaited(_groupKeyReadySub?.cancel());
    _locationConsent.removeListener(_onLocationConsentChanged);
    SocialUnreadStore.instance.removeListener(_onSocialUnreadChanged);
    SocialGroupsStore.instance.removeListener(_onSocialUnreadChanged);
    GroupHikePlanStore.instance.removeListener(_onSocialUnreadChanged);
    FcmNotificationService.instance.pendingSocialIntent
        .removeListener(_handlePendingSocialIntent);
    final activeGid = _activeGroup?.group.id;
    if (activeGid != null) {
      FcmNotificationService.instance.clearActiveRoom(
        type: 'group',
        id: activeGid,
      );
      _markActiveGroupReadNow(activeGid);
    }
    if (_ownsAccount) _account.dispose();
    unawaited(_messageSubscription?.cancel());
    unawaited(_localStoreMsgSub?.cancel());
    unawaited(_localStoreLocSub?.cancel());
    unawaited(_meshPeersSub?.cancel());
    unawaited(_meshIncomingMsgSub?.cancel());
    unawaited(_syncService?.unsubscribeGroup());
    unawaited(GroupHikePlanStore.instance.unsubscribeGroupPrep());
    if (_ownsSyncService) unawaited(_syncService?.dispose());
    if (_ownsMeshRouter) unawaited(_meshRouter?.dispose());
    if (_ownsLocalStore) unawaited(_localStore?.dispose());
    try {
      unawaited(_audioPlayer?.dispose());
      unawaited(_audioRecorder?.dispose());
    } catch (_) {}
    _input
      ..removeListener(_onInputChanged)
      ..dispose();
    _scroll.dispose();
    if (_ownsDb) unawaited(_database?.close());
    super.dispose();
  }

  Future<void> _initConnectivity() async {
    try {
      final conn = Connectivity();
      final current = await conn.checkConnectivity();
      if (mounted) {
        _handleConnectivityChange(current);
      }
      _connectivitySub =
          conn.onConnectivityChanged.listen(_handleConnectivityChange);
    } catch (_) {
      // Abaikan jika plugin connectivity tidak aktif (mis. di unit/widget test).
    }
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online == _isOnline) return;
    if (!mounted) return;
    setState(() => _isOnline = online);
    _syncMeshLifecycleForConnectivity(online);
    if (online) {
      // Reset state galat / offline lama agar undang anggota & kirim pesan
      // langsung bekerja normal begitu kembali online.
      _account.clearError();
      unawaited(_account.refresh());
      unawaited(_syncPendingOfflineQueue());
    }
  }

  /// Mengatur siklus hidup BLE Mesh + Foreground Service secara hemat & cerdas:
  /// - Saat ONLINE: hentikan BLE Mesh & Foreground Service (notifikasi `Hiqeo
  ///   Mesh Aktif` tidak boleh jalan paksa saat online/idle).
  /// - Saat OFFLINE di dalam Ruang Obrolan: jalankan BLE Mesh + Wi-Fi Direct.
  void _syncMeshLifecycleForConnectivity(bool online) {
    final router = _meshRouter;
    if (router == null) return;
    if (online) {
      if (router.isStarted) {
        unawaited(router.stop());
      }
      if (_meshConnectedPeers != 0 && mounted) {
        setState(() => _meshConnectedPeers = 0);
      }
      return;
    }
    final activeGroup = _activeGroup?.group;
    if (activeGroup != null && _viewMode != _GroupViewMode.list) {
      router.invalidateGroupKeyCache(activeGroup.id);
      unawaited(
        router.start(
          groupId: activeGroup.id,
          keyVersion: activeGroup.keyVersion,
          highDuty: true,
          useForegroundService: true,
        ),
      );
    }
  }

  Future<void> _openLocalDatabase() async {
    try {
      final file = await defaultAppDatabaseFile();
      final database = openAppDatabase(file);
      if (!mounted) {
        await database.close();
        return;
      }
      _database = database;
      _chat ??= DriftChatRepository(database);
      _groupRepo ??= DriftGroupRepository(database);
      _ownsDb = true;
      _initOffGridStack(database: database);
      unawaited(_localStore?.cleanupDuplicateMessages());
      await _loadPersistedGroups();
    } catch (_) {
      // Pada widget test tanpa path_provider, tetap lanjut dengan state in-memory.
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadPersistedGroups() async {
    final repo = _groupRepo;
    if (repo == null) return;
    try {
      await SocialGroupsStore.instance.load();
      final deletedIds = SocialGroupsStore.instance.deletedGroupIds;
      final serverIds = _account.groups.map((r) => r.group.id).toSet();
      final groups = await repo.watchGroups().first;
      if (!mounted) return;
      for (final g in groups) {
        final isStaleServerRow = _account.hasSyncedGroupsFromServer &&
            !g.id.startsWith('grup-lokal-') &&
            !serverIds.contains(g.id);
        if (deletedIds.contains(g.id) || isStaleServerRow) {
          unawaited(repo.deleteGroup(g.id).catchError((_) {}));
          continue;
        }
        final existing = _localCreatedGroups.any((c) => c.group.id == g.id) ||
            _account.groups.any((r) => r.group.id == g.id);
        if (!existing) {
          final members = await repo.membersOf(g.id);
          _localCreatedGroups.add(
            GroupCardData(
              remote: RemoteGroup(group: g, role: GroupRole.owner),
              memberCount: math.max(1, members.length),
            ),
          );
        }
      }
      if (mounted) setState(() {});
    } catch (_) {
      // Abaikan kegagalan baca DB opsional.
    }
  }

  Future<void> _syncPendingOfflineQueue() async {
    if (!mounted || !_isOnline) return;
    var changed = false;

    // 1. Sinkronkan grup yang dibuat saat offline bila akun terhubung
    if (_account.groupsEnabled && _account.user != null) {
      for (var i = 0; i < _localCreatedGroups.length; i++) {
        final item = _localCreatedGroups[i];
        if (!item.pendingSync) continue;
        final created = await _account.createGroup(
          item.group.name,
          mountain: item.group.mountain,
        );
        if (created) {
          _localCreatedGroups[i] = item.copyWith(pendingSync: false);
          changed = true;
        }
      }
    }

    // 2. Sinkronkan seluruh pesan teks, voice note `.m4a`, dan lokasi berstatus
    //    `pending` ke Supabase secara idempoten (untuk semua grup).
    final sync = _syncService;
    if (sync != null) {
      try {
        final synced = await sync.syncPending();
        if (synced > 0) changed = true;
      } catch (_) {
        // Biarkan berstatus 'pending' di DB lokal agar dicoba ulang otomatis.
      }
    }

    // 3. Aktifkan stream Supabase Realtime & segarkan daftar anggota jika online
    final activeId = _activeGroup?.group.id;
    if (activeId != null) {
      if (_account.groupsEnabled && isValidUuid(activeId)) {
        try {
          await _account
              .ensureGroupKeyDistributed(activeId)
              .timeout(const Duration(seconds: 4), onTimeout: () => false);
        } catch (_) {}
        try {
          final refreshed = await _account.membersOf(activeId);
          if (refreshed.isNotEmpty &&
              mounted &&
              _activeGroup?.group.id == activeId) {
            setState(() => _members = refreshed);
            changed = true;
          }
        } catch (_) {}
      }
      if (sync != null && isValidUuid(activeId)) {
        await sync.subscribeGroup(
          activeId,
          currentUserId: _effectiveUserId,
          minCreatedAtUtc: _activeGroupJoinedAtUtc,
          onInitialPaginationResolved: (hasMore) {
            if (!mounted || _activeGroup?.group.id != activeId) return;
            if (_hasMoreOlderMessages != hasMore) {
              setState(() => _hasMoreOlderMessages = hasMore);
            }
          },
        );
      }
    }

    if (changed && mounted) {
      setState(() {});
      _showNotice('Data offline berhasil disinkronkan.');
    }
  }

  void _onSocialUnreadChanged() {
    if (mounted) setState(() {});
  }

  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  void _onAccountChanged() {
    if (!mounted) return;
    if (_account.groups.isNotEmpty) {
      GroupHikePlanStore.instance.ensureRealtimeSubscribed(
        groupNamesById: <String, String>{
          for (final g in _account.groups) g.group.id: g.group.name,
        },
      );
    }
    if (_account.hasSyncedGroupsFromServer) {
      final serverIds = _account.groups.map((r) => r.group.id).toSet();
      _localCreatedGroups.removeWhere((item) {
        final id = item.group.id;
        if (id.startsWith('grup-lokal-')) {
          return !item.pendingSync &&
              _account.groups.any((s) => s.group.name == item.group.name);
        }
        return !item.pendingSync && !serverIds.contains(id);
      });
    }
    final activeId = _activeGroup?.group.id;
    if (activeId != null) {
      final cachedMembers = _account.cachedMembersOf(activeId);
      if (cachedMembers.isNotEmpty) {
        _members = cachedMembers;
      }
      if (_account.keyStatusFor(activeId)?.availability ==
          GroupKeyAvailability.ready) {
        _meshRouter?.invalidateGroupKeyCache(activeId);
      }
    }
    setState(() {});
  }

  List<IncomingInvitation> get _visibleInvitations {
    final merged = <IncomingInvitation>[];
    final seen = <String>{};
    for (final inv
        in widget.initialInvitations ?? const <IncomingInvitation>[]) {
      if (_dismissedInvitationIds.contains(inv.id)) continue;
      if (seen.add(inv.id)) merged.add(inv);
    }
    for (final inv in _account.invitations) {
      if (_dismissedInvitationIds.contains(inv.id)) continue;
      if (seen.add(inv.id)) merged.add(inv);
    }
    return merged;
  }

  List<GroupCardData> get _visibleGroups {
    final list = <GroupCardData>[];
    final seenIds = <String>{};
    final deletedIds = SocialGroupsStore.instance.deletedGroupIds;

    // 1. Grup dari server / cache SQLite AccountController
    for (final remote in _account.groups) {
      final id = remote.group.id;
      if (deletedIds.contains(id) || !seenIds.add(id)) continue;
      final extraMembers = _localExtraMembers[id]?.length ?? 0;
      final baseMembers =
          math.max(1, _account.memberCountFor(id) + extraMembers);
      final msgs = _memoryMessages[id];
      final hasLocationMsg =
          (msgs?.any((m) => m.type == PacketType.location) ?? false) ||
              (_groupMemberLocations[id]?.any((m) => m.hasSignal) ?? false);
      final preview = SocialUnreadStore.instance.groupPreview(id);
      final activePlan = GroupHikePlanStore.instance.activePlanForGroup(id);
      final hasActiveInvite = activePlan != null && !activePlan.isCancelled;
      final readyCount = hasActiveInvite ? activePlan.readyUserIds.length : 0;
      list.add(
        GroupCardData(
          remote: remote,
          memberCount: baseMembers,
          unreadCount: _unreadOverrides[id] ?? 0,
          readyCount: readyCount,
          hasActiveHikeInvite: hasActiveInvite,
          locationShared: hasLocationMsg,
          lastMessageSnippet: preview?.snippet,
          lastMessageAtUtc: preview?.createdAtUtc,
          hasUnread: preview?.hasUnread ?? false,
        ),
      );
    }

    // 2. Grup yang dibuat di sesi lokal / cache / undangan yang diterima offline
    for (final inv in _localAcceptedInvitations) {
      if (deletedIds.contains(inv.groupId) || !seenIds.add(inv.groupId)) {
        continue;
      }
      final g = Group(
        id: inv.groupId,
        name: inv.groupName,
        ownerId: inv.inviterUsername,
        mountain: 'Gunung Merbabu',
        createdAtUtc: inv.createdAtUtc,
      );
      final extraMembers = _localExtraMembers[g.id]?.length ?? 0;
      final preview = SocialUnreadStore.instance.groupPreview(g.id);
      final activePlan = GroupHikePlanStore.instance.activePlanForGroup(g.id);
      final hasActiveInvite = activePlan != null && !activePlan.isCancelled;
      final readyCount = hasActiveInvite ? activePlan.readyUserIds.length : 0;
      list.add(
        GroupCardData(
          remote: RemoteGroup(group: g, role: GroupRole.member),
          memberCount: 2 + extraMembers,
          unreadCount: _unreadOverrides[g.id] ?? 0,
          readyCount: readyCount,
          hasActiveHikeInvite: hasActiveInvite,
          pendingSync: !_isOnline,
          lastMessageSnippet: preview?.snippet,
          lastMessageAtUtc: preview?.createdAtUtc,
          hasUnread: preview?.hasUnread ?? false,
        ),
      );
    }

    for (final local in _localCreatedGroups) {
      final id = local.group.id;
      if (deletedIds.contains(id) || !seenIds.add(id)) continue;
      final extraMembers = _localExtraMembers[id]?.length ?? 0;
      final locShared = local.locationShared || _locationConsent.isEnabled(id);
      final preview = SocialUnreadStore.instance.groupPreview(id);
      final activePlan = GroupHikePlanStore.instance.activePlanForGroup(id);
      final hasActiveInvite = activePlan != null
          ? !activePlan.isCancelled
          : local.hasActiveHikeInvite;
      final readyCount = activePlan != null
          ? (hasActiveInvite ? activePlan.readyUserIds.length : 0)
          : (local.hasActiveHikeInvite ? local.readyCount : 0);
      list.add(
        local.copyWith(
          memberCount: local.memberCount + extraMembers,
          unreadCount: _unreadOverrides[id] ?? local.unreadCount,
          hasActiveHikeInvite: hasActiveInvite,
          readyCount: readyCount,
          locationShared: locShared,
          lastMessageSnippet: preview?.snippet ?? local.lastMessageSnippet,
          lastMessageAtUtc: preview?.createdAtUtc ?? local.lastMessageAtUtc,
          hasUnread: preview?.hasUnread ?? local.hasUnread,
        ),
      );
    }

    return list;
  }

  void _onLocationConsentChanged() {
    if (mounted) setState(() {});
    _syncPeriodicLocationSharing();
  }

  TrackPoint? get _currentUserFix {
    final shared = _locationService.freshPoint;
    final direct = _directGpsFix;
    if (shared == null) return direct;
    if (direct == null) return shared;
    return shared.timestampUtc.isAfter(direct.timestampUtc) ? shared : direct;
  }

  bool get _isLockingGps {
    if (_currentUserFix != null) return false;
    if (_fetchingDirectGps) return true;
    final st = _locationService.state.status;
    return st == LiveLocationStatus.searching || st == LiveLocationStatus.idle;
  }

  void _onLiveLocationChanged() {
    if (!mounted) return;
    final fix = _currentUserFix;
    if (fix != null) {
      final groupId = _activeGroup?.group.id;
      if (_pendingLocationShare ||
          (groupId != null &&
              _locationConsent.isEnabled(groupId) &&
              _viewMode == _GroupViewMode.lastLocation)) {
        _pendingLocationShare = false;
        unawaited(_shareCurrentLocationToGroup(silent: true, force: true));
      }
    }
    if (_viewMode == _GroupViewMode.lastLocation) {
      setState(() {});
    }
  }

  Future<void> _fetchImmediateGpsFix({
    bool requestPermissionIfDenied = false,
  }) async {
    if (widget.locationService != null) {
      if (requestPermissionIfDenied) {
        await _locationService.requestPermission();
      }
      return;
    }
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    if (_fetchingDirectGps) return;
    if (mounted) {
      setState(() => _fetchingDirectGps = true);
    }
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied &&
          requestPermissionIfDenied) {
        permission = await Geolocator.requestPermission();
        unawaited(_locationService.refresh());
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }
      if (position == null || !mounted) return;
      final point = TrackPoint(
        lat: position.latitude,
        lon: position.longitude,
        timestampUtc: position.timestamp.toUtc(),
        accuracyM: position.accuracy,
        altitudeM: position.hasAltitude ? position.altitude : null,
        speedMps:
            position.hasSpeed && position.speed >= 0 ? position.speed : null,
        heading: position.heading.isFinite &&
                position.heading >= 0 &&
                position.heading <= 360
            ? position.heading
            : null,
        isMocked: position.isMocked,
        receivedAtUtc: widget.clock.nowUtc(),
      );
      _directGpsFix = point;
      _onLiveLocationChanged();
    } catch (_) {
      // Abaikan kegagalan platform GPS di lingkungan desktop/uji.
    } finally {
      if (mounted) {
        setState(() => _fetchingDirectGps = false);
      }
    }
  }

  Future<void> _retryGpsFromLastLocation() async {
    final st = _locationService.state.status;
    if (st == LiveLocationStatus.serviceDisabled) {
      await _locationService.openLocationSettings();
    } else if (st == LiveLocationStatus.permissionDeniedForever) {
      await _locationService.openAppSettings();
    } else if (st == LiveLocationStatus.permissionDenied) {
      await _locationService.requestPermission();
    } else {
      await _locationService.refresh();
    }
    unawaited(_fetchImmediateGpsFix(requestPermissionIfDenied: true));
  }

  Future<void> _loadDownloadedMountainPacks() async {
    if (mounted) {
      setState(() => _loadingDownloadedPacks = true);
    }
    try {
      final List<MountainPack> resolved;
      if (widget.downloadedPacksLoader != null) {
        resolved = await widget.downloadedPacksLoader!();
      } else {
        final prefs = await SharedPreferences.getInstance();
        final downloadedIds =
            (prefs.getStringList(OfflinePackService.keyDownloadedIds) ??
                    const <String>[])
                .toSet();
        final base = MountainPackData.createDefaultPacks();
        for (final pack in base) {
          final status = await OfflinePackService.instance.getStatus(
            pack.id,
            remoteVersion: pack.version,
          );
          if (status == MountainDownloadStatus.downloaded ||
              status == MountainDownloadStatus.updateAvailable) {
            downloadedIds.add(pack.id);
          } else if (prefs.getString(
                  '${OfflinePackService.keyStatusPrefix}${pack.id}') ==
              MountainDownloadStatus.notDownloaded.name) {
            downloadedIds.remove(pack.id);
          }
        }
        final hydrated = await MountainPackData.loadHydratedPacks(
          downloadedIds: downloadedIds,
        );
        resolved = hydrated
            .where((p) => p.isDownloaded || p.isUpdateAvailable)
            .toList(growable: false);
      }
      if (!mounted) return;
      setState(() => _downloadedMountainPacks = resolved);
    } catch (_) {
      // Tetap gunakan cache memori terakhir jika terjadi kegagalan baca disk.
    } finally {
      if (mounted) {
        setState(() => _loadingDownloadedPacks = false);
      }
    }
  }

  void _syncPeriodicLocationSharing() {
    _locationShareTimer?.cancel();
    _locationShareTimer = null;
    final groupId = _activeGroup?.group.id;
    final viewingLastLoc = _viewMode == _GroupViewMode.lastLocation;
    if (groupId == null) {
      _lastLocationLease?.release();
      _lastLocationLease = null;
      return;
    }
    final activeSession = TrackingController.instance.isRecording;
    final sharingEnabled = _locationConsent.isEnabled(groupId);
    if (viewingLastLoc || activeSession) {
      _lastLocationLease ??= _locationService.acquire();
    } else {
      _lastLocationLease?.release();
      _lastLocationLease = null;
    }
    if (!viewingLastLoc && !(sharingEnabled && activeSession)) {
      return;
    }
    // Pembaruan lokasi 1 baris UPSERT ke `member_locations` tiap 12 detik atau
    // perpindahan >= 10 m (TIDAK pernah menulis ke group_messages).
    _locationShareTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!mounted) return;
      unawaited(
        _shareCurrentLocationToGroup(
          silent: true,
          force: viewingLastLoc,
        ),
      );
    });
  }

  void _handlePendingSocialIntent() {
    final intent = FcmNotificationService.instance.consumeSocialIntent();
    if (intent == null || !mounted) return;
    switch (intent.kind) {
      case SocialNavigationTargetKind.groupRoom:
      case SocialNavigationTargetKind.groupLastLocation:
        if (_viewMode != _GroupViewMode.list &&
            _activeGroup?.group.id != intent.targetId) {
          _closeRoomChat();
        }
        GroupCardData? matched;
        for (final card in _visibleGroups) {
          if (card.group.id == intent.targetId) {
            matched = card;
            break;
          }
        }
        matched ??= GroupCardData(
          remote: RemoteGroup(
            group: Group(
              id: intent.targetId,
              name: 'Grup Pendakian',
              ownerId: _effectiveUserId,
              createdAtUtc: DateTime.now().toUtc(),
            ),
            role: GroupRole.member,
          ),
          memberCount: 1,
        );
        setState(() => _socialTab = _SocialTab.grup);
        _openRoomChat(matched);
        if (intent.kind == SocialNavigationTargetKind.groupLastLocation) {
          _openLastLocation();
        }
      case SocialNavigationTargetKind.communityRoom:
        if (_viewMode != _GroupViewMode.list) {
          _closeRoomChat();
        }
        setState(() => _socialTab = _SocialTab.komunitas);
        unawaited(
          _openCommunityRoomById(
            intent.targetId,
            targetMessageId: intent.messageId,
          ),
        );
    }
  }

  Future<void> _openCommunityRoomById(
    String communityId, {
    String? targetMessageId,
  }) async {
    CommunitySummary? found;
    for (final c in CommunityService.instance.communities) {
      if (c.id == communityId) {
        found = c;
        break;
      }
    }
    if (found == null) {
      await CommunityService.instance.loadCommunities();
      for (final c in CommunityService.instance.communities) {
        if (c.id == communityId) {
          found = c;
          break;
        }
      }
    }
    if (found == null || !mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityChatPage(
          community: found!,
          initialTargetMessageId: targetMessageId,
        ),
      ),
    );
  }

  DateTime? get _activeGroupJoinedAtUtc {
    final active = _activeGroup;
    if (active == null) return null;
    if (active.remote.joinedAtUtc != null) {
      return active.remote.joinedAtUtc!.toUtc();
    }
    for (final m in _members) {
      if (m.userId == _effectiveUserId) {
        return m.joinedAtUtc.toUtc();
      }
    }
    return null;
  }

  void _markActiveGroupReadNow(String gid) {
    final latestMsg = _messages.isNotEmpty ? _messages.last : null;
    final storeRecords = _storeMessagesByGroup[gid];
    final latestStoreRecord =
        (storeRecords != null && storeRecords.isNotEmpty)
            ? storeRecords.last
            : null;
    final preview = SocialUnreadStore.instance.groupPreview(gid);
    var stamp = widget.clock.nowUtc();
    for (final candidate in <DateTime?>[
      latestMsg?.sentAtUtc,
      latestStoreRecord?.createdAtUtc,
      preview?.createdAtUtc,
    ]) {
      if (candidate != null && candidate.isAfter(stamp)) {
        stamp = candidate;
      }
    }
    final lastId = latestStoreRecord?.clientMsgId ??
        (latestMsg != null
            ? (_clientMsgIdByMessageId[latestMsg.messageId] ??
                latestMsg.messageId)
            : preview?.lastMessageId);
    unawaited(
      SocialUnreadStore.instance.markGroupRead(
        gid,
        at: stamp,
        lastMessageId: lastId,
      ),
    );
  }

  void _openRoomChat(GroupCardData card) {
    _unreadOverrides[card.group.id] = 0;
    _lastLocationUploadAt = null;
    _lastLocationUploadPos = null;
    _lastLocationPollTimer?.cancel();
    _lastLocationPollTimer = null;
    FcmNotificationService.instance.setActiveRoom(
      type: 'group',
      id: card.group.id,
    );
    unawaited(ChatMuteService.instance.loadAll());
    unawaited(_locationConsent.load(card.group.id));
    unawaited(
      GroupHikePlanStore.instance.refreshForGroup(
        card.group.id,
        groupName: card.group.name,
      ),
    );
    GroupHikePlanStore.instance.subscribeGroupPrep(card.group.id);
    if (_isOnline) {
      unawaited(FriendsService.instance.refresh());
    }
    setState(() {
      _activeGroup = card;
      _viewMode = _GroupViewMode.room;
      _menuOpen = false;
      _members = const <MemberDirectoryEntry>[];
      _messages = const <ChatMessage>[];
      _deletedMessageIds.clear();
      _cancelledMessageIds.clear();
      _clientMsgIdByMessageId.clear();
      _roomInitialReadCursor = null;
      _roomFirstUnreadIndex = null;
      _roomUnreadDividerCount = 0;
      _roomInitialScrollDone = false;
      _lastRoomKeyboardInset = 0.0;
      _lastRoomViewportHeight = 0.0;
      _hasMoreOlderMessages = false;
    });
    NavBarVisibilityController.instance.setRoomChatOpen(true);
    unawaited(_captureRoomReadCursorAndLoad(card.group.id));
    _syncPeriodicLocationSharing();
  }

  Future<void> _captureRoomReadCursorAndLoad(String groupId) async {
    final cursor = await SocialUnreadStore.instance.getGroupReadCursor(groupId);
    if (!mounted || _activeGroup?.group.id != groupId) return;
    _roomInitialReadCursor = cursor;
    _markActiveGroupReadNow(groupId);
    await _loadRoomData(groupId);
  }

  void _closeRoomChat() {
    final closingGroupId = _activeGroup?.group.id;
    if (closingGroupId != null) {
      FcmNotificationService.instance.clearActiveRoom(
        type: 'group',
        id: closingGroupId,
      );
      _markActiveGroupReadNow(closingGroupId);
    }
    unawaited(GroupHikePlanStore.instance.unsubscribeGroupPrep());
    _lastLocationUploadAt = null;
    _lastLocationUploadPos = null;
    _playbackTimer?.cancel();
    _recordingTimer?.cancel();
    _locationShareTimer?.cancel();
    _locationShareTimer = null;
    _lastLocationPollTimer?.cancel();
    _lastLocationPollTimer = null;
    _keyDecryptRetryTimer?.cancel();
    _keyDecryptRetryTimer = null;
    _roomSyncTimeoutTimer?.cancel();
    _roomSyncTimeoutTimer = null;
    _keyDecryptRetryCount = 0;
    _keyVerifiedForRoomId = null;
    try {
      unawaited(_audioPlayer?.stop());
    } catch (_) {}
    unawaited(_messageSubscription?.cancel());
    _messageSubscription = null;
    unawaited(_localStoreMsgSub?.cancel());
    _localStoreMsgSub = null;
    unawaited(_localStoreLocSub?.cancel());
    _localStoreLocSub = null;
    unawaited(_syncService?.unsubscribeGroup());
    // Hentikan BLE Mesh & Foreground Service saat keluar dari Ruang Obrolan
    // agar notifikasi `Hiqeo Mesh Aktif` tidak terus menggantung saat idle.
    unawaited(_meshRouter?.stop());
    setState(() {
      _meshConnectedPeers = 0;
      _playingMessageId = null;
      _menuOpen = false;
      _activeGroup = null;
      _viewMode = _GroupViewMode.list;
    });
    NavBarVisibilityController.instance.setRoomChatOpen(false);
  }

  void _openLastLocation() {
    _lastLocationPollTimer?.cancel();
    _lastLocationPollTimer = null;
    setState(() {
      _menuOpen = false;
      _viewMode = _GroupViewMode.lastLocation;
    });
    NavBarVisibilityController.instance.setRoomChatOpen(true);
    final lastLocGroupId = _activeGroup?.group.id;
    _ensureGroupLocationsSeeded(lastLocGroupId);
    if (lastLocGroupId != null) {
      unawaited(_syncLastLocationRoom(lastLocGroupId));
      if (_isOnline && _chatRemote != null && isValidUuid(lastLocGroupId)) {
        _lastLocationPollTimer = Timer.periodic(
          const Duration(seconds: 15),
          (_) {
            if (!mounted ||
                _viewMode != _GroupViewMode.lastLocation ||
                !_isOnline) {
              return;
            }
            unawaited(
              _syncService?.refreshLocationsOnce(
                lastLocGroupId,
                currentUserId: _effectiveUserId,
              ),
            );
          },
        );
      }
    }
    _syncPeriodicLocationSharing();
    unawaited(_loadDownloadedMountainPacks());
    if (_currentUserFix == null) {
      unawaited(_fetchImmediateGpsFix(requestPermissionIfDenied: true));
    }
    if (_activeGroup != null) {
      _pendingLocationShare = true;
      unawaited(_shareCurrentLocationToGroup(silent: true, force: true));
    }
  }

  Future<void> _syncLastLocationRoom(String groupId) async {
    if (_isOnline && _account.groupsEnabled && isValidUuid(groupId)) {
      try {
        if (_account.keyStatusFor(groupId)?.availability !=
            GroupKeyAvailability.ready) {
          await _account
              .ensureGroupKey(groupId)
              .timeout(const Duration(seconds: 3), onTimeout: () {});
        }
        await _account
            .ensureGroupKeyDistributed(groupId)
            .timeout(const Duration(seconds: 3), onTimeout: () => false);
      } catch (_) {}
    }
    await _syncService?.refreshLocationsOnce(
      groupId,
      currentUserId: _effectiveUserId,
    );
    await _syncService?.subscribeLocations(
      groupId,
      currentUserId: _effectiveUserId,
    );
  }

  void _handleGroupKeyReady(String readyGroupId) {
    final activeId = _activeGroup?.group.id;
    if (!mounted || activeId == null || activeId != readyGroupId) return;
    _meshRouter?.invalidateGroupKeyCache(readyGroupId);
    unawaited(() async {
      await _syncService?.redecryptGroup(
        readyGroupId,
        currentUserId: _effectiveUserId,
      );
      if (mounted && _activeGroup?.group.id == readyGroupId) {
        await _syncLastLocationRoom(readyGroupId);
      }
    }());
  }

  void _scheduleKeyDecryptRetry(String groupId) {
    if (!_isOnline ||
        !isValidUuid(groupId) ||
        _keyDecryptRetryTimer?.isActive == true ||
        _keyDecryptRetryCount >= 6) {
      return;
    }
    _keyDecryptRetryTimer = Timer(const Duration(seconds: 5), () {
      _keyDecryptRetryTimer = null;
      if (!mounted || _activeGroup?.group.id != groupId || !_isOnline) return;
      final stillHasEncrypted = _messages.any(
        (m) =>
            m.type == PacketType.text &&
            utf8.decode(m.payload, allowMalformed: true) ==
                'Pesan terenkripsi (menunggu kunci grup)',
      );
      if (!stillHasEncrypted) {
        _keyDecryptRetryCount = 0;
        return;
      }
      _keyDecryptRetryCount++;
      unawaited(() async {
        await _account
            .ensureGroupKeyDistributed(groupId)
            .timeout(const Duration(seconds: 4), onTimeout: () => false);
        final ready = await _syncService?.redecryptGroup(
              groupId,
              currentUserId: _effectiveUserId,
            ) ??
            false;
        if (!ready && mounted && _activeGroup?.group.id == groupId) {
          _scheduleKeyDecryptRetry(groupId);
        }
      }());
    });
  }

  void _backToRoomFromLastLocation() {
    _lastLocationPollTimer?.cancel();
    _lastLocationPollTimer = null;
    unawaited(_syncService?.unsubscribeLocations());
    setState(() {
      _viewMode = _GroupViewMode.room;
    });
    NavBarVisibilityController.instance.setRoomChatOpen(true);
    _syncPeriodicLocationSharing();
  }

  Future<void> _loadRoomData(String groupId) async {
    // 0. Hidrasi anggota instan dari cache lokal AccountController (tanpa delay jaringan)
    final initialMembers = <MemberDirectoryEntry>[];
    final cachedAccountMembers = _account.cachedMembersOf(groupId);
    if (cachedAccountMembers.isNotEmpty) {
      initialMembers.addAll(cachedAccountMembers);
    } else {
      initialMembers.add(
        MemberDirectoryEntry(
          userId: _effectiveUserId,
          username: _account.profile?.username ?? _effectiveUserDisplayName,
          displayName: _effectiveUserDisplayName,
          avatarUrl: _account.profile?.avatarUrl,
          role: _activeGroup?.remote.role ?? GroupRole.owner,
          publicKeyBase64: '',
          joinedAtUtc: _activeGroup?.remote.joinedAtUtc ??
              _activeGroup?.group.createdAtUtc ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ),
      );
    }
    final extras = _localExtraMembers[groupId];
    if (extras != null) {
      for (final e in extras) {
        if (!initialMembers.any((m) => m.userId == e.userId)) {
          initialMembers.add(e);
        }
      }
    }

    // 1. Berlangganan Single Source of Truth lokal (`OffGridChatLocalStore`) SEGERA
    //    tanpa menunggu panggilan jaringan `membersOf` atau key fetch.
    unawaited(_messageSubscription?.cancel());
    _messageSubscription = null;
    unawaited(_localStoreMsgSub?.cancel());
    _localStoreMsgSub = null;
    unawaited(_localStoreLocSub?.cancel());
    _localStoreLocSub = null;
    _roomSyncTimeoutTimer?.cancel();
    _keyDecryptRetryTimer?.cancel();
    _keyDecryptRetryTimer = null;
    _keyDecryptRetryCount = 0;

    final gen = ++_messageGeneration;
    if (mounted && _activeGroup?.group.id == groupId) {
      setState(() {
        _members = List<MemberDirectoryEntry>.unmodifiable(initialMembers);
        _messagesLoading = _messages.isEmpty;
        _messagesError = null;
      });
    }

    _roomSyncTimeoutTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && gen == _messageGeneration && _messagesLoading) {
        setState(() {
          _messages = _mergeLocalAndRemoteMessages(groupId);
          _messagesLoading = false;
        });
      }
    });

    final store = _localStore;
    if (store != null) {
      // Bersihkan otomatis baris duplikat historis yang mungkin tersimpan sebelum fix.
      unawaited(store.cleanupDuplicateMessages(groupId: groupId));

      _localStoreMsgSub = store.watchGroupMessages(groupId).listen((records) {
        if (!mounted || gen != _messageGeneration) return;
        _roomSyncTimeoutTimer?.cancel();
        var hasEncryptedPlaceholder = false;
        for (final r in records) {
          _remoteSenderNames[r.senderId] = r.senderName;
          if (!r.isDeleted &&
              r.content == 'Pesan terenkripsi (menunggu kunci grup)') {
            hasEncryptedPlaceholder = true;
          }
          final readyEvent = GroupHikeInviteMessage.tryDecodeReady(r.content);
          if (readyEvent != null) {
            unawaited(
              GroupHikePlanStore.instance.markUserReady(
                readyEvent.inviteId,
                readyEvent.userId,
              ),
            );
          }
          final cancelEvent = GroupHikeInviteMessage.tryDecodeCancel(r.content);
          if (cancelEvent != null) {
            GroupHikePlanStore.instance
                .markInviteCancelledLocally(cancelEvent.inviteId);
          }
        }
        _storeMessagesByGroup[groupId] = records;
        setState(() {
          _pendingSyncMessageIds.clear();
          _messageSyncStatusById.clear();
          _deletedMessageIds.clear();
          _cancelledMessageIds.clear();
          _clientMsgIdByMessageId.clear();
          for (final r in records) {
            final msgId =
                r.toChatMessage(currentUserId: _effectiveUserId).messageId;
            _clientMsgIdByMessageId[msgId] = r.clientMsgId;
            _messageSyncStatusById[msgId] = r.syncStatus;
            if (r.syncStatus == ChatSyncStatus.pending) {
              _pendingSyncMessageIds.add(msgId);
            }
            if (r.isDeleted) {
              _deletedMessageIds.add(msgId);
            }
            if (r.isCancelled) {
              _cancelledMessageIds.add(msgId);
            }
          }
          _messages = _mergeLocalAndRemoteMessages(groupId);
          _messagesLoading = false;
          _prepareInitialUnreadMarkerIfNeeded();
        });
        _handlePostMessagesScrollAndMarkRead(groupId);
        if (hasEncryptedPlaceholder) {
          _scheduleKeyDecryptRetry(groupId);
        } else {
          _keyDecryptRetryTimer?.cancel();
          _keyDecryptRetryTimer = null;
          _keyDecryptRetryCount = 0;
        }
      });

      _localStoreLocSub = store
          .watchMemberLocations(groupId, currentUserId: _effectiveUserId)
          .listen((locations) {
        if (!mounted || gen != _messageGeneration) return;
        if (locations.isNotEmpty) {
          setState(() {
            _groupMemberLocations[groupId] = locations;
          });
        }
      });
    }

    // 2. Pantau ChatRepository hanya untuk pesan non teks/suara (kartu lokasi)
    //    atau saat widget test menyuntikkan `widget.chatRepository` secara eksplisit.
    //    Jalur ganda teks/suara di produksi dihentikan total agar pesan tidak
    //    pernah muncul 2x di HP pengirim.
    final repo = _chat;
    final hasInjectedRepo = widget.chatRepository != null;
    if (repo != null) {
      _messageSubscription = repo.watchMessages(groupId).listen(
        (msgs) async {
          if (!mounted || gen != _messageGeneration) return;
          _roomSyncTimeoutTimer?.cancel();
          _localMessagesByGroup[groupId] = msgs;
          if (store != null && hasInjectedRepo) {
            final existingStore = _storeMessagesByGroup[groupId] ??
                await store.messagesForGroup(groupId);
            final toInsert = <GroupMessageRecord>[];
            for (final m in msgs) {
              if (_bridgedRepoMessageIds.contains(m.messageId)) continue;
              if (m.type == PacketType.text ||
                  m.type == PacketType.voiceFragment) {
                final candidate = GroupMessageRecord.fromChatMessage(
                  m,
                  senderName: _senderNameFor(m),
                  keyVersion: _activeGroup?.group.keyVersion ?? 1,
                  originTransport: ChatTransportOrigin.online,
                  syncStatus: ChatSyncStatus.sent,
                );
                final alreadyMatched = existingStore.any(
                  (r) => _isSameLogicalMessage(r, candidate),
                );
                if (!alreadyMatched) {
                  toInsert.add(candidate);
                }
              }
            }
            if (toInsert.isNotEmpty) {
              await store.upsertMessagesBatch(toInsert);
            }
          }
          if (!mounted || gen != _messageGeneration) return;
          setState(() {
            _messages = _mergeLocalAndRemoteMessages(groupId);
            _messagesLoading = false;
            _prepareInitialUnreadMarkerIfNeeded();
          });
          _handlePostMessagesScrollAndMarkRead(groupId);
        },
        onError: (_) {
          if (!mounted || gen != _messageGeneration) return;
          _roomSyncTimeoutTimer?.cancel();
          setState(() {
            _messages = _mergeLocalAndRemoteMessages(groupId);
            _messagesLoading = false;
            _prepareInitialUnreadMarkerIfNeeded();
          });
          _handlePostMessagesScrollAndMarkRead(groupId);
        },
      );
    } else if (store == null) {
      _roomSyncTimeoutTimer?.cancel();
      setState(() {
        _messages = _mergeLocalAndRemoteMessages(groupId);
        _messagesLoading = false;
        _prepareInitialUnreadMarkerIfNeeded();
      });
      _handlePostMessagesScrollAndMarkRead(groupId);
    }

    // 3. Sinkronkan daftar anggota grup di latar tanpa menahan ruang chat.
    unawaited(_refreshRoomMembersAsync(groupId, gen));

    // 4. Sinkronisasi kunci enkripsi grup saat online & siklus hidup BLE Mesh:
    //    - ONLINE: JANGAN jalankan Foreground Service / BLE Mesh! Sinkronkan
    //      kunci E2EE grup (dan lengkapi anggota yang belum dapat kunci) + Realtime.
    //    - OFFLINE: aktifkan BLE Mesh + Wi-Fi Direct (Foreground Service).
    final router = _meshRouter;
    if (_isOnline) {
      if (router != null && router.isStarted) {
        unawaited(router.stop());
      }
      if (_account.groupsEnabled && isValidUuid(groupId)) {
        unawaited(() async {
          if (_account.keyStatusFor(groupId)?.availability !=
              GroupKeyAvailability.ready) {
            await _account
                .ensureGroupKey(groupId)
                .timeout(const Duration(seconds: 6), onTimeout: () {});
          }
          await _account
              .ensureGroupKeyDistributed(groupId)
              .timeout(const Duration(seconds: 6), onTimeout: () => false);
          _meshRouter?.invalidateGroupKeyCache(groupId);
        }());
      }
    } else if (router != null) {
      router.invalidateGroupKeyCache(groupId);
      unawaited(
        router.start(
          groupId: groupId,
          keyVersion: _activeGroup?.group.keyVersion ?? 1,
          highDuty: true,
          useForegroundService: true,
        ),
      );
    }

    // 5. Saat online, aktifkan Supabase Realtime & sinkronkan antrean pending
    final sync = _syncService;
    if (sync != null && _isOnline && isValidUuid(groupId)) {
      unawaited(
        sync.subscribeGroup(
          groupId,
          currentUserId: _effectiveUserId,
          minCreatedAtUtc: _activeGroupJoinedAtUtc,
          onInitialPaginationResolved: (hasMore) {
            if (!mounted ||
                gen != _messageGeneration ||
                _activeGroup?.group.id != groupId) {
              return;
            }
            if (_hasMoreOlderMessages != hasMore) {
              setState(() => _hasMoreOlderMessages = hasMore);
            }
          },
        ),
      );
      unawaited(sync.syncPending(groupId: groupId));
    }
  }

  Future<void> _refreshRoomMembersAsync(String groupId, int gen) async {
    final loaded = <MemberDirectoryEntry>[];
    try {
      final fetchedMembers = await _account
          .membersOf(groupId)
          .timeout(const Duration(seconds: 8));
      loaded.addAll(fetchedMembers);
    } catch (_) {
      loaded.addAll(_members);
    }
    final extras = _localExtraMembers[groupId];
    if (extras != null) {
      for (final e in extras) {
        if (!loaded.any((m) => m.userId == e.userId)) loaded.add(e);
      }
    }
    if (_groupRepo != null) {
      try {
        final repoMembers = await _groupRepo!
            .membersOf(groupId)
            .timeout(const Duration(seconds: 5));
        for (final gm in repoMembers) {
          if (!loaded.any((m) => m.userId == gm.userId)) {
            loaded.add(
              MemberDirectoryEntry(
                userId: gm.userId,
                username: gm.username,
                role: gm.role,
                publicKeyBase64: '',
                joinedAtUtc: gm.joinedAtUtc,
              ),
            );
          }
        }
      } catch (_) {}
    }
    if (!mounted ||
        gen != _messageGeneration ||
        _activeGroup?.group.id != groupId ||
        loaded.isEmpty) {
      return;
    }
    setState(() {
      _members = List<MemberDirectoryEntry>.unmodifiable(loaded);
      _messages = _mergeLocalAndRemoteMessages(groupId);
    });
  }

  bool _isSameLogicalMessage(GroupMessageRecord a, GroupMessageRecord b) {
    if (a.clientMsgId == b.clientMsgId) return true;
    if (a.groupId != b.groupId ||
        a.senderId != b.senderId ||
        a.messageType != b.messageType) {
      return false;
    }
    final deltaMs = a.clientCreatedAtUtc
        .difference(b.clientCreatedAtUtc)
        .inMilliseconds
        .abs();
    if (deltaMs > 2500) return false;
    if (a.messageType == GroupMessageType.text) {
      return (a.content ?? '') == (b.content ?? '');
    }
    return (a.audioDurationSec ?? -1) == (b.audioDurationSec ?? -1);
  }

  List<ChatMessage> _mergeLocalAndRemoteMessages(String groupId) {
    final storeRecords =
        _storeMessagesByGroup[groupId] ?? const <GroupMessageRecord>[];
    final legacyMsgs = _localMessagesByGroup[groupId] ??
        _memoryMessages[groupId] ??
        const <ChatMessage>[];
    final joinedAt = _activeGroupJoinedAtUtc;

    // Deduplikasi ketat menurut `client_msg_id` (single source of truth) dan
    // saring pesan sebelum `joined_at` agar anggota baru tidak melihat riwayat lama.
    final seenClientIds = <String>{};
    final uniqueRecords = <GroupMessageRecord>[];
    for (final r in storeRecords) {
      final isOwnUnsent =
          r.senderId == _effectiveUserId && r.syncStatus != ChatSyncStatus.sent;
      final createdUtc = r.createdAtUtc ?? r.clientCreatedAtUtc;
      if (!isOwnUnsent && joinedAt != null && createdUtc.isBefore(joinedAt)) {
        continue;
      }
      if (seenClientIds.add(r.clientMsgId)) {
        uniqueRecords.add(r);
      }
    }

    final merged = <ChatMessage>[
      for (final r in uniqueRecords)
        r.toChatMessage(currentUserId: _effectiveUserId),
    ];

    // Hanya sertakan pesan non teks/suara (kartu berbagi lokasi) dari repository
    // lokal; untuk teks/suara hanya dipakai jika _localStore kosong atau
    // test menyuntikkan chatRepository secara eksplisit tanpa bentrok.
    final includeLegacyTextVoice =
        uniqueRecords.isEmpty || widget.chatRepository != null;
    for (final m in legacyMsgs) {
      if (!m.isOutgoing &&
          joinedAt != null &&
          m.sentAtUtc.isBefore(joinedAt)) {
        continue;
      }
      if (m.type == PacketType.text || m.type == PacketType.voiceFragment) {
        if (!includeLegacyTextVoice) continue;
        final candidate = GroupMessageRecord.fromChatMessage(
          m,
          senderName: _senderNameFor(m),
          keyVersion: _activeGroup?.group.keyVersion ?? 1,
        );
        final alreadyInStore = uniqueRecords.any(
          (r) => _isSameLogicalMessage(r, candidate),
        );
        if (!alreadyInStore) {
          merged.add(m);
        }
      } else {
        merged.add(m);
      }
    }

    merged.sort((a, b) => a.sentAtUtc.compareTo(b.sentAtUtc));
    return List<ChatMessage>.unmodifiable(merged);
  }

  void _ensureGroupLocationsSeeded(String? groupId) {
    if (groupId == null) return;
    _groupMemberLocations.putIfAbsent(groupId, () => <MemberLastLocation>[]);
  }

  void _prepareInitialUnreadMarkerIfNeeded() {
    if (_roomInitialScrollDone || _messages.isEmpty) return;
    final marker = computeUnreadMarker<ChatMessage>(
      messages: _messages,
      cursor: _roomInitialReadCursor ?? const RoomReadCursor(),
      currentUserId: _effectiveUserId,
      idOf: (m) => _clientMsgIdByMessageId[m.messageId] ?? m.messageId,
      senderIdOf: (m) => m.authorId,
      createdAtOf: (m) => m.sentAtUtc,
    );
    if (marker.unreadCount > 0 && marker.firstUnreadIndex != null) {
      _roomFirstUnreadIndex = marker.firstUnreadIndex;
      _roomUnreadDividerCount = marker.unreadCount;
    }
  }

  void _handlePostMessagesScrollAndMarkRead(String groupId) {
    if (!mounted || _activeGroup?.group.id != groupId || _messages.isEmpty) {
      return;
    }
    if (!_roomInitialScrollDone) {
      _roomInitialScrollDone = true;
      if (_roomUnreadDividerCount > 0 && _roomFirstUnreadIndex != null) {
        _scrollToRoomUnreadDivider(_roomFirstUnreadIndex!);
      } else {
        _scrollToBottom();
      }
    } else {
      final nearBottom = !_scroll.hasClients ||
          (_scroll.position.maxScrollExtent - _scroll.position.pixels) < 180;
      if (_messages.last.isOutgoing || nearBottom) {
        _scrollToBottom();
      }
    }

    _markActiveGroupReadNow(groupId);
  }

  void _scrollToRoomUnreadDivider(int targetIndex) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final keyCtx = _roomUnreadDividerKey.currentContext;
      if (keyCtx != null) {
        unawaited(
          Scrollable.ensureVisible(
            keyCtx,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: 0.15,
          ),
        );
        return;
      }
      final maxExt = _scroll.position.maxScrollExtent;
      if (maxExt > 0 && _messages.isNotEmpty) {
        final ratio = (targetIndex / _messages.length).clamp(0.0, 1.0);
        _scroll.jumpTo(maxExt * ratio);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _roomUnreadDividerKey.currentContext;
          if (mounted && ctx != null) {
            unawaited(
              Scrollable.ensureVisible(
                ctx,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                alignment: 0.15,
              ),
            );
          }
        });
      }
    });
  }

  List<MemberLastLocation> _resolvedMembersForLastLocation(String? groupId) {
    if (groupId == null) return const <MemberLastLocation>[];
    final stored = _groupMemberLocations[groupId] ?? const <MemberLastLocation>[];
    final profileCache = PublicProfileCacheService.instance;
    final result = <MemberLastLocation>[];
    for (final m in stored) {
      final lat = m.lat;
      final lon = m.lon;
      if (lat == null ||
          lon == null ||
          !lat.isFinite ||
          !lon.isFinite ||
          (lat == 0.0 && lon == 0.0)) {
        continue;
      }
      var enriched = m;
      if (m.userId != _effectiveUserId &&
          (m.displayName.trim().isEmpty || m.displayName.trim() == 'Anggota')) {
        final member = _memberEntryFor(m.userId);
        final fallbackName = member?.displayName?.trim().isNotEmpty == true
            ? member!.displayName!.trim()
            : (member?.username.trim().isNotEmpty == true
                ? member!.username.trim()
                : m.displayName);
        final resolvedName = profileCache.resolveDisplayName(
          m.userId,
          fallback: fallbackName,
        );
        if (resolvedName.isNotEmpty && resolvedName != m.displayName) {
          enriched = m.copyWith(
            displayName: resolvedName,
            initial: resolvedName[0].toUpperCase(),
          );
        }
      }
      result.add(enriched);
    }
    final fix = _currentUserFix;
    if (fix != null) {
      final selfIdx = result.indexWhere((m) => m.userId == _effectiveUserId);
      final existingSelf = selfIdx >= 0 ? result[selfIdx] : null;
      final liveSelf = MemberLastLocation(
        groupId: groupId,
        userId: _effectiveUserId,
        displayName: 'Kamu',
        initial: _effectiveUserDisplayName.isNotEmpty
            ? _effectiveUserDisplayName[0].toUpperCase()
            : 'K',
        hasSignal: true,
        accuracyM: fix.accuracyM.round(),
        lat: fix.lat,
        lon: fix.lon,
        altitudeMdpl: fix.altitudeM?.round() ?? existingSelf?.altitudeMdpl,
        batteryPercent: existingSelf?.batteryPercent,
        sourceTransport: existingSelf?.sourceTransport ??
            (_isOnline
                ? ChatTransportOrigin.online
                : ChatTransportOrigin.bleMesh),
        syncStatus: existingSelf?.syncStatus ?? ChatSyncStatus.pending,
        recordedAtUtc: fix.timestampUtc,
        updatedAtUtc: fix.timestampUtc,
        mapX: existingSelf?.mapX ?? 0.48,
        mapY: existingSelf?.mapY ?? 0.56,
      );
      if (selfIdx >= 0) {
        result[selfIdx] = liveSelf;
      } else {
        result.insert(0, liveSelf);
      }
    }
    return List<MemberLastLocation>.unmodifiable(result);
  }

  Future<void> _shareCurrentLocationToGroup({
    bool silent = false,
    bool force = false,
  }) async {
    final group = _activeGroup?.group;
    if (group == null) return;
    _ensureGroupLocationsSeeded(group.id);
    final fix = _currentUserFix;
    if (fix == null) {
      // Belum ada fix GPS nyata — jangan pernah menyimpan koordinat palsu.
      _pendingLocationShare = true;
      _syncPeriodicLocationSharing();
      unawaited(_fetchImmediateGpsFix(requestPermissionIfDenied: !silent));
      if (!silent && mounted) {
        _showNotice('Sedang mencari sinyal GPS akurat…');
      }
      return;
    }
    final now = widget.clock.nowUtc();
    final lat = fix.lat;
    final lon = fix.lon;
    final currentPos = LatLng(lat, lon);
    if (!shouldUploadMemberLocation(
      lastUploadedAt: _lastLocationUploadAt,
      lastPosition: _lastLocationUploadPos,
      nowUtc: now,
      currentPosition: currentPos,
      isActiveSession: TrackingController.instance.isRecording,
      force: force,
    )) {
      return;
    }
    _lastLocationUploadAt = now;
    _lastLocationUploadPos = currentPos;

    final acc = fix.accuracyM.round();
    final altMdpl = fix.altitudeM?.round();
    var batteryPct = 85;
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        batteryPct = await Battery().batteryLevel;
      } catch (_) {}
    }
    final transport =
        _isOnline ? ChatTransportOrigin.online : ChatTransportOrigin.bleMesh;

    final currentList = List<MemberLastLocation>.of(
        _groupMemberLocations[group.id] ?? const []);
    final idx = currentList.indexWhere((m) => m.userId == _effectiveUserId);
    final updatedSelf = MemberLastLocation(
      groupId: group.id,
      userId: _effectiveUserId,
      displayName: _effectiveUserDisplayName,
      initial: _effectiveUserDisplayName.isNotEmpty
          ? _effectiveUserDisplayName[0].toUpperCase()
          : 'K',
      hasSignal: true,
      accuracyM: acc,
      lat: lat,
      lon: lon,
      altitudeMdpl: altMdpl,
      batteryPercent: batteryPct,
      sourceTransport: transport,
      syncStatus: ChatSyncStatus.pending,
      recordedAtUtc: now,
      updatedAtUtc: now,
      mapX: 0.48,
      mapY: 0.56,
    );
    if (idx >= 0) {
      currentList[idx] = updatedSelf;
    } else {
      currentList.add(updatedSelf);
    }
    _groupMemberLocations[group.id] = currentList;

    // Hanya UPSERT 1 baris per user ke `member_locations` (TIDAK pernah mengirim
    // pesan otomatis "Kamu membagikan lokasi" ke `group_messages`).
    await _localStore?.upsertMemberLocation(group.id, updatedSelf);

    final router = _meshRouter;
    if (!_isOnline && router != null) {
      unawaited(
        router.broadcastLocationEnvelope(
          updatedSelf,
          groupId: group.id,
          keyVersion: group.keyVersion,
        ),
      );
    }

    if (_isOnline) {
      try {
        await _syncService?.syncPending(groupId: group.id);
      } catch (_) {}
    }

    if (mounted) {
      setState(() {});
      if (!silent) {
        _showNotice(
          _isOnline
              ? 'Lokasi terakhir diperbarui.'
              : 'Lokasi disimpan lokal dan dikirim saat sinyal kembali.',
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _sendText() async {
    final text = _input.text.trim();
    final groupId = _activeGroup?.group.id;
    if (text.isEmpty || _sending || groupId == null) return;
    setState(() => _sending = true);
    try {
      await _persistMessage(
        groupId: groupId,
        type: PacketType.text,
        payload: Uint8List.fromList(utf8.encode(text)),
      );
      if (mounted) _input.clear();
    } catch (_) {
      if (mounted) _showNotice('Pesan gagal disimpan di perangkat.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // Rekam pesan suara telah dihapus dari komposer obrolan grup; pemutaran
  // pesan suara historis yang sudah tersimpan tetap dipertahankan.
  Future<String> _resolveVoiceFilePath(String clientMsgId) async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final support = await getApplicationSupportDirectory();
        final dir =
            Directory('${support.path}${Platform.pathSeparator}offgrid_voice');
        if (!dir.existsSync()) dir.createSync(recursive: true);
        return '${dir.path}${Platform.pathSeparator}$clientMsgId.m4a';
      } catch (_) {}
    }
    final temp = Directory.systemTemp;
    final dir = Directory('${temp.path}${Platform.pathSeparator}offgrid_voice');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return '${dir.path}${Platform.pathSeparator}$clientMsgId.m4a';
  }

  Future<void> _persistMessage({
    required String groupId,
    required PacketType type,
    required Uint8List payload,
    String? clientMsgIdOverride,
    String? localAudioPath,
  }) async {
    final userId = _effectiveUserId;
    final now = widget.clock.nowUtc();
    final repo = _chat;
    final int seq;
    if (repo != null) {
      seq = await repo.nextSeq(groupId: groupId, authorId: userId);
    } else {
      final list = _memoryMessages[groupId] ?? const <ChatMessage>[];
      seq = list.where((m) => m.authorId == userId).length + 1;
    }

    final clientMsgId = clientMsgIdOverride ?? generateUuidV4();

    final storedPayload = type == PacketType.voiceFragment
        ? (() {
            final vn = VoiceNoteData.fromBytes(payload);
            return VoiceNoteData(
              durationSeconds: vn.durationSeconds,
              peaks: vn.peaks,
              localAudioPath: localAudioPath ?? vn.localAudioPath,
              audioUrl: vn.audioUrl,
              clientMsgId: vn.clientMsgId ?? clientMsgId,
              syncStatus: vn.syncStatus ?? 'pending',
            ).toBytes();
          })()
        : payload;

    final msg = ChatMessage(
      authorId: userId,
      seq: seq,
      groupId: groupId,
      type: type,
      sentAtUtc: now,
      receivedAtUtc: now,
      payload: storedPayload,
      isOutgoing: true,
    );

    if (type == PacketType.text || type == PacketType.voiceFragment) {
      _bridgedRepoMessageIds.add(msg.messageId);
      final origin = _isOnline
          ? ChatTransportOrigin.online
          : (type == PacketType.voiceFragment
              ? ChatTransportOrigin.wifiDirect
              : ChatTransportOrigin.bleMesh);
      final record = GroupMessageRecord.fromChatMessage(
        msg,
        clientMsgId: clientMsgId,
        senderName: _effectiveUserDisplayName,
        keyVersion: _activeGroup?.group.keyVersion ?? 1,
        originTransport: origin,
        syncStatus: ChatSyncStatus.pending,
        localAudioPath: localAudioPath,
      );

      // Pastikan masuk ke single source of truth lokal terlebih dahulu agar
      // input composer langsung bersih tanpa menunggu enkripsi/radio/network.
      await _localStore?.insertMessageIfAbsent(record);

      // Kirim via BLE Mesh secara asinkron saat offline agar tombol kirim tidak
      // pernah terkunci walaupun layanan latar depan / izin radio tertunda.
      final router = _meshRouter;
      if (!_isOnline) {
        if (router != null) {
          unawaited(() async {
            try {
              if (!router.isStarted) {
                await router.start(
                  groupId: groupId,
                  keyVersion: _activeGroup?.group.keyVersion ?? 1,
                  highDuty: true,
                  useForegroundService: true,
                );
              }
              await router.sendTextMessage(record);
            } catch (_) {
              // Tetap tersimpan di antrean lokal untuk dikirim via Mesh / Supabase.
            }
          }());
        }
      } else {
        if (router != null && router.isStarted) {
          await router.stop();
        }
        if (_keyVerifiedForRoomId != groupId &&
            _account.groupsEnabled &&
            isValidUuid(groupId)) {
          _keyVerifiedForRoomId = groupId;
          await _account
              .ensureGroupKeyDistributed(groupId)
              .timeout(const Duration(seconds: 2), onTimeout: () => false);
        }
        try {
          final synced = await _syncService?.syncPending(groupId: groupId) ?? 0;
          if (synced == 0 && _chatRemote != null && isValidUuid(groupId)) {
            await _chatRemote!.upsertMessage(
              record.copyWith(syncStatus: ChatSyncStatus.sent),
            );
            await _localStore?.updateMessageAudioAndSync(
              clientMsgId: record.clientMsgId,
              groupId: groupId,
              syncStatus: ChatSyncStatus.sent,
            );
          }
        } catch (_) {
          // Tetap berstatus 'pending' di SQLite lokal agar dicoba ulang otomatis.
        }
      }

      // Hentikan jalur tulis ganda ke tabel `messages` Drift lama ketika
      // `OffGridChatLocalStore` sudah menjadi single source of truth.
      // Hanya simpan ke `repo` bila disuntikkan eksplisit (unit/widget test)
      // atau `_localStore` tidak tersedia.
      if (_localStore == null || widget.chatRepository != null) {
        if (repo != null) {
          await repo.saveMessage(msg);
        } else {
          final list =
              _memoryMessages.putIfAbsent(groupId, () => <ChatMessage>[]);
          list.add(msg);
          if (mounted && _activeGroup?.group.id == groupId) {
            setState(() {
              _messages = _mergeLocalAndRemoteMessages(groupId);
            });
            _scrollToBottom();
          }
        }
      }
      return;
    }

    if (repo != null) {
      await repo.saveMessage(msg);
    } else {
      final list = _memoryMessages.putIfAbsent(groupId, () => <ChatMessage>[]);
      list.add(msg);
      if (mounted && _activeGroup?.group.id == groupId) {
        setState(() {
          _messages = _mergeLocalAndRemoteMessages(groupId);
        });
        _scrollToBottom();
      }
    }
  }

  void _toggleVoicePlayback(String messageId, VoiceNoteData voice) {
    if (_playingMessageId == messageId) {
      _playbackTimer?.cancel();
      _playbackTimer = null;
      try {
        unawaited(_audioPlayer?.stop());
      } catch (_) {}
      setState(() {
        _playingMessageId = null;
        _playingProgress = 0.0;
      });
      return;
    }

    _playbackTimer?.cancel();
    try {
      unawaited(_audioPlayer?.stop());
    } catch (_) {}
    setState(() {
      _playingMessageId = messageId;
      _playingProgress = 0.08;
    });

    unawaited(_startAudioPlayerForVoice(voice));

    final totalTicks = math.max(4, voice.durationSeconds * 4);
    var tick = 1;
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!mounted || _playingMessageId != messageId) {
        timer.cancel();
        return;
      }
      tick++;
      if (tick >= totalTicks) {
        timer.cancel();
        try {
          unawaited(_audioPlayer?.stop());
        } catch (_) {}
        setState(() {
          _playingMessageId = null;
          _playingProgress = 0.0;
        });
      } else {
        setState(() {
          _playingProgress = (tick / totalTicks).clamp(0.0, 1.0);
        });
      }
    });
  }

  Future<void> _startAudioPlayerForVoice(VoiceNoteData voice) async {
    try {
      final localPath = voice.localAudioPath;
      if (localPath != null && File(localPath).existsSync()) {
        final player = _audioPlayer ??= AudioPlayer();
        await player.setFilePath(localPath);
        await player.play();
        return;
      }
      final remoteUrl = voice.audioUrl;
      final group = _activeGroup?.group;
      if (remoteUrl != null && remoteUrl.isNotEmpty) {
        final player = _audioPlayer ??= AudioPlayer();
        if (_chatRemote != null &&
            group != null &&
            voice.clientMsgId != null &&
            !remoteUrl.startsWith('http')) {
          final cachePath =
              await _resolveVoiceFilePath('dec-${voice.clientMsgId!}');
          final cacheFile = File(cachePath);
          if (!cacheFile.existsSync()) {
            final decrypted = await _chatRemote!.downloadVoiceNote(
              groupId: group.id,
              clientMsgId: voice.clientMsgId!,
              storagePath: remoteUrl,
              keyVersion: group.keyVersion,
            );
            if (decrypted != null && decrypted.isNotEmpty) {
              cacheFile.writeAsBytesSync(decrypted, flush: true);
            }
          }
          if (cacheFile.existsSync()) {
            await player.setFilePath(cachePath);
            await player.play();
            return;
          }
        }
        final resolvedUrl = _chatRemote != null
            ? await _chatRemote!.resolveVoiceNotePlayUrl(remoteUrl)
            : remoteUrl;
        await player.setUrl(resolvedUrl);
        await player.play();
      }
    } catch (_) {
      // Jika file lokal hanya metadata placeholder / plugin audio nonaktif,
      // pemutaran visual progress tetap berjalan mulus tanpa error.
    }
  }

  Future<void> _loadOlderMessages() async {
    final group = _activeGroup?.group;
    final remote = _chatRemote;
    if (group == null ||
        remote == null ||
        !_isOnline ||
        _loadingOlderMessages ||
        !_hasMoreOlderMessages ||
        !isValidUuid(group.id)) {
      return;
    }
    final oldest = _messages.isNotEmpty ? _messages.first.sentAtUtc : null;
    final joinedAt = _activeGroupJoinedAtUtc;
    if (oldest == null ||
        (joinedAt != null && !oldest.isAfter(joinedAt))) {
      setState(() => _hasMoreOlderMessages = false);
      return;
    }
    setState(() => _loadingOlderMessages = true);
    try {
      final fetched = remote is GroupChatSinceFilterRemoteService
          ? await remote.fetchMessagesSince(
              group.id,
              limit: 41,
              beforeCreatedAtUtc: oldest,
              minCreatedAtUtc: joinedAt,
            )
          : await remote.fetchMessages(
              group.id,
              limit: 41,
              beforeCreatedAtUtc: oldest,
            );
      if (!mounted) return;
      final withinBound = joinedAt == null
          ? fetched
          : fetched
              .where(
                (m) => !(m.createdAtUtc ?? m.clientCreatedAtUtc)
                    .isBefore(joinedAt),
              )
              .toList(growable: false);
      if (withinBound.isEmpty) {
        setState(() {
          _hasMoreOlderMessages = false;
          _loadingOlderMessages = false;
        });
        return;
      }
      final hasMore = withinBound.length > 40;
      final page = hasMore
          ? withinBound.sublist(withinBound.length - 40)
          : withinBound;
      for (final rec in page) {
        await _localStore?.insertMessageIfAbsent(
          rec.copyWith(syncStatus: ChatSyncStatus.sent),
        );
      }
      final oldestPageAt =
          page.first.createdAtUtc ?? page.first.clientCreatedAtUtc;
      setState(() {
        _hasMoreOlderMessages =
            hasMore && !(joinedAt != null && !oldestPageAt.isAfter(joinedAt));
        _loadingOlderMessages = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOlderMessages = false);
    }
  }

  Future<void> _respondToInvitation(
    IncomingInvitation inv, {
    required bool accept,
  }) async {
    _dismissedInvitationIds.add(inv.id);
    if (accept) {
      _localAcceptedInvitations.add(inv);
    }
    if (_account.groupsEnabled && _isOnline && _account.user != null) {
      await _account.respondToInvitation(inv, accept: accept);
    }
    if (mounted) {
      setState(() {});
      _showNotice(accept
          ? 'Undangan ke "${inv.groupName}" diterima.'
          : 'Undangan ditolak.');
    }
  }

  Future<void> _showCreateGroupSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (_) => _CreateGroupSheet(
        onSubmit: ({required String name, File? avatarFile}) =>
            _createGroup(name: name, avatarFile: avatarFile),
      ),
    );
  }

  Future<({bool ok, String? error})> _createGroup({
    required String name,
    File? avatarFile,
  }) async {
    final now = widget.clock.nowUtc();
    if (_isOnline && _account.groupsEnabled && _account.user != null) {
      final createdRemote = avatarFile != null
          ? await _account.createGroupWithOptions(
              name: name,
              avatarFile: avatarFile,
            )
          : await _account.createGroup(name);
      if (!createdRemote) {
        return (
          ok: false,
          error: _account.error ?? 'Gagal membuat grup. Periksa sinyal lalu coba lagi.',
        );
      }
      if (mounted) {
        setState(() {});
        _showNotice('Grup "$name" berhasil dibuat.');
      }
      return (ok: true, error: null);
    }

    final newId = 'grup-lokal-${now.microsecondsSinceEpoch}';
    final group = Group(
      id: newId,
      name: name,
      ownerId: _effectiveUserId,
      avatarUrl: avatarFile?.path,
      createdAtUtc: now,
    );
    if (_groupRepo != null) {
      try {
        await _groupRepo!.saveGroup(group);
        await _groupRepo!.saveMember(
          GroupMember(
            groupId: newId,
            userId: _effectiveUserId,
            username: _effectiveUserDisplayName,
            role: GroupRole.owner,
            joinedAtUtc: now,
          ),
        );
      } catch (_) {
        // Lanjut dengan state memori bila DB belum terbuka.
      }
    }
    final createdRemote = RemoteGroup(
      group: group,
      role: GroupRole.owner,
      joinedAtUtc: now,
    );
    SocialGroupsStore.instance.addLocalGroup(createdRemote);
    _localCreatedGroups.insert(
      0,
      GroupCardData(
        remote: createdRemote,
        memberCount: 1,
        pendingSync: !_isOnline,
      ),
    );

    if (mounted) {
      setState(() {});
      _showNotice(
        _isOnline
            ? 'Grup "$name" berhasil dibuat.'
            : 'Grup "$name" disimpan lokal (akan disinkronkan saat online).',
      );
    }
    return (ok: true, error: null);
  }

  Future<void> _showMemberInfoSheet() async {
    final card = _activeGroup;
    if (card == null) return;
    setState(() => _menuOpen = false);

    final groupId = card.group.id;
    final currentMembers = _members.isNotEmpty
        ? _members
        : _account.cachedMembersOf(groupId);
    final locations = _groupMemberLocations[groupId] ??
        await _localStore?.memberLocationsForGroup(
          groupId,
          currentUserId: _effectiveUserId,
        ) ??
        const <MemberLastLocation>[];
    if (!mounted) return;

    await showGroupMembersSheet(
      context,
      groupName: card.group.name,
      mountain: card.group.mountain,
      currentUserId: _effectiveUserId,
      initialMembers: currentMembers,
      memberLocations: locations,
      nowUtc: widget.clock.nowUtc(),
      isOnline: _isOnline,
      onRefreshMembers: (_isOnline && _account.groupsEnabled)
          ? () async {
              final refreshed = await _account.membersOf(groupId);
              if (refreshed.isNotEmpty &&
                  mounted &&
                  _activeGroup?.group.id == groupId) {
                setState(
                  () => _members =
                      List<MemberDirectoryEntry>.unmodifiable(refreshed),
                );
              }
              return refreshed;
            }
          : null,
    );
  }

  Future<void> _showAddMemberDialog() async {
    final group = _activeGroup?.group;
    if (group == null) return;
    setState(() => _menuOpen = false);

    // Tolak secara jelas bila offline — tidak boleh membuat undangan palsu lokal.
    if (!_isOnline) {
      _showNotice(
        'Fitur undang teman ke grup hanya bisa digunakan saat terhubung ke internet.',
      );
      return;
    }

    final submitted = await showDialog<String>(
      context: context,
      builder: (_) => const _AddMemberDialog(),
    );

    if (submitted == null || submitted.isEmpty || !mounted) return;
    final cleanUsername = submitted.replaceFirst(RegExp(r'^@+'), '');
    if (cleanUsername.isEmpty) return;

    if (!_isOnline) {
      _showNotice(
        'Koneksi terputus. Sambungkan internet untuk mengundang @$cleanUsername.',
      );
      return;
    }

    _account.clearError();
    if (_account.groupsEnabled && _account.user != null) {
      final invitedOnline = await _account.invite(
        groupId: group.id,
        username: cleanUsername,
      );
      if (!mounted) return;
      if (invitedOnline) {
        _showNotice('Undangan untuk @$cleanUsername terkirim.');
      } else {
        _showNotice(
          _account.error ?? 'Gagal mengundang @$cleanUsername. Coba lagi.',
        );
      }
      return;
    }

    // Fallback khusus lingkungan widget test lokal (tanpa Supabase remote).
    final now = widget.clock.nowUtc();
    final entry = MemberDirectoryEntry(
      userId: 'anggota-$cleanUsername',
      username: cleanUsername,
      role: GroupRole.member,
      publicKeyBase64: '',
      joinedAtUtc: now,
    );
    _localExtraMembers
        .putIfAbsent(group.id, () => <MemberDirectoryEntry>[])
        .add(entry);
    if (mounted && _activeGroup?.group.id == group.id) {
      setState(() {
        _members = <MemberDirectoryEntry>[..._members, entry];
      });
      _showNotice('@$cleanUsername ditambahkan ke daftar grup.');
    }
  }

  Future<void> _showShareGroupSheet() async {
    final group = _activeGroup?.group;
    if (group == null) return;
    setState(() => _menuOpen = false);
    final code = group.id.length >= 6
        ? group.id.substring(group.id.length - 6).toUpperCase()
        : group.id.toUpperCase();
    final mountainPart = (group.mountain != null && group.mountain!.isNotEmpty)
        ? ' (${group.mountain})'
        : '';
    final shareText =
        'Gabung ke grup pendakian "${group.name}"$mountainPart di Hiqeo. '
        'Kode grup: HIQEO-$code';
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await SharePlus.instance.share(
          ShareParams(text: shareText, subject: 'Undangan grup Hiqeo'),
        );
        return;
      }
    } catch (_) {
      // Jatuh ke dialog kode grup jika lembar berbagi sistem tidak tersedia.
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final colors = HiqeoColors.of(dialogContext);
        return AlertDialog(
          backgroundColor: colors.surface,
          title: const Text('Bagikan grup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Bagikan kode undangan grup "${group.name}" ke teman pendakianmu:',
              ),
              const SizedBox(height: HiqeoSpacing.md),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: colors.hairline,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'HIQEO-$code',
                  textAlign: TextAlign.center,
                  style:
                      Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteCurrentGroup() async {
    final group = _activeGroup?.group;
    if (group == null) return;
    setState(() => _menuOpen = false);

    // Konfirmasi 2 tahap khusus pemilik grup.
    final step1 = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = HiqeoColors.of(dialogContext);
        return AlertDialog(
          backgroundColor: colors.surface,
          title: const Text('Hapus grup?'),
          content: Text(
            'Grup "${group.name}", seluruh pesan, pesan suara, dan lokasi '
            'terakhir anggota akan dihapus permanen untuk semua anggota.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Batal'),
            ),
            TextButton(
              key: const ValueKey<String>('delete-group-step1-next'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                'Lanjut hapus',
                style: TextStyle(
                  color: colors.warningText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
    if (step1 != true || !mounted) return;

    final step2 = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = HiqeoColors.of(dialogContext);
        return AlertDialog(
          backgroundColor: colors.surface,
          title: Text(
            'Konfirmasi hapus permanen',
            style: TextStyle(color: colors.warningText),
          ),
          content: Text(
            'Tindakan ini tidak dapat dibatalkan. Yakin ingin menghapus grup '
            '"${group.name}" sekarang?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              key: const ValueKey<String>('delete-group-step2-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.warning,
                foregroundColor: HiqeoColors.light.glassHighlight,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Hapus grup'),
            ),
          ],
        );
      },
    );
    if (step2 != true || !mounted) return;

    if (_isOnline && _account.groupsEnabled && isValidUuid(group.id)) {
      final ok = await _account.deleteGroup(group.id);
      if (!ok) {
        if (mounted) {
          _showNotice(
            _account.error ?? 'Gagal menghapus grup. Periksa jaringan lalu coba lagi.',
          );
        }
        return;
      }
    }

    await _persistDeletedGroupTombstone(group.id);
    _localCreatedGroups.removeWhere((g) => g.group.id == group.id);
    _localAcceptedInvitations.removeWhere((i) => i.groupId == group.id);
    try {
      await _localStore?.deleteGroupData(group.id);
    } catch (_) {}
    try {
      await _locationConsent.clearGroup(group.id);
    } catch (_) {}
    if (_groupRepo != null) {
      try {
        await _groupRepo!.deleteGroup(group.id);
      } catch (_) {}
    }

    final deletedName = group.name;
    _closeRoomChat();
    if (mounted) {
      _showNotice('Grup "$deletedName" dihapus.');
    }
  }

  Future<void> _leaveCurrentGroup() async {
    final group = _activeGroup?.group;
    if (group == null) return;
    setState(() => _menuOpen = false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = HiqeoColors.of(dialogContext);
        return AlertDialog(
          backgroundColor: colors.surface,
          title: const Text('Keluar grup?'),
          content: Text(
            'Kamu akan keluar dari grup "${group.name}" dan berhenti menerima '
            'pesan maupun berbagi lokasi di grup ini.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Batal'),
            ),
            TextButton(
              key: const ValueKey<String>('leave-group-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                'Keluar grup',
                style: TextStyle(
                  color: colors.warningText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    if (_isOnline && _account.groupsEnabled && isValidUuid(group.id)) {
      final ok = await _account.leaveGroup(group.id);
      if (!ok) {
        if (mounted) {
          _showNotice(
            _account.error ?? 'Gagal keluar dari grup. Periksa jaringan lalu coba lagi.',
          );
        }
        return;
      }
    }
    await _persistDeletedGroupTombstone(group.id, cancelRemotePlan: false);
    _localCreatedGroups.removeWhere((g) => g.group.id == group.id);
    _localAcceptedInvitations.removeWhere((i) => i.groupId == group.id);
    try {
      await _localStore?.deleteGroupData(group.id);
    } catch (_) {}
    try {
      await _locationConsent.clearGroup(group.id);
    } catch (_) {}
    if (_groupRepo != null) {
      try {
        await _groupRepo!.deleteGroup(group.id);
      } catch (_) {}
    }
    final leftName = group.name;
    _closeRoomChat();
    if (mounted) {
      _showNotice('Kamu keluar dari grup "$leftName".');
    }
  }

  void _showNotice(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _formatTimeHm(DateTime utc) {
    final local = utc.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _senderNameFor(ChatMessage message) {
    if (message.isOutgoing || message.authorId == _effectiveUserId) {
      return _effectiveUserDisplayName;
    }
    for (final m in _members) {
      if (m.userId == message.authorId) return m.username;
    }
    return _remoteSenderNames[message.authorId] ?? message.authorId;
  }

  @override
  Widget build(BuildContext context) {
    switch (_viewMode) {
      case _GroupViewMode.lastLocation:
        final card = _activeGroup;
        final id = card?.group.id;
        final fix = _currentUserFix;
        return LastLocationView(
          groupName: card?.group.name ?? 'Grup Pendakian',
          mountainName: card?.group.mountain,
          members: _resolvedMembersForLastLocation(id),
          nowUtc: widget.clock.nowUtc(),
          isOnline: _isOnline,
          userLocation: fix != null ? LatLng(fix.lat, fix.lon) : null,
          isLockingGps: _isLockingGps,
          locationStatus: _locationService.state.status,
          downloadedPacks: _downloadedMountainPacks,
          isLoadingOfflinePacks: _loadingDownloadedPacks,
          locationSharingEnabled: true,
          onLocationSharingChanged: null,
          onBack: _backToRoomFromLastLocation,
          onShareLocation: () =>
              _shareCurrentLocationToGroup(silent: false, force: true),
          onRetryLocation: () => unawaited(_retryGpsFromLastLocation()),
          onOpenOfflineMaps: widget.onOpenOfflineMaps ??
              () {
                unawaited(_syncService?.unsubscribeLocations());
                setState(() {
                  _viewMode = _GroupViewMode.list;
                });
                NavBarVisibilityController.instance.setRoomChatOpen(false);
                _syncPeriodicLocationSharing();
                GoRouter.maybeOf(context)?.go('/peta');
              },
        );
      case _GroupViewMode.room:
        return _buildRoomChat(context);
      case _GroupViewMode.list:
        return _buildGroupList(context);
    }
  }

  // ===========================================================================
  // TAMPILAN 1: HALAMAN UTAMA GRUP (DAFTAR KOSONG / DAFTAR GRUP)
  // ===========================================================================
  Widget _buildGroupList(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final invitations = _visibleInvitations;
    final groups = _visibleGroups;
    final bottomInset = AppLayout.bottomInset(context);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Header Halaman Utama Sosial (dengan 3 sub-tab: Grup, Komunitas, Leaderboard)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HiqeoSpacing.lg,
              HiqeoSpacing.lg,
              HiqeoSpacing.lg,
              HiqeoSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Sosial',
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _socialTab == _SocialTab.grup
                            ? 'Rencanakan dan ngobrol bersama rombongan'
                            : (_socialTab == _SocialTab.komunitas
                                ? 'Diskusi terbuka bersama pendaki seluruh Indonesia'
                                : 'Papan peringkat pendakian Hiqeo'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_socialTab == _SocialTab.grup) ...<Widget>[
                  const SizedBox(width: 12),
                  Semantics(
                    button: true,
                    label: 'Buat grup',
                    child: GestureDetector(
                      key: const ValueKey<String>('grup-create-header-btn'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => unawaited(_showCreateGroupSheet()),
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            HiqeoIcon(
                              HiqeoIcons.plus,
                              size: 16,
                              color: colors.onPrimary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Buat grup',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: colors.onPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 3 Sub-Tab Utama: Grup | Komunitas | Leaderboard
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HiqeoSpacing.lg,
              4,
              HiqeoSpacing.lg,
              10,
            ),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: colors.hairline),
              ),
              child: GooeySelector<_SocialTab>(
                key: const ValueKey<String>('social-tab-selector'),
                axis: Axis.horizontal,
                expandItems: true,
                gap: 4,
                borderRadius: 18,
                indicatorColor: colors.primary,
                itemPadding: const EdgeInsets.symmetric(
                  vertical: 11,
                  horizontal: 4,
                ),
                selected: _socialTab,
                onChanged: (tab) => setState(() => _socialTab = tab),
                items: <GooeySelectorItem<_SocialTab>>[
                  for (final entry in const <(_SocialTab, String)>[
                    (_SocialTab.grup, 'Grup'),
                    (_SocialTab.komunitas, 'Komunitas'),
                    (_SocialTab.leaderboard, 'Leaderboard'),
                  ])
                    GooeySelectorItem<_SocialTab>(
                      value: entry.$1,
                      semanticsLabel: entry.$2,
                      builder: (context, state) => Center(
                        key: ValueKey<String>('social-tab-${entry.$1.name}'),
                        child: Text(
                          entry.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color.lerp(
                              colors.textSecondary,
                              colors.onPrimary,
                              state.coverage,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Konten Sub-Tab Aktif
          Expanded(
            child: _socialTab == _SocialTab.komunitas
                ? const SocialCommunityTab()
                : _socialTab == _SocialTab.leaderboard
                    ? const SocialLeaderboardTab()
                    : (invitations.isEmpty && groups.isEmpty
                        ? _buildEmptyGroupList(theme, colors, bottomInset)
                        : ListView(
                    padding: EdgeInsets.fromLTRB(
                      HiqeoSpacing.lg,
                      HiqeoSpacing.xs,
                      HiqeoSpacing.lg,
                      bottomInset,
                    ),
                    children: <Widget>[
                      if (invitations.isNotEmpty) ...<Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                'Undangan masuk',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: colors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              key: const ValueKey<String>(
                                'grup-refresh-invitations',
                              ),
                              tooltip: 'Muat ulang undangan',
                              onPressed: _account.isBusy
                                  ? null
                                  : () => unawaited(_account.refresh()),
                              icon: Icon(
                                Icons.refresh_rounded,
                                size: 20,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        for (final inv in invitations) ...<Widget>[
                          _InvitationCard(
                            invitation: inv,
                            onReject: () => unawaited(
                                _respondToInvitation(inv, accept: false)),
                            onAccept: () => unawaited(
                                _respondToInvitation(inv, accept: true)),
                          ),
                          const SizedBox(height: 8),
                        ],
                        const SizedBox(height: 8),
                      ],
                      if (groups.isNotEmpty) ...<Widget>[
                        Text(
                          'Grup saya',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final card in groups) ...<Widget>[
                          _GroupListCard(
                            key:
                                ValueKey<String>('group-card-${card.group.id}'),
                            card: card,
                            onTap: () => _openRoomChat(card),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ],
                  )),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyGroupList(
    ThemeData theme,
    HiqeoColors colors,
    double bottomInset,
  ) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          HiqeoSpacing.lg,
          HiqeoSpacing.xl,
          HiqeoSpacing.lg,
          bottomInset,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.secondary.withValues(alpha: 0.32),
              ),
              child: Center(
                child: HiqeoIcon(
                  HiqeoIcons.group,
                  size: 32,
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: HiqeoSpacing.lg),
            Text(
              'Belum ada grup',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: HiqeoSpacing.xs),
            Text(
              'Buat grup untuk mengundang teman pendakianmu.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: HiqeoSpacing.xl),
            HiqeoButton(
              key: const ValueKey<String>('grup-create-empty-btn'),
              label: 'Buat grup baru',
              leading: HiqeoIcon(
                HiqeoIcons.plus,
                size: 18,
                color: colors.onPrimary,
              ),
              onPressed: () => unawaited(_showCreateGroupSheet()),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TAMPILAN 2: RUANG OBROLAN (ROOM CHAT — FULL-SCREEN STACK LIQUID GLASS)
  // ===========================================================================
  Widget _buildRoomChat(BuildContext context) {
    final group = _activeGroup?.group;
    final liveAccountCount =
        group != null ? _account.memberCountFor(group.id) : 1;
    final memberCount = math.max(
      math.max(_activeGroup?.memberCount ?? 1, _members.length),
      liveAccountCount,
    );
    final topPad = MediaQuery.paddingOf(context).top;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final isOwner = _activeGroup?.remote.isOwner ?? true;

    return ChatRoomCanvas(
      child: Builder(
        builder: (roomContext) {
          final colors = HiqeoColors.of(roomContext);
          final theme = Theme.of(roomContext);
          final keyboardInset = MediaQuery.viewInsetsOf(roomContext).bottom;
          final composerBottom =
              (keyboardInset > 0 ? keyboardInset : safeBottom) + 10;
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) {
                if (_menuOpen) {
                  setState(() => _menuOpen = false);
                } else {
                  _closeRoomChat();
                }
              }
            },
            child: ListenableBuilder(
              listenable: ChatMuteService.instance,
              builder: (context, _) {
                final isMuted = group != null &&
                    ChatMuteService.instance.isMuted('group', group.id);
                final muteSub = group != null
                    ? chatMuteStatusShortLabel(
                        ChatMuteService.instance,
                        'group',
                        group.id,
                      )
                    : '';
                return Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    // 1. Area pesan mengalir penuh di belakang header & pil input kaca
                    _buildRoomMessages(
                      theme,
                      colors,
                      topPadding: ChatRoomHeaderBar.listTopPadding(topPad),
                      bottomPadding: composerBottom + 76,
                    ),

                    // 2. Header Melayang seragam: [<] | Pil Kaca Grup | [≡]
                    Positioned(
                      top: topPad + ChatRoomHeaderBar.topMargin,
                      left: 14,
                      right: 14,
                      child: ChatRoomHeaderBar(
                        backKey: const ValueKey<String>('room-chat-back'),
                        onBack: _closeRoomChat,
                        headerPillKey:
                            const ValueKey<String>('room-chat-header-pill'),
                        headerTapKey: const ValueKey<String>(
                          'room-chat-header-info-btn',
                        ),
                        headerSemanticsLabel: 'Info anggota grup',
                        onHeaderTap: () => unawaited(_showMemberInfoSheet()),
                        avatarUrl: group?.avatarUrl,
                        avatarCacheKey:
                            group != null ? 'group_${group.id}' : null,
                        fallbackIcon: Icons.terrain_rounded,
                        title: group?.name ?? 'Ruang Obrolan',
                        subtitle: _isOnline
                            ? 'Online · $memberCount anggota'
                            : 'Offline · $_meshConnectedPeers perangkat sekitar',
                        isOnline: _isOnline,
                        isMuted: isMuted,
                        badgeLabel: 'Terenkripsi',
                        badgeIcon: Icons.lock_outline_rounded,
                        badgeColor: ChatRoomPalette.badgeE2eeText,
                        menuButtonKey:
                            const ValueKey<String>('room-chat-menu-btn'),
                        menuSemanticsLabel: 'Menu grup',
                        onMenuTap: () =>
                            setState(() => _menuOpen = !_menuOpen),
                      ),
                    ),

                    // 3. Pil Input & Tombol Kirim Melayang (tanpa wadah solid di belakang)
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: composerBottom,
                      child: _buildComposer(theme, colors),
                    ),

                    // 4. Overlay Menu Dropdown Melayang (Kanan Atas, jarak 12 px dari header)
                    if (_menuOpen) ...<Widget>[
                      Positioned.fill(
                        child: GestureDetector(
                          key: const ValueKey<String>(
                            'room-chat-dropdown-scrim',
                          ),
                          behavior: HitTestBehavior.translucent,
                          onTap: () => setState(() => _menuOpen = false),
                        ),
                      ),
                      Positioned(
                        top: ChatRoomHeaderBar.dropdownTop(topPad),
                        right: 14,
                        child: ChatRoomDropdownMenu(
                          menuKey: const ValueKey<String>('room-chat-dropdown'),
                          entries: <ChatRoomMenuEntry>[
                            ChatRoomMenuEntry.item(
                              key: const ValueKey<String>('menu-member-info'),
                              icon: Icons.groups_outlined,
                              label: 'Info anggota',
                              onTap: () {
                                setState(() => _menuOpen = false);
                                unawaited(_showMemberInfoSheet());
                              },
                            ),
                            ChatRoomMenuEntry.item(
                              key: const ValueKey<String>('menu-add-member'),
                              icon: Icons.person_add_alt_1_outlined,
                              label: 'Tambah anggota',
                              enabled: _isOnline,
                              subtitle:
                                  _isOnline ? null : 'Butuh koneksi internet',
                              trailingIcon: _isOnline
                                  ? null
                                  : Icons.lock_outline_rounded,
                              onTap: () {
                                setState(() => _menuOpen = false);
                                unawaited(_showAddMemberDialog());
                              },
                              onDisabledTap: () {
                                setState(() => _menuOpen = false);
                                _showNotice(
                                  'Fitur undang teman ke grup hanya bisa digunakan saat terhubung ke internet.',
                                );
                              },
                            ),
                            ChatRoomMenuEntry.item(
                              key: const ValueKey<String>('menu-share-group'),
                              icon: Icons.share_outlined,
                              label: 'Bagikan grup',
                              onTap: () {
                                setState(() => _menuOpen = false);
                                unawaited(_showShareGroupSheet());
                              },
                            ),
                            ChatRoomMenuEntry.item(
                              key: const ValueKey<String>('menu-last-location'),
                              icon: Icons.location_on_outlined,
                              label: 'Lokasi terakhir',
                              onTap: () {
                                setState(() => _menuOpen = false);
                                _openLastLocation();
                              },
                            ),
                            ChatRoomMenuEntry.item(
                              key: const ValueKey<String>(
                                'menu-mute-notifications',
                              ),
                              icon: isMuted
                                  ? Icons.notifications_off_outlined
                                  : Icons.notifications_outlined,
                              label: 'Bisukan notifikasi',
                              subtitle: muteSub.isNotEmpty ? muteSub : null,
                              onTap: () {
                                setState(() => _menuOpen = false);
                                if (group != null) {
                                  unawaited(
                                    showChatMuteSheet(
                                      context,
                                      roomType: 'group',
                                      roomId: group.id,
                                      roomName: group.name,
                                    ),
                                  );
                                }
                              },
                            ),
                            const ChatRoomMenuEntry.divider(),
                            ChatRoomMenuEntry.item(
                              key: const ValueKey<String>('menu-leave-group'),
                              icon: Icons.logout_rounded,
                              label: 'Keluar grup',
                              destructive: true,
                              onTap: () {
                                setState(() => _menuOpen = false);
                                unawaited(_leaveCurrentGroup());
                              },
                            ),
                            if (isOwner)
                              ChatRoomMenuEntry.item(
                                key:
                                    const ValueKey<String>('menu-delete-group'),
                                icon: Icons.delete_outline_rounded,
                                label: 'Hapus grup',
                                destructive: true,
                                onTap: () {
                                  setState(() => _menuOpen = false);
                                  unawaited(_deleteCurrentGroup());
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  String _dayDividerLabel(DateTime utc) =>
      formatChatDayDividerLabel(utc, widget.clock.nowUtc());

  bool _isHikeInviteMessage(ChatMessage msg) {
    if (msg.type != PacketType.text) return false;
    final decoded = utf8.decode(msg.payload, allowMalformed: true);
    return GroupHikeInviteMessage.tryDecodeInvite(decoded) != null;
  }

  Widget _buildRoomMessages(
    ThemeData theme,
    HiqeoColors colors, {
    required double topPadding,
    required double bottomPadding,
  }) {
    if (_messagesLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(
              strokeWidth: 2.2,
              color: ChatRoomPalette.textPrimary,
            ),
            const SizedBox(height: 12),
            Text(
              'Memuat pesan…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ChatRoomPalette.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    if (_messagesError != null) {
      return Center(
        child: HiqeoStateView(
          icon: Icons.wifi_off_rounded,
          title: 'Pesan belum bisa dimuat',
          message: _messagesError!,
          isError: true,
          darkRoom: true,
          actionLabel: _activeGroup != null ? 'Coba lagi' : null,
          onAction:
              _activeGroup != null ? () => _openRoomChat(_activeGroup!) : null,
        ),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            HiqeoSpacing.xl,
            topPadding,
            HiqeoSpacing.xl,
            bottomPadding,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ChatDateDividerPill(label: 'Hari ini'),
              const SizedBox(height: HiqeoSpacing.lg),
              Text(
                'Belum ada pesan',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: ChatRoomPalette.textPrimary,
                ),
              ),
              const SizedBox(height: HiqeoSpacing.xs),
              Text(
                _isOnline
                    ? 'Pesanmu terenkripsi dan hanya bisa dibaca anggota grup. Mulai obrolan di sini.'
                    : 'Offline: pesan teks & suara disimpan di HP dan dikirim saat ada sinyal.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ChatRoomPalette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final oldestLoadedAt =
        _messages.isNotEmpty ? _messages.first.sentAtUtc : null;
    final joinedAt = _activeGroupJoinedAtUtc;
    final reachedJoinBound = joinedAt != null &&
        (oldestLoadedAt == null || !oldestLoadedAt.isAfter(joinedAt));
    final showLoadOlder = _isOnline &&
        _hasMoreOlderMessages &&
        _messages.isNotEmpty &&
        !reachedJoinBound &&
        _chatRemote != null &&
        _activeGroup != null &&
        isValidUuid(_activeGroup!.group.id);

    return LayoutBuilder(
      builder: (context, constraints) {
        final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
        final deltaInset = keyboardInset - _lastRoomKeyboardInset;
        final deltaHeight = _lastRoomViewportHeight > 0
            ? _lastRoomViewportHeight - constraints.maxHeight
            : 0.0;
        final delta = math.max(deltaInset, deltaHeight);
        _lastRoomKeyboardInset = keyboardInset;
        _lastRoomViewportHeight = constraints.maxHeight;

        if (delta > 24 && _scroll.hasClients && _messages.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scroll.hasClients) return;
            final maxExt = _scroll.position.maxScrollExtent;
            if ((maxExt - _scroll.position.pixels) <= 180 + delta) {
              _scroll.jumpTo(maxExt);
            } else {
              _scroll.jumpTo(
                (_scroll.position.pixels + delta).clamp(0.0, maxExt),
              );
            }
          });
        }

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.pixels <= 40 && showLoadOlder) {
              unawaited(_loadOlderMessages());
            }
            return false;
          },
          child: ListView.builder(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(14, topPadding, 14, bottomPadding),
            itemCount: _messages.length + (showLoadOlder ? 1 : 0),
            itemBuilder: (context, rawIndex) {
              if (showLoadOlder && rawIndex == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Center(
                    child: _loadingOlderMessages
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: () => unawaited(_loadOlderMessages()),
                            child: const Text('Muat pesan sebelumnya'),
                          ),
                  ),
                );
              }
              final index = showLoadOlder ? rawIndex - 1 : rawIndex;
              final msg = _messages[index];
              final dayLabel = _dayDividerLabel(msg.sentAtUtc);
              final showDayHeader = index == 0 ||
                  _dayDividerLabel(_messages[index - 1].sentAtUtc) != dayLabel;
              final showUnreadDivider = _roomFirstUnreadIndex != null &&
                  _roomUnreadDividerCount > 0 &&
                  index == _roomFirstUnreadIndex;
              final nextHasUnreadDivider = _roomFirstUnreadIndex != null &&
                  _roomUnreadDividerCount > 0 &&
                  (index + 1) == _roomFirstUnreadIndex;
              final isStandalone = _isHikeInviteMessage(msg);
              final sameSenderAsPrev = !isStandalone &&
                  !showDayHeader &&
                  !showUnreadDivider &&
                  index > 0 &&
                  !_isHikeInviteMessage(_messages[index - 1]) &&
                  _messages[index - 1].authorId == msg.authorId &&
                  _messages[index - 1].isOutgoing == msg.isOutgoing;
              final sameSenderAsNext = !isStandalone &&
                  !nextHasUnreadDivider &&
                  index + 1 < _messages.length &&
                  _dayDividerLabel(_messages[index + 1].sentAtUtc) ==
                      dayLabel &&
                  !_isHikeInviteMessage(_messages[index + 1]) &&
                  _messages[index + 1].authorId == msg.authorId &&
                  _messages[index + 1].isOutgoing == msg.isOutgoing;
              final cluster = ChatBubbleCluster.compute(
                sameSenderAsPrev: sameSenderAsPrev,
                sameSenderAsNext: sameSenderAsNext,
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (showDayHeader)
                    Padding(
                      padding: EdgeInsets.only(
                        top: index == 0 ? 0 : 8,
                        bottom: 10,
                      ),
                      child: Center(child: ChatDateDividerPill(label: dayLabel)),
                    ),
                  if (showUnreadDivider)
                    Padding(
                      key: _roomUnreadDividerKey,
                      padding: const EdgeInsets.only(top: 4, bottom: 10),
                      child: Center(
                        child: ChatUnreadDividerPill(
                          count: _roomUnreadDividerCount,
                        ),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.only(bottom: cluster.bottomGap),
                    child: _buildRoomBubble(
                      msg,
                      theme,
                      colors,
                      cluster: cluster,
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  MemberDirectoryEntry? _memberEntryFor(String userId) {
    for (final m in _members) {
      if (m.userId == userId) return m;
    }
    return null;
  }

  Widget _buildRoomBubble(
    ChatMessage message,
    ThemeData theme,
    HiqeoColors colors, {
    required ChatBubbleCluster cluster,
  }) {
    final outgoing = message.isOutgoing;
    final syncStatus = _messageSyncStatusById[message.messageId] ??
        (_pendingSyncMessageIds.contains(message.messageId)
            ? ChatSyncStatus.pending
            : ChatSyncStatus.sent);
    final pendingSync = syncStatus == ChatSyncStatus.pending;
    final timeStr = _formatTimeHm(message.sentAtUtc);
    final sender = _senderNameFor(message);
    final memberEntry = _memberEntryFor(message.authorId);
    final canInspectSender =
        !outgoing && message.authorId != _effectiveUserId;
    final showSenderName = !outgoing && cluster.isFirstInGroup;
    final senderColor = ChatRoomPalette.senderPastel(message.authorId);

    final isMsgDeleted = _deletedMessageIds.contains(message.messageId);
    final isMsgCancelled = _cancelledMessageIds.contains(message.messageId);
    String reportExcerpt = '';
    final Widget bubble;
    if (isMsgDeleted) {
      reportExcerpt = 'Pesan telah dihapus';
      bubble = _TextChatBubble(
        bubbleKey: ValueKey<String>('group-bubble-${message.messageId}'),
        sender: showSenderName ? sender : null,
        senderColor: senderColor,
        senderKey: canInspectSender && showSenderName
            ? ValueKey<String>('group-msg-sender-${message.messageId}')
            : null,
        onTapSender: canInspectSender
            ? () => unawaited(_onTapGroupSender(message, reportExcerpt))
            : null,
        text: 'Pesan telah dihapus',
        timeLabel: timeStr,
        outgoing: outgoing,
        cluster: cluster,
        pendingSync: pendingSync,
        syncStatus: syncStatus,
        isDeleted: true,
      );
    } else {
      switch (message.type) {
      case PacketType.text:
        final decodedText = utf8.decode(message.payload, allowMalformed: true);
        reportExcerpt = decodedText;
        final hikeInvite = GroupHikeInviteMessage.tryDecodeInvite(decodedText);
        final hikeReady = GroupHikeInviteMessage.tryDecodeReady(decodedText);
        final hikeCancel = GroupHikeInviteMessage.tryDecodeCancel(decodedText);
        if (hikeInvite != null) {
          bubble = _HikeInviteBubble(
            plan: hikeInvite,
            currentUserId: _effectiveUserId,
            timeLabel: timeStr,
            outgoing: outgoing,
            syncStatus: syncStatus,
            isCancelled: isMsgCancelled ||
                hikeInvite.isCancelled ||
                GroupHikePlanStore.instance
                    .isInviteCancelled(hikeInvite.inviteId),
            onReadyPressed: () {
              unawaited(HapticFeedback.lightImpact());
              unawaited(_confirmReadyForHikeInvite(hikeInvite));
            },
            onCancelReadyPressed: () {
              unawaited(HapticFeedback.selectionClick());
              unawaited(_cancelReadyForHikeInvite(hikeInvite));
            },
          );
        } else if (hikeCancel != null) {
          bubble = _TextChatBubble(
            bubbleKey: ValueKey<String>('group-bubble-${message.messageId}'),
            sender: showSenderName ? sender : null,
            senderColor: senderColor,
            senderKey: canInspectSender && showSenderName
                ? ValueKey<String>('group-msg-sender-${message.messageId}')
                : null,
            onTapSender: canInspectSender
                ? () => unawaited(_onTapGroupSender(message, reportExcerpt))
                : null,
            text: 'Ajakan pendakian telah dibatalkan oleh pembuatnya.',
            timeLabel: timeStr,
            outgoing: outgoing,
            cluster: cluster,
            pendingSync: pendingSync,
            syncStatus: syncStatus,
            isDeleted: true,
          );
        } else if (hikeReady != null) {
          bubble = _TextChatBubble(
            bubbleKey: ValueKey<String>('group-bubble-${message.messageId}'),
            sender: showSenderName ? sender : null,
            senderColor: senderColor,
            senderKey: canInspectSender && showSenderName
                ? ValueKey<String>('group-msg-sender-${message.messageId}')
                : null,
            onTapSender: canInspectSender
                ? () => unawaited(_onTapGroupSender(message, reportExcerpt))
                : null,
            text: '${hikeReady.userName} sudah SIAP untuk pendakian!',
            timeLabel: timeStr,
            outgoing: outgoing,
            cluster: cluster,
            pendingSync: pendingSync,
            syncStatus: syncStatus,
          );
        } else {
          bubble = _TextChatBubble(
            bubbleKey: ValueKey<String>('group-bubble-${message.messageId}'),
            sender: showSenderName ? sender : null,
            senderColor: senderColor,
            senderKey: canInspectSender && showSenderName
                ? ValueKey<String>('group-msg-sender-${message.messageId}')
                : null,
            onTapSender: canInspectSender
                ? () => unawaited(_onTapGroupSender(message, reportExcerpt))
                : null,
            text: decodedText,
            timeLabel: timeStr,
            outgoing: outgoing,
            cluster: cluster,
            pendingSync: pendingSync,
            syncStatus: syncStatus,
          );
        }
      case PacketType.voiceFragment:
        final voice = VoiceNoteData.fromBytes(message.payload);
        reportExcerpt = '[Pesan suara ${voice.formattedDuration}]';
        final isPlaying = _playingMessageId == message.messageId;
        bubble = _VoiceNoteBubble(
          buttonKey: ValueKey<String>('voice-play-${message.messageId}'),
          sender: showSenderName ? sender : null,
          senderColor: senderColor,
          senderKey: canInspectSender && showSenderName
              ? ValueKey<String>('group-msg-sender-${message.messageId}')
              : null,
          onTapSender: canInspectSender
              ? () => unawaited(_onTapGroupSender(message, reportExcerpt))
              : null,
          voice: voice,
          timeLabel: timeStr,
          outgoing: outgoing,
          cluster: cluster,
          pendingSync: pendingSync,
          isPlaying: isPlaying,
          progress: isPlaying ? _playingProgress : 0.0,
          onTogglePlay: () => _toggleVoicePlayback(
            message.messageId,
            voice,
          ),
        );
      case PacketType.location:
        LocationPayload? loc;
        try {
          loc = LocationPayload.fromBytes(message.payload);
        } catch (_) {}
        reportExcerpt = '[Lokasi]';
        bubble = GestureDetector(
          onTap: _openLastLocation,
          child: _LocationChatBubble(
            title: outgoing
                ? 'Kamu membagikan lokasi'
                : '$sender membagikan lokasi',
            subtitle: loc == null
                ? 'Ketuk untuk lihat lokasi terakhir'
                : '±${loc.accuracyM} m · ${formatDecimal(LatLng(loc.lat, loc.lon))}',
            timeLabel: timeStr,
            outgoing: outgoing,
            cluster: cluster,
            pendingSync: pendingSync,
          ),
        );
      default:
        reportExcerpt = 'Pesan diterima.';
        bubble = _TextChatBubble(
          bubbleKey: ValueKey<String>('group-bubble-${message.messageId}'),
          sender: showSenderName ? sender : null,
          senderColor: senderColor,
          senderKey: canInspectSender && showSenderName
              ? ValueKey<String>('group-msg-sender-${message.messageId}')
              : null,
          onTapSender: canInspectSender
              ? () => unawaited(_onTapGroupSender(message, reportExcerpt))
              : null,
          text: 'Pesan diterima.',
          timeLabel: timeStr,
          outgoing: outgoing,
          cluster: cluster,
          pendingSync: pendingSync,
        );
      }
    }

    if (canInspectSender) {
      final showAvatar = cluster.isLastInGroup;
      return Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          ChatSenderAvatarSlot(
            visible: showAvatar,
            senderId: message.authorId,
            senderName: sender,
            avatarUrl: memberEntry?.avatarUrl,
            avatarKey: showAvatar
                ? ValueKey<String>('group-msg-avatar-${message.messageId}')
                : null,
            onTap: showAvatar
                ? () => unawaited(_onTapGroupSender(message, reportExcerpt))
                : null,
          ),
          Flexible(child: bubble),
        ],
      );
    }

    final Widget interactiveBubble = (outgoing && !isMsgDeleted)
        ? GestureDetector(
            behavior: HitTestBehavior.translucent,
            onLongPress: () => unawaited(_showOwnGroupMessageActions(message)),
            child: bubble,
          )
        : bubble;

    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: interactiveBubble,
    );
  }

  Future<void> _showOwnGroupMessageActions(ChatMessage message) async {
    unawaited(HapticFeedback.mediumImpact());
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) {
        final safeBottom = MediaQuery.paddingOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + safeBottom),
          child: HiqeoLiquidGlassSurface(
            key: const ValueKey<String>('group-own-msg-sheet'),
            borderRadius: 24,
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ChatRoomPalette.textSecondary.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  key: const ValueKey<String>('group-msg-action-delete'),
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: ChatRoomPalette.destructiveRed,
                  ),
                  title: const Text(
                    'Hapus pesan',
                    style: TextStyle(
                      color: ChatRoomPalette.destructiveRed,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () => Navigator.of(ctx).pop('delete'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (action != 'delete' || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey<String>('group-msg-delete-dialog'),
        title: const Text('Hapus pesan?'),
        content: const Text(
          'Pesan ini akan dihapus untuk semua anggota grup.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const ValueKey<String>('group-msg-delete-confirm-btn'),
            style: FilledButton.styleFrom(
              backgroundColor: ChatRoomPalette.destructiveRed,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final groupId = _activeGroup?.group.id ?? message.groupId;
    final clientMsgId =
        _clientMsgIdByMessageId[message.messageId] ?? message.messageId;
    setState(() => _deletedMessageIds.add(message.messageId));
    await _localStore?.markMessageDeleted(
      groupId: groupId,
      clientMsgId: clientMsgId,
    );
    if (_isOnline && _chatRemote != null && isValidUuid(groupId)) {
      try {
        await _chatRemote!.softDeleteMessage(
          groupId: groupId,
          clientMsgId: clientMsgId,
        );
      } catch (_) {}
    }
  }

  /// Modal profil pengirim di Ruang Obrolan Grup:
  /// 1) "Tambahkan teman" (tampilkan status bila sudah berteman / menunggu)
  /// 2) "Laporkan pesan" (simpan ke `moderation_reports` developer)
  Future<void> _onTapGroupSender(
    ChatMessage message,
    String messageExcerpt,
  ) async {
    final senderId = message.authorId;
    if (senderId == _effectiveUserId) return;
    final colors = HiqeoColors.of(context);
    final senderName = _senderNameFor(message);
    final member = _memberEntryFor(senderId);
    final cache = PublicProfileCacheService.instance;
    final resolvedName = cache.resolveDisplayName(
      senderId,
      fallback: member?.displayName?.trim().isNotEmpty == true
          ? member!.displayName!.trim()
          : senderName,
    );
    final resolvedUsername = cache.resolveUsername(
      senderId,
      fallback: member?.username,
    );
    final resolvedAvatar = cache.resolveAvatarUrl(
      senderId,
      fallback: member?.avatarUrl,
    );
    final relation = FriendsService.instance.relationshipStatusFor(senderId);
    final incomingReq = FriendsService.instance.incomingRequestFrom(senderId);

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) {
        final safeBottom = MediaQuery.paddingOf(ctx).bottom;
        final initial =
            resolvedName.isNotEmpty ? resolvedName[0].toUpperCase() : '?';
        final fallbackAvatar = Center(
          child: Text(
            initial,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        );
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + safeBottom),
          child: HiqeoLiquidGlassSurface(
            key: const ValueKey<String>('group-sender-action-sheet'),
            borderRadius: 28,
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textSecondary.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: <Widget>[
                      PersistentAvatarImage(
                        cacheKey: senderId,
                        avatarUrl: resolvedAvatar,
                        size: 40,
                        backgroundColor: colors.hairline,
                        fallback: fallbackAvatar,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              resolvedName,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                            ),
                            if (resolvedUsername != null &&
                                resolvedUsername.isNotEmpty)
                              Text(
                                '@$resolvedUsername',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: colors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(color: colors.hairline, height: 1),
                ListTile(
                  key: const ValueKey<String>('group-sender-add-friend'),
                  leading: Icon(
                    relation == 'friend'
                        ? Icons.check_circle_outline_rounded
                        : Icons.person_add_alt_1_rounded,
                    color: relation == 'friend'
                        ? colors.textSecondary
                        : colors.primary,
                  ),
                  title: Text(
                    relation == 'friend'
                        ? 'Sudah berteman'
                        : (relation == 'outgoing'
                            ? 'Permintaan terkirim'
                            : (relation == 'incoming'
                                ? 'Terima permintaan teman'
                                : 'Tambahkan teman')),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  enabled: relation == null || relation == 'incoming',
                  onTap: (relation == null || relation == 'incoming')
                      ? () => Navigator.of(ctx).pop(
                            relation == 'incoming'
                                ? 'accept_friend'
                                : 'add_friend',
                          )
                      : null,
                ),
                ListTile(
                  key: const ValueKey<String>('group-sender-report-message'),
                  leading: Icon(Icons.flag_outlined, color: colors.warningText),
                  title: Text(
                    'Laporkan pesan',
                    style: TextStyle(
                      color: colors.warningText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () => Navigator.of(ctx).pop('report_message'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    if (action == 'add_friend') {
      try {
        if (widget.onSendFriendRequest != null) {
          await widget.onSendFriendRequest!(senderId);
        } else {
          await FriendsService.instance.sendFriendRequest(senderId);
        }
        if (mounted) {
          _showNotice('Permintaan pertemanan dikirim ke $senderName.');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('ChatPage addFriend failed: $e');
        }
        if (mounted) {
          _showNotice(
            e is StateError
                ? e.message
                : 'Permintaan teman belum terkirim. Periksa sinyal lalu coba lagi.',
          );
        }
      }
    } else if (action == 'accept_friend' && incomingReq != null) {
      try {
        await FriendsService.instance.respondToRequest(
          incomingReq.friendshipId,
          accept: true,
        );
        if (mounted) {
          _showNotice('Sekarang kamu berteman dengan $senderName.');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('ChatPage acceptFriend failed: $e');
        }
        if (mounted) {
          _showNotice('Belum bisa menerima permintaan. Periksa sinyal lalu coba lagi.');
        }
      }
    } else if (action == 'report_message') {
      await _showReportGroupMessageDialog(
        message: message,
        senderName: senderName,
        excerpt: messageExcerpt,
      );
    }
  }

  Future<void> _showReportGroupMessageDialog({
    required ChatMessage message,
    required String senderName,
    required String excerpt,
  }) async {
    final groupId = _activeGroup?.group.id ?? message.groupId;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (_) => _GroupReportDialog(
        senderName: senderName,
        onSubmit: (reason, details) async {
          if (widget.onSubmitMessageReport != null) {
            await widget.onSubmitMessageReport!(
              groupId: groupId,
              messageId: message.messageId,
              reportedUserId: message.authorId,
              reason: reason,
              details: details,
              excerpt: excerpt,
            );
          } else {
            await ModerationService.instance.submitReport(
              targetType: ModerationTargetType.groupMessage,
              targetId: message.messageId,
              groupId: groupId,
              reportedUserId: message.authorId,
              reason: reason,
              details: details,
              messageExcerpt: excerpt,
            );
          }
        },
      ),
    );
    if (submitted == true && mounted) {
      _showNotice('Laporan dikirim ke tim moderasi.');
    }
  }

  /// Memperbarui kesiapan anggota pada baris `group_hike_prep` yang SAMA dan
  /// mengunci gunung+grup di Siapkan Pendakian TANPA mengirim ulang tombol Siap.
  Future<void> _confirmReadyForHikeInvite(GroupHikePlan plan) async {
    await GroupHikePlanStore.instance.markReadyRemote(plan, _effectiveUserId);
    if (mounted) {
      setState(() {});
      _showNotice(
        'Kamu siap mendaki ${plan.mountainName} bersama ${plan.groupName}. '
        'Gunung & grup telah dikunci di Siapkan Pendakian.',
      );
    }
  }

  Future<void> _cancelReadyForHikeInvite(GroupHikePlan plan) async {
    await GroupHikePlanStore.instance
        .unmarkReadyRemote(plan, _effectiveUserId);
    if (mounted) {
      setState(() {});
      _showNotice('Status siap untuk pendakian ${plan.mountainName} dibatalkan.');
    }
  }

  Widget _buildComposer(
    ThemeData theme,
    HiqeoColors colors,
  ) {
    final hasText = _input.text.trim().isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: HiqeoLiquidGlassSurface(
            key: const ValueKey<String>('chat-composer-pill'),
            borderRadius: 26,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 50),
              child: Center(
                child: TextField(
                  key: const ValueKey<String>('chat-input'),
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => unawaited(_sendText()),
                  style: const TextStyle(
                    fontSize: 14.5,
                    color: ChatRoomPalette.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Tulis pesan…',
                    hintStyle: TextStyle(
                      color: ChatRoomPalette.textSecondary,
                      fontSize: 14,
                    ),
                    counterText: '',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        HiqeoGlassCircleButton(
          key: const ValueKey<String>('chat-send'),
          semanticsLabel: 'Kirim pesan',
          size: 50,
          emphasized: hasText,
          onTap: (!hasText || _sending) ? null : () => unawaited(_sendText()),
          child: _sending
              ? const Padding(
                  padding: EdgeInsets.all(13),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: ChatRoomPalette.textPrimary,
                  ),
                )
              : Icon(
                  Icons.send_rounded,
                  size: 20,
                  color: hasText
                      ? ChatRoomPalette.textPrimary
                      : ChatRoomPalette.textSecondary,
                ),
        ),
      ],
    );
  }
}

// =============================================================================
// KOMPONEN PENDUKUNG HALAMAN GRUP & RUANG OBROLAN
// =============================================================================

class _GroupReportDialog extends StatefulWidget {
  const _GroupReportDialog({
    required this.senderName,
    required this.onSubmit,
  });

  final String senderName;
  final Future<void> Function(String reason, String details) onSubmit;

  @override
  State<_GroupReportDialog> createState() => _GroupReportDialogState();
}

class _GroupReportDialogState extends State<_GroupReportDialog> {
  final TextEditingController _detailsCtrl = TextEditingController();
  String _selectedReason = ModerationService.defaultReasons.first;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _detailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_selectedReason, _detailsCtrl.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ChatPage._GroupReportDialog failed: $e');
      }
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Laporan belum terkirim. Periksa sinyal lalu coba lagi.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return AlertDialog(
      title: const Text('Laporkan pesan'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Laporkan pesan dari ${widget.senderName} ke tim moderasi.',
              style: const TextStyle(fontSize: 13.5),
            ),
            const SizedBox(height: 12),
            for (final reason in ModerationService.defaultReasons)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _submitting
                    ? null
                    : () => setState(() => _selectedReason = reason),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        _selectedReason == reason
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        size: 20,
                        color: _selectedReason == reason
                            ? colors.primary
                            : colors.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          reason,
                          style: const TextStyle(fontSize: 13.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _detailsCtrl,
              maxLines: 2,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Detail tambahan (opsional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(fontSize: 12, color: colors.warningText),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          key: const ValueKey<String>('group-report-submit-btn'),
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Mengirim…' : 'Kirim laporan'),
        ),
      ],
    );
  }
}

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({
    required this.invitation,
    required this.onReject,
    required this.onAccept,
  });

  final IncomingInvitation invitation;
  final VoidCallback onReject;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return GlassSurface(
      tier: GlassTier.card,
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            invitation.groupName,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Diundang oleh @${invitation.inviterUsername}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: HiqeoSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Tolak undangan ${invitation.groupName}',
                  child: GestureDetector(
                    key: ValueKey<String>('inv-reject-${invitation.id}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onReject,
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: colors.secondary.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                      ),
                      child: Center(
                        child: Text(
                          'Tolak',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: HiqeoSpacing.md),
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Terima undangan ${invitation.groupName}',
                  child: GestureDetector(
                    key: ValueKey<String>('inv-accept-${invitation.id}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onAccept,
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                      ),
                      child: Center(
                        child: Text(
                          'Terima',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colors.onPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GroupListCard extends StatelessWidget {
  const _GroupListCard({
    super.key,
    required this.card,
    required this.onTap,
  });

  final GroupCardData card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final subtitle = '${card.memberCount} anggota';

    return Semantics(
      button: true,
      label: '${card.group.name}. $subtitle',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: GlassSurface(
          tier: GlassTier.card,
          borderRadius: 24,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  PersistentAvatarImage(
                    cacheKey: 'group_${card.group.id}',
                    avatarUrl: card.group.avatarUrl,
                    size: 46,
                    resolveFromProfileCache: false,
                    backgroundColor: colors.hairline,
                    fallback: Icon(
                      Icons.terrain_rounded,
                      size: 22,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          card.group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        if (card.lastMessageSnippet != null &&
                            card.lastMessageSnippet!.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 4),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  card.lastMessageSnippet!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: card.hasUnread
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color: card.hasUnread
                                        ? colors.textPrimary
                                        : colors.textSecondary,
                                  ),
                                ),
                              ),
                              if (card.lastMessageAtUtc != null) ...<Widget>[
                                const SizedBox(width: 6),
                                Text(
                                  formatSocialTimeShort(card.lastMessageAtUtc!),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (card.unreadCount > 0) ...<Widget>[
                    const SizedBox(width: HiqeoSpacing.md),
                    Container(
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.primary,
                      ),
                      child: Center(
                        child: Text(
                          '${card.unreadCount}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ] else if (card.hasUnread) ...<Widget>[
                    const SizedBox(width: HiqeoSpacing.md),
                    Container(
                      key: ValueKey<String>(
                        'group-unread-dot-${card.group.id}',
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Pesan baru',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              () {
                final readinessLabel = formatGroupReadinessBadge(
                  hasActiveInvite: card.hasActiveHikeInvite,
                  readyCount: card.readyCount,
                  memberCount: card.memberCount,
                );
                final pills = <Widget>[
                  if (readinessLabel != null)
                    _StatusPill(
                      label: readinessLabel,
                      colors: colors,
                      theme: theme,
                    ),
                  if (card.locationShared)
                    _StatusPill(
                      label: 'Lokasi dibagikan',
                      colors: colors,
                      theme: theme,
                    ),
                  if (card.pendingSync)
                    _StatusPill(
                      label: 'Tersimpan lokal',
                      colors: colors,
                      theme: theme,
                    ),
                ];
                if (pills.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: HiqeoSpacing.md),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: pills,
                  ),
                );
              }(),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.colors,
    required this.theme,
  });

  final String label;
  final HiqeoColors colors;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.secondary.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(HiqeoRadius.pill),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _HikeInviteBubble extends StatelessWidget {
  const _HikeInviteBubble({
    required this.plan,
    required this.currentUserId,
    required this.timeLabel,
    required this.outgoing,
    required this.syncStatus,
    this.isCancelled = false,
    required this.onReadyPressed,
    this.onCancelReadyPressed,
  });

  final GroupHikePlan plan;
  final String currentUserId;
  final String timeLabel;
  final bool outgoing;
  final ChatSyncStatus syncStatus;
  final bool isCancelled;
  final VoidCallback onReadyPressed;
  final VoidCallback? onCancelReadyPressed;

  @override
  Widget build(BuildContext context) {
    final fg =
        outgoing ? ChatRoomPalette.outgoingText : ChatRoomPalette.incomingText;
    final metaFg =
        outgoing ? ChatRoomPalette.outgoingMeta : ChatRoomPalette.incomingMeta;
    final activePlan =
        GroupHikePlanStore.instance.activePlanForGroup(plan.groupId) ??
            GroupHikePlanStore.instance.activePlan;
    final livePlan = (activePlan != null &&
            (activePlan.groupId == plan.groupId ||
                activePlan.inviteId == plan.inviteId))
        ? activePlan
        : plan;
    final effectiveCancelled = isCancelled ||
        livePlan.isCancelled ||
        GroupHikePlanStore.instance.isInviteCancelled(livePlan.inviteId);
    final readyCount = livePlan.readyUserIds.length;
    final totalMembers = math.max(livePlan.memberCount, readyCount);
    final progress =
        totalMembers > 0 ? (readyCount / totalMembers).clamp(0.0, 1.0) : 0.0;
    final isAlreadyReady = livePlan.readyUserIds.contains(currentUserId);
    final chipBg = outgoing
        ? ChatRoomPalette.outgoingText.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.10);
    final trackBg = outgoing
        ? ChatRoomPalette.outgoingText.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.14);
    final progressColor = effectiveCancelled
        ? ChatRoomPalette.destructiveRed.withValues(alpha: 0.7)
        : (isAlreadyReady || progress >= 1.0
            ? const Color(0xFF22C55E)
            : (outgoing
                ? const Color(0xFF1D2436)
                : ChatRoomPalette.statusOnline));

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      ),
      child: DecoratedBox(
        decoration: chatBubbleDecoration(
          outgoing: outgoing,
          cluster: const ChatBubbleCluster(
            isFirstInGroup: true,
            isLastInGroup: true,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: effectiveCancelled
                          ? ChatRoomPalette.destructiveRed.withValues(alpha: 0.16)
                          : chipBg,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      effectiveCancelled
                          ? Icons.cancel_outlined
                          : Icons.terrain_rounded,
                      size: 16,
                      color: effectiveCancelled
                          ? ChatRoomPalette.destructiveRed
                          : fg,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      effectiveCancelled
                          ? 'AJAKAN DIBATALKAN'
                          : 'AJAKAN PENDAKIAN',
                      style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 0.7,
                        color: effectiveCancelled
                            ? ChatRoomPalette.destructiveRed
                            : metaFg,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      effectiveCancelled
                          ? 'Undangan dibatalkan'
                          : (livePlan.isStarted
                              ? 'Pendakian berlangsung'
                              : (formatGroupReadinessBadge(
                                    hasActiveInvite: true,
                                    readyCount: readyCount,
                                    memberCount: totalMembers,
                                  ) ??
                                  '$readyCount/$totalMembers siap')),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: effectiveCancelled ? metaFg : fg,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                plan.trailName != null && plan.trailName!.isNotEmpty
                    ? '${plan.mountainName} · ${plan.trailName}'
                    : plan.mountainName,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: effectiveCancelled ? metaFg : fg,
                  decoration: effectiveCancelled
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                effectiveCancelled
                    ? 'Ajakan pendakian oleh ${plan.organizerName} telah dibatalkan.'
                    : 'Diajak oleh ${plan.organizerName}. Konfirmasi kesiapanmu untuk mengunci rencana pendakian.',
                style: TextStyle(
                  fontSize: 12.2,
                  color: metaFg,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 11),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    'Kesiapan anggota',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: metaFg,
                    ),
                  ),
                  Text(
                    '${(progress * 100).round()}%',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: fg,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  key: ValueKey<String>('hike-invite-progress-${plan.inviteId}'),
                  value: effectiveCancelled ? 0.0 : progress,
                  minHeight: 7,
                  backgroundColor: trackBg,
                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                ),
              ),
              const SizedBox(height: 12),
              if (effectiveCancelled)
                Container(
                  key: ValueKey<String>(
                    'hike-invite-cancelled-${plan.inviteId}',
                  ),
                  width: double.infinity,
                  height: 42,
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: ChatRoomPalette.destructiveRed.withValues(
                        alpha: 0.35,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const Icon(
                          Icons.block_rounded,
                          size: 16,
                          color: ChatRoomPalette.destructiveRed,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Undangan dibatalkan',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: metaFg,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (livePlan.isStarted)
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton.icon(
                    key: ValueKey<String>(
                      'hike-invite-open-map-${plan.inviteId}',
                    ),
                    onPressed: () {
                      final router = GoRouter.maybeOf(context);
                      if (router != null) {
                        openGroupHikeMapFromPlan(router, livePlan);
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: outgoing
                          ? ChatRoomPalette.outgoingText
                          : ChatRoomPalette.outgoingFill,
                      foregroundColor: outgoing
                          ? ChatRoomPalette.outgoingFill
                          : ChatRoomPalette.outgoingText,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    icon: const Icon(Icons.map_rounded, size: 17),
                    label: const Text('Buka peta jalur'),
                  ),
                )
              else ...<Widget>[
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton(
                    key: ValueKey<String>(
                      'hike-invite-ready-${plan.inviteId}',
                    ),
                    onPressed: isAlreadyReady ? null : onReadyPressed,
                    style: FilledButton.styleFrom(
                      backgroundColor: outgoing
                          ? ChatRoomPalette.outgoingText
                          : ChatRoomPalette.outgoingFill,
                      foregroundColor: outgoing
                          ? ChatRoomPalette.outgoingFill
                          : ChatRoomPalette.outgoingText,
                      disabledBackgroundColor: isAlreadyReady
                          ? const Color(0xFF22C55E).withValues(alpha: 0.22)
                          : chipBg,
                      disabledForegroundColor: isAlreadyReady
                          ? (outgoing
                              ? const Color(0xFF15803D)
                              : const Color(0xFF86EFAC))
                          : metaFg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(isAlreadyReady ? 'Sudah Siap ✓' : 'Saya Siap'),
                  ),
                ),
                if (isAlreadyReady &&
                    livePlan.organizerUserId != currentUserId &&
                    onCancelReadyPressed != null)
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      key: ValueKey<String>(
                        'hike-invite-unready-${plan.inviteId}',
                      ),
                      onPressed: onCancelReadyPressed,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 40),
                        foregroundColor: metaFg,
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Batalkan siap'),
                    ),
                  ),
              ],
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: _BubbleMetaStatus(
                  timeLabel: timeLabel,
                  outgoing: outgoing,
                  pendingSync: syncStatus == ChatSyncStatus.pending,
                  syncStatus: syncStatus,
                  color: metaFg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextChatBubble extends StatelessWidget {
  const _TextChatBubble({
    this.bubbleKey,
    this.sender,
    this.senderColor,
    this.senderKey,
    this.onTapSender,
    required this.text,
    required this.timeLabel,
    required this.outgoing,
    required this.cluster,
    this.pendingSync = false,
    this.syncStatus,
    this.isDeleted = false,
  });

  final Key? bubbleKey;
  final String? sender;
  final Color? senderColor;
  final Key? senderKey;
  final VoidCallback? onTapSender;
  final String text;
  final String timeLabel;
  final bool outgoing;
  final ChatBubbleCluster cluster;
  final bool pendingSync;
  final ChatSyncStatus? syncStatus;
  final bool isDeleted;

  @override
  Widget build(BuildContext context) {
    final fg =
        outgoing ? ChatRoomPalette.outgoingText : ChatRoomPalette.incomingText;
    final metaFg =
        outgoing ? ChatRoomPalette.outgoingMeta : ChatRoomPalette.incomingMeta;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.76,
      ),
      child: DecoratedBox(
        key: bubbleKey,
        decoration: chatBubbleDecoration(outgoing: outgoing, cluster: cluster),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 9, 13, 8),
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (sender != null) ...<Widget>[
                  GestureDetector(
                    key: senderKey,
                    behavior: HitTestBehavior.opaque,
                    onTap: onTapSender,
                    child: Text(
                      sender!,
                      style: TextStyle(
                        fontSize: 12,
                        color: senderColor ?? ChatRoomPalette.badgeE2eeText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                ],
                Text(
                  text,
                  style: TextStyle(
                    fontSize: isDeleted ? 13.5 : 14.2,
                    fontStyle:
                        isDeleted ? FontStyle.italic : FontStyle.normal,
                    color: isDeleted ? metaFg : fg,
                    height: 1.38,
                  ),
                ),
                const SizedBox(height: 3),
                Align(
                  alignment: Alignment.centerRight,
                  child: _BubbleMetaStatus(
                    timeLabel: timeLabel,
                    outgoing: outgoing,
                    pendingSync: pendingSync,
                    syncStatus: syncStatus,
                    color: metaFg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceNoteBubble extends StatelessWidget {
  const _VoiceNoteBubble({
    required this.buttonKey,
    this.sender,
    this.senderColor,
    this.senderKey,
    this.onTapSender,
    required this.voice,
    required this.timeLabel,
    required this.outgoing,
    required this.cluster,
    required this.pendingSync,
    required this.isPlaying,
    required this.progress,
    required this.onTogglePlay,
  });

  final Key buttonKey;
  final String? sender;
  final Color? senderColor;
  final Key? senderKey;
  final VoidCallback? onTapSender;
  final VoiceNoteData voice;
  final String timeLabel;
  final bool outgoing;
  final ChatBubbleCluster cluster;
  final bool pendingSync;
  final bool isPlaying;
  final double progress;
  final VoidCallback onTogglePlay;

  @override
  Widget build(BuildContext context) {
    final fg =
        outgoing ? ChatRoomPalette.outgoingText : ChatRoomPalette.incomingText;
    final metaFg =
        outgoing ? ChatRoomPalette.outgoingMeta : ChatRoomPalette.incomingMeta;
    final mutedWave = fg.withValues(alpha: 0.32);

    return Container(
      width: MediaQuery.sizeOf(context).width * 0.70,
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 8),
      decoration: chatBubbleDecoration(outgoing: outgoing, cluster: cluster),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (sender != null) ...<Widget>[
            GestureDetector(
              key: senderKey,
              behavior: HitTestBehavior.opaque,
              onTap: onTapSender,
              child: Text(
                sender!,
                style: TextStyle(
                  fontSize: 12,
                  color: senderColor ?? ChatRoomPalette.badgeE2eeText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: <Widget>[
              Semantics(
                button: true,
                label: isPlaying ? 'Jeda pesan suara' : 'Putar pesan suara',
                child: GestureDetector(
                  key: buttonKey,
                  behavior: HitTestBehavior.opaque,
                  onTap: onTogglePlay,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: fg.withValues(alpha: 0.14),
                    ),
                    child: Center(
                      child: HiqeoIcon(
                        isPlaying ? HiqeoIcons.pause : HiqeoIcons.play,
                        size: 16,
                        color: fg,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 24,
                  child: CustomPaint(
                    painter: _WaveformPainter(
                      peaks: voice.peaks,
                      progress: progress,
                      activeColor: fg,
                      inactiveColor: mutedWave,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                voice.formattedDuration,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: _BubbleMetaStatus(
              timeLabel: timeLabel,
              outgoing: outgoing,
              pendingSync: pendingSync,
              color: metaFg,
            ),
          ),
        ],
      ),
    );
  }
}

class _BubbleMetaStatus extends StatelessWidget {
  const _BubbleMetaStatus({
    required this.timeLabel,
    required this.outgoing,
    required this.pendingSync,
    this.syncStatus,
    required this.color,
  });

  final String timeLabel;
  final bool outgoing;
  final bool pendingSync;
  final ChatSyncStatus? syncStatus;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final effectiveStatus = syncStatus ??
        (pendingSync ? ChatSyncStatus.pending : ChatSyncStatus.sent);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          timeLabel,
          style: TextStyle(
            color: color,
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (outgoing) ...<Widget>[
          const SizedBox(width: 4),
          switch (effectiveStatus) {
            ChatSyncStatus.sent => const Icon(
                Icons.done_all_rounded,
                key: ValueKey<String>('bubble-status-sent'),
                size: 14,
                color: ChatRoomPalette.outgoingCheck,
              ),
            ChatSyncStatus.meshDelivered => const Icon(
                Icons.done_rounded,
                key: ValueKey<String>('bubble-status-mesh'),
                size: 14,
                color: ChatRoomPalette.outgoingMeshCheck,
              ),
            ChatSyncStatus.pending => Icon(
                Icons.schedule_rounded,
                key: const ValueKey<String>('bubble-status-queued'),
                size: 13,
                color: color,
              ),
          },
        ],
      ],
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.peaks,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  final List<double> peaks;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty || size.width <= 0) return;
    const barCount = 14;
    final step = size.width / barCount;
    final barWidth = (step * 0.48).clamp(1.8, 3.2);
    final midY = size.height / 2;

    for (var i = 0; i < barCount; i++) {
      final frac = i / barCount;
      final peak = peaks[(i * peaks.length) ~/ barCount];
      final isActive = progress > 0 && frac <= progress;
      final paint = Paint()
        ..color = (progress > 0 && !isActive) ? inactiveColor : activeColor
        ..strokeWidth = barWidth
        ..strokeCap = StrokeCap.round;
      final x = i * step + step / 2;
      final halfH = (size.height * 0.46) * peak;
      canvas.drawLine(Offset(x, midY - halfH), Offset(x, midY + halfH), paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.inactiveColor != inactiveColor;
}

class _LocationChatBubble extends StatelessWidget {
  const _LocationChatBubble({
    required this.title,
    required this.subtitle,
    required this.timeLabel,
    required this.outgoing,
    required this.cluster,
    required this.pendingSync,
  });

  final String title;
  final String subtitle;
  final String timeLabel;
  final bool outgoing;
  final ChatBubbleCluster cluster;
  final bool pendingSync;

  @override
  Widget build(BuildContext context) {
    final fg =
        outgoing ? ChatRoomPalette.outgoingText : ChatRoomPalette.incomingText;
    final secondary =
        outgoing ? ChatRoomPalette.outgoingMeta : ChatRoomPalette.incomingMeta;

    return Container(
      width: MediaQuery.sizeOf(context).width * 0.72,
      padding: const EdgeInsets.all(12),
      decoration: chatBubbleDecoration(outgoing: outgoing, cluster: cluster),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              HiqeoIcon(HiqeoIcons.pin, size: 18, color: fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: secondary),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: _BubbleMetaStatus(
              timeLabel: timeLabel,
              outgoing: outgoing,
              pendingSync: pendingSync,
              color: secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetFieldContainer extends StatelessWidget {
  const _SheetFieldContainer({
    required this.colors,
    required this.child,
  });

  final HiqeoColors colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.hairline),
      ),
      child: child,
    );
  }
}

class _CreateGroupSheet extends StatefulWidget {
  const _CreateGroupSheet({
    required this.onSubmit,
  });

  final Future<({bool ok, String? error})> Function({
    required String name,
    File? avatarFile,
  }) onSubmit;

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final TextEditingController _nameController = TextEditingController();
  File? _avatarFile;
  bool _submitting = false;
  String? _validationError;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (picked != null && mounted) {
      setState(() => _avatarFile = File(picked.path));
    }
  }

  Future<void> _handleSubmit() async {
    final groupName = _nameController.text.trim();
    if (groupName.isEmpty) {
      setState(() {
        _validationError = 'Nama grup wajib diisi.';
      });
      return;
    }
    setState(() {
      _validationError = null;
      _submitting = true;
    });
    final res = await widget.onSubmit(
      name: groupName,
      avatarFile: _avatarFile,
    );
    if (!mounted) return;
    if (res.ok) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _submitting = false;
      _validationError = res.error ?? 'Gagal membuat grup.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final viewInsetsBottom = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final hintStyle = theme.textTheme.bodyMedium?.copyWith(
      color: colors.textSecondary.withValues(alpha: 0.65),
      fontWeight: FontWeight.w500,
    );

    return PopScope(
      canPop: !_submitting,
      child: AnimatedPadding(
        key: const ValueKey<String>('create-group-sheet-animated-padding'),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: viewInsetsBottom),
        child: GlassSurface(
          key: const ValueKey<String>('create-group-sheet-card'),
          tier: GlassTier.panel,
          borderRadius: 28,
          padding: EdgeInsets.fromLTRB(20, 10, 20, 24 + safeBottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.textSecondary.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Buat grup baru',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: HiqeoSpacing.lg),

                Center(
                  child: Semantics(
                    button: true,
                    label: 'Pilih foto profil grup',
                    child: GestureDetector(
                      key: const ValueKey<String>('create-group-avatar-picker'),
                      onTap: _submitting ? null : _pickAvatar,
                      child: Column(
                        children: <Widget>[
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: colors.hairline,
                            backgroundImage: _avatarFile != null
                                ? FileImage(_avatarFile!)
                                : null,
                            child: _avatarFile == null
                                ? Icon(
                                    Icons.add_a_photo_outlined,
                                    size: 28,
                                    color: colors.textPrimary,
                                  )
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _avatarFile == null
                                ? 'Pilih foto profil grup (opsional)'
                                : 'Ganti foto profil grup',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: HiqeoSpacing.lg),

                _SheetFieldContainer(
                  colors: colors,
                  child: Row(
                    children: <Widget>[
                      Text(
                        'Nama grup',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          key: const ValueKey<String>(
                            'create-group-name-input',
                          ),
                          controller: _nameController,
                          enabled: !_submitting,
                          maxLength: 60,
                          textAlign: TextAlign.right,
                          textCapitalization: TextCapitalization.words,
                          onChanged: (_) {
                            if (_validationError != null) {
                              setState(() => _validationError = null);
                            }
                          },
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Masukkan nama grup',
                            hintStyle: hintStyle,
                            counterText: '',
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_submitting) ...<Widget>[
                  const SizedBox(height: HiqeoSpacing.md),
                  Row(
                    key: const ValueKey<String>('create-group-loading-notice'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Sedang membuat grup...',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
                if (_validationError != null) ...<Widget>[
                  const SizedBox(height: HiqeoSpacing.sm),
                  Text(
                    _validationError!,
                    key: const ValueKey<String>('create-group-validation-error'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.warningText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: HiqeoSpacing.lg),

                HiqeoButton(
                  key: const ValueKey<String>('create-group-submit-btn'),
                  label: _submitting ? 'Membuat…' : 'Buat grup',
                  onPressed: _submitting ? null : _handleSubmit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddMemberDialog extends StatefulWidget {
  const _AddMemberDialog();

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  final TextEditingController _usernameController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return AlertDialog(
      backgroundColor: colors.surface,
      title: const Text('Tambah anggota'),
      content: TextField(
        key: const ValueKey<String>('add-member-username-input'),
        controller: _usernameController,
        autofocus: true,
        maxLength: 21,
        decoration: const InputDecoration(
          hintText: 'Masukkan @username teman',
          prefixText: '@',
          counterText: '',
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          key: const ValueKey<String>('add-member-confirm-btn'),
          onPressed: () =>
              Navigator.of(context).pop(_usernameController.text.trim()),
          child: const Text('Undang'),
        ),
      ],
    );
  }
}
