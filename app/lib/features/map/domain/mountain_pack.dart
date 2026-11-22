import 'package:flutter/material.dart';
import 'package:geo_utils/geo_utils.dart';

import 'map_package.dart';

/// Status unduhan satu paket gunung.
enum MountainDownloadStatus {
  notDownloaded,
  downloading,
  downloaded,
  updateAvailable,
  failed,
}

/// Model domain untuk paket gunung di katalog dan daftar peta.
class MountainPack {
  MountainPack({
    required this.id,
    required this.name,
    required this.province,
    required this.elevationM,
    required this.trailCount,
    required this.sizeMb,
    required this.package,
    this.status = MountainDownloadStatus.notDownloaded,
    this.progress = 0.0,
    this.version = 1,
    this.downloadedVersion,
    this.failureReason,
    this.gpxAssetPath,
    List<Offset>? cachedNormalizedPoints,
  }) : normalizedPoints = cachedNormalizedPoints != null
            ? List<Offset>.unmodifiable(cachedNormalizedPoints)
            : _computeNormalizedPoints(package);

  final String id;
  final String name;
  final String province;
  final int elevationM;
  final int trailCount;
  final int sizeMb;
  final MountainMapPackage package;
  final MountainDownloadStatus status;
  final double progress;
  final int version;
  final int? downloadedVersion;
  final String? failureReason;
  final String? gpxAssetPath;
  final List<Offset> normalizedPoints;

  bool get isDownloaded => status == MountainDownloadStatus.downloaded;
  bool get isDownloading => status == MountainDownloadStatus.downloading;
  bool get isUpdateAvailable => status == MountainDownloadStatus.updateAvailable;
  bool get isFailed => status == MountainDownloadStatus.failed;

  String get formattedElevation =>
      '${_formatGrouped(elevationM)} mdpl';

  String get subtitle => '$province · $formattedElevation';

  String get statusText {
    switch (status) {
      case MountainDownloadStatus.notDownloaded:
        return '$trailCount jalur · $sizeMb MB';
      case MountainDownloadStatus.downloading:
        final pct = (progress * 100).clamp(0, 100).round();
        return 'Mengunduh $pct%';
      case MountainDownloadStatus.downloaded:
        return 'Tersedia offline';
      case MountainDownloadStatus.updateAvailable:
        return 'Pembaruan tersedia';
      case MountainDownloadStatus.failed:
        return 'Unduhan gagal';
    }
  }

  MountainPack copyWith({
    MountainDownloadStatus? status,
    double? progress,
    int? version,
    int? downloadedVersion,
    String? failureReason,
  }) {
    return MountainPack(
      id: id,
      name: name,
      province: province,
      elevationM: elevationM,
      trailCount: trailCount,
      sizeMb: sizeMb,
      package: package,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      version: version ?? this.version,
      downloadedVersion: downloadedVersion ?? this.downloadedVersion,
      failureReason: failureReason ?? this.failureReason,
      gpxAssetPath: gpxAssetPath,
      cachedNormalizedPoints: normalizedPoints,
    );
  }

  static List<Offset> _computeNormalizedPoints(MountainMapPackage package) {
    if (package.trails.isEmpty) return const [];
    final allPoints = <LatLng>[];
    for (final trail in package.trails) {
      allPoints.addAll(trail.points);
    }
    if (allPoints.isEmpty) return const [];

    double minLat = allPoints.first.lat;
    double maxLat = allPoints.first.lat;
    double minLon = allPoints.first.lon;
    double maxLon = allPoints.first.lon;

    for (final p in allPoints) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lon < minLon) minLon = p.lon;
      if (p.lon > maxLon) maxLon = p.lon;
    }

    final dLat = maxLat - minLat;
    final dLon = maxLon - minLon;
    final span = (dLat > dLon ? dLat : dLon).clamp(1e-6, 180.0);

    // Normalisasi ke 0.0 - 1.0 (dengan Y dibalik karena lat makin besar makin ke atas/utara)
    final trail = package.trails.first;
    final result = <Offset>[];
    for (final p in trail.points) {
      final nx = ((p.lon - minLon) / span).clamp(0.0, 1.0);
      final ny = (1.0 - ((p.lat - minLat) / span)).clamp(0.0, 1.0);
      result.add(Offset(nx, ny));
    }
    return result;
  }

  static String _formatGrouped(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return value < 0 ? '-$buffer' : buffer.toString();
  }
}
