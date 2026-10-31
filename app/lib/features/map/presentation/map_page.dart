import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../design/glass/glass_surface.dart';
import '../../../design/system_ui.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';
import '../../../design/widgets/line_icons.dart';
import '../../../infrastructure/map/asset_map_catalog_repository.dart';
import '../../../infrastructure/map/mapbox_offline_map_service.dart';
import '../../compass/domain/compass_calibration.dart';
import '../../compass/presentation/compass_sheet.dart';
import '../../plus/application/plus_navigation.dart';
import '../../tracking/domain/track_point.dart';
import '../../trails/domain/off_trail_detector.dart';
import '../application/map_track_source.dart';
import '../application/offline_download_controller.dart';
import '../application/offline_map_service.dart';
import '../domain/map_package.dart';
import '../domain/track_geojson.dart';
import '../domain/trail_guidance.dart';
import 'offline_sheet.dart';

typedef MapCatalogLoader = Future<MapPackageCatalog> Function();

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

/// Layar Peta Offline: peta penuh, kartu status jalur, tombol kompas dan
/// pemusatan posisi, serta sheet panduan jalur/pengelolaan unduhan.
class MapPage extends StatefulWidget {
  MapPage({
    super.key,
    MapCatalogLoader? catalogLoader,
    OfflineMapService? offlineService,
    MapTrackSource? trackSource,
    this.mapboxToken,
    this.trackPollInterval = const Duration(seconds: 5),
    this.compassEvents,
    this.compassOffsetStore,
  })  : catalogLoader = catalogLoader ?? _loadAssetCatalog,
        offlineService = offlineService ?? MapboxOfflineMapService(),
        trackSource = trackSource ?? const TrackingControllerMapTrackSource();

  static const String _environmentToken =
      String.fromEnvironment('MAPBOX_ACCESS_TOKEN');

  static Future<MapPackageCatalog> _loadAssetCatalog() =>
      AssetMapCatalogRepository().load();

  final MapCatalogLoader catalogLoader;
  final OfflineMapService offlineService;
  final MapTrackSource trackSource;

  /// Null berarti memakai `--dart-define=MAPBOX_ACCESS_TOKEN=...`.
  final String? mapboxToken;
  final Duration trackPollInterval;

  /// Disuntikkan untuk uji; produksi memakai sensor perangkat.
  final Stream<CompassEvent>? compassEvents;
  final CompassOffsetStore? compassOffsetStore;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const _trailSourceId = 'nama-trail-source';
  static const _trackSourceId = 'nama-track-source';
  static const _positionSourceId = 'nama-position-source';
  static const _trailCasingLayerId = 'nama-trail-casing';
  static const _trailLayerId = 'nama-trail-line';
  static const _trackCasingLayerId = 'nama-track-casing';
  static const _trackLayerId = 'nama-track-line';
  static const _positionHaloLayerId = 'nama-position-halo';
  static const _positionDotLayerId = 'nama-position-dot';

  late final OfflineDownloadController _offlineController;

  MapPackageCatalog? _catalog;
  bool _catalogLoading = true;
  String? _catalogError;

  MountainMapPackage? _selectedPackage;
  MapTrail? _selectedTrail;

  List<TrackPoint> _trackPoints = const [];
  TrackPoint? _latestPoint;
  Timer? _trackTimer;
  bool _trackRefreshInFlight = false;
  String? _trackError;

  MapboxMap? _map;
  GeoJsonSource? _trailSource;
  GeoJsonSource? _trackSource;
  GeoJsonSource? _positionSource;
  bool _layersInstalled = false;
  bool _styleReady = false;
  bool _mapLoading = true;
  bool _overviewApplied = false;
  bool _cameraInitialized = false;
  String? _mapIssue;
  String? _mapLoadError;
  bool _sheetVisible = false;
  Brightness? _lastBrightness;
  double _systemInset = 0;

  OffTrailDetector? _detector;
  TrailState _trailState = TrailState.onTrail;
  TrailGuidance? _guidance;
  DateTime? _consumedTimestamp;

  String get _token => (widget.mapboxToken ?? MapPage._environmentToken).trim();

  bool get _platformSupportsMap =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _mapAvailable => _token.isNotEmpty && _platformSupportsMap;

