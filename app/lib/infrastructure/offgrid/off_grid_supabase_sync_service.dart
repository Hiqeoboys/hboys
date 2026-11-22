import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../features/chat/domain/group_chat_models.dart';
import '../../features/chat/domain/group_chat_remote_service.dart';
import 'mesh_router_service.dart';
import 'off_grid_chat_local_store.dart';

/// Layanan sinkronisasi otomatis dua arah antara [OffGridChatLocalStore]
/// (single source of truth lokal) dan Supabase (`group_messages`,
/// `member_locations`, serta bucket `chat-voice-notes`).
class OffGridSupabaseSyncService {
  OffGridSupabaseSyncService({
    required OffGridChatLocalStore localStore,
    GroupChatRemoteService? remoteService,
    MeshRouterService? meshRouter,
  })  : _localStore = localStore,
        _remote = remoteService,
        _meshRouter = meshRouter;

  final OffGridChatLocalStore _localStore;
  final GroupChatRemoteService? _remote;
  final MeshRouterService? _meshRouter;

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  StreamSubscription<List<GroupMessageRecord>>? _remoteMsgSub;
  StreamSubscription<List<MemberLastLocation>>? _remoteLocSub;

  String? _subscribedGroupId;
  int _groupSubGeneration = 0;
  int _locSubGeneration = 0;
  bool _syncing = false;
  bool _resyncQueued = false;
  String? _queuedGroupId;
  int _retryAttempt = 0;
  Timer? _retryTimer;

  static const Duration _remoteTimeout = Duration(seconds: 9);

  static const List<Duration> _retryDelays = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  /// Memantau perubahan konektivitas OS; setiap kali perangkat memperoleh akses
  /// internet, langsung menjalankan *background sync* data berstatus `pending`.
  Future<void> startConnectivityMonitor({
    void Function(bool isOnline)? onConnectivityChanged,
  }) async {
    try {
      final conn = Connectivity();
      final current = await conn
          .checkConnectivity()
          .timeout(const Duration(seconds: 2));
      final initialOnline =
          current.any((r) => r != ConnectivityResult.none);
      onConnectivityChanged?.call(initialOnline);
      if (initialOnline) {
        unawaited(syncPending());
      }
      await _connSub?.cancel();
      _connSub = conn.onConnectivityChanged.listen((results) {
        final online = results.any((r) => r != ConnectivityResult.none);
        onConnectivityChanged?.call(online);
        if (online) {
          unawaited(syncPending(groupId: _subscribedGroupId));
        }
      });
    } catch (_) {
      // Abaikan bila plugin connectivity tidak aktif di lingkungan uji unit/widget.
    }
  }

  /// Berlangganan Supabase Realtime (`group_messages` & `member_locations`)
  /// dan menyimpan setiap baris baru ke database lokal secara bebas duplikat.
  Future<void> subscribeGroup(
    String groupId, {
    required String currentUserId,
    DateTime? minCreatedAtUtc,
    void Function(bool hasMoreOlder)? onInitialPaginationResolved,
  }) async {
    final remote = _remote;
    if (remote == null || !isValidUuid(groupId)) return;

    final gen = ++_groupSubGeneration;
    _subscribedGroupId = groupId;
    await _remoteMsgSub?.cancel();
    await _remoteLocSub?.cancel();
    _remoteLocSub = null;

    if (onInitialPaginationResolved != null) {
      unawaited(() async {
        try {
          final probe = remote is GroupChatSinceFilterRemoteService
              ? await remote
                  .fetchMessagesSince(
                    groupId,
                    limit: 41,
                    minCreatedAtUtc: minCreatedAtUtc,
                  )
                  .timeout(_remoteTimeout)
              : await remote
                  .fetchMessages(groupId, limit: 41)
                  .timeout(_remoteTimeout);
          if (gen != _groupSubGeneration) return;
          final filtered = minCreatedAtUtc == null
              ? probe
              : probe
                  .where(
                    (m) => !(m.createdAtUtc ?? m.clientCreatedAtUtc)
                        .isBefore(minCreatedAtUtc),
                  )
                  .toList(growable: false);
          final hasMore = filtered.length > 40;
          final page = hasMore
              ? filtered.sublist(filtered.length - 40)
              : filtered;
          if (page.isNotEmpty) {
            await _localStore.upsertMessagesBatch(<GroupMessageRecord>[
              for (final record in page)
                record.copyWith(syncStatus: ChatSyncStatus.sent),
            ]);
          }
          onInitialPaginationResolved(hasMore);
        } catch (_) {}
      }());
    }

    final stream = remote is GroupChatSinceFilterRemoteService
        ? remote.watchMessagesSince(groupId, minCreatedAtUtc: minCreatedAtUtc)
        : remote.watchMessages(groupId);

    _remoteMsgSub = stream.listen(
      (records) async {
        if (gen != _groupSubGeneration || records.isEmpty) return;
        final filtered = minCreatedAtUtc == null
            ? records
            : records
                .where(
                  (r) => !(r.createdAtUtc ?? r.clientCreatedAtUtc)
                      .isBefore(minCreatedAtUtc),
                )
                .toList(growable: false);
        if (filtered.isEmpty) return;
        final normalized = <GroupMessageRecord>[
          for (final record in filtered)
            record.copyWith(syncStatus: ChatSyncStatus.sent),
        ];
        if (_meshRouter != null) {
          for (final record in normalized) {
            await _meshRouter.ingestExternalMessage(record);
          }
        } else {
          await _localStore.upsertMessagesBatch(normalized);
        }
      },
      onError: (_) {},
    );
  }

