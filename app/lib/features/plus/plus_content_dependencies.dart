import 'package:flutter/foundation.dart';

import '../kartu/application/kartu_exporter.dart';
import 'domain/cloud_backup.dart';
import 'domain/gpx_export.dart';
import 'domain/route_weather.dart';
import 'infrastructure/debug_route_weather.dart';
import 'infrastructure/device_sharing.dart';
import 'infrastructure/plus_local_caches.dart';

/// Sumber data untuk layar Plus D2–D6.
///
/// Semua backend masih dummy sesuai tahap ini: cuaca demo hanya di debug,
/// cadangan cloud masih lokal, dan ekspor berjalan di perangkat.
abstract final class PlusContentDependencies {
  static RouteWeatherRepository get routeWeather => kDebugMode
      ? const DebugRouteWeatherRepository()
      : const UnavailableRouteWeatherRepository();

  static RouteWeatherCache get weatherCache =>
      const SharedPreferencesRouteWeatherCache();

  static CloudBackupRepository cloudBackup() =>
      SharedPreferencesCloudBackupRepository();

  static GpxExporter get gpxExporter => const DeviceGpxExporter();

  static PlusTextSharer get textSharer => const DevicePlusTextSharer();

  static KartuExporter get kartuExporter => const DeviceKartuExporter();
}
