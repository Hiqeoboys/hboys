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