  /// Channel lokasi hanya hidup selama layar "Lokasi terakhir" terbuka.
  Future<void> subscribeLocations(
    String groupId, {
    required String currentUserId,
  }) async {
    final remote = _remote;
    if (remote == null || !isValidUuid(groupId)) return;
    final locGen = ++_locSubGeneration;
    await _remoteLocSub?.cancel();
    _remoteLocSub = remote
        .watchMemberLocations(groupId, currentUserId: currentUserId)
        .listen(
      (locations) async {
        if (locGen != _locSubGeneration || locations.isEmpty) return;
        final normalized = <MemberLastLocation>[
          for (final loc in locations)
            loc.copyWith(syncStatus: ChatSyncStatus.sent),
        ];
        await _localStore.upsertMemberLocationsBatch(groupId, normalized);
      },
      onError: (_) {},
    );
  }

  /// Mengambil lokasi seluruh anggota grup sekali secara langsung (REST) agar
  /// titik teman langsung tampil saat layar Lokasi Terakhir baru dibuka.
  Future<List<MemberLastLocation>> refreshLocationsOnce(
    String groupId, {
    required String currentUserId,
  }) async {
    final remote = _remote;
    if (remote == null || !isValidUuid(groupId)) {
      return const <MemberLastLocation>[];
    }
    try {
      final locations = await remote
          .fetchMemberLocations(groupId, currentUserId: currentUserId)
          .timeout(_remoteTimeout);
      if (locations.isNotEmpty) {
        final normalized = <MemberLastLocation>[
          for (final loc in locations)
            loc.copyWith(syncStatus: ChatSyncStatus.sent),
        ];
        await _localStore.upsertMemberLocationsBatch(groupId, normalized);
      }
      return locations;
    } catch (_) {
      return const <MemberLastLocation>[];
    }
  }

  /// Mendekripsi ulang pesan dan lokasi anggota dari server segera setelah kunci
  /// grup baru diterima di perangkat (misalnya lewat Realtime `group_key_blobs`).
  Future<bool> redecryptGroup(
    String groupId, {
    required String currentUserId,
    int limit = 40,
  }) async {
    final remote = _remote;
    if (remote == null || !isValidUuid(groupId)) return false;
    var updated = false;
    try {
      final messages = await remote
          .fetchMessages(groupId, limit: limit)
          .timeout(_remoteTimeout);
      if (messages.isNotEmpty) {
        await _localStore.upsertMessagesBatch(<GroupMessageRecord>[
          for (final m in messages) m.copyWith(syncStatus: ChatSyncStatus.sent),
        ]);
        updated = true;
      }
    } catch (_) {}

    if (currentUserId.isNotEmpty) {
      try {
        final locs = await refreshLocationsOnce(
          groupId,
          currentUserId: currentUserId,
        );
        if (locs.isNotEmpty) updated = true;
      } catch (_) {}
    }
    return updated;
  }

