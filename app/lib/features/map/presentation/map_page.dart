import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../infrastructure/map/asset_map_catalog_repository.dart';
import '../../../infrastructure/map/mapbox_offline_map_service.dart';
import '../../compass/presentation/compass_panel.dart';
import '../../tracking/domain/track_point.dart';
import '../application/map_track_source.dart';
import '../application/offline_download_controller.dart';
import '../application/offline_map_service.dart';
import '../domain/map_package.dart';
import '../domain/track_geojson.dart';
import 'off_trail_panel.dart';
import 'offline_package_panel.dart';

typedef MapCatalogLoader = Future<MapPackageCatalog> Function();

class MapPage extends StatefulWidget {
  MapPage({
    super.key,
    MapCatalogLoader? catalogLoader,
    OfflineMapService? offlineService,
    MapTrackSource? trackSource,
    this.mapboxToken,
    this.trackPollInterval = const Duration(seconds: 5),
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

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const _trailSourceId = 'nama-trail-source';
  static const _trackSourceId = 'nama-track-source';
  static const _trailCasingLayerId = 'nama-trail-casing';
  static const _trailLayerId = 'nama-trail-line';
  static const _trackCasingLayerId = 'nama-track-casing';
  static const _trackLayerId = 'nama-track-line';

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
  bool _layersInstalled = false;
  bool _mapLoading = true;
  bool _overviewCameraApplied = false;
  String? _mapIssue;
  String? _mapLoadError;

  String get _token => (widget.mapboxToken ?? MapPage._environmentToken).trim();

  bool get _platformSupportsMap =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _mapAvailable => _token.isNotEmpty && _platformSupportsMap;

  @override
  void initState() {
    super.initState();
    _offlineController = OfflineDownloadController(service: widget.offlineService);
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
  void dispose() {
    _trackTimer?.cancel();
    _offlineController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
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
      final changed =
          snapshot.latestPoint?.timestampUtc != _latestPoint?.timestampUtc ||
              snapshot.points.length != _trackPoints.length;
      setState(() {
        _trackPoints = snapshot.points;
        _latestPoint = snapshot.latestPoint;
        _trackError = null;
      });
      if (changed) {
        await _pushTrackData();
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

  void _selectPackage(String? id) {
    final package = id == null ? null : _catalog?.byId(id);
    if (package == null || identical(package, _selectedPackage)) return;
    final trail = package.trails.isEmpty ? null : package.trails.first;
    setState(() {
      _selectedPackage = package;
      _selectedTrail = trail;
    });
    if (_mapAvailable) {
      _offlineController.select(package);
    }
    unawaited(_pushTrailData());
    unawaited(_fitSelectedPackage());
  }

  void _selectTrail(String? id) {
    final package = _selectedPackage;
    if (package == null || id == null) return;
    final trail = package.trailById(id);
    if (trail == null || identical(trail, _selectedTrail)) return;
    setState(() => _selectedTrail = trail);
    unawaited(_pushTrailData());
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

  void _reportMapIssue(String message) {
    if (!mounted) return;
    setState(() => _mapIssue = message);
  }

  void _onMapCreated(MapboxMap map) {
    _map = map;
  }

  void _onMapLoadError(MapLoadingErrorEventData event) {
    if (!mounted) return;
    setState(() {
      _mapLoading = false;
      _mapLoadError = 'Peta gagal dimuat: ${event.message}';
    });
  }

  Future<void> _onStyleLoaded() async {
    if (_layersInstalled) return;
    _layersInstalled = true;
    final map = _map;
    if (map == null) return;

    try {
      final trailSource = GeoJsonSource(
        id: _trailSourceId,
        data: _trailGeoJson(),
      );
      final trackSource = GeoJsonSource(
        id: _trackSourceId,
        data: trackPointsToGeoJson(_trackPoints),
      );

      await map.addSource(trailSource);
      await map.addLayer(LineLayer(
        id: _trailCasingLayerId,
        sourceId: _trailSourceId,
        lineColor: 0xFFFFFFFF,
        lineWidth: 7,
        lineJoin: LineJoin.ROUND,
        lineCap: LineCap.ROUND,
      ));
      await map.addLayer(LineLayer(
        id: _trailLayerId,
        sourceId: _trailSourceId,
        lineColor: 0xFF1B5E20,
        lineWidth: 4,
        lineJoin: LineJoin.ROUND,
        lineCap: LineCap.ROUND,
      ));
      await map.addSource(trackSource);
      await map.addLayer(LineLayer(
        id: _trackCasingLayerId,
        sourceId: _trackSourceId,
        lineColor: 0xFFFFFFFF,
        lineWidth: 6,
        lineJoin: LineJoin.ROUND,
        lineCap: LineCap.ROUND,
      ));
      await map.addLayer(LineLayer(
        id: _trackLayerId,
        sourceId: _trackSourceId,
        lineColor: 0xFFD84315,
        lineWidth: 4,
        lineJoin: LineJoin.ROUND,
        lineCap: LineCap.ROUND,
      ));

      _trailSource = trailSource;
      _trackSource = trackSource;
      if (!mounted) return;
      setState(() {
        _mapLoading = false;
        _mapLoadError = null;
      });
      if (_selectedPackage != null) {
        await _fitSelectedPackage();
      } else {
        await _applyOverviewCamera();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _mapLoading = false;
        _mapIssue = 'Gagal menyiapkan layer peta: $error';
      });
    }
  }

  Future<void> _applyOverviewCamera() async {
    if (_overviewCameraApplied) return;
    _overviewCameraApplied = true;
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
      _reportMapIssue('Gagal mengatur kamera awal: $error');
    }
  }

  Future<void> _fitSelectedPackage() async {
    final package = _selectedPackage;
    final map = _map;
    if (package == null || map == null || !_layersInstalled) return;
    final bounds = package.offline.bounds;
    try {
      final camera = await map.cameraForCoordinateBounds(
        CoordinateBounds(
          southwest: Point(
            coordinates: Position(bounds.west, bounds.south),
          ),
          northeast: Point(
            coordinates: Position(bounds.east, bounds.north),
          ),
          infiniteBounds: false,
        ),
        MbxEdgeInsets(top: 32, left: 32, bottom: 32, right: 32),
        0,
        0,
        package.offline.maxZoom.toDouble(),
        null,
      );
      if (!mounted || _selectedPackage?.id != package.id) return;
      await map.setCamera(camera);
      _overviewCameraApplied = true;
    } catch (error) {
      _reportMapIssue('Gagal mengarahkan kamera ke paket: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Peta & Offline')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildMapArea(theme),
          const SizedBox(height: 8),
          Text(
            'Peta: © Mapbox · © OpenStreetMap. Logo dan tombol atribusi '
            'Mapbox di sudut peta wajib tetap terlihat, termasuk saat memakai '
            'data offline.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          _buildPackageSection(theme),
          const SizedBox(height: 12),
          if (_mapAvailable) ...[
            OfflinePackagePanel(controller: _offlineController),
            const SizedBox(height: 12),
          ] else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Unduhan offline memerlukan Mapbox yang aktif. Estimasi '
                  'tile tetap dihitung dari batas paket setelah Mapbox '
                  'dikonfigurasi.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_trackError != null) ...[
            _NoticeCard(
              icon: Icons.gps_off,
              title: 'Jejak GPS tidak tersedia',
              body: _trackError!,
              isError: true,
            ),
            const SizedBox(height: 12),
          ],
          OffTrailPanel(
            trail: _selectedTrail,
            latestPoint: _latestPoint,
          ),
          const SizedBox(height: 12),
          const CompassPanel(),
        ],
      ),
    );
  }

  Widget _buildMapArea(ThemeData theme) {
    if (!_mapAvailable) {
      return _MapSetupCard(
        tokenMissing: _token.isEmpty,
        platformUnsupported: _token.isNotEmpty && !_platformSupportsMap,
      );
    }
    return SizedBox(
      height: 320,
      child: Stack(
        children: [
          Positioned.fill(
            child: MapWidget(
              styleUri: MapboxStyles.OUTDOORS,
              onMapCreated: _onMapCreated,
              onStyleLoadedListener: (_) => unawaited(_onStyleLoaded()),
              onMapLoadErrorListener: _onMapLoadError,
            ),
          ),
          if (_mapLoading)
            Positioned(
              top: 8,
              left: 8,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text('Memuat peta...', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
          if (_mapLoadError != null || _mapIssue != null)
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _mapLoadError ?? _mapIssue!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPackageSection(ThemeData theme) {
    if (_catalogLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: LinearProgressIndicator(),
        ),
      );
    }
    if (_catalogError != null) {
      return _NoticeCard(
        icon: Icons.error_outline,
        title: 'Katalog paket tidak tersedia',
        body: _catalogError!,
        isError: true,
      );
    }
    final catalog = _catalog;
    if (catalog == null || catalog.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.map_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Belum ada paket gunung',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Katalog aplikasi kosong dan tidak membundel data gunung '
                'fiktif. Isi assets/map_packs/catalog.json dari pipeline data '
                'yang sudah diverifikasi; lihat docs/peta_offline.md.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    final selected = _selectedPackage;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.terrain_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Paket gunung', style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Pilih paket',
                border: OutlineInputBorder(),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selected?.id,
                  isExpanded: true,
                  hint: const Text('Belum memilih paket'),
                  items: [
                    for (final package in catalog.packages)
                      DropdownMenuItem(
                        value: package.id,
                        child: Text(
                          package.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _selectPackage,
                ),
              ),
            ),
            if (selected != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      selected.verified
                          ? 'Data terverifikasi'
                          : 'Data belum terverifikasi',
                      style: theme.textTheme.labelSmall,
                    ),
                    backgroundColor: selected.verified
                        ? theme.colorScheme.secondaryContainer
                        : theme.colorScheme.errorContainer,
                  ),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      'Versi ${selected.version} · ${_formatDate(selected.dataDateUtc)}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
              if (!selected.verified) ...[
                const SizedBox(height: 4),
                Text(
                  'Data paket belum diverifikasi lapangan. Jalur dan batas '
                  'area dapat berbeda dari kondisi nyata.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ],
              if (selected.trails.isNotEmpty) ...[
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Jalur untuk deteksi keluar jalur',
                    border: OutlineInputBorder(),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedTrail?.id,
                      isExpanded: true,
                      items: [
                        for (final trail in selected.trails)
                          DropdownMenuItem(
                            value: trail.id,
                            child: Text(
                              trail.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _selectTrail,
                    ),
                  ),
                ),
              ],
              if (selected.notes != null && selected.notes!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(selected.notes!, style: theme.textTheme.bodySmall),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${pad(date.month)}-${pad(date.day)}';
  }
}

class _MapSetupCard extends StatelessWidget {
  const _MapSetupCard({
    required this.tokenMissing,
    required this.platformUnsupported,
  });

  final bool tokenMissing;
  final bool platformUnsupported;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = platformUnsupported
        ? 'Peta Mapbox pada aplikasi ini hanya tersedia di Android dan iOS. '
            'Di platform lain layar ini tetap dapat dipakai untuk memilih jalur '
            'dan menampilkan kompas.'
        : 'Mapbox membutuhkan access token publik. Jalankan aplikasi dengan '
            '--dart-define=MAPBOX_ACCESS_TOKEN=... dan pastikan izin INTERNET '
            'serta ACCESS_NETWORK_STATE ada di AndroidManifest. Tanpa token, '
            'peta dan unduhan offline tidak dapat dipakai.';
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.map_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tokenMissing
                        ? 'Peta belum dikonfigurasi'
                        : 'Peta tidak tersedia di platform ini',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(body, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Text(
              'Batasan biaya: Maps SDK Mobile ditagih per pengguna aktif '
              'bulanan; 25.000 MAU pertama gratis menurut halaman harga '
              'Mapbox saat fitur ini ditulis. Verifikasi tarif dan ketentuan '
              'offline di akun Mapbox Anda sebelum rilis.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.title,
    required this.body,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: isError ? scheme.errorContainer : scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: isError ? scheme.onErrorContainer : scheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: isError ? scheme.onErrorContainer : null,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: TextStyle(
                      color: isError ? scheme.onErrorContainer : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
