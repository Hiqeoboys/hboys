import '../../../infrastructure/map/asset_map_catalog_repository.dart';
import '../../../infrastructure/map/mapbox_offline_map_service.dart';
import '../domain/map_package.dart';
import 'offline_map_service.dart';

/// Kesiapan peta offline untuk sebuah gunung, dibaca dari region yang benar-
/// benar tersimpan di perangkat. Nama gunung dicocokkan dengan katalog paket;
/// tanpa paket yang cocok tidak ada yang boleh diklaim siap.
Future<bool> defaultOfflineMapReady(
  String? mountain, {
  MapPackageCatalog? catalog,
  OfflineMapService? offlineService,
}) async {
  final name = mountain?.trim();
  if (name == null || name.isEmpty) return false;
  try {
    final resolvedCatalog = catalog ?? await AssetMapCatalogRepository().load();
    MountainMapPackage? match;
    for (final package in resolvedCatalog.packages) {
      if (package.name.trim().toLowerCase() == name.toLowerCase()) {
        match = package;
        break;
      }
    }
    if (match == null) return false;
    final service = offlineService ?? MapboxOfflineMapService();
    final status = await service.regionStatus(match);
    return status.ready;
  } catch (_) {
    return false;
  }
}
