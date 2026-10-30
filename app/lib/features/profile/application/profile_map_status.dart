import '../../../infrastructure/map/asset_map_catalog_repository.dart';
import '../../../infrastructure/map/mapbox_offline_map_service.dart';
import '../../map/application/offline_map_service.dart';

/// Menghitung paket gunung yang region offline-nya benar-benar siap di
/// perangkat. Katalog kosong atau SDK yang gagal dibaca menghasilkan 0, bukan
/// klaim bahwa peta sudah terunduh.
Future<int> defaultDownloadedMountainCount({OfflineMapService? service}) async {
  try {
    final catalog = await AssetMapCatalogRepository().load();
    if (catalog.isEmpty) return 0;
    final offline = service ?? MapboxOfflineMapService();
    var ready = 0;
    for (final package in catalog.packages) {
      final status = await offline.regionStatus(package);
      if (status.ready) ready++;
    }
    return ready;
  } catch (_) {
    return 0;
  }
}

String downloadedMountainLabel(int? count) {
  if (count == null) return 'Belum dapat dibaca';
  if (count <= 0) return 'Belum ada peta terunduh';
  return '$count gunung';
}
