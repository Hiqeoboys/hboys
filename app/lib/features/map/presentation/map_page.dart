import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui show Size;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:go_router/go_router.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../design/app_theme.dart';
import '../../../design/glass/glass_surface.dart';
import '../../../design/glass/hiqeo_liquid_glass.dart';
import '../../../design/system_ui.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/hiqeo_back_button.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/line_icons.dart';
import '../../../design/widgets/nav_bar_visibility.dart';
import '../../../infrastructure/location/shared_location_service.dart';
import '../../../infrastructure/map/asset_map_catalog_repository.dart';
import '../../../infrastructure/map/mapbox_offline_map_service.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../../compass/domain/compass_calibration.dart';
import '../../onboarding/permission_service.dart';
import '../../preparation/application/packing_list_store.dart';
import '../../safety/presentation/sos_page.dart';
import '../../tracking/application/tracking_controller.dart';
import '../../tracking/domain/track_point.dart';
import '../../tracking/domain/tracking_session.dart';
import '../../tracking/presentation/widgets/debug_simulation_panel.dart';
import '../../trails/application/recovery_guidance_service.dart';
import '../../trails/data/gpx_loader.dart';
import '../../trails/domain/guidance_state.dart';
import '../../trails/domain/heading_provider.dart';
import '../../trails/domain/track_route.dart';
import '../application/group_hike_member_tracker.dart';
import '../application/map_track_source.dart';
import '../application/offline_download_controller.dart';
import '../application/offline_map_service.dart';
import '../data/mountain_catalog_repository.dart';
import '../domain/map_package.dart';
import '../domain/mountain_pack_data.dart';
import '../domain/track_geojson.dart';
import 'offline_sheet.dart';
import 'widgets/directions_panel.dart';
import 'widgets/trail_map_bottom_panel.dart';

/// Konfigurasi titik awal tracking untuk pembaruan berikutnya.
const bool kRequireStartPointToTrack = false;

typedef MapCatalogLoader = Future<MapPackageCatalog> Function();
typedef GpxRouteLoader = Future<TrackRoute?> Function();

/// Jarak kanan tombol bulat (kompas, lokasiku, petunjuk jalur) dari tepi aman.
@visibleForTesting
const double mapControlRightMargin = 16;

/// Posisi atas minimum kolom tombol bulat kanan atas.
@visibleForTesting
const double mapControlTopOffset = 104;

/// Jarak vertikal antar tombol bulat di kanan atas.
@visibleForTesting
const double mapControlGap = 8;

/// Sisi tombol bulat; memenuhi target sentuh minimal 44 x 44 dp.
@visibleForTesting
const double mapControlSize = 44;

/// Alasan tombol petunjuk jalur belum bisa membuka panel.
enum DirectionsBlock {
  locationOff,
  permissionDenied,
  permissionDeniedForever,
  noRoute,
  searchingGps,
  locationError,
}

/// Menentukan apa yang menghalangi petunjuk jalur; `null` berarti siap.
///
/// Urutan: layanan lokasi, izin, jalur, lalu sinyal GPS. Lokasi dan izin
/// diperiksa lebih dulu karena itu syarat dasar yang harus dibereskan
/// pengguna di luar aplikasi.
@visibleForTesting
DirectionsBlock? directionsBlockFor({
  required LiveLocationState location,
  required bool hasFreshFix,
  required bool hasRoute,
}) {
  switch (location.status) {
    case LiveLocationStatus.serviceDisabled:
      return DirectionsBlock.locationOff;
    case LiveLocationStatus.permissionDenied:
      return DirectionsBlock.permissionDenied;
    case LiveLocationStatus.permissionDeniedForever:
      return DirectionsBlock.permissionDeniedForever;
    case LiveLocationStatus.idle:
    case LiveLocationStatus.searching:
    case LiveLocationStatus.active:
    case LiveLocationStatus.error:
      break;
  }
  if (!hasRoute) return DirectionsBlock.noRoute;
  if (hasFreshFix) return null;
  if (location.status == LiveLocationStatus.error) {
    return DirectionsBlock.locationError;
  }
  return DirectionsBlock.searchingGps;
}

/// Opasitas lapisan peredup peta pada mode gelap.
///
/// Gaya peta tetap `OUTDOORS` agar style pack offline yang sudah diunduh tetap
/// terpakai tanpa jaringan. Peredup navy menurunkan silau peta terang di bawah
/// kaca gelap; atribusi dan layer jalur tetap terlihat.
@visibleForTesting
double mapDimOpacityFor(Brightness brightness) =>
    brightness == Brightness.dark ? 0.35 : 0.0;

/// Jarak kecil antara navbar mengambang dan logo/atribusi Mapbox.
@visibleForTesting
const double mapOrnamentGap = 8;

/// Ruang yang disisakan di bawah panel panduan untuk logo dan atribusi
/// Mapbox, supaya keduanya tetap terlihat dan bisa diketuk.
@visibleForTesting
const double mapAttributionInset = 44;

/// Margin bawah logo dan atribusi Mapbox: di atas navbar mengambang.
@visibleForTesting
double mapOrnamentBottomMargin(double systemInset) =>
    HiqeoMetrics.floatingBottomInset(systemInset) + mapOrnamentGap;

/// Jarak panel panduan dari tepi bawah layar: di atas navbar dan baris
/// logo/atribusi.
@visibleForTesting
double mapSheetBottomOffset(double systemInset) =>
    HiqeoMetrics.floatingBottomInset(systemInset) + mapAttributionInset;

/// Jarak panel bawah dari tepi layar saat navbar tampil: 88 dp + safe area bawah.
@visibleForTesting
double mapBottomPanelOffset(double systemInset) => 88.0 + systemInset;

/// Layar Peta Offline: peta penuh, kartu status jalur, tombol kompas dan
/// pemusatan posisi, serta sheet panduan jalur/pengelolaan unduhan.
class MapPage extends StatefulWidget {
  MapPage({
    super.key,
    this.initialPackage,
    this.initialTrail,
    this.allowStartAscent = true,
    this.autoStartTracking = false,
    this.activeGroupId,
    this.activeGroupName,
    this.startButtonLabel = 'Mulai tracking',
    this.memberTracker,
    MapCatalogLoader? catalogLoader,
    GpxRouteLoader? gpxRouteLoader,
    OfflineMapService? offlineService,
    MapTrackSource? trackSource,
    this.mapboxToken,
    this.trackPollInterval = const Duration(seconds: 5),
    this.compassEvents,
    this.compassOffsetStore,
    this.locationService,
    this.guidanceService,
    this.permissionService = const PermissionService(),
    this.groupHikePlanStore,
    this.onCompassReset,
    this.onRecenterPressed,
  })  : catalogLoader = catalogLoader ?? _loadAssetCatalog,
        gpxRouteLoader = gpxRouteLoader ?? _loadDefaultGpxRoute,
        offlineService = offlineService ?? MapboxOfflineMapService(),
        trackSource = trackSource ?? const TrackingControllerMapTrackSource();

  static Future<MapPackageCatalog> _loadAssetCatalog() =>
      AssetMapCatalogRepository().load();

  static Future<TrackRoute?> _loadDefaultGpxRoute() async {
    try {
      return await GpxLoader.loadAsset(GpxLoader.defaultGpxAssetPath);
    } catch (_) {
      return null;
    }
  }

  final MountainMapPackage? initialPackage;
  final MapTrail? initialTrail;

  /// Menentukan apakah tombol "Mulai pendakian" / "Mulai tracking" ditampilkan.
  /// Saat dibuka langsung lewat tab Peta, bernilai `false` (hanya "Mulai turun").
  final bool allowStartAscent;

  /// Jika `true` (dipicu event grup `hike_started`), langsung memulai tracking
  /// atau menahan lewat kartu izin GPS di tempat bila izin/GPS belum aktif.
  final bool autoStartTracking;
  final String? activeGroupId;
  final String? activeGroupName;
  final String startButtonLabel;
  final GroupHikeMemberTracker? memberTracker;

  final MapCatalogLoader catalogLoader;
  final GpxRouteLoader gpxRouteLoader;
  final OfflineMapService offlineService;
  final MapTrackSource trackSource;

  /// Null berarti memakai `--dart-define=MAPBOX_ACCESS_TOKEN=...`.
  final String? mapboxToken;
  final Duration trackPollInterval;

  /// Disuntikkan untuk uji; produksi memakai sensor perangkat.
  final Stream<CompassEvent>? compassEvents;
  final CompassOffsetStore? compassOffsetStore;

  /// Layanan lokasi bersama. Null memakai [SharedLocationService.instance];
  /// uji menyuntikkan sendiri.
  final SharedLocationService? locationService;

  /// Layanan pemandu kembali ke jalur. Null membuat instance default.
  final RecoveryGuidanceService? guidanceService;

  /// Layanan pengecekan izin lokasi dan notifikasi.
  final PermissionService permissionService;

  /// Store rencana pendakian grup; null memakai [GroupHikePlanStore.instance].
  final GroupHikePlanStore? groupHikePlanStore;

  /// Hook opsional untuk uji tombol Kompas (reset arah ke utara).
  final VoidCallback? onCompassReset;

  /// Hook opsional untuk uji tombol Lokasiku (pusatkan kamera ke pengguna).
  final VoidCallback? onRecenterPressed;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const _gpxRouteSourceId = 'nama-gpx-route-source';
  static const _gpxStartSourceId = 'nama-gpx-start-source';
  static const _gpxEndSourceId = 'nama-gpx-end-source';
  static const _trackSourceId = 'nama-track-source';
  static const _positionSourceId = 'nama-position-source';
  static const _groupMembersSourceId = 'nama-group-members-source';
  static const _gpxRouteCasingLayerId = 'nama-gpx-route-casing';
  static const _gpxRouteLayerId = 'nama-gpx-route-line';
  static const _gpxStartMarkerLayerId = 'nama-gpx-start-marker';
  static const _gpxEndMarkerLayerId = 'nama-gpx-end-marker';
  static const _trackCasingLayerId = 'nama-track-casing';
  static const _trackLayerId = 'nama-track-line';
  static const _positionHaloLayerId = 'nama-position-halo';
  static const _positionDotLayerId = 'nama-position-dot';
  static const _groupMembersRingLayerId = 'nama-group-members-ring';
  static const _groupMembersAvatarLayerId = 'nama-group-members-avatar';
  static const _groupMembersLabelLayerId = 'nama-group-members-label';
  static const _guidanceTrailSourceId = 'nama-guidance-trail-source';
  static const _guidanceStraightSourceId = 'nama-guidance-straight-source';
  static const _guidanceTargetSourceId = 'nama-guidance-target-source';
  static const _guidanceTrailBaseLayerId = 'nama-guidance-trail-base';
  static const _guidanceTrailDotsLayerId = 'nama-guidance-trail-dots';
  static const _guidanceStraightLayerId = 'nama-guidance-straight-line';
  static const _guidanceTargetLayerId = 'nama-guidance-target-ring';

  static const Color _gpxStartMarkerColor = Color(0xFF22C55E);
  static const Color _gpxEndMarkerColor = Color(0xFFEF4444);

  late final OfflineDownloadController _offlineController;

  late final AnimationController _entranceController;
  late final AnimationController _pulsingController;
  late final Animation<double> _pulsingAnimation;
  late final AnimationController _panelTrackingController;
  late final Animation<double> _panelTrackingAnimation;
  late final AnimationController _directionsAnimController;
  late final Animation<double> _directionsScaleAnimation;

  final GlobalKey<TrailMapBottomPanelState> _bottomPanelKey =
      GlobalKey<TrailMapBottomPanelState>();

  bool _isOnline = true;

  MapPackageCatalog? _catalog;
  bool _catalogLoading = true;
  String? _catalogError;

  TrackRoute? _gpxRoute;

  MountainMapPackage? _selectedPackage;
  MapTrail? _selectedTrail;

