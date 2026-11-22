import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/utils/clock.dart';
import '../../groups/domain/group_remote_service.dart';
import '../../tracking/application/tracking_controller.dart';
import '../../tracking/domain/track_point.dart';
import '../../../infrastructure/location/shared_location_service.dart';
import '../../../infrastructure/offgrid/off_grid_chat_local_store.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../domain/group_chat_models.dart';
import '../domain/group_chat_remote_service.dart';

typedef AutoLocGroupsProvider = List<RemoteGroup> Function();
typedef AutoLocUserProvider = ({String? userId, String displayName}) Function();
typedef AutoLocRemoteFactory = GroupChatRemoteService? Function();
typedef AutoLocStoreFactory = OffGridChatLocalStore? Function();
typedef AutoLocPermissionChecker = Future<bool> Function();
typedef AutoLocPositionReader = Future<TrackPoint?> Function();

class _GroupUploadStamp {
  const _GroupUploadStamp({required this.atUtc, required this.position});

  final DateTime atUtc;
  final LatLng position;
}

/// Layanan latar depan & sesi aktif untuk membaca GPS secara berkala dan
/// menyinkronkan lokasi terakhir pengguna ke semua grup yang diikuti secara
/// otomatis tanpa pengguna perlu menekan sakelar manual.
class GroupAutoLocationService with WidgetsBindingObserver {
  GroupAutoLocationService({
    AutoLocGroupsProvider? groupsProvider,
    AutoLocUserProvider? userProvider,
    AutoLocRemoteFactory? remoteFactory,
    AutoLocStoreFactory? localStoreFactory,
    AutoLocPermissionChecker? permissionChecker,
    AutoLocPositionReader? positionReader,
    Clock clock = const SystemClock(),
    Duration syncInterval = const Duration(seconds: 45),
    Duration minUploadGap = const Duration(seconds: 45),
    double minMoveMeters = 15.0,
  })  : _groupsProvider = groupsProvider ?? _defaultGroupsProvider,
        _userProvider = userProvider ?? _defaultUserProvider,
        _remoteFactory = remoteFactory ?? SupabaseServices.createGroupChatRemoteService,
        _localStoreFactory = localStoreFactory,
        _permissionChecker = permissionChecker ?? _defaultPermissionChecker,
        _positionReader = positionReader ?? _defaultPositionReader,
        _clock = clock,
        _syncInterval = syncInterval,
        _minUploadGap = minUploadGap,
        _minMoveMeters = minMoveMeters;

  static final GroupAutoLocationService instance = GroupAutoLocationService();

  final AutoLocGroupsProvider _groupsProvider;
  final AutoLocUserProvider _userProvider;
  final AutoLocRemoteFactory _remoteFactory;
  final AutoLocStoreFactory? _localStoreFactory;
  final AutoLocPermissionChecker _permissionChecker;
  final AutoLocPositionReader _positionReader;
  final Clock _clock;
  final Duration _syncInterval;
  final Duration _minUploadGap;
  final double _minMoveMeters;

  final Map<String, _GroupUploadStamp> _lastUploadByGroup =
      <String, _GroupUploadStamp>{};
  Timer? _timer;
  StreamSubscription<String>? _keyReadySub;
  bool _started = false;
  bool _observerAttached = false;
  bool _listenersAttached = false;
  bool _inFlight = false;

  static const Duration _remoteTimeout = Duration(seconds: 9);

  bool get isStarted => _started;
  bool get isTimerActive => _timer?.isActive ?? false;

  static List<RemoteGroup> _defaultGroupsProvider() =>
      SupabaseServices.sharedAccountController?.groups ?? const <RemoteGroup>[];

  static ({String? userId, String displayName}) _defaultUserProvider() {
    final acc = SupabaseServices.sharedAccountController;
    final uid = acc?.user?.id ?? SupabaseServices.clientOrNull?.auth.currentUser?.id;
    final full = acc?.profile?.fullName?.trim();
    final uname = acc?.profile?.username?.trim();
    final disp = acc?.user?.displayName?.trim();
    final name = (full != null && full.isNotEmpty)
        ? full
        : ((disp != null && disp.isNotEmpty)
            ? disp
            : ((uname != null && uname.isNotEmpty) ? uname : 'Pendaki'));
    return (userId: uid, displayName: name);
  }