  @override
  void initState() {
    super.initState();
    _offlineController =
        OfflineDownloadController(service: widget.offlineService);
    if (_mapAvailable) {
      MapboxOptions.setAccessToken(_token);
    }
    unawaited(_loadCatalog());
    _trackTimer = Timer.periodic(
      widget.trackPollInterval,
      (_) => unawaited(_refreshTrack()),
    );
    unawaited(_refreshTrack());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
  void dispose() {
    _trackTimer?.cancel();
    _offlineController.dispose();
    super.dispose();
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
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _catalogLoading = false;
        _catalogError = 'Gagal memuat katalog paket: $error';
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
        if (latestChanged) _consumeLatest();
      });
      if (latestChanged || listChanged) {
        await _pushTrackData();
        await _pushPositionData();
        unawaited(_maybeApplyInitialCamera());
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _trackError = 'Tidak bisa membaca titik rekaman: $error';
      });
      _trackTimer?.cancel();
      _trackTimer = null;
    } finally {
      _trackRefreshInFlight = false;
    }
  }

  void _consumeLatest() {
    final point = _latestPoint;
    if (point == null) {
      _guidance = null;
      _trailState = TrailState.onTrail;
      _consumedTimestamp = null;
      return;
    }
    if (_consumedTimestamp == point.timestampUtc) return;
    _consumedTimestamp = point.timestampUtc;
    final trail = _selectedTrail;
    if (trail != null && trail.points.isNotEmpty) {
      _guidance = guidanceForTrail(trail.points, point.position);
    } else {
      _guidance = null;
    }
    final detector = _detector;
    if (detector != null) {
      _trailState = detector.update(point.position);
    }
  }

  void _resetTrailState({bool consume = true}) {
    final trail = _selectedTrail;
    _detector = trail != null && trail.points.length >= 2
        ? OffTrailDetector(trail: trail.points)
        : null;
    _trailState = TrailState.onTrail;
    _guidance = null;
    _consumedTimestamp = null;
    if (consume) _consumeLatest();
  }

  void _selectPackage(MountainMapPackage package) {
    setState(() {
      _selectedPackage = package;
      _selectedTrail = package.trails.isEmpty ? null : package.trails.first;
      _resetTrailState(consume: false);
      _consumeLatest();
      _cameraInitialized = false;
    });
    _offlineController.select(package);
    unawaited(_pushTrailData());
    if (_styleReady && _map != null) {
      _cameraInitialized = true;
      unawaited(_fitSelectedPackage());
    }
  }

  String _trailGeoJson() {
    final trail = _selectedTrail;
    return trailsToGeoJson(trail == null ? const [] : [trail]);
  }

  Future<void> _pushTrailData() async {
    final source = _trailSource;
    if (source == null) return;
    try {
      await source.updateGeoJSON(_trailGeoJson());
    } catch (error) {
      _reportMapIssue('Gagal memperbarui layer jalur: $error');
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
      await source.updateGeoJSON(trackPointToGeoJson(_latestPoint));
    } catch (error) {
      _reportMapIssue('Gagal memperbarui titik posisi: $error');
    }
  }

  void _reportMapIssue(String message) {
    if (!mounted) return;
    setState(() => _mapIssue = message);
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
    setState(() {
      _mapLoading = false;
      _mapLoadError = 'Peta gagal dimuat: ${event.message}';
    });
  }

  Future<void> _onStyleLoaded() async {
    if (_layersInstalled || !mounted) return;
    _layersInstalled = true;
    final map = _map;
    if (map == null) return;

    final colors = HiqeoColors.of(context);
    try {
      final trailSource = GeoJsonSource(
        id: _trailSourceId,
        data: _trailGeoJson(),
      );
      final trackSource = GeoJsonSource(
        id: _trackSourceId,
        data: trackPointsToGeoJson(_trackPoints),
      );
      final positionSource = GeoJsonSource(
        id: _positionSourceId,
        data: trackPointToGeoJson(_latestPoint),
      );

      await map.addSource(trailSource);
      await map.addSource(trackSource);
      await map.addSource(positionSource);
      for (final layer in _mapLayers(colors)) {
        await map.addLayer(layer);
      }

      _trailSource = trailSource;
      _trackSource = trackSource;
      _positionSource = positionSource;
      if (!mounted) return;
      setState(() {
        _styleReady = true;
        _mapLoading = false;
        _mapLoadError = null;
      });
      await _maybeApplyInitialCamera();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _mapLoading = false;
        _mapIssue = 'Gagal menyiapkan layer peta: $error';
      });
    }
  }

  List<Layer> _mapLayers(HiqeoColors colors) => <Layer>[
        LineLayer(
          id: _trailCasingLayerId,
          sourceId: _trailSourceId,
          lineColor: colors.surface.toARGB32(),
          lineWidth: 6,
          lineDasharray: <double?>[1.6, 2.2],
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
        ),
        LineLayer(
          id: _trailLayerId,
          sourceId: _trailSourceId,
          lineColor: colors.textSecondary.toARGB32(),
          lineWidth: 3.5,
          lineDasharray: <double?>[1.6, 2.2],
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
        ),
        LineLayer(
          id: _trackCasingLayerId,
          sourceId: _trackSourceId,
          lineColor: colors.surface.toARGB32(),
          lineWidth: 7,
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
        ),
        LineLayer(
          id: _trackLayerId,
          sourceId: _trackSourceId,
          lineColor: colors.primary.toARGB32(),
          lineWidth: 4,
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
        ),
        CircleLayer(
          id: _positionHaloLayerId,
          sourceId: _positionSourceId,
          circleColor: colors.secondary.toARGB32(),
          circleOpacity: 0.6,
          circleRadius: 16,
        ),
        CircleLayer(
          id: _positionDotLayerId,
          sourceId: _positionSourceId,
          circleColor: colors.primary.toARGB32(),
          circleRadius: 7,
          circleStrokeColor: colors.surface.toARGB32(),
          circleStrokeWidth: 3,
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

  void _locate() {
    final point = _latestPoint;
    if (point == null) return;
    _cameraInitialized = true;
    unawaited(_centerOn(point.position, 15));
  }

  void _recenterOnTrail() {
    final guidance = _guidance;
    if (guidance == null) return;
    _cameraInitialized = true;
    unawaited(_centerOn(guidance.point, 15));
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

  Future<void> _openCompassSheet() async {
    setState(() => _sheetVisible = true);
    try {
      await showCompassSheet(
        context,
        events: widget.compassEvents,
        offsetStore: widget.compassOffsetStore,
      );
    } finally {
      if (mounted) setState(() => _sheetVisible = false);
    }
  }

  _TrailSummary get _trailSummary {
    final trail = _selectedTrail;
    if (_catalogLoading) {
      return const _TrailSummary(
        title: 'Memuat data jalur…',
        subtitle: 'Membaca katalog paket dari perangkat.',
      );
    }
    if (_catalogError != null) {
      return const _TrailSummary(
        title: 'Katalog jalur tidak terbaca',
        subtitle: 'Jalur belum tersedia; coba muat ulang dari Peta offline.',
        warning: true,
      );
    }
    if (trail != null) {
      if (trail.isVerified) {
        final verifiedAt =
            trail.verifiedAtUtc ?? _selectedPackage?.verifiedAtUtc;
        final stamp = verifiedAt == null
            ? 'tanggal verifikasi tidak tercatat'
            : _formatDate(verifiedAt);
        return _TrailSummary(
          title: 'Jalur terverifikasi',
          subtitle: 'Diverifikasi $stamp · kondisi jalur dapat berubah',
        );
      }
      return _TrailSummary(
        title: 'Jalur belum terverifikasi',
        subtitle: 'Sumber: ${trail.source} · jangan jadikan satu-satunya acuan',
        warning: true,
      );
    }
    final catalog = _catalog;
    if (catalog == null || catalog.isEmpty) {
      return const _TrailSummary(
        title: 'Belum ada data jalur',
        subtitle: 'Katalog paket kosong · tidak ada data jalur dibundel',
      );
    }
    return const _TrailSummary(
      title: 'Belum ada jalur dipilih',
      subtitle: 'Pilih paket lewat Peta offline',
    );
  }

  String get _guidanceText {
    if (_trackError != null) return 'GPS tidak tersedia';
    if (_selectedTrail == null) {
      final point = _latestPoint;
      if (point == null) return 'GPS belum aktif';
      return 'akurasi ±${point.accuracyM.round()} m';
    }
    final guidance = _guidance;
    if (guidance == null) {
      return _latestPoint == null ? 'GPS belum aktif' : 'Menunggu GPS';
    }
    return '${formatGuidanceDistance(guidance.distanceM)} · '
        '${formatBearing(guidance.bearingDeg)}';
  }

  String get _sheetActionLabel {
    if (_selectedTrail != null &&
        _latestPoint != null &&
        _trailState == TrailState.offTrail &&
        _mapAvailable) {
      return 'Kembali menyusuri jejak';
    }
    return 'Kelola peta offline';
  }

  void _onSheetAction() {
    if (_sheetActionLabel == 'Kembali menyusuri jejak') {
      _recenterOnTrail();
    } else {
      unawaited(_openOfflineSheet());
    }
  }

  String? get _mapNotice {
    if (!_mapAvailable) return null;
    if (_mapLoadError != null) return _mapLoadError;
    if (_mapIssue != null) return _mapIssue;
    if (_trackError != null) return _trackError;
    if (_mapLoading) return 'Memuat peta…';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final dimOpacity = mapDimOpacityFor(Theme.of(context).brightness);
    final colors = HiqeoColors.of(context);
    final systemInset = HiqeoSystemInset.bottomOf(context);
    // Peta penuh sampai tepi layar; status bar dan navbar mengambang di
    // atasnya. Warna dasar token dipakai saat peta belum tersedia agar tidak
    // ada pita warna di tepi.
    return ColoredBox(
      color: colors.background,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: <Widget>[
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
            Positioned.fill(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    HiqeoSpacing.lg,
                    HiqeoSpacing.lg,
                    HiqeoSpacing.lg,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: _TrailStatusCard(summary: _trailSummary),
                          ),
                          const SizedBox(width: HiqeoSpacing.md),
                          Column(
                            children: <Widget>[
                              _GlassCircleButton(
                                icon: HiqeoIcons.compass,
                                semanticLabel: 'Buka kompas',
                                onPressed: () => unawaited(_openCompassSheet()),
                              ),
                              const SizedBox(height: HiqeoSpacing.md),
                              _GlassCircleButton(
                                icon: HiqeoIcons.locate,
                                semanticLabel: 'Pusatkan ke posisi terakhir',
                                onPressed: _mapAvailable && _latestPoint != null
                                    ? _locate
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (_mapNotice != null) ...<Widget>[
                        const SizedBox(height: HiqeoSpacing.sm),
                        _MapNotice(
                          text: _mapNotice!,
                          isError: _mapLoadError != null ||
                              _mapIssue != null ||
                              _trackError != null,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (!_sheetVisible)
              Positioned(
                left: HiqeoSpacing.lg,
                right: HiqeoSpacing.lg,
                bottom: mapSheetBottomOffset(systemInset),
                child: ListenableBuilder(
                  listenable: _offlineController,
                  builder: (context, _) => _buildGuidanceSheet(context),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    return MapWidget(
      styleUri: MapboxStyles.OUTDOORS,
      onMapCreated: _onMapCreated,
      onStyleLoadedListener: (_) => unawaited(_onStyleLoaded()),
      onMapLoadErrorListener: _onMapLoadError,
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
        ? 'Peta Mapbox membutuhkan token publik. Jalankan aplikasi dengan '
            '--dart-define=MAPBOX_ACCESS_TOKEN=... dan pastikan izin INTERNET '
            'serta ACCESS_NETWORK_STATE ada di AndroidManifest.'
        : 'Peta Mapbox hanya tersedia di Android dan iOS. Jalur, jejak, dan '
            'unduhan offline belum bisa digambar di platform ini.';
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          HiqeoSpacing.lg,
          140,
          HiqeoSpacing.lg,
          230 + bottomClearance,
        ),
        child: GlassSurface(
          borderRadius: HiqeoRadius.card,
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

  Widget _buildGuidanceSheet(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final trail = _selectedTrail;
    final hasPoint = _latestPoint != null;
    final downloading =
        _offlineController.phase == OfflineDownloadPhase.downloading;
    final progress = _offlineController.progress;
    final offlineReady = _offlineController.isReady;
    final offlineLabel = downloading && progress != null
        ? 'Peta offline ${(progress.fraction * 100).round()}%'
        : (offlineReady ? 'Peta offline' : 'Peta offline belum siap');

    return GlassSurface(
      borderRadius: HiqeoRadius.hero,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: Text(
                  trail?.name ?? 'Peta offline',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              const SizedBox(width: HiqeoSpacing.md),
              Flexible(
                child: Text(
                  _guidanceText,
                  key: const ValueKey('map-guidance'),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: HiqeoSpacing.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              if (trail != null)
                _StatusPill(
                  label: !hasPoint
                      ? 'Menunggu GPS'
                      : (_trailState == TrailState.offTrail
                          ? 'Di luar jalur'
                          : 'Dijalur'),
                  icon: !hasPoint
                      ? null
                      : (_trailState == TrailState.offTrail
                          ? HiqeoIcons.warning
                          : HiqeoIcons.check),
                  ready: hasPoint && _trailState == TrailState.onTrail,
                  warning: hasPoint && _trailState == TrailState.offTrail,
                  key: const ValueKey('map-trail-state'),
                ),
              _StatusPill(
                label: offlineLabel,
                icon: offlineReady ? HiqeoIcons.check : null,
                ready: offlineReady,
                key: const ValueKey('map-offline-state'),
              ),
            ],
          ),
          if (_selectedPackage != null) ...<Widget>[
            const SizedBox(height: HiqeoSpacing.sm),
            Row(
              children: <Widget>[
                Expanded(
                  child: _SheetSmallAction(
                    key: const ValueKey('map-plus-cuaca'),
                    icon: HiqeoIcons.cloud,
                    label: 'Cuaca rute',
                    onTap: () =>
                        openPlusWeather(context, _selectedPackage!.name),
                  ),
                ),
                const SizedBox(width: HiqeoSpacing.sm),
                Expanded(
                  child: _SheetSmallAction(
                    key: const ValueKey('map-plus-estimasi'),
                    icon: HiqeoIcons.clock,
                    label: 'Estimasi',
                    onTap: () {
                      final trail = _selectedTrail;
                      final name = trail == null
                          ? _selectedPackage!.name
                          : '${_selectedPackage!.name} · ${trail.name}';
                      openPlusEstimate(
                        context,
                        PlusRouteContext(
                          name: name,
                          points: trail?.points ?? const <LatLng>[],
                          trailId: trail?.id,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: HiqeoSpacing.md),
          _SheetAction(
            label: _sheetActionLabel,
            onTap: _onSheetAction,
          ),
        ],
      ),
    );
  }
}

class _TrailSummary {
  const _TrailSummary({
    required this.title,
    required this.subtitle,
    this.warning = false,
  });

  final String title;
  final String subtitle;
  final bool warning;
}

class _TrailStatusCard extends StatelessWidget {
  const _TrailStatusCard({required this.summary});

  final _TrailSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return GlassSurface(
      borderRadius: HiqeoRadius.card,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            summary.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 2),
          Text(
            summary.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color:
                  summary.warning ? colors.warningText : colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.icon,
    required this.semanticLabel,
    this.onPressed,
  });

  final HiqeoIconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: SizedBox(
            width: 48,
            height: 48,
            child: GlassSurface(
              borderRadius: HiqeoRadius.pill,
              padding: const EdgeInsets.all(12),
              child: HiqeoIcon(icon, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    super.key,
    required this.label,
    required this.ready,
    this.icon,
    this.warning = false,
  });

  final String label;
  final bool ready;
  final HiqeoIconData? icon;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final foreground = warning ? colors.warningText : colors.textPrimary;
    return Semantics(
      label: label,
      container: true,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: ready || warning
                ? (warning
                    ? colors.warning.withValues(alpha: 0.12)
                    : colors.secondary)
                : null,
            borderRadius: BorderRadius.circular(HiqeoRadius.pill),
            border: warning ? Border.all(color: colors.warning) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                HiqeoIcon(
                  icon!,
                  size: 13,
                  strokeWidth: 2,
                  color: foreground,
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ready || warning ? foreground : colors.textSecondary,
                    fontWeight: HiqeoTypography.medium,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetSmallAction extends StatelessWidget {
  const _SheetSmallAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final HiqeoIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(HiqeoRadius.pill),
            border: Border.all(color: colors.hairline),
          ),
          child: ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                HiqeoIcon(icon, size: 16, color: colors.primary),
                const SizedBox(width: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 13,
                    color: colors.textPrimary,
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

class _SheetAction extends StatelessWidget {
  const _SheetAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 48,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(HiqeoRadius.floating),
            border: Border.all(color: colors.hairline),
          ),
          child: ExcludeSemantics(
            child: Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapNotice extends StatelessWidget {
  const _MapNotice({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return GlassSurface(
      borderRadius: HiqeoRadius.floating,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: <Widget>[
          if (!isError) ...<Widget>[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: HiqeoSpacing.sm),
          ],
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isError ? colors.warningText : colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) {
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
