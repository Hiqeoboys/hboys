import '../domain/map_package.dart';

enum OfflinePhase { stylePack, tiles }

class OfflineEstimate {
  const OfflineEstimate({
    required this.transferBytes,
    required this.storageBytes,
    required this.errorMargin,
  });

  final int transferBytes;
  final int storageBytes;
  final double errorMargin;
}

/// Keadaan region unduhan yang dibaca dari penyimpanan SDK, bukan dari
/// ingatan sesi aplikasi. Dipakai agar status siap bertahan setelah aplikasi
/// dibuka ulang.
class OfflineRegionStatus {
  const OfflineRegionStatus({
    required this.completedResources,
    required this.requiredResources,
    required this.completedBytes,
    required this.styleReady,
  });

  final int completedResources;
  final int requiredResources;
  final int completedBytes;
  final bool styleReady;

  bool get hasRegion => requiredResources > 0;

  bool get tilesReady =>
      requiredResources > 0 && completedResources >= requiredResources;

  bool get ready => tilesReady && styleReady;

  static const OfflineRegionStatus missing = OfflineRegionStatus(
    completedResources: 0,
    requiredResources: 0,
    completedBytes: 0,
    styleReady: false,
  );
}

class OfflineProgress {
  const OfflineProgress({
    required this.phase,
    required this.completedResources,
    required this.requiredResources,
    required this.completedBytes,
    required this.erroredResources,
  });

  final OfflinePhase phase;
  final int completedResources;
  final int requiredResources;
  final int completedBytes;
  final int erroredResources;

  double get fraction {
    if (requiredResources <= 0) return 0;
    return (completedResources / requiredResources).clamp(0.0, 1.0);
  }
}

abstract interface class OfflineMapService {
  /// Keadaan region dan style pack yang benar-benar tersimpan di perangkat.
  /// `missing` bila region belum pernah diunduh.
  Future<OfflineRegionStatus> regionStatus(MountainMapPackage package);

  /// Perkiraan byte transfer dan penyimpanan dari SDK Mapbox. Ini bukan
  /// perkiraan jumlah tile; jumlah tile dihitung oleh [OfflinePlan].
  Future<OfflineEstimate> estimate(MountainMapPackage package);

  /// Mengunduh style pack lalu tile region. Wajib dipanggil setelah estimasi
  /// ditampilkan ke pengguna.
  Future<void> download(
    MountainMapPackage package, {
    required void Function(OfflineProgress progress) onProgress,
  });
}
