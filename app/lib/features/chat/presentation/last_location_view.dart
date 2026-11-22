import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../../core/config/supabase_config.dart';
import '../../../design/glass/glass_surface.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/hiqeo_back_button.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/persistent_avatar_image.dart';
import '../../../infrastructure/cache/public_profile_cache_service.dart';
import '../../../infrastructure/location/shared_location_service.dart';
import '../../map/application/offline_pack_service.dart';
import '../../map/domain/mountain_pack.dart';
import '../../map/domain/mountain_pack_data.dart';
import '../../trails/data/gpx_loader.dart';
import '../domain/group_chat_models.dart';

/// Batas usia lokasi (menit) sebelum anggota ditandai abu-abu "Terakhir terlihat".
const int kStaleLocationMinutes = 15;

/// Pesan resmi saat pengguna offline di luar jangkauan peta gunung yang diunduh.
const String kOfflineMapUnavailableMessage =
    'Peta tidak tersedia saat offline. Unduh peta gunung tujuan terlebih dahulu atau pastikan perangkat terhubung ke internet untuk melihat peta.';

/// Margin atas scale bar Mapbox agar bersih di bawah status bar dan pil header
/// "Lokasi terakhir".
double lastLocationScaleBarTopMargin(double safeTop) => safeTop + 76.0;

/// Mode tampilan peta pada layar Lokasi Terakhir grup.
enum LastLocationMapMode {
  lockingGps,
  onlineMap,
  offlineDownloadedMountain,
  offlineUnavailable,
}

/// Hasil evaluasi aturan 3-skenario peta Online vs Offline.
@immutable
class LastLocationMapDecision {
  const LastLocationMapDecision({
    required this.mode,
    this.matchedOfflinePack,
    this.cameraTarget,
  });

  final LastLocationMapMode mode;
  final MountainPack? matchedOfflinePack;
  final LatLng? cameraTarget;
}

bool _isValidCoord(double? lat, double? lon) {
  if (lat == null || lon == null) return false;
  if (!lat.isFinite || !lon.isFinite) return false;
  if (lat == 0.0 && lon == 0.0) return false;
  return lat >= -90.0 && lat <= 90.0 && lon >= -180.0 && lon <= 180.0;
}

LatLng? _firstValidMemberCoord(List<MemberLastLocation> members) {
  for (final m in members) {
    if (_isValidCoord(m.lat, m.lon)) {
      return LatLng(m.lat!, m.lon!);
    }
  }
  return null;
}

/// Mencocokkan posisi GPS saat ini ke salah satu paket gunung offline yang
/// sudah diunduh perangkat (berdasarkan bounding box atau jarak <= 2,5 km dari jalur).
MountainPack? findDownloadedMountainForPosition(
  LatLng position,
  List<MountainPack> packs,
) {
  MountainPack? best;
  double bestDistanceM = double.infinity;
  const double fallbackRadiusM = 2500.0;

  for (final pack in packs) {
    if (!pack.isDownloaded && !pack.isUpdateAvailable) continue;
    final bounds = pack.package.offline.bounds;
    var matches = false;
    var refDistanceM = double.infinity;

    if (bounds.isValid) {
      matches = bounds.contains(position);
      if (matches) {
        refDistanceM = distanceMeters(position, bounds.center);
      }
    } else {
      for (final trail in pack.package.trails) {
        for (final pt in trail.points) {
          final d = distanceMeters(position, pt);
          if (d <= fallbackRadiusM) {
            matches = true;
            if (d < refDistanceM) refDistanceM = d;
          }
        }
      }
    }

    if (matches && refDistanceM < bestDistanceM) {
      best = pack;
      bestDistanceM = refDistanceM;
    }
  }
  return best;
}