  List<TrackPoint> _trackPoints = const [];
  TrackPoint? _latestPoint;
  Timer? _trackTimer;
  bool _trackRefreshInFlight = false;
  String? _trackError;

  MapboxMap? _map;
  GeoJsonSource? _gpxRouteSource;
  GeoJsonSource? _gpxStartSource;
  GeoJsonSource? _gpxEndSource;
  GeoJsonSource? _trackSource;
  GeoJsonSource? _positionSource;
  GeoJsonSource? _groupMembersSource;
  GeoJsonSource? _guidanceTrailSource;
  GeoJsonSource? _guidanceStraightSource;
  GeoJsonSource? _guidanceTargetSource;
  bool _userPannedMap = false;
  bool _layersInstalled = false;
  bool _styleReady = false;
  bool _overviewApplied = false;
  bool _cameraInitialized = false;
  bool _sheetVisible = false;
  Brightness? _lastBrightness;
  double _systemInset = 0;

  // Lokasi bersama: lease hanya dipegang saat tab Peta terlihat dan aplikasi
  // di latar depan, supaya tidak ada aliran GPS yang menyala percuma dan
  // tidak berebut dengan rekaman di tab Track.
  late final SharedLocationService _location;
  late final GroupHikePlanStore _groupPlanStore;
  late final GroupHikeMemberTracker _memberTracker;
  late final bool _ownsMemberTracker;
  late final RecoveryGuidanceService _guidanceService;
  late final bool _ownsGuidanceService;
  StreamSubscription<GuidanceState>? _guidanceSub;
  bool _straightLineAcknowledged = false;
  LocationLease? _lease;
  bool _tabVisible = true;
  bool _appActive = true;
  bool _directionsOpen = false;
  bool _directionsMinimized = false;
  bool _directionsBusy = false;
  bool _showDebugSimulation = false;
  bool _isMapTracking = false;
  bool _isDescentMode = false;
  bool _summitHandled = false;
  TrackRoute? _ascentGpxRoute;
  int _localTrackingSeconds = 0;
  Timer? _localTrackingTimer;
  PermissionReport? _blockingPermissionReport;
  bool _pendingAutoStartTracking = false;
  bool _autoStartAttempted = false;
  bool _hasRequestedLocationPrompt = false;
  Timer? _permissionPollTimer;
  bool _staleBannerCollapsed = false;
  final Set<String> _registeredMemberImageIds = <String>{};

  static const double _summitArrivalToleranceM = 80.0;

  bool get _isTrackingActive =>
      !_isDescentMode &&
      (_isMapTracking || TrackingController.instance.isRecording);

  String get _token =>
      (widget.mapboxToken ?? SupabaseConfig.mapboxAccessToken).trim();

  bool get _platformSupportsMap =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _mapAvailable => _token.isNotEmpty && _platformSupportsMap;

  /// Posisi pengguna untuk titik di peta: fix segar dari layanan lokasi
  /// bersama, jatuh ke titik rekaman terakhir bila belum ada.
  TrackPoint? get _userPoint => _location.freshPoint ?? _latestPoint;

  bool get _hasRoute =>
      _selectedTrail != null || (_gpxRoute != null && _gpxRoute!.isNotEmpty);

  TrackRoute? get _effectiveRoute {
    final gpx = _gpxRoute;
    if (gpx != null && gpx.isNotEmpty) return gpx;
    final trail = _selectedTrail;
    if (trail != null && trail.points.isNotEmpty) {
      return TrackRoute.fromPoints(
        id: trail.id,
        name: trail.name,
        points: trail.points
            .map((p) => TrackRoutePoint(lat: p.lat, lon: p.lon))
            .toList(growable: false),
      );
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final defaultPkg = widget.initialPackage ??
        MountainPackData.createDefaultPacks().first.package;
    _selectedPackage = defaultPkg;
    _selectedTrail = widget.initialTrail ??
        (defaultPkg.trails.isNotEmpty ? defaultPkg.trails.first : null);

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );

    final isRecording = _isTrackingActive;
    if (isRecording) {
      _syncMapTrackingNavVisibility(deferred: true);
    }

    _pulsingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    if (isRecording) {
      _pulsingController.repeat(reverse: true);
    }
    _pulsingAnimation =
        Tween<double>(begin: 0.35, end: 1.0).animate(_pulsingController);
    _panelTrackingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: isRecording ? 0.0 : 1.0,
    );
    _panelTrackingAnimation = CurvedAnimation(
      parent: _panelTrackingController,
      curve: const Cubic(0.4, 0.0, 0.2, 1.0),
    );

