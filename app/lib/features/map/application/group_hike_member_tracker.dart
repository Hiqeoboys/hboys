import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:geolocator/geolocator.dart';

import '../../../core/utils/clock.dart';
import '../../../infrastructure/cache/public_profile_cache_service.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_connection.dart';
import '../../../infrastructure/location/shared_location_service.dart';
import '../../../infrastructure/notifications/notification_avatar_helper.dart';
import '../../../infrastructure/offgrid/off_grid_chat_local_store.dart';
import '../../../infrastructure/offgrid/off_grid_supabase_sync_service.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../../chat/application/group_auto_location_service.dart';
import '../../chat/domain/group_chat_models.dart';
import '../../tracking/domain/track_point.dart';

/// Ambang batas ketidakaktifan GPS / pembaruan lokasi anggota saat pendakian aktif.
const Duration kActiveHikeStaleThreshold = Duration(minutes: 5);

/// Status lokasi satu anggota grup pada peta jalur pendakian aktif.
@immutable
class GroupHikeMemberState {
  const GroupHikeMemberState({
    required this.userId,
    required this.displayName,
    required this.initial,
    required this.isSelf,
    required this.hasSignal,
    required this.recordedAtUtc,
    required this.updatedAtUtc,
    required this.isStale,
    required this.staleDuration,
    required this.lastSeenLabel,
    required this.sourceTransport,
    this.avatarUrl,
    this.lat,
    this.lon,
  });

  final String userId;
  final String displayName;
  final String initial;
  final String? avatarUrl;
  final bool isSelf;
  final double? lat;
  final double? lon;
  final bool hasSignal;
  final DateTime recordedAtUtc;
  final DateTime updatedAtUtc;
  final bool isStale;
  final Duration staleDuration;
  final String lastSeenLabel;
  final ChatTransportOrigin sourceTransport;

  bool get hasValidCoord =>
      lat != null &&
      lon != null &&
      lat!.isFinite &&
      lon!.isFinite &&
      !(lat == 0.0 && lon == 0.0) &&
      lat! >= -90.0 &&
      lat! <= 90.0 &&
      lon! >= -180.0 &&
      lon! <= 180.0;
}

/// Memformat usia lokasi menjadi label ringkas berbahasa Indonesia.
String formatLastSeenCompact(Duration age) {
  final mins = age.isNegative ? 0 : age.inMinutes;
  if (mins < 1) return 'Baru saja';
  if (mins < 60) return '$mins mnt lalu';
  final hours = age.inHours;
  if (hours < 24) return '$hours jam lalu';
  return '${age.inDays} hr lalu';
}

/// Mengevaluasi kesegaran lokasi anggota grup terhadap [nowUtc] dan menandai
/// anggota sebagai "lokasi terakhir" jika >= 5 menit tidak terbarui atau GPS mati.
List<GroupHikeMemberState> evaluateGroupMemberFreshness({
  required List<MemberLastLocation> rawLocations,
  required DateTime nowUtc,
  required String currentUserId,
  String? Function(String userId)? resolveAvatarUrl,
  String Function(String userId, String fallback)? resolveDisplayName,
}) {
  final evaluated = <GroupHikeMemberState>[];
  for (final loc in rawLocations) {
    final validCoord = loc.lat != null &&
        loc.lon != null &&
        loc.lat!.isFinite &&
        loc.lon!.isFinite &&
        !(loc.lat == 0.0 && loc.lon == 0.0);
    if (!validCoord) continue;

    final isSelf = currentUserId.isNotEmpty && loc.userId == currentUserId;
    final refUtc = loc.effectiveRecordedAtUtc.isAfter(loc.updatedAtUtc)
        ? loc.effectiveRecordedAtUtc
        : loc.updatedAtUtc;
    final rawAge = nowUtc.toUtc().difference(refUtc.toUtc());
    final age = rawAge.isNegative ? Duration.zero : rawAge;
    final isStale = !loc.hasSignal || age >= kActiveHikeStaleThreshold;

    final rawName = resolveDisplayName != null
        ? resolveDisplayName(loc.userId, loc.displayName)
        : loc.displayName;
    final name = rawName.trim().isNotEmpty ? rawName.trim() : 'Pendaki';
    final initial = name[0].toUpperCase();
    final label = formatLastSeenCompact(age);
    evaluated.add(
      GroupHikeMemberState(
        userId: loc.userId,
        displayName: name,
        initial: initial,
        avatarUrl: resolveAvatarUrl?.call(loc.userId),
        isSelf: isSelf,
        lat: loc.lat,
        lon: loc.lon,
        hasSignal: loc.hasSignal && !isStale,
        recordedAtUtc: loc.effectiveRecordedAtUtc.toUtc(),
        updatedAtUtc: loc.updatedAtUtc.toUtc(),
        isStale: isStale,
        staleDuration: age,
        lastSeenLabel: label,
        sourceTransport: loc.sourceTransport,
      ),
    );
  }
  return evaluated;
}