  Future<void> unsubscribeLocations() async {
    _locSubGeneration++;
    final sub = _remoteLocSub;
    _remoteLocSub = null;
    await sub?.cancel();
  }

  Future<void> unsubscribeGroup() async {
    _groupSubGeneration++;
    _locSubGeneration++;
    _subscribedGroupId = null;
    await _remoteMsgSub?.cancel();
    await _remoteLocSub?.cancel();
    _remoteMsgSub = null;
    _remoteLocSub = null;
  }

  /// Mengunggah seluruh pesan & lokasi berstatus `pending` ke Supabase dan
  /// menandainya sebagai `sent` di database lokal.
  Future<int> syncPending({String? groupId}) async {
    final remote = _remote;
    if (remote == null) return 0;
    if (_syncing) {
      _resyncQueued = true;
      _queuedGroupId = groupId ?? _queuedGroupId;
      return 0;
    }
    _syncing = true;
    var syncedCount = 0;

    try {
      // 1. Sinkronkan pesan teks & voice note yang masih berstatus 'pending'
      final pendingMsgs = await _localStore.pendingMessages(groupId: groupId);
      final uuidMessages = pendingMsgs
          .where((m) => isValidUuid(m.groupId))
          .toList(growable: false);

      if (uuidMessages.isNotEmpty) {
        final prepared = <GroupMessageRecord>[];
        for (final msg in uuidMessages) {
          var current = msg;
          if (msg.messageType == GroupMessageType.audio &&
              (msg.audioUrl == null || msg.audioUrl!.isEmpty)) {
            final bytes = await _readAudioBytes(msg);
            if (bytes != null) {
              final storagePath = await remote
                  .uploadVoiceNote(
                    groupId: msg.groupId,
                    clientMsgId: msg.clientMsgId,
                    audioBytes: bytes,
                    keyVersion: msg.keyVersion,
                  )
                  .timeout(_remoteTimeout);
              current = current.copyWith(audioUrl: storagePath);
            }
          }
          prepared.add(current.copyWith(syncStatus: ChatSyncStatus.sent));
        }

        await remote.syncOfflineMessages(prepared).timeout(_remoteTimeout);
        for (final msg in prepared) {
          await _localStore.updateMessageAudioAndSync(
            clientMsgId: msg.clientMsgId,
            groupId: msg.groupId,
            audioUrl: msg.audioUrl,
            syncStatus: ChatSyncStatus.sent,
          );
        }
        syncedCount += prepared.length;
      }

      // 2. Sinkronkan lokasi anggota yang masih berstatus 'pending'
      final pendingLocs =
          await _localStore.pendingMemberLocations(groupId: groupId);
      for (final loc in pendingLocs) {
        final gid = loc.groupId ?? groupId;
        if (gid == null || !isValidUuid(gid)) continue;
        await remote
            .upsertMemberLocation(groupId: gid, location: loc)
            .timeout(_remoteTimeout);
        await _localStore.markMemberLocationSent(
          groupId: gid,
          userId: loc.userId,
        );
        syncedCount++;
      }
      _retryAttempt = 0;
      _retryTimer?.cancel();
      _retryTimer = null;
    } catch (_) {
      final delay = _retryDelays[
          _retryAttempt.clamp(0, _retryDelays.length - 1)];
      _retryAttempt++;
      _retryTimer?.cancel();
      _retryTimer = Timer(delay, () {
        unawaited(syncPending(groupId: groupId ?? _subscribedGroupId));
      });
    } finally {
      _syncing = false;
      if (_resyncQueued) {
        final nextGroup = _queuedGroupId;
        _resyncQueued = false;
        _queuedGroupId = null;
        unawaited(syncPending(groupId: nextGroup));
      }
    }

    return syncedCount;
  }

  Future<Uint8List?> _readAudioBytes(GroupMessageRecord msg) async {
    final localPath = msg.localAudioPath;
    if (localPath != null && localPath.isNotEmpty) {
      final f = File(localPath);
      if (f.existsSync()) {
        return f.readAsBytesSync();
      }
    }
    return VoiceNoteData(
      durationSeconds: msg.audioDurationSec ?? 12,
      peaks: VoiceNoteData.defaultPeaks,
      clientMsgId: msg.clientMsgId,
    ).toBytes();
  }

  Future<void> dispose() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    await _connSub?.cancel();
    await unsubscribeGroup();
  }
}
