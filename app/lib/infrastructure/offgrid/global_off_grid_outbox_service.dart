import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import '../../features/chat/domain/group_chat_remote_service.dart';
import '../../features/social/data/social_unread_store.dart';
import '../database/app_database.dart';
import '../database/database_connection.dart';
import '../supabase/supabase_services.dart';
import 'off_grid_chat_local_store.dart';
import 'off_grid_supabase_sync_service.dart';

/// Layanan global *Local Outbox Queue* untuk menyinkronkan pesan & lokasi
/// berstatus `pending` ke Supabase secara otomatis dan idempoten (`UUID v4` +
/// `ON CONFLICT (id) DO NOTHING`) segera saat perangkat kembali online tanpa
/// pengguna harus keluar dari halaman obrolan atau restart aplikasi.
class GlobalOffGridOutboxService with WidgetsBindingObserver {
  GlobalOffGridOutboxService({
    OffGridChatLocalStore? localStore,
    GroupChatRemoteService? Function()? remoteFactory,
    Stream<bool>? connectivityOnlineStream,
  })  : _localStoreOverride = localStore,
        _remoteFactory = remoteFactory ?? SupabaseServices.createGroupChatRemoteService,
        _connectivityOnlineStream = connectivityOnlineStream;

  static final GlobalOffGridOutboxService instance =
      GlobalOffGridOutboxService();

  final OffGridChatLocalStore? _localStoreOverride;
  final GroupChatRemoteService? Function() _remoteFactory;
  final Stream<bool>? _connectivityOnlineStream;

  AppDatabase? _db;
  OffGridChatLocalStore? _ownedStore;
  StreamSubscription<List<ConnectivityResult>>? _osConnSub;
  StreamSubscription<bool>? _overrideConnSub;
  Timer? _retryTimer;
  int _retryCount = 0;
  bool _started = false;
  bool _openingStore = false;
  bool _syncing = false;
  bool _observerAttached = false;

  static const List<Duration> _retryBackoffs = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  OffGridChatLocalStore? get sharedLocalStore =>
      _localStoreOverride ?? _ownedStore;

  bool get isStarted => _started;

  Future<OffGridChatLocalStore?> ensureLocalStore() async {
    if (_localStoreOverride != null) return _localStoreOverride;
    if (_ownedStore != null) return _ownedStore;
    if (_openingStore) return null;
    _openingStore = true;
    try {
      final db = openAppDatabase(await defaultAppDatabaseFile());
      _db = db;
      _ownedStore = OffGridChatLocalStore(database: db);
      return _ownedStore;
    } catch (_) {
      return null;
    } finally {
      _openingStore = false;
    }
  }

  void start() {
    if (_started) return;
    _started = true;

    try {
      WidgetsBinding.instance.addObserver(this);
      _observerAttached = true;
    } catch (_) {}

    if (_connectivityOnlineStream != null) {
      _overrideConnSub = _connectivityOnlineStream.listen((online) {
        if (online) unawaited(syncNow());
      });
    } else {
      try {
        final conn = Connectivity();
        unawaited(
          conn.checkConnectivity().then((results) {
            if (!_started) return;
            if (results.any((r) => r != ConnectivityResult.none)) {
              unawaited(syncNow());
            }
          }).catchError((_) {}),
        );
        _osConnSub = conn.onConnectivityChanged.listen((results) {
          if (results.any((r) => r != ConnectivityResult.none)) {
            unawaited(syncNow());
          }
        });
      } catch (_) {}
    }

    unawaited(syncNow());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(syncNow());
    }
  }

  Future<int> syncNow({String? groupId}) async {
    if (_syncing) return 0;
    final store = await ensureLocalStore();
    final remote = _remoteFactory();
    if (store == null || remote == null) return 0;

    _syncing = true;
    try {
      final sync = OffGridSupabaseSyncService(
        localStore: store,
        remoteService: remote,
      );
      final synced = await sync.syncPending(groupId: groupId);
      final remainingMsgs = await store.pendingMessages();
      if (remainingMsgs.isEmpty) {
        _retryCount = 0;
        _retryTimer?.cancel();
        _retryTimer = null;
      } else {
        _scheduleRetry(groupId: groupId);
      }
      if (synced > 0) {
        unawaited(SocialUnreadStore.instance.refresh());
      }
      return synced;
    } catch (_) {
      _scheduleRetry(groupId: groupId);
      return 0;
    } finally {
      _syncing = false;
    }
  }

  void _scheduleRetry({String? groupId}) {
    if (!_started) return;
    _retryTimer?.cancel();
    final delay = _retryBackoffs[_retryCount.clamp(0, _retryBackoffs.length - 1)];
    _retryCount++;
    _retryTimer = Timer(delay, () {
      if (_started) unawaited(syncNow(groupId: groupId));
    });
  }

  Future<void> dispose() async {
    _started = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    if (_observerAttached) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
      _observerAttached = false;
    }
    await _osConnSub?.cancel();
    await _overrideConnSub?.cancel();
    _osConnSub = null;
    _overrideConnSub = null;
    await _ownedStore?.dispose();
    _ownedStore = null;
    await _db?.close();
    _db = null;
  }
}