/// Menghasilkan GeoJSON `FeatureCollection` marker lokasi anggota untuk Mapbox.
String groupMembersToGeoJson(
  List<GroupHikeMemberState> members, {
  Map<String, String> imageIdByUserId = const <String, String>{},
}) {
  final features = <Map<String, Object?>>[];
  for (final m in members) {
    if (!m.hasValidCoord) continue;
    final mapLabel =
        m.isStale ? '${m.displayName}\nTerakhir ${m.lastSeenLabel}' : m.displayName;
    features.add(<String, Object?>{
      'type': 'Feature',
      'properties': <String, Object?>{
        'user_id': m.userId,
        'name': m.displayName,
        'label': mapLabel,
        'initial': m.initial,
        'stale': m.isStale ? 1 : 0,
        'icon_id': imageIdByUserId[m.userId] ?? '',
      },
      'geometry': <String, Object?>{
        'type': 'Point',
        'coordinates': <double>[m.lon!, m.lat!],
      },
    });
  }
  return jsonEncode(<String, Object?>{
    'type': 'FeatureCollection',
    'features': features,
  });
}

String formatStaleBannerTitle(List<GroupHikeMemberState> staleMembers) {
  if (staleMembers.isEmpty) return '';
  if (staleMembers.length == 1) {
    final m = staleMembers.first;
    final mins = m.staleDuration.inMinutes < 5 ? 5 : m.staleDuration.inMinutes;
    return '${m.displayName} tidak terdeteksi >$mins menit';
  }
  return '${staleMembers.length} anggota tidak terdeteksi >5 menit';
}

String formatStaleBannerBody(List<GroupHikeMemberState> staleMembers) {
  if (staleMembers.isEmpty) return '';
  if (staleMembers.length == 1) {
    final m = staleMembers.first;
    return 'Lokasi terakhir terlihat ${m.lastSeenLabel}. Segera pastikan ${m.displayName} masih bersama rombongan.';
  }
  final names = staleMembers.map((m) => m.displayName).take(3).join(', ');
  return '$names belum mengirim posisi terbaru. Segera pastikan mereka masih bersama rombongan.';
}

/// Menghasilkan badge PNG lingkaran untuk marker Mapbox tiap anggota grup.
Future<Uint8List?> renderMemberMarkerPng({
  required String userId,
  required String initial,
  String? avatarUrl,
  required bool isStale,
}) async {
  Uint8List? avatarBytes;
  if (avatarUrl != null && avatarUrl.trim().isNotEmpty) {
    try {
      avatarBytes = await NotificationAvatarHelper.resolveCircularAvatarPng(
        cacheKey: userId,
        avatarUrl: avatarUrl,
        fallbackLabel: initial,
        allowMonogramFallback: false,
      );
    } catch (_) {
      avatarBytes = null;
    }
  }

  try {
    const double size = 80.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      const ui.Rect.fromLTWH(0, 0, size, size),
    );
    const center = ui.Offset(size / 2, size / 2);
    const outerRadius = size / 2 - 4.0;
    const innerRadius = outerRadius - 4.0;

    // Halo latar tipis + cincin tepi putih/peringatan
    canvas.drawCircle(
      center,
      outerRadius + 2.0,
      ui.Paint()..color = const ui.Color(0x33000000),
    );
    canvas.drawCircle(
      center,
      outerRadius,
      ui.Paint()
        ..color = isStale ? const ui.Color(0xFFD97706) : Colors.white,
    );

    if (avatarBytes != null && avatarBytes.isNotEmpty) {
      final codec = await ui.instantiateImageCodec(
        avatarBytes,
        targetWidth: 72,
        targetHeight: 72,
      );
      final frame = await codec.getNextFrame();
      final img = frame.image;
      try {
        canvas.save();
        canvas.clipPath(
          ui.Path()
            ..addOval(
              ui.Rect.fromCircle(center: center, radius: innerRadius),
            ),
        );
        final paint = ui.Paint()..isAntiAlias = true;
        if (isStale) {
          paint.color = const ui.Color(0xAAFFFFFF);
        }
        canvas.drawImageRect(
          img,
          ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          ui.Rect.fromCircle(center: center, radius: innerRadius),
          paint,
        );
        canvas.restore();
      } finally {
        img.dispose();
        codec.dispose();
      }
    } else {
      final bgColor = isStale
          ? const ui.Color(0xFF64748B)
          : const ui.Color(0xFF242B40);
      canvas.drawCircle(
        center,
        innerRadius,
        ui.Paint()..color = bgColor,
      );

      final builder = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          textAlign: ui.TextAlign.center,
          fontSize: 30,
          fontWeight: ui.FontWeight.w700,
        ),
      )
        ..pushStyle(ui.TextStyle(color: Colors.white))
        ..addText(initial.isNotEmpty ? initial[0].toUpperCase() : '?');
      final paragraph = builder.build()
        ..layout(const ui.ParagraphConstraints(width: size));
      canvas.drawParagraph(
        paragraph,
        ui.Offset(0, (size - paragraph.height) / 2),
      );
      paragraph.dispose();
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  } catch (_) {
    return NotificationAvatarHelper.renderMonogramCirclePngSync(
      seed: userId,
      label: initial,
    );
  }
}