    _directionsAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      value: isRecording ? 1.0 : 0.0,
    );
    _directionsScaleAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _directionsAnimController,
        curve: Curves.easeOutBack,
      ),
    );

    _location = widget.locationService ?? SharedLocationService.instance;
    _location.addListener(_onLocationChanged);
    _groupPlanStore = widget.groupHikePlanStore ?? GroupHikePlanStore.instance;
    _groupPlanStore.addListener(_onGroupPlanChanged);
    _memberTracker = widget.memberTracker ?? GroupHikeMemberTracker();
    _ownsMemberTracker = widget.memberTracker == null;
    _memberTracker.onNewStaleMembers = _onNewStaleMembers;
    _memberTracker.addListener(_onMemberTrackerChanged);
    unawaited(_refreshGroupHikePlan());
    _ownsGuidanceService = widget.guidanceService == null;
    _guidanceService = widget.guidanceService ??
        RecoveryGuidanceService(
          locationService: _location,
          headingProvider: HeadingProvider(
            compassStream: widget.compassEvents,
          ),
        );
    _offlineController =
        OfflineDownloadController(service: widget.offlineService);
    if (_mapAvailable) {
      MapboxOptions.setAccessToken(_token);
    }
    unawaited(_loadCatalog());
    unawaited(_loadGpxRoute());
    TrackingController.instance.addListener(_onLiveTrackingTick);
    _trackTimer = Timer.periodic(
      widget.trackPollInterval,
      (_) => unawaited(_refreshTrack()),
    );
    unawaited(_refreshTrack());
    unawaited(_checkConnectivity());
    _entranceController.forward();
    if (widget.autoStartTracking) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_attemptAutoStartGroupTracking());
      });
    }
    _syncGroupMemberTracking();
  }

  @override
  void didUpdateWidget(MapPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoStartTracking && !oldWidget.autoStartTracking) {
      _autoStartAttempted = false;
      unawaited(_attemptAutoStartGroupTracking());
    }
    if (widget.activeGroupId != oldWidget.activeGroupId ||
        widget.initialPackage?.id != oldWidget.initialPackage?.id) {
      _syncGroupMemberTracking();
    }
  }

  Future<void> _checkConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (mounted) {
        setState(() {
          _isOnline = results.any((r) => r != ConnectivityResult.none);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isOnline = true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cabang tab yang tidak aktif dibungkus TickerMode(enabled: false) oleh
    // go_router, jadi ini penanda Peta sedang terlihat atau tidak.
    _tabVisible = TickerMode.valuesOf(context).enabled;
    _syncLocationLease();
    // Inset sistem mentah dari kerangka tab; di dalam Scaffold ber-extendBody
    // padding bawah sudah termasuk tinggi navbar dan viewPadding dibuang.
    final bottomInset = HiqeoSystemInset.bottomOf(context);
    if (bottomInset != _systemInset) {
      _systemInset = bottomInset;
      _updateMapOrnaments();
    }
    final brightness = Theme.of(context).brightness;
    if (_lastBrightness == brightness) return;
    _lastBrightness = brightness;
    if (_styleReady) {
      unawaited(_syncLayerPalette());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` terjadi saat dialog izin sistem tampil; jangan lepas lease.
    switch (state) {
      case AppLifecycleState.resumed:
        _appActive = true;
        _syncLocationLease();
        // Pengguna mungkin baru menyalakan lokasi atau memberi izin di
        // pengaturan.
        unawaited(_location.refresh());
        unawaited(_refreshGroupHikePlan());
        if (_blockingPermissionReport != null) {
          unawaited(_recheckInPlaceLocationGate());
        }
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _appActive = false;
        _syncLocationLease();
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _syncMapTrackingNavVisibility({bool deferred = false}) {
    final active = _tabVisible && _isTrackingActive;
    final onRoute = _tabVisible;
    if (deferred) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        NavBarVisibilityController.instance.setRouteScreenOpen(_tabVisible);
        NavBarVisibilityController.instance.setMapTrackingActive(
          _tabVisible && _isTrackingActive,
        );
      });
    } else {
      NavBarVisibilityController.instance.setRouteScreenOpen(onRoute);
      NavBarVisibilityController.instance.setMapTrackingActive(active);
    }
  }

  void _syncLocationLease() {
    final wanted = _tabVisible && _appActive;
    if (wanted && _lease == null) {
      _lease = _location.acquire();
    } else if (!wanted && _lease != null) {
      _lease!.release();
      _lease = null;
    }
    _syncMapTrackingNavVisibility(deferred: true);
  }

  void _onLocationChanged() {
    if (!mounted) return;
    // Melepas lease dari didChangeDependencies terjadi saat fase build; setState
    // di sana dilarang, jadi tunda sampai frame selesai.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onLocationChanged();
      });
      return;
    }
    setState(() {});
    unawaited(_pushPositionData());
    _checkSummitArrival();
    if (_blockingPermissionReport != null) {
      unawaited(_recheckInPlaceLocationGate());
    }
  }

  GroupHikePlan? get _blockingGroupPlan {
    if (!widget.allowStartAscent) return null;
    final plan = _activeGroupPlan;
    if (plan == null || plan.isStarted || plan.allMembersReady) return null;
    return plan;
  }

  GroupHikePlan? get _activeGroupPlan {
    final explicitGroupId = widget.activeGroupId?.trim();
    if (explicitGroupId != null && explicitGroupId.isNotEmpty) {
      return _groupPlanStore.activePlanForGroup(explicitGroupId);
    }
    return _groupPlanStore.activePlan;
  }

  String? get _activeGroupIdForTracking {
    final explicit = widget.activeGroupId?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return _groupPlanStore.activePlan?.groupId;
  }

  bool get _isGroupHikeActive {
    final gid = _activeGroupIdForTracking;
    if (gid == null || gid.isEmpty) return false;
    final plan = _activeGroupPlan;
    return _isTrackingActive || (plan != null && plan.isStarted);
  }

  bool get _isTrackingLockedByGroup => _blockingGroupPlan != null;

  void _onGroupPlanChanged() {
    if (!mounted) return;
    _syncGroupMemberTracking();
    setState(() {});
  }

  void _onNewStaleMembers(List<GroupHikeMemberState> newlyStale) {
    if (!mounted || newlyStale.isEmpty) return;
    unawaited(HapticFeedback.mediumImpact());
    setState(() => _staleBannerCollapsed = false);
  }

  void _onMemberTrackerChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onMemberTrackerChanged();
      });
      return;
    }
    unawaited(_pushGroupMembersData());
    setState(() {});
  }

  void _syncGroupMemberTracking() {
    final gid = _activeGroupIdForTracking;
    if (gid != null && gid.isNotEmpty && _isGroupHikeActive) {
      final uid = SupabaseServices.sharedAccountController?.user?.id ??
          SupabaseServices.clientOrNull?.auth.currentUser?.id ??
          '';
      unawaited(_memberTracker.start(groupId: gid, currentUserId: uid));
    } else if (_memberTracker.activeGroupId != null) {
      unawaited(_memberTracker.stop());
      unawaited(_pushGroupMembersData());
    }
  }

  Future<void> _refreshGroupHikePlan() async {
    await _groupPlanStore.load();
    final active = _groupPlanStore.activePlan;
    if (active != null) {
      await _groupPlanStore.refreshForGroup(
        active.groupId,
        groupName: active.groupName,
      );
      return;
    }
    final account = SupabaseServices.sharedAccountController;
    if (account == null || account.groups.isEmpty) return;
    final groupIds = <String>[for (final g in account.groups) g.group.id];
    final names = <String, String>{
      for (final g in account.groups) g.group.id: g.group.name,
    };
    await _groupPlanStore.refreshForGroups(groupIds, groupNamesById: names);
  }

  @override
  void dispose() {
    NavBarVisibilityController.instance.setRouteScreenOpen(false);
    NavBarVisibilityController.instance.setMapTrackingActive(false);
    _permissionPollTimer?.cancel();
    _permissionPollTimer = null;
    _localTrackingTimer?.cancel();
    _localTrackingTimer = null;
    _guidanceSub?.cancel();
    _guidanceSub = null;
    WidgetsBinding.instance.removeObserver(this);
    _memberTracker.onNewStaleMembers = null;
    _memberTracker.removeListener(_onMemberTrackerChanged);
    if (_ownsMemberTracker) {
      _memberTracker.dispose();
    } else {
      unawaited(_memberTracker.stop());
    }
    _groupPlanStore.removeListener(_onGroupPlanChanged);
    _location.removeListener(_onLocationChanged);
    _lease?.release();
    _lease = null;
    TrackingController.instance.removeListener(_onLiveTrackingTick);
    _trackTimer?.cancel();
    if (_ownsGuidanceService) {
      _guidanceService.dispose();
    }
    _offlineController.dispose();
    _entranceController.dispose();
    _pulsingController.dispose();
    _panelTrackingController.dispose();
    _directionsAnimController.dispose();
    super.dispose();
  }

  void _onLiveTrackingTick() {
    if (!mounted) return;
    if (!TrackingController.instance.isRecording &&
        TrackingController.instance.phase == TrackingPhase.finished) {
      _isMapTracking = false;
      _localTrackingTimer?.cancel();
      _localTrackingTimer = null;
    }
    final isRecording = _isTrackingActive;
    NavBarVisibilityController.instance.setMapTrackingActive(
      _tabVisible && isRecording,
    );
    if (isRecording) {
      _syncGroupMemberTracking();
      if (!_pulsingController.isAnimating) {
        _pulsingController.repeat(reverse: true);
      }
      if (_panelTrackingController.status != AnimationStatus.reverse &&
          _panelTrackingController.value > 0) {
        _panelTrackingController.reverse();
      }
      if (_directionsAnimController.status != AnimationStatus.forward &&
          _directionsAnimController.value < 1.0) {
        _directionsAnimController.forward();
      }
    } else {
      if (_pulsingController.isAnimating) {
        _pulsingController.stop();
      }
      if (_panelTrackingController.status != AnimationStatus.forward &&
          _panelTrackingController.value < 1.0) {
        _panelTrackingController.forward();
      }
      if (_directionsAnimController.status != AnimationStatus.reverse &&
          _directionsAnimController.value > 0.0) {
        _directionsAnimController.reverse();
      }
      if (_directionsOpen) {
        _closeDirections();
      }
      _straightLineAcknowledged = false;
    }
    unawaited(_refreshTrack());
    setState(() {});
  }

  Future<void> _loadGpxRoute() async {
    try {
      final trailAsset =
          _selectedTrail?.gpxAssetPath ?? _selectedPackage?.gpxAssetPath;
      TrackRoute? route;
      if (trailAsset != null && trailAsset.isNotEmpty) {
        try {
          route = await GpxLoader.loadAsset(
            trailAsset,
            id: _selectedTrail?.id ?? _selectedPackage?.id,
            defaultName:
                _selectedTrail?.name ?? _selectedPackage?.name ?? 'Jalur',
          );
        } catch (_) {
          route = null;
        }
      }
      // Gunakan fallback ke koordinat trail hanya jika berkas GPX tidak ada,
      // agar tidak menggambar garis lurus buatan di atas jalur gunung asli.
      if ((route == null || route.isEmpty) &&
          (trailAsset == null || trailAsset.isEmpty) &&
          _selectedTrail != null &&
          _selectedTrail!.points.length >= 2) {
        route = TrackRoute.fromPoints(
          id: _selectedTrail!.id,
          name: _selectedTrail!.name,
          points: _selectedTrail!.points
              .map((p) => TrackRoutePoint(lat: p.lat, lon: p.lon))
              .toList(growable: false),
        );
      }
      route ??= await widget.gpxRouteLoader();
      if (!mounted || route == null || route.isEmpty) return;
      setState(() {
        _ascentGpxRoute = route;
        _gpxRoute = _isDescentMode ? route!.reversed() : route;
      });
      await _pushGpxRouteData();
      unawaited(_maybeApplyInitialCamera());
    } catch (_) {
      // Gagal membaca GPX opsional tidak boleh menghentikan halaman Peta.
    }
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _catalogLoading = true;
      _catalogError = null;
    });
    try {
      final catalog = await widget.catalogLoader();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _catalogLoading = false;
        if (widget.initialPackage == null && catalog.packages.isEmpty) {
          _selectedPackage = null;
          _selectedTrail = null;
        }
      });
    } catch (error) {
      if (kDebugMode) {
        debugPrint('MapPage._loadCatalog failed: $error');
      }
      if (!mounted) return;
      setState(() {
        _catalogLoading = false;
        _catalogError = 'Daftar paket peta belum bisa dimuat. Coba lagi nanti.';
      });
    }
  }

  Future<void> _refreshTrack() async {
    if (_trackRefreshInFlight) return;
    _trackRefreshInFlight = true;
    try {
      final snapshot = await widget.trackSource.load();
      if (!mounted) return;
      final latestChanged =
          snapshot.latestPoint?.timestampUtc != _latestPoint?.timestampUtc;
      final listChanged = snapshot.points.length != _trackPoints.length;
      final hadError = _trackError != null;
      // Polling tiap beberapa detik sering tidak menemukan data baru; lewati
      // rebuild dan dorongan GeoJSON agar layar tidak di-render percuma.
      if (!latestChanged && !listChanged && !hadError) return;
      setState(() {
        _trackPoints = snapshot.points;
        _latestPoint = snapshot.latestPoint;
        _trackError = null;
      });
      if (latestChanged || listChanged) {
        await _pushTrackData();
        await _pushPositionData();
        _checkSummitArrival();
        unawaited(_maybeApplyInitialCamera());
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('MapPage._refreshTrack failed: $error');
      }
      if (!mounted) return;
      setState(() {
        _trackError = 'Jejak perjalanan di perangkat belum dapat dibaca.';
      });
      _trackTimer?.cancel();
      _trackTimer = null;
    } finally {
      _trackRefreshInFlight = false;
    }
  }

  void _selectPackage(MountainMapPackage package) {
    setState(() {
      _selectedPackage = package;
      _selectedTrail = package.trails.isEmpty ? null : package.trails.first;
      _cameraInitialized = false;
    });
    _offlineController.select(package);
    unawaited(_pushSelectedTrailData());
    if (_styleReady && _map != null) {
      _cameraInitialized = true;
      unawaited(_fitSelectedPackage());
    }
  }

  Future<void> _pushGroupMembersData() async {
    final source = _groupMembersSource;
    final map = _map;
    if (source == null || map == null || !_styleReady) return;
    final teammates = _memberTracker.teammates;
    final imageIdByUserId = <String, String>{};
    for (final m in teammates) {
      final imageId = 'member_${m.userId}_${m.isStale ? 'stale' : 'live'}';
      if (!_registeredMemberImageIds.contains(imageId)) {
        final png = await renderMemberMarkerPng(
          userId: m.userId,
          initial: m.initial,
          avatarUrl: m.avatarUrl,
          isStale: m.isStale,
        );
        if (!mounted) return;
        if (png != null && png.isNotEmpty) {
          try {
            await map.addImage(imageId, 2.0, StyleImage.bytes(png));
            _registeredMemberImageIds.add(imageId);
          } catch (_) {}
        }
      }
      if (_registeredMemberImageIds.contains(imageId)) {
        imageIdByUserId[m.userId] = imageId;
      }
    }
    try {
      await source.updateGeoJSON(
        groupMembersToGeoJson(
          teammates,
          imageIdByUserId: imageIdByUserId,
        ),
      );
    } catch (error) {
      _reportMapIssue('Gagal memperbarui layer anggota grup: $error');
    }
  }

  Future<void> _pushGpxRouteData() async {
    final routeSource = _gpxRouteSource;
    final startSource = _gpxStartSource;
    final endSource = _gpxEndSource;
    if (routeSource == null || startSource == null || endSource == null) return;
    try {
      await routeSource.updateGeoJSON(trackRouteLineToGeoJson(_gpxRoute));
      await startSource.updateGeoJSON(
        trackRouteMarkerToGeoJson(_gpxRoute?.startPoint, role: 'start'),
      );
      await endSource.updateGeoJSON(
        trackRouteMarkerToGeoJson(_gpxRoute?.endPoint, role: 'end'),
      );
    } catch (error) {
      _reportMapIssue('Gagal memperbarui layer jalur GPX: $error');
    }
  }

  Future<void> _pushTrackData() async {
    final source = _trackSource;
    if (source == null) return;
    try {
      await source.updateGeoJSON(trackPointsToGeoJson(_trackPoints));
    } catch (error) {
      _reportMapIssue('Gagal memperbarui layer jejak: $error');
    }
  }

  Future<void> _pushPositionData() async {
    final source = _positionSource;
    if (source == null) return;
    try {
      await source.updateGeoJSON(trackPointToGeoJson(_userPoint));
    } catch (error) {
      _reportMapIssue('Gagal memperbarui titik posisi: $error');
    }
  }

  void _reportMapIssue(String message) {
    if (!mounted) return;
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  void _onMapCreated(MapboxMap map) {
    _map = map;
    // Skala bawaan Mapbox berada di bawah status bar dan tidak ada di desain.
    unawaited(
      map.scaleBar
          .updateSettings(ScaleBarSettings(enabled: false))
          .catchError((Object _) {}),
    );
    _updateMapOrnaments();
  }

  /// Menaikkan logo dan tombol atribusi Mapbox ke atas navbar mengambang.
  void _updateMapOrnaments() {
    final map = _map;
    if (map == null) return;
    final margin = mapOrnamentBottomMargin(_systemInset);
    unawaited(
      map.logo
          .updateSettings(LogoSettings(marginBottom: margin))
          .catchError((Object _) {}),
    );
    unawaited(
      map.attribution
          .updateSettings(AttributionSettings(marginBottom: margin))
          .catchError((Object _) {}),
    );
  }

  void _onMapLoadError(MapLoadingErrorEventData event) {
    if (!mounted) return;
    if (kDebugMode) {
      debugPrint('Peta gagal dimuat: ${event.message}');
    }
  }

  Future<void> _onStyleLoaded() async {
    if (_layersInstalled || !mounted) return;
    _layersInstalled = true;
    final map = _map;
    if (map == null) return;

    final colors = HiqeoColors.of(context);
    try {
      final gpxRouteSource = GeoJsonSource(
        id: _gpxRouteSourceId,
        data: trackRouteLineToGeoJson(_gpxRoute),
      );
      final gpxStartSource = GeoJsonSource(
        id: _gpxStartSourceId,
        data: trackRouteMarkerToGeoJson(_gpxRoute?.startPoint, role: 'start'),
      );
      final gpxEndSource = GeoJsonSource(
        id: _gpxEndSourceId,
        data: trackRouteMarkerToGeoJson(_gpxRoute?.endPoint, role: 'end'),
      );
      final trackSource = GeoJsonSource(
        id: _trackSourceId,
        data: trackPointsToGeoJson(_trackPoints),
      );
      final positionSource = GeoJsonSource(
        id: _positionSourceId,
        data: trackPointToGeoJson(_userPoint),
      );
      final groupMembersSource = GeoJsonSource(
        id: _groupMembersSourceId,
        data: groupMembersToGeoJson(_memberTracker.teammates),
      );
      final guidanceTrailSource = GeoJsonSource(
        id: _guidanceTrailSourceId,
        data: latLngsToGeoJsonLine(const <LatLng>[]),
      );
      final guidanceStraightSource = GeoJsonSource(
        id: _guidanceStraightSourceId,
        data: latLngsToGeoJsonLine(const <LatLng>[]),
      );
      final guidanceTargetSource = GeoJsonSource(
        id: _guidanceTargetSourceId,
        data: latLngToGeoJsonPoint(null),
      );

      await map.addSource(gpxRouteSource);
      await map.addSource(gpxStartSource);
      await map.addSource(gpxEndSource);
      await map.addSource(trackSource);
      await map.addSource(positionSource);
      await map.addSource(groupMembersSource);
      await map.addSource(guidanceTrailSource);
      await map.addSource(guidanceStraightSource);
      await map.addSource(guidanceTargetSource);
      for (final layer in _mapLayers(colors)) {
        await map.addLayer(layer);
      }

      _gpxRouteSource = gpxRouteSource;
      _gpxStartSource = gpxStartSource;
      _gpxEndSource = gpxEndSource;
      _trackSource = trackSource;
      _positionSource = positionSource;
      _groupMembersSource = groupMembersSource;
      _guidanceTrailSource = guidanceTrailSource;
      _guidanceStraightSource = guidanceStraightSource;
      _guidanceTargetSource = guidanceTargetSource;
      if (!mounted) return;
      setState(() {
        _styleReady = true;
      });
      if (_memberTracker.teammates.isNotEmpty) {
        unawaited(_pushGroupMembersData());
      }
      await _maybeApplyInitialCamera();
    } catch (error) {
      if (!mounted) return;
      _reportMapIssue('Gagal menyiapkan layer peta: $error');
    }
  }

  List<Layer> _mapLayers(HiqeoColors colors) => <Layer>[
        LineLayer(
          id: _gpxRouteCasingLayerId,
          sourceId: _gpxRouteSourceId,
          lineColor: colors.background.toARGB32(),
          lineWidth: 10.0,
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
        ),
        LineLayer(
          id: _gpxRouteLayerId,
          sourceId: _gpxRouteSourceId,
          lineColor: colors.primary.toARGB32(),
          lineWidth: 4.5,
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
        ),
        LineLayer(
          id: _trackCasingLayerId,
          sourceId: _trackSourceId,
          lineColor: colors.background.toARGB32(),
          lineWidth: 5.0,
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
        ),
        // Jejak rekaman: putus-putus textSecondary, 2,4 px, pola 3/5, ujung bulat
        LineLayer(
          id: _trackLayerId,
          sourceId: _trackSourceId,
          lineColor: colors.textSecondary.toARGB32(),
          lineWidth: 2.4,
          lineDasharray: <double?>[3.0, 5.0],
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
        ),
        // Garis panduan (mode ikuti jejak): primary 6 px
        LineLayer(
          id: _guidanceTrailBaseLayerId,
          sourceId: _guidanceTrailSourceId,
          lineColor: colors.primary.toARGB32(),
          lineWidth: 6.0,
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
        ),
        // Lapisan atas titik mengalir onPrimary 2 px pola 4/8
        LineLayer(
          id: _guidanceTrailDotsLayerId,
          sourceId: _guidanceTrailSourceId,
          lineColor: colors.onPrimary.toARGB32(),
          lineWidth: 2.0,
          lineDasharray: <double?>[4.0, 8.0],
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
        ),
        // Garis lurus: warning 3,5 px pola 7/5 mengalir searah target
        LineLayer(
          id: _guidanceStraightLayerId,
          sourceId: _guidanceStraightSourceId,
          lineColor: colors.warning.toARGB32(),
          lineWidth: 3.5,
          lineDasharray: <double?>[7.0, 5.0],
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
        ),
        // Titik target: cincin 7 dp (primary, atau warning di garis lurus)
        CircleLayer(
          id: _guidanceTargetLayerId,
          sourceId: _guidanceTargetSourceId,
          circleRadius: 7.0,
          circleColor: Colors.transparent.toARGB32(),
          circleStrokeColor: colors.primary.toARGB32(),
          circleStrokeWidth: 2.5,
        ),
        CircleLayer(
          id: _gpxStartMarkerLayerId,
          sourceId: _gpxStartSourceId,
          circleColor: _gpxStartMarkerColor.toARGB32(),
          circleRadius: 7,
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 2.5,
        ),
        CircleLayer(
          id: _gpxEndMarkerLayerId,
          sourceId: _gpxEndSourceId,
          circleColor: _gpxEndMarkerColor.toARGB32(),
          circleRadius: 7,
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 2.5,
        ),
        CircleLayer(
          id: _positionHaloLayerId,
          sourceId: _positionSourceId,
          circleColor: colors.primary.withValues(alpha: 0.20).toARGB32(),
          circleOpacity: 0.6,
          circleRadius: 16,
        ),
        CircleLayer(
          id: _positionDotLayerId,
          sourceId: _positionSourceId,
          circleColor: colors.primary.toARGB32(),
          circleRadius: 7,
          circleStrokeColor: colors.background.toARGB32(),
          circleStrokeWidth: 3,
        ),
        CircleLayer(
          id: _groupMembersRingLayerId,
          sourceId: _groupMembersSourceId,
          circleRadius: 15.0,
          circleColorExpression: const <Object>[
            'case',
            <Object>[
              '==',
              <Object>['get', 'stale'],
              1
            ],
            '#64748B',
            '#2563EB',
          ],
          circleOpacityExpression: const <Object>[
            'case',
            <Object>[
              '==',
              <Object>['get', 'stale'],
              1
            ],
            0.55,
            0.9,
          ],
          circleStrokeWidth: 2.5,
          circleStrokeColorExpression: const <Object>[
            'case',
            <Object>[
              '==',
              <Object>['get', 'stale'],
              1
            ],
            '#D97706',
            '#FFFFFF',
          ],
        ),
        SymbolLayer(
          id: _groupMembersAvatarLayerId,
          sourceId: _groupMembersSourceId,
          iconImageExpression: const <Object>['get', 'icon_id'],
          iconSize: 0.68,
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          iconOpacityExpression: const <Object>[
            'case',
            <Object>[
              '==',
              <Object>['get', 'stale'],
              1
            ],
            0.65,
            1.0,
          ],
        ),
        SymbolLayer(
          id: _groupMembersLabelLayerId,
          sourceId: _groupMembersSourceId,
          textFieldExpression: const <Object>['get', 'label'],
          textSize: 11.5,
          textOffset: const <double>[0.0, 2.25],
          textAllowOverlap: true,
          textColor: colors.textPrimary.toARGB32(),
          textHaloColor: colors.surface.toARGB32(),
          textHaloWidth: 1.6,
        ),
      ];

  /// Gaya dasar peta sengaja tidak diganti saat tema berubah; hanya layer
  /// jalur, jejak, dan posisi yang diwarnai ulang agar tetap kontras.
  Future<void> _syncLayerPalette() async {
    final map = _map;
    if (map == null || !_styleReady) return;
    final colors = HiqeoColors.of(context);
    try {
      for (final layer in _mapLayers(colors)) {
        await map.updateLayer(layer);
      }
    } catch (error) {
      _reportMapIssue('Gagal memperbarui warna layer peta: $error');
    }
  }

  Future<void> _maybeApplyInitialCamera() async {
    if (!_styleReady || _cameraInitialized) return;
    if (_selectedPackage != null) {
      _cameraInitialized = true;
      await _fitSelectedPackage();
      return;
    }
    final gpxRoute = _gpxRoute;
    if (gpxRoute != null && gpxRoute.isNotEmpty) {
      _cameraInitialized = true;
      await _fitGpxRoute();
      return;
    }
    final point = _latestPoint;
    if (point != null) {
      _cameraInitialized = true;
      await _centerOn(point.position, 14);
      return;
    }
    if (_overviewApplied) return;
    _overviewApplied = true;
    await _showOverview();
  }

  Future<void> _showOverview() async {
    final map = _map;
    if (map == null) return;
    try {
      await map.setCamera(CameraOptions(
        center: Point(coordinates: Position(110.3695, -7.5)),
        zoom: 4.5,
        bearing: 0,
        pitch: 0,
      ));
    } catch (error) {
      _overviewApplied = false;
      _reportMapIssue('Gagal mengatur kamera awal: $error');
    }
  }

  Future<void> _fitSelectedPackage() async {
    final package = _selectedPackage;
    final map = _map;
    if (package == null || map == null || !_styleReady) return;
    final bounds = package.offline.bounds;
    try {
      final camera = await map.cameraForCoordinateBounds(
        CoordinateBounds(
          southwest: Point(coordinates: Position(bounds.west, bounds.south)),
          northeast: Point(coordinates: Position(bounds.east, bounds.north)),
          infiniteBounds: false,
        ),
        MbxEdgeInsets(top: 160, left: 40, bottom: 240, right: 40),
        0,
        0,
        package.offline.maxZoom.toDouble(),
        null,
      );
      if (!mounted || _selectedPackage?.id != package.id) return;
      await map.setCamera(camera);
      _overviewApplied = true;
    } catch (error) {
      _reportMapIssue('Gagal mengarahkan kamera ke paket: $error');
    }
  }

  Future<void> _fitGpxRoute() async {
    final route = _gpxRoute;
    final map = _map;
    if (route == null || route.isEmpty || map == null || !_styleReady) return;
    final bounds = route.bounds;
    final bottomPad = mapSheetBottomOffset(_systemInset) + 140;
    try {
      final camera = await map.cameraForCoordinateBounds(
        CoordinateBounds(
          southwest: Point(coordinates: Position(bounds.west, bounds.south)),
          northeast: Point(coordinates: Position(bounds.east, bounds.north)),
          infiniteBounds: false,
        ),
        MbxEdgeInsets(top: 230, left: 44, bottom: bottomPad, right: 44),
        0,
        0,
        16.0,
        null,
      );
      if (!mounted) return;
      await map.setCamera(camera);
      _overviewApplied = true;
    } catch (error) {
      _reportMapIssue('Gagal mengarahkan kamera ke jalur GPX: $error');
    }
  }

  Future<void> _centerOn(LatLng point, double zoom) async {
    final map = _map;
    if (map == null) return;
    try {
      await map.setCamera(CameraOptions(
        center: Point(coordinates: Position(point.lon, point.lat)),
        zoom: zoom,
        bearing: 0,
        pitch: 0,
      ));
    } catch (error) {
      _reportMapIssue('Gagal memusatkan peta: $error');
    }
  }

  /// Tombol petunjuk jalur selalu bisa ditekan. Bila syarat belum terpenuhi,
  /// alasan dan jalan keluarnya ditampilkan; bila terpenuhi, panel dibuka.
  Future<void> _onDirectionsPressed() async {
    if (_directionsBusy) return;
    if (_directionsOpen) {
      if (_directionsMinimized) {
        setState(() => _directionsMinimized = false);
        return;
      }
      _closeDirections();
      return;
    }
    _directionsBusy = true;
    try {
      // Periksa ulang layanan lokasi dan izin agar keputusan memakai kondisi
      // terbaru, bukan keadaan saat Peta dibuka.
      await _location.refresh();
      if (!mounted) return;
      final block = directionsBlockFor(
        location: _location.state,
        hasFreshFix: _location.freshPoint != null,
        hasRoute: _hasRoute,
      );
      if (block == null || block == DirectionsBlock.searchingGps) {
        final route = _effectiveRoute;
        if (route != null) {
          _startGuidance(route);
        }
        setState(() {
          _directionsOpen = true;
          _directionsMinimized = false;
        });
        return;
      }
      await _showDirectionsBlockSheet(block);
    } finally {
      _directionsBusy = false;
    }
  }

  void _startGuidance(TrackRoute route) {
    _userPannedMap = false;
    _guidanceSub?.cancel();
    _guidanceSub = _guidanceService.states.listen(_onGuidanceStateChanged);
    _guidanceService.start(route, initialTrail: _trackPoints);
    _onGuidanceStateChanged(_guidanceService.currentState);
  }

  Future<void> _updateGuidanceMapLayers(GuidanceState state) async {
    final map = _map;
    if (map == null || !_styleReady) return;
    final colors = HiqeoColors.of(context);

    try {
      if (state is GuidanceFollowingTrail) {
        await _guidanceTrailSource?.updateGeoJSON(
          latLngsToGeoJsonLine(state.guidePath),
        );
        await _guidanceStraightSource?.updateGeoJSON(
          latLngsToGeoJsonLine(const <LatLng>[]),
        );
        await _guidanceTargetSource?.updateGeoJSON(
          latLngToGeoJsonPoint(state.targetPoint),
        );
        await map.updateLayer(
          CircleLayer(
            id: _guidanceTargetLayerId,
            sourceId: _guidanceTargetSourceId,
            circleRadius: 7.0,
            circleColor: Colors.transparent.toARGB32(),
            circleStrokeColor: colors.primary.toARGB32(),
            circleStrokeWidth: 2.5,
          ),
        );
      } else if (state is GuidanceStraightLine) {
        final userFix = _userPoint;
        final points = <LatLng>[
          if (userFix != null) LatLng(userFix.lat, userFix.lon),
          state.targetPoint,
        ];
        await _guidanceTrailSource?.updateGeoJSON(
          latLngsToGeoJsonLine(const <LatLng>[]),
        );
        await _guidanceStraightSource?.updateGeoJSON(
          latLngsToGeoJsonLine(points),
        );
        await _guidanceTargetSource?.updateGeoJSON(
          latLngToGeoJsonPoint(state.targetPoint),
        );
        await map.updateLayer(
          CircleLayer(
            id: _guidanceTargetLayerId,
            sourceId: _guidanceTargetSourceId,
            circleRadius: 7.0,
            circleColor: Colors.transparent.toARGB32(),
            circleStrokeColor: colors.warning.toARGB32(),
            circleStrokeWidth: 2.5,
          ),
        );
      } else {
        await _guidanceTrailSource?.updateGeoJSON(
          latLngsToGeoJsonLine(const <LatLng>[]),
        );
        await _guidanceStraightSource?.updateGeoJSON(
          latLngsToGeoJsonLine(const <LatLng>[]),
        );
        await _guidanceTargetSource?.updateGeoJSON(
          latLngToGeoJsonPoint(null),
        );
      }
    } catch (_) {}
  }

  Future<void> _frameGuidanceTarget({bool force = false}) async {
    final map = _map;
    if (map == null || !_styleReady) return;
    if (_userPannedMap && !force) return;

    final userFix = _userPoint;
    final state = _guidanceService.currentState;
    LatLng? target;
    if (state is GuidanceFollowingTrail) {
      target = state.targetPoint;
    } else if (state is GuidanceStraightLine) {
      target = state.targetPoint;
    }

    if (userFix == null) return;
    final points = <Point>[
      Point(coordinates: Position(userFix.lon, userFix.lat)),
      if (target != null) Point(coordinates: Position(target.lon, target.lat)),
    ];

    final minLon =
        points.map((p) => p.coordinates.lng.toDouble()).reduce(math.min);
    final maxLon =
        points.map((p) => p.coordinates.lng.toDouble()).reduce(math.max);
    final minLat =
        points.map((p) => p.coordinates.lat.toDouble()).reduce(math.min);
    final maxLat =
        points.map((p) => p.coordinates.lat.toDouble()).reduce(math.max);

    final bottomPadding = mapSheetBottomOffset(_systemInset) + 180.0;
    try {
      final camera = await map.cameraForCoordinateBounds(
        CoordinateBounds(
          southwest: Point(coordinates: Position(minLon, minLat)),
          northeast: Point(coordinates: Position(maxLon, maxLat)),
          infiniteBounds: false,
        ),
        MbxEdgeInsets(
          top: 120.0,
          left: 24.0,
          bottom: bottomPadding,
          right: 24.0,
        ),
        0,
        0,
        17.0,
        null,
      );
      await map.setCamera(camera);
    } catch (_) {}
  }

  void _onGuidanceStateChanged(GuidanceState state) {
    if (!mounted) return;
    unawaited(_updateGuidanceMapLayers(state));
    if (_directionsOpen) {
      unawaited(_frameGuidanceTarget());
    }

    if (state is GuidanceStraightLine) {
      if (!_directionsOpen) {
        unawaited(HapticFeedback.heavyImpact());
      }
    } else if (state is GuidanceReturned) {
      unawaited(HapticFeedback.lightImpact());
      try {
        final view = View.of(context);
        SemanticsService.sendAnnouncement(
          view,
          'Kamu sudah kembali di jalur utama',
          TextDirection.ltr,
        );
      } catch (_) {}
    }
  }

  void _closeDirections() {
    _guidanceSub?.cancel();
    _guidanceSub = null;
    _userPannedMap = false;
    _guidanceService.stop();
    unawaited(_updateGuidanceMapLayers(
      const GuidanceUnavailable(GuidanceUnavailableReason.noRoute),
    ));
    if (mounted) {
      setState(() {
        _directionsOpen = false;
        _directionsMinimized = false;
      });
    }
  }

  void _openSos([BuildContext? targetContext]) {
    final ctx = targetContext ?? context;
    try {
      ctx.push('/sos');
    } catch (_) {
      Navigator.of(ctx).push(
        MaterialPageRoute<void>(builder: (_) => const SosPage()),
      );
    }
  }

  Future<void> _showDirectionsBlockSheet(DirectionsBlock block) async {
    final content = _directionsBlockContent(block);
    VoidCallback? afterClose;
    setState(() => _sheetVisible = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => _DirectionsReasonSheet(
          key: const ValueKey('map-directions-reason'),
          title: content.title,
          message: content.message,
          actionLabel: content.actionLabel,
          onAction: content.action == null
              ? null
              : () {
                  afterClose = content.action;
                  Navigator.of(sheetContext).pop();
                },
        ),
      );
    } finally {
      if (mounted) setState(() => _sheetVisible = false);
    }
    // Aksi dijalankan setelah sheet alasan tertutup supaya sheet berikutnya
    // (mis. peta offline) tidak ikut menyalakan kembali panel panduan.
    if (mounted) afterClose?.call();
  }

  ({String title, String message, String? actionLabel, VoidCallback? action})
      _directionsBlockContent(DirectionsBlock block) {
    switch (block) {
      case DirectionsBlock.locationOff:
        return (
          title: 'Lokasi mati',
          message: 'Nyalakan lokasi di HP agar posisimu terbaca di peta.',
          actionLabel: 'Buka pengaturan lokasi',
          action: () => unawaited(_location.openLocationSettings()),
        );
      case DirectionsBlock.permissionDenied:
        return (
          title: 'Izin lokasi belum diberikan',
          message: 'Beri izin lokasi agar petunjuk jalur tahu posisimu.',
          actionLabel: 'Beri izin',
          action: () => unawaited(_location.requestPermission()),
        );
      case DirectionsBlock.permissionDeniedForever:
        return (
          title: 'Izin lokasi ditolak',
          message: 'Izin ditolak permanen. Buka pengaturan aplikasi lalu '
              'izinkan lokasi.',
          actionLabel: 'Beri izin',
          action: () => unawaited(_location.openAppSettings()),
        );
      case DirectionsBlock.noRoute:
        return (
          title: 'Pilih jalur dulu',
          message: 'Pilih jalur lewat peta offline agar petunjuk punya tujuan.',
          actionLabel: 'Pilih jalur',
          action: () => unawaited(_openOfflineSheet()),
        );
      case DirectionsBlock.searchingGps:
        return (
          title: 'Mencari sinyal GPS',
          message: 'Tunggu sebentar atau pindah ke tempat terbuka. Petunjuk '
              'jalur aktif begitu posisimu ditemukan.',
          actionLabel: null,
          action: null,
        );
      case DirectionsBlock.locationError:
        return (
          title: 'Lokasi belum terbaca',
          message: 'Posisi belum bisa dibaca. Coba lagi sebentar lagi.',
          actionLabel: 'Coba lagi',
          action: () => unawaited(_location.refresh()),
        );
    }
  }

  Future<void> _openOfflineSheet() async {
    if (_offlineController.package != null) {
      unawaited(_offlineController.refreshStatus());
    }
    setState(() => _sheetVisible = true);
    try {
      await showOfflineMapSheet(
        context,
        catalog: _catalog,
        loading: _catalogLoading,
        error: _catalogError,
        controller: _offlineController,
        mapAvailable: _mapAvailable,
        onSelect: _selectPackage,
        onRetry: () => unawaited(_loadCatalog()),
      );
    } finally {
      if (mounted) setState(() => _sheetVisible = false);
    }
  }

  /// Mereset arah peta (bearing & pitch) kembali menghadap utara (0°).
  Future<void> _resetBearingToNorth() async {
    widget.onCompassReset?.call();
    final map = _map;
    if (map == null) return;
    try {
      await map.flyTo(
        CameraOptions(bearing: 0.0, pitch: 0.0),
        MapAnimationOptions(duration: 400),
      );
    } catch (error) {
      _reportMapIssue('Gagal mereset arah peta ke utara: $error');
    }
  }

  Widget _buildStaggeredTopBar({
    required Widget child,
    required bool disableAnimations,
  }) {
    if (disableAnimations) return child;
    final anim = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 380 / 550, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        if (anim.value >= 1.0) return child;
        return Opacity(
          opacity: anim.value,
          child: Transform.translate(
            offset: Offset(0, -10 * (1 - anim.value)),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildStaggeredFabs({
    required Widget child,
    required bool disableAnimations,
  }) {
    if (disableAnimations) return child;
    final anim = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(45 / 550, (45 + 380) / 550,
          curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        if (anim.value >= 1.0) return child;
        return Opacity(
          opacity: anim.value,
          child: Transform.translate(
            offset: Offset(0, -10 * (1 - anim.value)),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildStaggeredBottomPanel({
    required Widget child,
    required bool disableAnimations,
  }) {
    if (disableAnimations) return child;
    final anim = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 420 / 550, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        if (anim.value >= 1.0) return child;
        return Opacity(
          opacity: anim.value,
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - anim.value)),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext context, HiqeoColors colors) {
    final isRecording = _isTrackingActive;
    final status = TrackingController.instance.status;
    final mountainName = _selectedPackage?.name ?? 'Peta Jalur';

    return Row(
      children: [
        HiqeoBackButton(
          key: const ValueKey('map-back-button'),
          overMap: true,
          onTap: () => unawaited(_handleBack()),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: HiqeoLiquidGlassSurface(
            overMap: true,
            borderRadius: 26,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  // Judul Nama Gunung + Nama Via Jalur (tanpa pernah menampilkan nama file .gpx)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mountainName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                            height: 1.15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_selectedTrail != null)
                          Text(
                            _isDescentMode
                                ? '${_selectedTrail!.name} · Turun'
                                : _selectedTrail!.name,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: colors.textSecondary,
                              height: 1.15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Chip Status Kanan
                  GestureDetector(
                    key: const ValueKey('map-status-chip'),
                    behavior: HitTestBehavior.opaque,
                    onTap: isRecording
                        ? () {
                            NavBarVisibilityController.instance
                                .setMapTrackingActive(false);
                            context.go('/lacak');
                          }
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.hairline,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isDescentMode) ...[
                            Icon(
                              Icons.trending_down_rounded,
                              size: 14,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Mode turun',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                            ),
                          ] else if (isRecording) ...[
                            // Titik warning berdenyut
                            FadeTransition(
                              opacity: _pulsingAnimation,
                              child: Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: colors.warning,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Merekam ${_formatRecordingTimer(status?.movingSeconds ?? _localTrackingSeconds)}',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ] else ...[
                            // Titik primary + Offline / Online
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: colors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isOnline ? 'Online' : 'Offline',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: colors.textPrimary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<bool> _handleBack() async {
    if (_isTrackingActive) {
      final choice = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          final colors = HiqeoColors.of(dialogContext);
          return AlertDialog(
            backgroundColor: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'Tracking masih berjalan',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            content: Text(
              'Sesi perekaman sedang aktif di latar belakang. Pilih kelanjutan tracking:',
              style: TextStyle(
                fontSize: 14,
                color: colors.textSecondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop('stay'),
                child: Text(
                  'Tetap di peta',
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop('leave'),
                child: Text(
                  'Keluar dari peta',
                  style: TextStyle(color: colors.textPrimary),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop('stop'),
                child: Text(
                  'Selesaikan tracking',
                  style: TextStyle(
                    color: colors.warning,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      );

      if (choice == 'stay' || choice == null) {
        return false;
      }
      if (choice == 'stop') {
        final confirmed = await _confirmStopBeforeSummit();
        if (!confirmed) return false;
        await _finishActiveTracking(reachedSummit: false);
      } else {
        NavBarVisibilityController.instance.setMapTrackingActive(false);
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
      return false;
    }

    if (mounted) {
      Navigator.of(context).maybePop();
    }
    return true;
  }

  Future<bool> _confirmStopBeforeSummit() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = HiqeoColors.of(dialogContext);
        return AlertDialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Belum sampai puncak',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          content: Text(
            'Kamu belum mencapai titik puncak pada jalur ini. Yakin ingin menghentikan tracking sekarang? Sesi akan disimpan dengan status belum sampai puncak.',
            style: TextStyle(fontSize: 14, color: colors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Lanjut tracking'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Hentikan'),
            ),
          ],
        );
      },
    );
    return res == true;
  }

  Future<void> _finishActiveTracking({required bool reachedSummit}) async {
    _isMapTracking = false;
    _localTrackingTimer?.cancel();
    _localTrackingTimer = null;
    NavBarVisibilityController.instance.setMapTrackingActive(false);
    if (TrackingController.instance.isRecording) {
      await TrackingController.instance.stop(
        reachedSummit: reachedSummit,
        mountainName: _selectedPackage?.name,
        trailName: _selectedTrail?.name,
      );
    } else {
      unawaited(PackingListStore.instance.clearAll());
      unawaited(GroupHikePlanStore.instance.completeAndResetAfterHike());
    }
    if (mounted) {
      if (_panelTrackingController.value < 1.0) {
        _panelTrackingController.forward();
      }
      if (_directionsAnimController.value > 0.0) {
        _directionsAnimController.reverse();
      }
      _syncGroupMemberTracking();
      setState(() {});
    }
  }

  void _checkSummitArrival() {
    if (!_isTrackingActive || _isDescentMode || _summitHandled) return;
    final userPt = _userPoint;
    final route = _ascentGpxRoute ?? _effectiveRoute;
    final summit = route?.summitPoint;
    if (userPt == null || summit == null) return;
    final distToSummit = distanceMeters(userPt.position, summit.position);
    if (distToSummit <= _summitArrivalToleranceM) {
      _summitHandled = true;
      unawaited(_onSummitReached());
    }
  }

  Future<void> _onSummitReached() async {
    await _finishActiveTracking(reachedSummit: true);
    if (!mounted) return;
    unawaited(HapticFeedback.heavyImpact());
    final mountain = _selectedPackage?.name ?? 'puncak';
    final startDescent = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = HiqeoColors.of(dialogContext);
        return AlertDialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Row(
            children: [
              Icon(Icons.flag_rounded, color: colors.primary, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sampai di Puncak!',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Selamat! Kamu telah mencapai puncak $mountain. Tracking otomatis berhenti dan tersimpan ke Riwayat Pendakian.',
            style: TextStyle(fontSize: 14, color: colors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Tutup'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.trending_down_rounded, size: 18),
              label: const Text('Mulai turun'),
            ),
          ],
        );
      },
    );
    if (startDescent == true && mounted) {
      await _startDescentMode();
    }
  }

  Future<void> _startDescentMode() async {
    final baseRoute = _ascentGpxRoute ?? _effectiveRoute;
    if (baseRoute == null || baseRoute.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rute jalur belum tersedia.')),
        );
      }
      return;
    }
    final reversed = baseRoute.reversed();
    setState(() {
      _ascentGpxRoute ??= baseRoute;
      _isDescentMode = true;
      _gpxRoute = reversed;
    });
    await _pushGpxRouteData();
    if (_directionsAnimController.value < 1.0) {
      _directionsAnimController.forward();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Mode turun aktif (rute dibalik dari puncak ke awal, tidak direkam ke Riwayat).',
          ),
        ),
      );
    }
  }

  Future<void> _stopDescentMode() async {
    final original = _ascentGpxRoute;
    setState(() {
      _isDescentMode = false;
      if (original != null) {
        _gpxRoute = original;
      }
    });
    if (_directionsOpen) {
      _closeDirections();
    }
    if (_directionsAnimController.value > 0.0 && !_isTrackingActive) {
      _directionsAnimController.reverse();
    }
    await _pushGpxRouteData();
  }

  void _onTrailSelected(MapTrail trail) {
    if (_selectedTrail?.id == trail.id) return;
    setState(() {
      _selectedTrail = trail;
    });
    unawaited(_pushSelectedTrailData());
    if (_styleReady && _map != null) {
      unawaited(_fitSelectedTrail(trail));
    }
    if (_selectedPackage != null) {
      unawaited(MountainCatalogRepository.instance
          .saveSelectedTrailId(_selectedPackage!.id, trail.id));
    }
  }

  Future<void> _pushSelectedTrailData() async {
    final trail = _selectedTrail;
    if (trail != null) {
      TrackRoute? route;
      final assetPath = trail.gpxAssetPath;
      if (assetPath != null && assetPath.isNotEmpty) {
        try {
          route = await GpxLoader.loadAsset(
            assetPath,
            id: trail.id,
            defaultName: trail.name,
          );
        } catch (_) {
          route = null;
        }
      }
      if (route == null && trail.points.isNotEmpty) {
        route = TrackRoute.fromPoints(
          id: trail.id,
          name: trail.name,
          points: trail.points
              .map((p) => TrackRoutePoint(lat: p.lat, lon: p.lon))
              .toList(growable: false),
        );
      }
      if (route != null) {
        _ascentGpxRoute = route;
        _gpxRoute = _isDescentMode ? route.reversed() : route;
        await _pushGpxRouteData();
      }
    }
  }

  Future<void> _fitSelectedTrail(MapTrail trail) async {
    final map = _map;
    if (map == null || trail.points.isEmpty) return;
    double minLat = trail.points.first.lat;
    double maxLat = trail.points.first.lat;
    double minLon = trail.points.first.lon;
    double maxLon = trail.points.first.lon;
    for (final p in trail.points) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lon < minLon) minLon = p.lon;
      if (p.lon > maxLon) maxLon = p.lon;
    }
    final bounds = CoordinateBounds(
      southwest: Point(coordinates: Position(minLon, minLat)),
      northeast: Point(coordinates: Position(maxLon, maxLat)),
      infiniteBounds: false,
    );
    try {
      final camera = await map.cameraForCoordinateBounds(
        bounds,
        MbxEdgeInsets(
          top: 120,
          left: 32,
          bottom: mapBottomPanelOffset(_systemInset) + 60,
          right: 32,
        ),
        null,
        null,
        null,
        null,
      );
      await map.flyTo(camera, MapAnimationOptions(duration: 600));
    } catch (_) {}
  }

  Future<void> _recenterPosition() async {
    widget.onRecenterPressed?.call();
    final map = _map;
    final userPt = _userPoint;
    if (map != null && userPt != null) {
      try {
        await map.flyTo(
          CameraOptions(
            center: Point(coordinates: Position(userPt.lon, userPt.lat)),
            zoom: 14.5,
          ),
          MapAnimationOptions(duration: 500),
        );
        setState(() => _userPannedMap = false);
        return;
      } catch (_) {}
    }
    if (_selectedTrail != null) {
      await _fitSelectedTrail(_selectedTrail!);
    } else if (_gpxRoute != null) {
      await _fitGpxRoute();
    }
    setState(() => _userPannedMap = false);
  }

  Future<bool> _confirmPackingBeforeTracking() async {
    final store = PackingListStore.instance;
    await store.load();
    if (!store.hasPackingList) {
      // User tidak membuat packing list -> langsung mulai tracking tanpa dialog.
      return true;
    }
    if (!mounted) return false;
    final missing = store.missingItems;
    if (missing.isNotEmpty) {
      // Ada item packing list yang terlewat -> dialog 2 tombol (Kembali & Lanjutkan).
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          final colors = HiqeoColors.of(dialogContext);
          return AlertDialog(
            backgroundColor: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: Text(
              'Ada perlengkapan yang terlewat',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Barang berikut belum diceklis dibawa dari daftar packing kamu:',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: missing.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, idx) => Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 16,
                              color: colors.warning,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                missing[idx].name,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                key: const ValueKey('packing-reminder-back'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Kembali'),
              ),
              FilledButton(
                key: const ValueKey('packing-reminder-continue'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Lanjutkan'),
              ),
            ],
          );
        },
      );
      return proceed == true;
    }

    // Semua item sudah diceklis -> dialog cek ulang 1 tombol (Selesai).
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final colors = HiqeoColors.of(dialogContext);
        return AlertDialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: colors.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cek ulang perlengkapan',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Semua ${store.selectedItems.length} perlengkapan di daftar packing sudah diceklis. Pastikan seluruh barang benar-benar sudah dibawa di dalam tas sebelum berangkat.',
            style: TextStyle(fontSize: 14, color: colors.textSecondary),
          ),
          actions: [
            FilledButton(
              key: const ValueKey('packing-reminder-done'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Selesai'),
            ),
          ],
        );
      },
    );
    return mounted;
  }

  Future<void> _attemptAutoStartGroupTracking() async {
    if (!mounted || !widget.autoStartTracking || _autoStartAttempted) return;
    _autoStartAttempted = true;
    await _startTrackingFromMap(
      skipPackingConfirmation: true,
      isAutoStart: true,
    );
  }

  bool _isPermissionReportReady(PermissionReport report) {
    return report.locationServiceEnabled &&
        (report.locationWhileInUse || report.locationAlways);
  }

  Future<bool> _ensureLocationReadyInPlace({bool isAutoStart = false}) async {
    if (TrackingController.instance.simulationEnabled) {
      return true;
    }
    final report = await widget.permissionService.check();
    if (!mounted) return false;
    if (_isPermissionReportReady(report)) {
      _permissionPollTimer?.cancel();
      _permissionPollTimer = null;
      if (_blockingPermissionReport != null) {
        setState(() => _blockingPermissionReport = null);
      }
      return true;
    }
    setState(() {
      _blockingPermissionReport = report;
      _pendingAutoStartTracking = true;
    });
    _startPermissionGatePolling();
    return false;
  }

  void _startPermissionGatePolling() {
    _permissionPollTimer?.cancel();
    _permissionPollTimer = Timer.periodic(
      const Duration(milliseconds: 1400),
      (_) => unawaited(_recheckInPlaceLocationGate()),
    );
  }

  Future<void> _recheckInPlaceLocationGate() async {
    if (!mounted) return;
    final report = await widget.permissionService.check();
    if (!mounted) return;
    if (_isPermissionReportReady(report)) {
      _permissionPollTimer?.cancel();
      _permissionPollTimer = null;
      final shouldResumeAutoStart = _pendingAutoStartTracking;
      _pendingAutoStartTracking = false;
      setState(() => _blockingPermissionReport = null);
      unawaited(_location.refresh());
      if (shouldResumeAutoStart) {
        await _startTrackingFromMap(
          skipPackingConfirmation: true,
          isAutoStart: true,
        );
      }
      return;
    }
    setState(() => _blockingPermissionReport = report);
  }

  Future<void> _handleInPlacePermissionPrimaryAction() async {
    final report = _blockingPermissionReport;
    if (report == null) return;
    if (!report.locationWhileInUse && !report.locationAlways) {
      if (_hasRequestedLocationPrompt) {
        await widget.permissionService.openSettings();
      } else {
        _hasRequestedLocationPrompt = true;
        await widget.permissionService.requestCore();
      }
    } else if (!report.locationServiceEnabled) {
      await widget.permissionService.openLocationSettings();
    }
    if (mounted) {
      await _recheckInPlaceLocationGate();
    }
  }

  Future<void> _handleInPlaceOpenSettingsAction() async {
    final report = _blockingPermissionReport;
    if (report != null &&
        !report.locationServiceEnabled &&
        (report.locationWhileInUse || report.locationAlways)) {
      await widget.permissionService.openLocationSettings();
    } else {
      await widget.permissionService.openSettings();
    }
    if (mounted) {
      await _recheckInPlaceLocationGate();
    }
  }

  Future<void> _focusCameraOnMember(GroupHikeMemberState member) async {
    if (!member.hasValidCoord) return;
    setState(() => _userPannedMap = true);
    await _centerOn(LatLng(member.lat!, member.lon!), 15.2);
  }

  Future<void> _startTrackingFromMap({
    bool skipPackingConfirmation = false,
    bool isAutoStart = false,
  }) async {
    if (!isAutoStart && _isTrackingLockedByGroup) return;
    if (!skipPackingConfirmation) {
      final canProceed = await _confirmPackingBeforeTracking();
      if (!canProceed || !mounted) return;
    }

    final locationReady = await _ensureLocationReadyInPlace(
      isAutoStart: isAutoStart,
    );
    if (!locationReady || !mounted) return;

    try {
      if (_isDescentMode) {
        await _stopDescentMode();
      }
      _summitHandled = false;
      _straightLineAcknowledged = false;
      TrackingController.instance.setActiveRoute(
        mountainName: _selectedPackage?.name,
        trailName: _selectedTrail?.name,
        trailId: _selectedTrail?.id,
      );
      final started = await TrackingController.instance.start(
        activityType: TrackingSession.activityHiking,
        allowForegroundOnly: true,
      );
      if (!mounted) return;
      if (!started && !TrackingController.instance.isRecording) {
        _isMapTracking = true;
        _localTrackingSeconds = 0;
        _localTrackingTimer?.cancel();
        _localTrackingTimer = Timer.periodic(
          const Duration(seconds: 1),
          (_) {
            if (!mounted) return;
            setState(() => _localTrackingSeconds++);
          },
        );
      }

      final activePlan = _activeGroupPlan;
      if (!isAutoStart &&
          activePlan != null &&
          !activePlan.isStarted &&
          !activePlan.isCancelled &&
          (_selectedPackage == null ||
              activePlan.mountainId.toLowerCase() ==
                  _selectedPackage!.id.toLowerCase())) {
        final uid = SupabaseServices.sharedAccountController?.user?.id ??
            SupabaseServices.clientOrNull?.auth.currentUser?.id ??
            '';
        unawaited(
          _groupPlanStore.startGroupHikeRemote(
            activePlan,
            startedByUserId: uid,
            mountainId: _selectedPackage?.id,
            trailId: _selectedTrail?.id,
          ),
        );
      }

      _syncGroupMemberTracking();
      _syncMapTrackingNavVisibility();
      if (!_pulsingController.isAnimating) {
        _pulsingController.repeat(reverse: true);
      }
      if (_panelTrackingController.status != AnimationStatus.reverse &&
          _panelTrackingController.value > 0) {
        _panelTrackingController.reverse();
      }
      if (_directionsAnimController.status != AnimationStatus.forward &&
          _directionsAnimController.value < 1.0) {
        _directionsAnimController.forward();
      }
      setState(() {});
    } catch (e) {
      if (kDebugMode) {
        debugPrint('MapPage start tracking failed: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rekaman perjalanan belum bisa dimulai. Coba lagi.'),
          ),
        );
      }
    }
  }

  static String _formatRecordingTimer(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final hours = safe ~/ 3600;
    final minutes = (safe % 3600) ~/ 60;
    final secs = safe % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = secs.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$mm:$ss';
    }
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final dimOpacity = mapDimOpacityFor(Theme.of(context).brightness);
    final colors = HiqeoColors.of(context);
    final systemInset = HiqeoSystemInset.bottomOf(context);
    final safeTop = MediaQuery.paddingOf(context).top;
    final safeRight = MediaQuery.paddingOf(context).right;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    if (disableAnimations && _entranceController.value < 1.0) {
      _entranceController.value = 1.0;
    }

    return PopScope(
      canPop: !_isTrackingActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_handleBack());
        }
      },
      child: ColoredBox(
        color: colors.background,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: <Widget>[
              // 1. Peta Penuh
              Positioned.fill(
                child: _mapAvailable ? _buildMap() : _buildMapUnavailable(),
              ),
              if (_mapAvailable && dimOpacity > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      key: const ValueKey('map-dark-dim'),
                      color: colors.background.withValues(alpha: dimOpacity),
                    ),
                  ),
                ),

              // 2. Bar Atas (Judul Gunung, Status Chip, Tombol Kembali)
              Positioned(
                left: 16,
                right: 16,
                top: safeTop + 8,
                child: _buildStaggeredTopBar(
                  disableAnimations: disableAnimations,
                  child: _buildTopBar(context, colors),
                ),
              ),

              // 3. Kolom Tombol Kanan (44 dp, kanan 16, atas 104, jarak 8):
              //    (a) Kompas (reset arah ke utara)
              //    (b) Lokasiku (pusatkan kamera ke pengguna)
              //    (c) Petunjuk jalur (hanya tampil saat tracking aktif)
              Positioned(
                right: mapControlRightMargin + safeRight,
                top: math.max(mapControlTopOffset, safeTop + 8 + 52 + 8),
                child: _buildStaggeredFabs(
                  disableAnimations: disableAnimations,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _GlassCircleButton(
                        key: const ValueKey('map-compass-button'),
                        icon: HiqeoIcons.compass,
                        semanticLabel: 'Reset arah ke utara',
                        onPressed: () => unawaited(_resetBearingToNorth()),
                      ),
                      const SizedBox(height: mapControlGap),
                      _GlassCircleButton(
                        key: const ValueKey('map-recenter-button'),
                        icon: HiqeoIcons.crosshair,
                        semanticLabel: 'Lokasiku',
                        onPressed: () => unawaited(_recenterPosition()),
                      ),
                      AnimatedBuilder(
                        animation: _directionsAnimController,
                        builder: (context, _) {
                          final progress = _directionsAnimController.value;
                          if (progress <= 0.0) return const SizedBox.shrink();
                          final scale = disableAnimations
                              ? 1.0
                              : _directionsScaleAnimation.value;

                          return Padding(
                            padding: const EdgeInsets.only(top: mapControlGap),
                            child: Transform.scale(
                              scale: scale,
                              child: Opacity(
                                opacity: progress.clamp(0.0, 1.0),
                                child: _GlassCircleButton(
                                  key: const ValueKey('map-directions-button'),
                                  icon: HiqeoIcons.locate,
                                  semanticLabel: 'Petunjuk jalur',
                                  active: _directionsOpen,
                                  filledPrimary: false,
                                  onPressed: () =>
                                      unawaited(_onDirectionsPressed()),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              if (kDebugMode && _showDebugSimulation)
                Positioned(
                  left: HiqeoSpacing.lg,
                  right: HiqeoSpacing.lg,
                  top: safeTop + 8 + 52 + 12,
                  bottom: mapBottomPanelOffset(systemInset) + 8,
                  child: DebugSimulationPanel(
                    onClose: () => setState(() => _showDebugSimulation = false),
                  ),
                ),

              if (_directionsOpen && _userPannedMap)
                Positioned(
                  right: mapControlRightMargin,
                  bottom: (_isTrackingActive
                          ? (systemInset + 16.0)
                          : (HiqeoMetrics.floatingBottomInset(systemInset) +
                              12.0)) +
                      (_directionsMinimized ? 84.0 : 170.0),
                  child: Semantics(
                    button: true,
                    label: 'Pusatkan peta',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () async {
                        unawaited(HapticFeedback.selectionClick());
                        setState(() => _userPannedMap = false);
                        await _frameGuidanceTarget(force: true);
                      },
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        child: Center(
                          child: LightweightGlassSurface(
                            borderRadius: HiqeoRadius.pill,
                            useMapFill: true,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  Icons.center_focus_strong_rounded,
                                  size: 16,
                                  color: colors.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Pusatkan',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: colors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // 4. Panel Bawah (atau DirectionsPanel bila dibuka saat tracking)
              if (!_sheetVisible)
                AnimatedPositioned(
                  duration: disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  curve: const Cubic(0.4, 0.0, 0.2, 1.0),
                  left: 16,
                  right: 16,
                  bottom: (_isTrackingActive || kHideNavbarOnRouteScreen)
                      ? (systemInset + 16.0)
                      : mapBottomPanelOffset(systemInset),
                  child: _directionsOpen
                      ? DirectionsPanel(
                          key: const ValueKey('map-directions-panel'),
                          guidanceService: _guidanceService,
                          straightLineAcknowledged: _straightLineAcknowledged,
                          initialMinimized: _directionsMinimized,
                          onMinimizedChanged: (min) {
                            if (mounted) {
                              setState(() => _directionsMinimized = min);
                            }
                          },
                          onClose: _closeDirections,
                          onSos: () => _openSos(),
                          onAcknowledge: () {
                            setState(() => _straightLineAcknowledged = true);
                          },
                          onActionUnavailable: (reason) {
                            final block = switch (reason) {
                              GuidanceUnavailableReason.needsLocation =>
                                DirectionsBlock.locationOff,
                              GuidanceUnavailableReason.needsPermission =>
                                DirectionsBlock.permissionDenied,
                              GuidanceUnavailableReason.noRoute =>
                                DirectionsBlock.noRoute,
                              GuidanceUnavailableReason.waitingGps =>
                                DirectionsBlock.searchingGps,
                            };
                            unawaited(_showDirectionsBlockSheet(block));
                          },
                        )
                      : _isDescentMode
                          ? GlassSurface(
                              key: const ValueKey('map-descent-panel'),
                              tier: GlassTier.overMap,
                              borderRadius: 24,
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 12),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.trending_down_rounded,
                                    color: colors.primary,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Mode turun aktif',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: colors.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          'Rute puncak → awal · tidak direkam',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    key: const ValueKey(
                                        'map-stop-descent-button'),
                                    onPressed: () =>
                                        unawaited(_stopDescentMode()),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: colors.primary,
                                      foregroundColor: colors.onPrimary,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                    ),
                                    child: const Text('Selesai'),
                                  ),
                                ],
                              ),
                            )
                          : _isTrackingActive
                              ? GlassSurface(
                                  key: const ValueKey(
                                      'map-active-tracking-panel'),
                                  tier: GlassTier.overMap,
                                  borderRadius: 24,
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 12, 16, 12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Tracking berlangsung',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: colors.textPrimary,
                                              ),
                                            ),
                                            Text(
                                              '${((TrackingController.instance.status?.distanceM ?? 0) / 1000).toStringAsFixed(2)} km · +${(TrackingController.instance.status?.elevationGainM ?? 0).round()} m',
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                color: colors.textSecondary,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      FilledButton(
                                        key: const ValueKey(
                                          'map-stop-tracking-button',
                                        ),
                                        onPressed: () async {
                                          final ok =
                                              await _confirmStopBeforeSummit();
                                          if (ok && mounted) {
                                            await _finishActiveTracking(
                                              reachedSummit: false,
                                            );
                                          }
                                        },
                                        style: FilledButton.styleFrom(
                                          backgroundColor: colors.warning,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 10,
                                          ),
                                        ),
                                        child: const Text('Selesai'),
                                      ),
                                    ],
                                  ),
                                )
                              : AnimatedBuilder(
                                  animation: _panelTrackingAnimation,
                                  builder: (context, child) {
                                    final t = _panelTrackingAnimation.value;
                                    if (t >= 1.0) return child!;
                                    if (t <= 0.0) {
                                      return const SizedBox.shrink();
                                    }
                                    final dy = (1.0 - t) * 28.0;
                                    return Transform.translate(
                                      offset: Offset(0, dy),
                                      child: Opacity(
                                        opacity: t,
                                        child: IgnorePointer(
                                          ignoring: t < 0.5,
                                          child: child,
                                        ),
                                      ),
                                    );
                                  },
                                  child: _buildStaggeredBottomPanel(
                                    disableAnimations: disableAnimations,
                                    child: TrailMapBottomPanel(
                                      key: _bottomPanelKey,
                                      trails:
                                          _selectedPackage?.trails ?? const [],
                                      selectedTrail: _selectedTrail,
                                      onSelectTrail: _onTrailSelected,
                                      onStartTracking: () =>
                                          unawaited(_startTrackingFromMap()),
                                      onStartDescent: () =>
                                          unawaited(_startDescentMode()),
                                      showStartTracking:
                                          widget.allowStartAscent,
                                      startButtonLabel: widget.startButtonLabel,
                                      isTrackingLocked:
                                          widget.allowStartAscent &&
                                              _isTrackingLockedByGroup,
                                      trackingLockNote: _blockingGroupPlan
                                          ?.waitingLockMessage,
                                    ),
                                  ),
                                ),
                ),

              // 5. Peringatan non-blocking jika ada anggota grup >= 5 menit tidak
              //    terdeteksi saat pendakian aktif.
              if (_isGroupHikeActive && _memberTracker.staleMembers.isNotEmpty)
                Positioned(
                  left: 16,
                  right: 16 + mapControlSize + 8 + safeRight,
                  top: safeTop + 8 + 52 + 8,
                  child: _StaleMemberWarningBanner(
                    key: const ValueKey('map-stale-member-banner'),
                    staleMembers: _memberTracker.staleMembers,
                    collapsed: _staleBannerCollapsed,
                    onToggleCollapsed: () => setState(
                      () => _staleBannerCollapsed = !_staleBannerCollapsed,
                    ),
                    onLocateMember: (member) =>
                        unawaited(_focusCameraOnMember(member)),
                  ),
                ),

              // 6. Overlay izin lokasi & GPS non-dismissible di tempat (tanpa keluar peta).
              if (_blockingPermissionReport != null)
                Positioned.fill(
                  child: _InPlaceLocationGateOverlay(
                    key: const ValueKey('map-inplace-permission-overlay'),
                    report: _blockingPermissionReport!,
                    onPrimaryAction: () =>
                        unawaited(_handleInPlacePermissionPrimaryAction()),
                    onSecondarySettings: () =>
                        unawaited(_handleInPlaceOpenSettingsAction()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMap() {
    return Listener(
      onPointerDown: (_) {
        _bottomPanelKey.currentState?.closeSelection();
      },
      onPointerMove: (_) {
        if (!_userPannedMap && mounted) {
          setState(() => _userPannedMap = true);
        }
      },
      child: MapWidget(
        styleUri: MapboxStyles.OUTDOORS,
        onMapCreated: _onMapCreated,
        onStyleLoadedListener: (_) => unawaited(_onStyleLoaded()),
        onMapLoadErrorListener: _onMapLoadError,
      ),
    );
  }

  Widget _buildMapUnavailable() {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final bottomClearance = HiqeoMetrics.floatingBottomInset(
      HiqeoSystemInset.bottomOf(context),
    );
    final tokenMissing = _token.isEmpty;
    final body = tokenMissing
        ? 'Layanan peta belum siap dipakai sekarang. Periksa pengaturan atau '
            'coba buka ulang halaman Peta nanti.'
        : 'Peta interaktif hanya tersedia di perangkat Android dan iOS. Jalur, '
            'jejak, dan peta offline belum bisa ditampilkan di perangkat ini.';
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          HiqeoSpacing.lg,
          140,
          HiqeoSpacing.lg,
          230 + bottomClearance,
        ),
        child: GlassSurface(
          tier: GlassTier.overMap,
          borderRadius: 24,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  HiqeoIcon(
                    HiqeoIcons.mountain,
                    color: colors.textPrimary,
                  ),
                  const SizedBox(width: HiqeoSpacing.md),
                  Expanded(
                    child: Text(
                      'Peta belum tersedia',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HiqeoSpacing.sm),
              Text(
                body,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: HiqeoSpacing.sm),
              Text(
                'Kompas dan pengelolaan paket offline tetap bisa dibuka. Saat '
                'peta dipakai, logo dan atribusi Mapbox/OpenStreetMap wajib '
                'tetap terlihat.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassCircleButton extends StatefulWidget {
  const _GlassCircleButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onPressed,
    this.active = false,
    this.filledPrimary = false,
  });

  final HiqeoIconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final bool active;
  final bool filledPrimary;

  @override
  State<_GlassCircleButton> createState() => _GlassCircleButtonState();
}

class _GlassCircleButtonState extends State<_GlassCircleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _scaleAnimation = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.14)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.14, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 50,
      ),
    ]).animate(_pulseController);

    if (widget.active) {
      _pulseController.forward(from: 0.0);
    }
  }

  @override
  void didUpdateWidget(_GlassCircleButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _pulseController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final colors = HiqeoColors.of(context);
    final showPrimary = widget.active || widget.filledPrimary;

    Widget buttonContent = showPrimary
        ? DecoratedBox(
            key: const ValueKey('map-circle-button-active'),
            decoration: BoxDecoration(
              color: colors.primary,
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[HiqeoGlass.shadow(colors)],
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: HiqeoIcon(
                widget.icon,
                size: 22,
                color: colors.onPrimary,
              ),
            ),
          )
        : GlassSurface(
            tier: GlassTier.overMap,
            shape: BoxShape.circle,
            padding: const EdgeInsets.all(10),
            child: HiqeoIcon(
              widget.icon,
              size: 22,
              color: colors.textPrimary,
            ),
          );

    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.active,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.45,
          child: SizedBox(
            width: mapControlSize,
            height: mapControlSize,
            child: AnimatedBuilder(
              animation: _scaleAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: child,
                );
              },
              child: buttonContent,
            ),
          ),
        ),
      ),
    );
  }
}

/// Alasan singkat dan jalan keluar saat petunjuk jalur belum bisa dibuka.
class _DirectionsReasonSheet extends StatelessWidget {
  const _DirectionsReasonSheet({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = hiqeoDarkTheme;
    const colors = HiqeoColors.dark;
    // Navbar mengambang menutupi dasar layar, jadi sheet diangkat di atasnya.
    final bottom =
        HiqeoMetrics.floatingBottomInset(HiqeoSystemInset.bottomOf(context)) +
            HiqeoSpacing.sm;
    return Theme(
      data: theme,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          HiqeoSpacing.lg,
          0,
          HiqeoSpacing.lg,
          bottom,
        ),
        child: GlassSurface(
          tier: GlassTier.overMap,
          borderRadius: HiqeoRadius.hero,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: HiqeoSpacing.xs),
              Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: HiqeoSpacing.lg),
              if (actionLabel != null && onAction != null) ...<Widget>[
                HiqeoButton(label: actionLabel!, onPressed: onAction),
                const SizedBox(height: HiqeoSpacing.sm),
              ],
              HiqeoButton(
                label: 'Tutup',
                variant: HiqeoButtonVariant.secondary,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Overlay peringatan non-dismissible ketika anggota terbawa otomatis ke peta
/// namun izin lokasi atau layanan GPS belum aktif. Tidak menutup halaman Peta.
class _InPlaceLocationGateOverlay extends StatelessWidget {
  const _InPlaceLocationGateOverlay({
    super.key,
    required this.report,
    required this.onPrimaryAction,
    required this.onSecondarySettings,
  });

  final PermissionReport report;
  final VoidCallback onPrimaryAction;
  final VoidCallback onSecondarySettings;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final safePad = MediaQuery.paddingOf(context);
    final hasPermission = report.locationWhileInUse || report.locationAlways;
    final hasGps = report.locationServiceEnabled;

    final String title = !hasPermission
        ? 'Izin lokasi diperlukan untuk tracking'
        : 'Aktifkan GPS perangkat';
    final String body = !hasPermission
        ? 'Pendakian grup sudah dimulai. Izinkan akses lokasi langsung di '
            'layar ini agar posisimu otomatis terekam dan terlihat rombongan.'
        : 'Layanan lokasi (GPS) HP kamu sedang mati. Nyalakan GPS sekarang '
            'supaya tracking pendakian langsung berjalan otomatis.';
    final String primaryLabel =
        !hasPermission ? 'Izinkan lokasi sekarang' : 'Nyalakan GPS sekarang';

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.56),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          safePad.top + 16,
          20,
          safePad.bottom + 24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colors.hairline),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: colors.warning.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            !hasPermission
                                ? Icons.location_searching_rounded
                                : Icons.gps_off_rounded,
                            color: colors.warningText,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      body,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _PermissionStatusRow(
                      label: 'Izin lokasi aplikasi',
                      ready: hasPermission,
                      colors: colors,
                    ),
                    const SizedBox(height: 8),
                    _PermissionStatusRow(
                      label: 'Layanan GPS perangkat',
                      ready: hasGps,
                      colors: colors,
                    ),
                    const SizedBox(height: 18),
                    HiqeoButton(
                      key: const ValueKey('map-inplace-permission-primary'),
                      label: primaryLabel,
                      onPressed: onPrimaryAction,
                    ),
                    const SizedBox(height: 8),
                    HiqeoButton(
                      key: const ValueKey('map-inplace-permission-settings'),
                      label: 'Buka pengaturan',
                      variant: HiqeoButtonVariant.secondary,
                      onPressed: onSecondarySettings,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionStatusRow extends StatelessWidget {
  const _PermissionStatusRow({
    required this.label,
    required this.ready,
    required this.colors,
  });

  final String label;
  final bool ready;
  final HiqeoColors colors;

  @override
  Widget build(BuildContext context) {
    final accent = ready ? colors.successText : colors.warningText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ready
              ? colors.successText.withValues(alpha: 0.35)
              : colors.hairline,
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            ready ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
          Text(
            ready ? 'Aktif' : 'Belum aktif',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner peringatan non-blocking saat ada anggota rombongan >= 5 menit tidak
/// mengirim pembaruan lokasi saat pendakian berlangsung.
class _StaleMemberWarningBanner extends StatelessWidget {
  const _StaleMemberWarningBanner({
    super.key,
    required this.staleMembers,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onLocateMember,
  });

  final List<GroupHikeMemberState> staleMembers;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<GroupHikeMemberState> onLocateMember;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final first = staleMembers.first;
    final title = formatStaleBannerTitle(staleMembers);
    final body = formatStaleBannerBody(staleMembers);

    if (collapsed) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: colors.glassFillMap,
          shape: StadiumBorder(
            side: BorderSide(color: colors.warning, width: 1.2),
          ),
          child: InkWell(
            key: const ValueKey('map-stale-collapsed-pill'),
            customBorder: const StadiumBorder(),
            onTap: onToggleCollapsed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.location_off_rounded,
                      size: 16,
                      color: colors.warningText,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.warningText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.glassFillMap,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.warning, width: 1.2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.location_off_rounded,
                    size: 18,
                    color: colors.warningText,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('map-stale-collapse-button'),
                  tooltip: 'Ringkas peringatan',
                  onPressed: onToggleCollapsed,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  icon: Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 20,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              body,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                key: const ValueKey('map-stale-locate-button'),
                onPressed: () => onLocateMember(first),
                style: FilledButton.styleFrom(
                  minimumSize: const ui.Size(44, 40),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                icon: const Icon(Icons.my_location_rounded, size: 15),
                label: Text(
                  staleMembers.length == 1
                      ? 'Lihat lokasi terakhir'
                      : 'Lihat ${first.displayName}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
