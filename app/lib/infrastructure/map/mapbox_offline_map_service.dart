import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../features/map/application/offline_map_service.dart';
import '../../features/map/domain/map_package.dart';

class MapboxOfflineMapService implements OfflineMapService {
  MapboxOfflineMapService({this.styleUri = MapboxStyles.OUTDOORS});

  final String styleUri;
  Future<OfflineManager>? _managerFuture;
  Future<TileStore>? _tileStoreFuture;

  Future<OfflineManager> _manager() =>
      _managerFuture ??= OfflineManager.create();

  Future<TileStore> _store() =>
      _tileStoreFuture ??= TileStore.createDefault();

  TilesetDescriptorOptions _descriptor(MountainMapPackage package) =>
      TilesetDescriptorOptions(
        styleURI: styleUri,
        minZoom: package.offline.minZoom,
        maxZoom: package.offline.maxZoom,
      );

  TileRegionLoadOptions _loadOptions(MountainMapPackage package) =>
      TileRegionLoadOptions(
        geometry: package.offline.bounds.toGeoJsonPolygon(),
        descriptorsOptions: [_descriptor(package)],
        metadata: {
          'pack_id': package.id,
          'version': package.version,
          'data_date': package.dataDateUtc.toIso8601String(),
          'min_zoom': package.offline.minZoom,
          'max_zoom': package.offline.maxZoom,
        },
        acceptExpired: false,
        networkRestriction: NetworkRestriction.NONE,
      );

  @override
  Future<OfflineRegionStatus> regionStatus(MountainMapPackage package) async {
    final store = await _store();
    final regions = await store.allTileRegions();
    TileRegion? region;
    for (final item in regions) {
      if (item.id == package.offlineRegionId) {
        region = item;
        break;
      }
    }

    var styleReady = false;
    try {
      final manager = await _manager();
      final packs = await manager.allStylePacks();
      for (final pack in packs) {
        if (pack.styleURI != styleUri) continue;
        styleReady = pack.requiredResourceCount > 0 &&
            pack.completedResourceCount >= pack.requiredResourceCount;
        break;
      }
    } catch (_) {
      styleReady = false;
    }

    if (region == null) {
      return OfflineRegionStatus(
        completedResources: 0,
        requiredResources: 0,
        completedBytes: 0,
        styleReady: styleReady,
      );
    }
    return OfflineRegionStatus(
      completedResources: region.completedResourceCount,
      requiredResources: region.requiredResourceCount,
      completedBytes: region.completedResourceSize,
      styleReady: styleReady,
    );
  }

  @override
  Future<OfflineEstimate> estimate(MountainMapPackage package) async {
    final plan = OfflinePlan.evaluate(package.offline);
    if (!plan.canDownload) {
      throw StateError(
        'Paket ditolak: ${plan.violations.map((v) => v.message).join(' ')}',
      );
    }
    final store = await _store();
    final result = await store.estimateTileRegion(
      package.offlineRegionId,
      _loadOptions(package),
      TileRegionEstimateOptions(
        errorMargin: 0.2,
        preciseEstimationTimeout: 10,
        timeout: 60,
      ),
      null,
    );
    return OfflineEstimate(
      transferBytes: result.transferSize,
      storageBytes: result.storageSize,
      errorMargin: result.errorMargin,
    );
  }

  @override
  Future<void> download(
    MountainMapPackage package, {
    required void Function(OfflineProgress progress) onProgress,
  }) async {
    final plan = OfflinePlan.evaluate(package.offline);
    if (!plan.canDownload) {
      throw StateError(
        'Paket ditolak: ${plan.violations.map((v) => v.message).join(' ')}',
      );
    }

    final manager = await _manager();
    final store = await _store();

    var styleErrors = 0;
    final stylePack = await manager.loadStylePack(
      styleUri,
      StylePackLoadOptions(
        glyphsRasterizationMode:
            GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY,
        metadata: {'app': 'nama_app'},
        acceptExpired: false,
      ),
      (progress) {
        styleErrors = progress.erroredResourceCount;
        onProgress(OfflineProgress(
          phase: OfflinePhase.stylePack,
          completedResources: progress.completedResourceCount,
          requiredResources: progress.requiredResourceCount,
          completedBytes: progress.completedResourceSize,
          erroredResources: progress.erroredResourceCount,
        ));
      },
    );
    onProgress(OfflineProgress(
      phase: OfflinePhase.stylePack,
      completedResources: stylePack.completedResourceCount,
      requiredResources: stylePack.requiredResourceCount,
      completedBytes: stylePack.completedResourceSize,
      erroredResources: styleErrors,
    ));
    if (styleErrors > 0 ||
        (stylePack.requiredResourceCount > 0 &&
            stylePack.completedResourceCount <
                stylePack.requiredResourceCount)) {
      throw StateError(
        'Style pack belum lengkap '
        '(${stylePack.completedResourceCount}/${stylePack.requiredResourceCount}, '
        '$styleErrors gagal).',
      );
    }

    var tileErrors = 0;
    final region = await store.loadTileRegion(
      package.offlineRegionId,
      _loadOptions(package),
      (progress) {
        tileErrors = progress.erroredResourceCount;
        onProgress(OfflineProgress(
          phase: OfflinePhase.tiles,
          completedResources: progress.completedResourceCount,
          requiredResources: progress.requiredResourceCount,
          completedBytes: progress.completedResourceSize,
          erroredResources: progress.erroredResourceCount,
        ));
      },
    );
    onProgress(OfflineProgress(
      phase: OfflinePhase.tiles,
      completedResources: region.completedResourceCount,
      requiredResources: region.requiredResourceCount,
      completedBytes: region.completedResourceSize,
      erroredResources: tileErrors,
    ));
    if (tileErrors > 0 ||
        (region.requiredResourceCount > 0 &&
            region.completedResourceCount < region.requiredResourceCount)) {
      throw StateError(
        'Tile region belum lengkap '
        '(${region.completedResourceCount}/${region.requiredResourceCount}, '
        '$tileErrors gagal).',
      );
    }
  }
}