/// Memantau lokasi seluruh anggota grup saat pendakian berlangsung (Realtime +
/// database Mesh lokal), mengevaluasi kehilangan sinyal >= 5 menit, serta menjaga
/// detak lokasi pengguna sendiri tetap segar meski sedang berhenti di pos.
class GroupHikeMemberTracker extends ChangeNotifier {
  GroupHikeMemberTracker({
    Clock clock = const SystemClock(),
    Stream<List<MemberLastLocation>>? locationsOverride,
    void Function(List<GroupHikeMemberState> newlyStale)? onNewStaleMembers,
    this.tickInterval = const Duration(seconds: 15),
    this.heartbeatInterval = const Duration(seconds: 30),
  })  : _clock = clock,
        _locationsOverride = locationsOverride,
        _onNewStaleMembers = onNewStaleMembers;

  final Clock _clock;
  final Stream<List<MemberLastLocation>>? _locationsOverride;
  void Function(List<GroupHikeMemberState> newlyStale)? _onNewStaleMembers;
  final Duration tickInterval;
  final Duration heartbeatInterval;

  String? _activeGroupId;
  String _currentUserId = '';
  AppDatabase? _db;
  OffGridChatLocalStore? _localStore;
  OffGridSupabaseSyncService? _syncService;
  StreamSubscription<List<MemberLastLocation>>? _localSub;
  StreamSubscription<List<MemberLastLocation>>? _overrideSub;
  Timer? _tickTimer;
  Timer? _heartbeatTimer;
  bool _disposed = false;
  bool _profileListening = false;
  int _startGeneration = 0;

  List<MemberLastLocation> _rawLocations = const <MemberLastLocation>[];
  List<GroupHikeMemberState> _teammates = const <GroupHikeMemberState>[];
  final Set<String> _notifiedStaleIds = <String>{};

  set onNewStaleMembers(
    void Function(List<GroupHikeMemberState> newlyStale)? cb,
  ) {
    _onNewStaleMembers = cb;
  }

  String? get activeGroupId => _activeGroupId;

  /// Anggota grup lain (di luar pengguna aktif) untuk dirender di peta agar
  /// marker tidak menumpuk di atas titik GPS pengguna sendiri.
  List<GroupHikeMemberState> get teammates => _teammates;

  List<GroupHikeMemberState> get staleMembers => _teammates
      .where((m) => m.isStale)
      .toList(growable: false);

  Future<void> start({
    required String groupId,
    required String currentUserId,
  }) async {
    final cleanGroupId = groupId.trim();
    final cleanUserId = currentUserId.trim();
    if (_disposed || cleanGroupId.isEmpty) return;
    if (_activeGroupId == cleanGroupId && _currentUserId == cleanUserId) {
      return;
    }
    final gen = ++_startGeneration;
    _cancelTimersSync();
    await _stopInternal();
    if (_disposed || gen != _startGeneration) return;

    _activeGroupId = cleanGroupId;
    _currentUserId = cleanUserId;

    if (!_profileListening) {
      PublicProfileCacheService.instance.addListener(_onProfilesUpdated);
      _profileListening = true;
    }

    if (_locationsOverride != null) {
      _overrideSub = _locationsOverride.listen((locs) {
        if (_disposed || gen != _startGeneration) return;
        _rawLocations = locs;
        _recomputeFreshness();
      });
    } else if (isValidUuid(cleanGroupId)) {
      await _startProductionFeeds(cleanGroupId, cleanUserId, generation: gen);
      if (_disposed || gen != _startGeneration) return;
    }

    _tickTimer = Timer.periodic(tickInterval, (_) => _recomputeFreshness());
    _heartbeatTimer = Timer.periodic(
      heartbeatInterval,
      (_) => unawaited(_sendActiveHikeHeartbeat()),
    );
    unawaited(_sendActiveHikeHeartbeat());
  }