/// Menentukan skenario peta Lokasi Terakhir (Online / Offline dalam area
/// unduhan / Offline di luar area unduhan) tanpa fallback koordinat palsu.
LastLocationMapDecision resolveLastLocationMapDecision({
  required bool isOnline,
  required LatLng? userPosition,
  required bool isLockingGps,
  required List<MemberLastLocation> members,
  required List<MountainPack> downloadedPacks,
  bool isLoadingOfflinePacks = false,
}) {
  if (isOnline) {
    if (userPosition != null) {
      return LastLocationMapDecision(
        mode: LastLocationMapMode.onlineMap,
        cameraTarget: userPosition,
      );
    }
    if (isLockingGps) {
      return const LastLocationMapDecision(
        mode: LastLocationMapMode.lockingGps,
      );
    }
    final memberCoord = _firstValidMemberCoord(members);
    if (memberCoord != null) {
      return LastLocationMapDecision(
        mode: LastLocationMapMode.onlineMap,
        cameraTarget: memberCoord,
      );
    }
    return const LastLocationMapDecision(mode: LastLocationMapMode.lockingGps);
  }

  // Offline: periksa paket gunung yang tersimpan lokal.
  if (isLoadingOfflinePacks) {
    return const LastLocationMapDecision(mode: LastLocationMapMode.lockingGps);
  }

  final available = downloadedPacks
      .where((p) => p.isDownloaded || p.isUpdateAvailable)
      .toList(growable: false);
  if (available.isEmpty) {
    return const LastLocationMapDecision(
      mode: LastLocationMapMode.offlineUnavailable,
    );
  }

  if (userPosition == null) {
    return LastLocationMapDecision(
      mode: isLockingGps
          ? LastLocationMapMode.lockingGps
          : LastLocationMapMode.offlineUnavailable,
    );
  }

  final matched = findDownloadedMountainForPosition(userPosition, available);
  if (matched != null) {
    return LastLocationMapDecision(
      mode: LastLocationMapMode.offlineDownloadedMountain,
      matchedOfflinePack: matched,
      cameraTarget: userPosition,
    );
  }

  return const LastLocationMapDecision(
    mode: LastLocationMapMode.offlineUnavailable,
  );
}

/// Layar "Lokasi terakhir" anggota grup dengan peta Mapbox penuh (atau peta
/// offline gunung terunduh / status offline informatif) serta panel bawah
/// opt-in berbagi lokasi per grup.
class LastLocationView extends StatefulWidget {
  const LastLocationView({
    super.key,
    required this.groupName,
    required this.members,
    required this.nowUtc,
    required this.isOnline,
    required this.onBack,
    this.mountainName,
    this.userLocation,
    this.isLockingGps = false,
    this.locationStatus,
    this.downloadedPacks = const <MountainPack>[],
    this.isLoadingOfflinePacks = false,
    this.locationSharingEnabled = false,
    this.onLocationSharingChanged,
    this.onShareLocation,
    this.onSelectMember,
    this.onOpenOfflineMaps,
    this.onRetryLocation,
  });

  final String groupName;
  final String? mountainName;
  final List<MemberLastLocation> members;
  final DateTime nowUtc;
  final bool isOnline;
  final VoidCallback onBack;
  final LatLng? userLocation;
  final bool isLockingGps;
  final LiveLocationStatus? locationStatus;
  final List<MountainPack> downloadedPacks;
  final bool isLoadingOfflinePacks;
  final bool locationSharingEnabled;
  final ValueChanged<bool>? onLocationSharingChanged;
  final Future<void> Function()? onShareLocation;
  final ValueChanged<MemberLastLocation>? onSelectMember;
  final VoidCallback? onOpenOfflineMaps;
  final VoidCallback? onRetryLocation;

  @override
  State<LastLocationView> createState() => _LastLocationViewState();
}

class _LastLocationViewState extends State<LastLocationView> {
  static const String _routeSourceId = 'last-loc-gpx-route-source';
  static const String _routeCasingLayerId = 'last-loc-gpx-route-casing';
  static const String _routeLineLayerId = 'last-loc-gpx-route-line';
  static const String _membersSourceId = 'last-loc-members-source';
  static const String _membersCircleLayerId = 'last-loc-members-circle';
  static const String _membersLabelLayerId = 'last-loc-members-label';