  static Future<bool> _defaultPermissionChecker() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      final perm = await Geolocator.checkPermission();
      return perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  static Future<TrackPoint?> _defaultPositionReader() async {
    final shared = SharedLocationService.instance.state.point;
    if (shared != null) return shared;
    final tracked = await TrackingController.instance.latestRecordedPoint();
    if (tracked != null) return tracked;
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return TrackPoint(
          lat: last.latitude,
          lon: last.longitude,
          timestampUtc: last.timestamp.toUtc(),
          accuracyM: last.accuracy,
          altitudeM: last.hasAltitude ? last.altitude : null,
        );
      }
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 6),
        ),
      );
      return TrackPoint(
        lat: current.latitude,
        lon: current.longitude,
        timestampUtc: current.timestamp.toUtc(),
        accuracyM: current.accuracy,
        altitudeM: current.hasAltitude ? current.altitude : null,
      );
    } catch (_) {
      return null;
    }
  }

  void start() {
    if (_started) return;
    _started = true;
    if (!_observerAttached) {
      try {
        WidgetsBinding.instance.addObserver(this);
        _observerAttached = true;
      } catch (_) {}
    }
    if (!_listenersAttached) {
      try {
        SharedLocationService.instance.addListener(_onSourceChanged);
        TrackingController.instance.addListener(_onSourceChanged);
        _listenersAttached = true;
      } catch (_) {}
    }
    unawaited(_keyReadySub?.cancel());
    if (SupabaseServices.isAvailable) {
      _keyReadySub =
          SupabaseServices.sharedAccountController?.onGroupKeyReady.listen(
        (groupId) {
          if (_started) {
            unawaited(syncNow(force: true, targetGroupId: groupId));
          }
        },
      );
    }
    _timer?.cancel();
    _timer = Timer.periodic(_syncInterval, (_) => unawaited(syncNow()));
    unawaited(syncNow());
  }

  void stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
    unawaited(_keyReadySub?.cancel());
    _keyReadySub = null;
    _lastUploadByGroup.clear();
    if (_observerAttached) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
      _observerAttached = false;
    }
    if (_listenersAttached) {
      try {
        SharedLocationService.instance.removeListener(_onSourceChanged);
        TrackingController.instance.removeListener(_onSourceChanged);
      } catch (_) {}
      _listenersAttached = false;
    }
  }

  void _onSourceChanged() {
    if (!_started) return;
    unawaited(syncNow());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(syncNow());
    }
  }

  /// Membaca koordinat GPS aktif dan mengunggah lokasi terakhir ke grup.
  Future<int> syncNow({
    bool force = false,
    String? targetGroupId,
    TrackPoint? pointOverride,
  }) async {
    if (_inFlight) return 0;
    final user = _userProvider();
    final userId = user.userId;
    if (userId == null || userId.isEmpty) return 0;

    final groups = _groupsProvider()
        .where(
          (g) =>
              isValidUuid(g.group.id) &&
              (targetGroupId == null || g.group.id == targetGroupId),
        )
        .toList(growable: false);
    if (groups.isEmpty) return 0;

    if (pointOverride == null && !await _permissionChecker()) {
      return 0;
    }

    _inFlight = true;
    var uploadedCount = 0;
    try {
      final point = pointOverride ?? await _positionReader();
      if (point == null || !point.lat.isFinite || !point.lon.isFinite) {
        return 0;
      }
      if (point.lat == 0.0 && point.lon == 0.0) return 0;

      final now = _clock.nowUtc();
      final pos = LatLng(point.lat, point.lon);
      final remote = _remoteFactory();
      final localStore = _localStoreFactory?.call();

      for (final remoteGroup in groups) {
        final gid = remoteGroup.group.id;
        final prev = _lastUploadByGroup[gid];
        if (!force && prev != null) {
          final elapsed = now.difference(prev.atUtc);
          final moved = distanceMeters(prev.position, pos);
          if (elapsed < _minUploadGap && moved < _minMoveMeters) {
            continue;
          }
        }

        final initial = user.displayName.isNotEmpty
            ? user.displayName[0].toUpperCase()
            : 'K';
        final loc = MemberLastLocation(
          groupId: gid,
          userId: userId,
          displayName: user.displayName,
          initial: initial,
          hasSignal: true,
          lat: point.lat,
          lon: point.lon,
          accuracyM: point.accuracyM.round(),
          altitudeMdpl: point.altitudeM?.round(),
          sourceTransport: ChatTransportOrigin.online,
          syncStatus: ChatSyncStatus.pending,
          recordedAtUtc: point.timestampUtc.toUtc(),
          updatedAtUtc: now,
          mapX: 0.48,
          mapY: 0.56,
        );

        await localStore?.upsertMemberLocation(gid, loc);
        if (remote != null) {
          try {
            if (SupabaseServices.isAvailable) {
              await SupabaseServices.sharedAccountController
                  ?.ensureGroupKeyDistributed(gid)
                  .timeout(const Duration(seconds: 3), onTimeout: () => false);
            }
            await remote
                .upsertMemberLocation(
                  groupId: gid,
                  location: loc,
                  keyVersion: remoteGroup.group.keyVersion,
                )
                .timeout(_remoteTimeout);
            await localStore?.markMemberLocationSent(
              groupId: gid,
              userId: userId,
            );
          } catch (_) {
            continue;
          }
        }

        _lastUploadByGroup[gid] = _GroupUploadStamp(atUtc: now, position: pos);
        uploadedCount++;
      }
    } finally {
      _inFlight = false;
    }
    return uploadedCount;
  }
}