  void _cancelTimersSync() {
    _tickTimer?.cancel();
    _tickTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _startProductionFeeds(
    String groupId,
    String currentUserId, {
    required int generation,
  }) async {
    try {
      final db = openAppDatabase(await defaultAppDatabaseFile());
      if (_disposed || generation != _startGeneration || _activeGroupId != groupId) {
        await db.close();
        return;
      }
      _db = db;
      final localStore = OffGridChatLocalStore(database: db);
      _localStore = localStore;
      _localSub = localStore
          .watchMemberLocations(groupId, currentUserId: currentUserId)
          .listen((locs) {
        if (_disposed || _activeGroupId != groupId) return;
        _rawLocations = locs;
        unawaited(
          PublicProfileCacheService.instance.fetchProfiles(
            locs.map((e) => e.userId),
          ),
        );
        _recomputeFreshness();
      });

      final remote = SupabaseServices.createGroupChatRemoteService();
      if (remote != null) {
        final sync = OffGridSupabaseSyncService(
          localStore: localStore,
          remoteService: remote,
        );
        _syncService = sync;
        await sync.subscribeLocations(groupId, currentUserId: currentUserId);
        await sync.refreshLocationsOnce(groupId, currentUserId: currentUserId);
      }
    } catch (_) {
      // Tetap aman saat dijalankan di lingkungan tanpa SQLite native.
    }
  }

  Future<void> _sendActiveHikeHeartbeat() async {
    final groupId = _activeGroupId;
    if (_disposed || groupId == null || !isValidUuid(groupId)) return;
    if (_locationsOverride != null) return;
    try {
      final sharedState = SharedLocationService.instance.state;
      TrackPoint? fresh = SharedLocationService.instance.freshPoint;
      // Saat GPS aktif tetapi pendaki diam di pos istirahat, perbarui cap
      // waktu ke sekarang agar anggota lain tidak mengira GPS mati >= 5 menit.
      if (fresh != null && sharedState.status == LiveLocationStatus.active) {
        fresh = fresh.copyWith(timestampUtc: _clock.nowUtc());
      } else {
        if (!await Geolocator.isLocationServiceEnabled()) return;
        final perm = await Geolocator.checkPermission();
        if (perm != LocationPermission.whileInUse &&
            perm != LocationPermission.always) {
          return;
        }
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 6),
          ),
        );
        fresh = TrackPoint(
          lat: pos.latitude,
          lon: pos.longitude,
          timestampUtc: _clock.nowUtc(),
          accuracyM: pos.accuracy,
          altitudeM: pos.hasAltitude ? pos.altitude : null,
        );
      }
      await GroupAutoLocationService.instance.syncNow(
        force: true,
        targetGroupId: groupId,
        pointOverride: fresh,
      );
    } catch (_) {}
  }

  void _onProfilesUpdated() {
    if (_disposed) return;
    _recomputeFreshness();
  }

  @visibleForTesting
  void setLocationsForTesting(List<MemberLastLocation> locations) {
    _rawLocations = locations;
    _recomputeFreshness();
  }

  @visibleForTesting
  void recomputeForTesting() => _recomputeFreshness();

  void _recomputeFreshness() {
    if (_disposed) return;
    final all = evaluateGroupMemberFreshness(
      rawLocations: _rawLocations,
      nowUtc: _clock.nowUtc(),
      currentUserId: _currentUserId,
      resolveAvatarUrl: (uid) =>
          PublicProfileCacheService.instance.resolveAvatarUrl(uid),
      resolveDisplayName: (uid, fallback) =>
          PublicProfileCacheService.instance.resolveDisplayName(
            uid,
            fallback: fallback,
          ),
    );
    _teammates = all.where((m) => !m.isSelf).toList(growable: false);

    final currentStaleIds = <String>{
      for (final m in _teammates)
        if (m.isStale) m.userId,
    };
    _notifiedStaleIds.removeWhere((id) => !currentStaleIds.contains(id));
    final newlyStale = <GroupHikeMemberState>[
      for (final m in _teammates)
        if (m.isStale && _notifiedStaleIds.add(m.userId)) m,
    ];
    if (newlyStale.isNotEmpty) {
      _onNewStaleMembers?.call(newlyStale);
    }
    notifyListeners();
  }

  Future<void> stop() async {
    _startGeneration++;
    await _stopInternal();
  }

  Future<void> _stopInternal() async {
    _activeGroupId = null;
    _cancelTimersSync();
    await _localSub?.cancel();
    _localSub = null;
    await _overrideSub?.cancel();
    _overrideSub = null;
    await _syncService?.unsubscribeLocations();
    await _syncService?.dispose();
    _syncService = null;
    await _localStore?.dispose();
    _localStore = null;
    await _db?.close();
    _db = null;
    _rawLocations = const <MemberLastLocation>[];
    _teammates = const <GroupHikeMemberState>[];
    _notifiedStaleIds.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _startGeneration++;
    _cancelTimersSync();
    if (_profileListening) {
      PublicProfileCacheService.instance.removeListener(_onProfilesUpdated);
      _profileListening = false;
    }
    unawaited(stop());
    super.dispose();
  }
}