  mapbox.MapboxMap? _map;
  mapbox.GeoJsonSource? _routeSource;
  mapbox.GeoJsonSource? _membersSource;
  bool _layersInstalled = false;
  List<List<List<double>>> _routeLinesCoords = const <List<List<double>>>[];
  String? _loadedRouteKey;
  String? _selectedMemberId;
  double _safeTop = 0;
  bool _centeredOnUserFix = false;
  bool _resharing = false;

  Future<void> _handleReshareTap() async {
    final cb = widget.onShareLocation;
    if (cb == null || _resharing) return;
    setState(() => _resharing = true);
    try {
      await cb();
    } finally {
      if (mounted) setState(() => _resharing = false);
    }
  }

  LastLocationMapDecision _computeDecision() {
    return resolveLastLocationMapDecision(
      isOnline: widget.isOnline,
      userPosition: widget.userLocation,
      isLockingGps: widget.isLockingGps,
      members: widget.members,
      downloadedPacks: widget.downloadedPacks,
      isLoadingOfflinePacks: widget.isLoadingOfflinePacks,
    );
  }

  @override
  void initState() {
    super.initState();
    final decision = _computeDecision();
    unawaited(_loadMountainRoute(offlinePack: decision.matchedOfflinePack));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _safeTop = MediaQuery.paddingOf(context).top;
    _applyMapOrnaments();
  }

  @override
  void didUpdateWidget(covariant LastLocationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final decision = _computeDecision();
    final nextRouteKey = decision.matchedOfflinePack?.id ??
        'name:${widget.mountainName?.trim().toLowerCase() ?? ''}';
    if (nextRouteKey != _loadedRouteKey) {
      unawaited(_loadMountainRoute(offlinePack: decision.matchedOfflinePack));
    }
    if (widget.userLocation != null && !_centeredOnUserFix && _map != null) {
      _centeredOnUserFix = true;
      unawaited(_flyCameraTo(widget.userLocation!, zoom: 14.5));
    }
    if (_layersInstalled) {
      unawaited(_pushMembersToMap());
    }
  }

  Future<void> _flyCameraTo(LatLng target, {double zoom = 14.5}) async {
    final map = _map;
    if (map == null) return;
    try {
      await map.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(target.lon, target.lat),
          ),
          zoom: zoom,
        ),
        mapbox.MapAnimationOptions(duration: 450),
      );
    } catch (_) {}
  }

  void _applyMapOrnaments() {
    final map = _map;
    if (map == null) return;
    final topMargin = lastLocationScaleBarTopMargin(_safeTop);
    unawaited(
      map.scaleBar
          .updateSettings(
            mapbox.ScaleBarSettings(
              enabled: true,
              position: mapbox.OrnamentPosition.TOP_LEFT,
              marginTop: topMargin,
              marginLeft: 16.0,
            ),
          )
          .catchError((Object _) {}),
    );
    unawaited(
      map.compass
          .updateSettings(
            mapbox.CompassSettings(
              position: mapbox.OrnamentPosition.TOP_RIGHT,
              marginTop: topMargin,
              marginRight: 16.0,
            ),
          )
          .catchError((Object _) {}),
    );
  }

  Future<void> _loadMountainRoute({MountainPack? offlinePack}) async {
    final routeKey = offlinePack?.id ??
        'name:${widget.mountainName?.trim().toLowerCase() ?? ''}';
    _loadedRouteKey = routeKey;

    MountainPack? pack = offlinePack;
    if (pack == null) {
      final target = widget.mountainName?.trim().toLowerCase() ?? '';
      if (target.isEmpty) {
        if (mounted) {
          _routeLinesCoords = const <List<List<double>>>[];
          await _pushRouteToMap();
        }
        return;
      }
      final packs = MountainPackData.createDefaultPacks();
      for (final candidate in packs) {
        if (candidate.name.toLowerCase().contains(target) ||
            target.contains(candidate.name.toLowerCase()) ||
            target.contains(candidate.id.toLowerCase())) {
          pack = candidate;
          break;
        }
      }
    }

    if (pack == null) return;

    final loadedLines = <List<List<double>>>[];
    for (final trail in pack.package.trails) {
      List<LatLng> pts = const <LatLng>[];
      final assetPath = trail.gpxAssetPath;
      if (assetPath != null && assetPath.isNotEmpty) {
        try {
          final route = await GpxLoader.loadAsset(assetPath);
          pts = route.simplifiedPositions.length >= 2
              ? route.simplifiedPositions
              : route.positions;
        } catch (_) {}
      }
      if (pts.length < 2 && trail.points.length >= 2) {
        pts = trail.points;
      }
      if (pts.length >= 2) {
        loadedLines.add(<List<double>>[
          for (final p in pts) <double>[p.lon, p.lat],
        ]);
      }
    }

    if (loadedLines.isEmpty &&
        pack.gpxAssetPath != null &&
        pack.gpxAssetPath!.isNotEmpty) {
      try {
        final route = await GpxLoader.loadAsset(pack.gpxAssetPath!);
        final pts = route.simplifiedPositions.length >= 2
            ? route.simplifiedPositions
            : route.positions;
        if (pts.length >= 2) {
          loadedLines.add(<List<double>>[
            for (final p in pts) <double>[p.lon, p.lat],
          ]);
        }
      } catch (_) {}
    }

    if (!mounted) return;
    _routeLinesCoords = loadedLines;
    await _pushRouteToMap();
  }

  String _routeGeoJson() {
    if (_routeLinesCoords.isEmpty) {
      return jsonEncode(<String, Object?>{
        'type': 'FeatureCollection',
        'features': const <Object?>[],
      });
    }
    return jsonEncode(<String, Object?>{
      'type': 'FeatureCollection',
      'features': <Object?>[
        for (final line in _routeLinesCoords)
          <String, Object?>{
            'type': 'Feature',
            'properties': <String, Object?>{},
            'geometry': <String, Object?>{
              'type': 'LineString',
              'coordinates': line,
            },
          },
      ],
    });
  }

  String _membersGeoJson() {
    final features = <Map<String, Object?>>[];
    var hasSelf = false;
    for (final m in widget.members) {
      if (!_isValidCoord(m.lat, m.lon)) continue;
      if (m.displayName == 'Kamu') hasSelf = true;
      features.add(<String, Object?>{
        'type': 'Feature',
        'properties': <String, Object?>{
          'user_id': m.userId,
          'name': m.displayName,
          'initial': m.initial,
          'stale': _isStale(m) ? 1 : 0,
        },
        'geometry': <String, Object?>{
          'type': 'Point',
          'coordinates': <double>[m.lon!, m.lat!],
        },
      });
    }
    final liveSelf = widget.userLocation;
    if (!hasSelf &&
        liveSelf != null &&
        _isValidCoord(liveSelf.lat, liveSelf.lon)) {
      features.add(<String, Object?>{
        'type': 'Feature',
        'properties': const <String, Object?>{
          'user_id': 'self',
          'name': 'Kamu',
          'initial': 'K',
          'stale': 0,
        },
        'geometry': <String, Object?>{
          'type': 'Point',
          'coordinates': <double>[liveSelf.lon, liveSelf.lat],
        },
      });
    }
    return jsonEncode(<String, Object?>{
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  Future<void> _onStyleLoaded() async {
    final map = _map;
    if (map == null || _layersInstalled || !mounted) return;
    _layersInstalled = true;
    final colors = HiqeoColors.of(context);
    try {
      final routeSource = mapbox.GeoJsonSource(
        id: _routeSourceId,
        data: _routeGeoJson(),
      );
      final membersSource = mapbox.GeoJsonSource(
        id: _membersSourceId,
        data: _membersGeoJson(),
      );
      await map.addSource(routeSource);
      await map.addSource(membersSource);

      await map.addLayer(
        mapbox.LineLayer(
          id: _routeCasingLayerId,
          sourceId: _routeSourceId,
          lineColor: colors.background.toARGB32(),
          lineWidth: 7.0,
          lineCap: mapbox.LineCap.ROUND,
          lineJoin: mapbox.LineJoin.ROUND,
        ),
      );
      await map.addLayer(
        mapbox.LineLayer(
          id: _routeLineLayerId,
          sourceId: _routeSourceId,
          lineColor: colors.primary.toARGB32(),
          lineWidth: 3.8,
          lineCap: mapbox.LineCap.ROUND,
          lineJoin: mapbox.LineJoin.ROUND,
        ),
      );
      await map.addLayer(
        mapbox.CircleLayer(
          id: _membersCircleLayerId,
          sourceId: _membersSourceId,
          circleRadius: 11.0,
          circleColor: const Color(0xFF2563EB).toARGB32(),
          circleStrokeWidth: 2.5,
          circleStrokeColor: Colors.white.toARGB32(),
        ),
      );
      await map.addLayer(
        mapbox.SymbolLayer(
          id: _membersLabelLayerId,
          sourceId: _membersSourceId,
          textField: '{name}',
          textSize: 11.5,
          textOffset: const <double>[0.0, 1.8],
          textColor: colors.textPrimary.toARGB32(),
          textHaloColor: colors.surface.toARGB32(),
          textHaloWidth: 1.5,
        ),
      );

      _routeSource = routeSource;
      _membersSource = membersSource;
      await _pushRouteToMap();
      await _pushMembersToMap();
    } catch (_) {
      _layersInstalled = false;
    }
  }

  Future<void> _pushRouteToMap() async {
    final source = _routeSource;
    if (source == null) return;
    try {
      await source.updateGeoJSON(_routeGeoJson());
    } catch (_) {}
  }

  Future<void> _pushMembersToMap() async {
    final source = _membersSource;
    if (source == null) return;
    try {
      await source.updateGeoJSON(_membersGeoJson());
    } catch (_) {}
  }

  bool get _canUseMapbox {
    if (kIsWeb) return false;
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    return SupabaseConfig.mapboxAccessToken.isNotEmpty;
  }

  bool _isStale(MemberLastLocation member) {
    if (!member.hasSignal) return true;
    final ageMin = widget.nowUtc
        .difference(member.effectiveRecordedAtUtc)
        .inMinutes;
    return ageMin > kStaleLocationMinutes;
  }

  String _timeLabelFor(MemberLastLocation member) {
    final diff = widget.nowUtc.difference(member.effectiveRecordedAtUtc);
    final mins = diff.inMinutes < 0 ? 0 : diff.inMinutes;
    final stale = _isStale(member);
    if (stale) {
      if (mins < 60) return 'Terakhir terlihat $mins menit lalu';
      return 'Terakhir terlihat ${diff.inHours} jam lalu';
    }
    if (mins <= 0) return 'Baru saja';
    return '$mins menit lalu';
  }

  Future<void> _centerOnMember(MemberLastLocation member) async {
    setState(() => _selectedMemberId = member.userId);
    widget.onSelectMember?.call(member);
    if (!_isValidCoord(member.lat, member.lon)) return;
    await _flyCameraTo(LatLng(member.lat!, member.lon!), zoom: 15.0);
  }

  Widget _buildTopBar(
    BuildContext context,
    HiqeoColors colors,
    ThemeData theme,
    LastLocationMapDecision decision,
  ) {
    final String subtitle = switch (decision.mode) {
      LastLocationMapMode.onlineMap => '${widget.groupName} · Online',
      LastLocationMapMode.offlineDownloadedMountain =>
        '${widget.groupName} · Offline (${decision.matchedOfflinePack!.name})',
      LastLocationMapMode.lockingGps =>
        '${widget.groupName} · Mengunci posisi GPS',
      LastLocationMapMode.offlineUnavailable =>
        '${widget.groupName} · Offline',
    };

    final String pillLabel = switch (decision.mode) {
      LastLocationMapMode.onlineMap => 'Realtime',
      LastLocationMapMode.offlineDownloadedMountain => 'Peta Offline',
      LastLocationMapMode.lockingGps => 'Mencari GPS',
      LastLocationMapMode.offlineUnavailable => 'Offline',
    };

    final Color pillDotColor = switch (decision.mode) {
      LastLocationMapMode.onlineMap => const Color(0xFF22C55E),
      LastLocationMapMode.offlineDownloadedMountain => colors.primary,
      LastLocationMapMode.lockingGps => colors.warning,
      LastLocationMapMode.offlineUnavailable => colors.warning,
    };

    return GlassSurface(
      tier: GlassTier.overMap,
      borderRadius: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: <Widget>[
          HiqeoBackButton(
            key: const ValueKey<String>('last-location-back'),
            overMap: true,
            onTap: widget.onBack,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Lokasi terakhir',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: colors.hairline,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: pillDotColor,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  pillLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomCard(
    BuildContext context,
    HiqeoColors colors,
    ThemeData theme,
    LastLocationMapDecision decision, {
    required double maxHeightFraction,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * maxHeightFraction,
      ),
      child: GlassSurface(
        key: const ValueKey<String>('last-location-card'),
        tier: GlassTier.overMap,
        borderRadius: 28,
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Pembaruan otomatis aktif selama GPS menyala + tombol manual bagikan ulang.
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Lokasi otomatis grup aktif',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Koordinat GPS diperbarui otomatis saat aplikasi berjalan',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 44,
                    child: FilledButton.icon(
                      key: const ValueKey<String>('last-location-reshare-btn'),
                      onPressed: (widget.onShareLocation == null || _resharing)
                          ? null
                          : () => unawaited(_handleReshareTap()),
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        minimumSize: const Size(44, 44),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      icon: _resharing
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.onPrimary,
                              ),
                            )
                          : const Icon(Icons.my_location_rounded, size: 16),
                      label: Text(
                        _resharing ? 'Memperbarui…' : 'Bagikan ulang lokasi',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(height: 1, color: colors.hairline),
              const SizedBox(height: 12),

              if (widget.members.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Belum ada anggota yang membagikan lokasi.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                )
              else
                for (var i = 0; i < widget.members.length; i++) ...<Widget>[
                  _MemberLocationRow(
                    member: widget.members[i],
                    stale: _isStale(widget.members[i]),
                    timeLabel: _timeLabelFor(widget.members[i]),
                    selected: _selectedMemberId == widget.members[i].userId,
                    onTap: () => unawaited(_centerOnMember(widget.members[i])),
                  ),
                  if (i < widget.members.length - 1) ...<Widget>[
                    const SizedBox(height: 10),
                    Container(height: 1, color: colors.hairline),
                    const SizedBox(height: 10),
                  ],
                ],

              if (!widget.isOnline) ...<Widget>[
                const SizedBox(height: 12),
                Container(height: 1, color: colors.hairline),
                const SizedBox(height: 8),
                Text(
                  decision.mode == LastLocationMapMode.offlineDownloadedMountain
                      ? 'Offline · menampilkan peta & jalur ${decision.matchedOfflinePack!.name} beserta posisi lokal/Mesh.'
                      : 'Offline · menampilkan posisi terakhir yang tersimpan di HP ini.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.warningText,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBody(
    BuildContext context,
    HiqeoColors colors,
    ThemeData theme,
    LastLocationMapDecision decision,
  ) {
    if (decision.mode == LastLocationMapMode.offlineUnavailable) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: GlassSurface(
            key: const ValueKey<String>('last-location-offline-unavailable'),
            tier: GlassTier.overMap,
            borderRadius: 26,
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.hairline,
                  ),
                  child: Icon(
                    Icons.map_outlined,
                    size: 28,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Peta tidak tersedia offline',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  kOfflineMapUnavailableMessage,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    height: 1.45,
                  ),
                ),
                if (widget.onOpenOfflineMaps != null) ...<Widget>[
                  const SizedBox(height: 18),
                  HiqeoButton(
                    key: const ValueKey<String>(
                      'last-location-open-maps-btn',
                    ),
                    label: 'Buka Peta & Unduh',
                    onPressed: widget.onOpenOfflineMaps,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // Mode lockingGps
    final status = widget.locationStatus;
    final gpsBlocked = status == LiveLocationStatus.serviceDisabled ||
        status == LiveLocationStatus.permissionDenied ||
        status == LiveLocationStatus.permissionDeniedForever ||
        status == LiveLocationStatus.error;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: GlassSurface(
          key: const ValueKey<String>('last-location-gps-loading'),
          tier: GlassTier.overMap,
          borderRadius: 26,
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (gpsBlocked)
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.hairline,
                  ),
                  child: Icon(
                    Icons.location_off_rounded,
                    size: 28,
                    color: colors.warning,
                  ),
                )
              else
                SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3.0,
                    color: colors.primary,
                  ),
                ),
              const SizedBox(height: 14),
              Text(
                gpsBlocked
                    ? 'Lokasi GPS belum aktif'
                    : 'Mencari sinyal GPS akurat…',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                gpsBlocked
                    ? 'Aktifkan layanan lokasi / izin GPS agar peta langsung memusat ke koordinat perangkatmu.'
                    : 'Mengunci koordinat perangkatmu sebelum memusatkan peta.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  height: 1.45,
                ),
              ),
              if (gpsBlocked && widget.onRetryLocation != null) ...<Widget>[
                const SizedBox(height: 18),
                HiqeoButton(
                  key: const ValueKey<String>('last-location-retry-gps-btn'),
                  label: 'Aktifkan GPS',
                  onPressed: widget.onRetryLocation,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final safeTop = MediaQuery.paddingOf(context).top;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final isDark = colors.brightness == Brightness.dark;
    final decision = _computeDecision();

    final showMap = decision.mode == LastLocationMapMode.onlineMap ||
        decision.mode == LastLocationMapMode.offlineDownloadedMountain;

    if (!showMap) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) widget.onBack();
        },
        child: Container(
          color: colors.background,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _buildTopBar(context, colors, theme, decision),
                ),
                Expanded(
                  child: _buildStatusBody(context, colors, theme, decision),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _buildBottomCard(
                    context,
                    colors,
                    theme,
                    decision,
                    maxHeightFraction: 0.40,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final cameraTarget = decision.cameraTarget!;
    final styleUri =
        decision.mode == LastLocationMapMode.offlineDownloadedMountain
            ? OfflinePackService.mapboxStyleUri
            : (isDark
                ? mapbox.MapboxStyles.DARK
                : mapbox.MapboxStyles.OUTDOORS);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onBack();
      },
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // 1. Peta Mapbox Penuh (atau fallback kontur topografi di uji/desktop)
          Positioned.fill(
            child: _canUseMapbox
                ? mapbox.MapWidget(
                    key: ValueKey<String>('last-location-mapbox-$styleUri'),
                    styleUri: styleUri,
                    onStyleLoadedListener: (_) => unawaited(_onStyleLoaded()),
                    onMapCreated: (map) {
                      _map = map;
                      _layersInstalled = false;
                      if (widget.userLocation != null) {
                        _centeredOnUserFix = true;
                      }
                      _applyMapOrnaments();
                      unawaited(
                        map
                            .setCamera(
                              mapbox.CameraOptions(
                                center: mapbox.Point(
                                  coordinates: mapbox.Position(
                                    cameraTarget.lon,
                                    cameraTarget.lat,
                                  ),
                                ),
                                zoom: 14.5,
                              ),
                            )
                            .catchError((Object _) {}),
                      );
                    },
                  )
                : RepaintBoundary(
                    child: CustomPaint(
                      painter: _TopographyCanvasPainter(
                        colors: colors,
                        members: widget.members,
                      ),
                    ),
                  ),
          ),

          // 2. Penanda Inisial 32 dp di atas Kanvas saat tidak pakai native Mapbox
          if (!_canUseMapbox)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final h = constraints.maxHeight;
                  return Stack(
                    children: <Widget>[
                      for (final m in widget.members)
                        Positioned(
                          left: (m.mapX * w) - 16,
                          top: (m.mapY * h) - 16,
                          child: GestureDetector(
                            onTap: () => unawaited(_centerOnMember(m)),
                            child: _MemberMapPin(
                              member: m,
                              stale: _isStale(m),
                              selected: _selectedMemberId == m.userId,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

          // 3. Bar Atas (GlassSurface tier overMap)
          Positioned(
            top: safeTop + 8,
            left: 16,
            right: 16,
            child: _buildTopBar(context, colors, theme, decision),
          ),

          // 4. Panel Bawah (GlassSurface tier overMap, radius 28)
          Positioned(
            left: 16,
            right: 16,
            bottom: safeBottom + 16,
            child: _buildBottomCard(
              context,
              colors,
              theme,
              decision,
              maxHeightFraction: 0.48,
            ),
          ),
        ],
      ),
    );
  }
}

/// Penanda inisial 32 dp pada peta (primer bila segar <= 15 menit, abu-abu bila lama).
class _MemberMapPin extends StatelessWidget {
  const _MemberMapPin({
    required this.member,
    required this.stale,
    required this.selected,
  });

  final MemberLastLocation member;
  final bool stale;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final fill = stale ? colors.secondary : colors.primary;
    final fg = stale ? colors.textSecondary : colors.onPrimary;

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(
          color: selected ? colors.warning : colors.glassBorder,
          width: selected ? 2.5 : 2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colors.glassShadow,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Text(
          member.initial,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: fg,
          ),
        ),
      ),
    );
  }
}

class _MemberLocationRow extends StatelessWidget {
  const _MemberLocationRow({
    required this.member,
    required this.stale,
    required this.timeLabel,
    required this.selected,
    required this.onTap,
  });

  final MemberLastLocation member;
  final bool stale;
  final String timeLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final badgeFill = stale ? colors.secondary : colors.primary;
    final badgeFg = stale ? colors.textSecondary : colors.onPrimary;

    final String subtitle;
    if (member.accuracyM != null && !stale) {
      subtitle = 'Akurasi ${member.accuracyM} m';
    } else if (stale) {
      subtitle = timeLabel;
    } else {
      subtitle = 'Lokasi aktif';
    }

    return InkWell(
      key: ValueKey<String>('last-location-row-${member.userId}'),
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: <Widget>[
            // Avatar persisten 40 dp (fallback inisial saat offline tanpa foto cache)
            PersistentAvatarImage(
              cacheKey: member.userId,
              size: 40,
              backgroundColor: badgeFill,
              border: selected
                  ? Border.all(color: colors.warning, width: 2)
                  : null,
              fallback: Center(
                child: Text(
                  member.initial,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: badgeFg,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ListenableBuilder(
                    listenable: PublicProfileCacheService.instance,
                    builder: (context, _) {
                      final resolvedName = member.displayName == 'Kamu'
                          ? 'Kamu'
                          : PublicProfileCacheService.instance
                              .resolveDisplayName(
                              member.userId,
                              fallback: member.displayName,
                            );
                      return Text(
                        resolvedName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: stale
                              ? colors.textSecondary
                              : colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    },
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
                ],
              ),
            ),
            if (!stale) ...<Widget>[
              const SizedBox(width: 8),
              Text(
                timeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopographyCanvasPainter extends CustomPainter {
  const _TopographyCanvasPainter({
    required this.colors,
    required this.members,
  });

  final HiqeoColors colors;
  final List<MemberLastLocation> members;

  @override
  void paint(Canvas canvas, Size size) {
    final contourPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = colors.hairline;

    final peakCenter = Offset(size.width * 0.62, size.height * 0.34);
    for (final rx in <double>[52, 110, 175, 250]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: peakCenter,
          width: rx * 1.45,
          height: rx * 2.0,
        ),
        contourPaint,
      );
    }

    if (members.length >= 2) {
      final path = Path()
        ..moveTo(
          members.first.mapX * size.width,
          members.first.mapY * size.height,
        );
      for (final m in members.skip(1)) {
        path.lineTo(m.mapX * size.width, m.mapY * size.height);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = colors.textSecondary.withValues(alpha: 0.40),
      );
    }
  }

  @override
  bool shouldRepaint(_TopographyCanvasPainter oldDelegate) =>
      oldDelegate.colors != colors || oldDelegate.members != members;
}
