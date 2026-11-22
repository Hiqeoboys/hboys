import 'package:flutter/foundation.dart';

import '../../infrastructure/supabase/supabase_services.dart';
import '../kartu/application/kartu_exporter.dart';
import 'domain/cloud_backup.dart';
import 'domain/gpx_export.dart';
import 'domain/leaderboard.dart';
import 'domain/route_weather.dart';
import 'infrastructure/debug_leaderboard.dart';
import 'infrastructure/device_sharing.dart';
import 'infrastructure/local_plus_stores.dart';
import 'infrastructure/open_meteo_route_weather.dart';
import 'infrastructure/plus_local_caches.dart';
import 'infrastructure/supabase_cloud_backup_service.dart';

/// Sumber data untuk layar Plus D2–D9.
abstract final class PlusContentDependencies {
  static RouteWeatherRepository get routeWeather =>
      OpenMeteoRouteWeatherRepository();

  static RouteWeatherCache get weatherCache =>
      const SharedPreferencesRouteWeatherCache();

  static CloudBackupRepository cloudBackup() => SupabaseServices.isAvailable
      ? SupabaseCloudBackupService.instance
      : SharedPreferencesCloudBackupRepository();

  static GpxExporter get gpxExporter => const DeviceGpxExporter();

  static PlusTextSharer get textSharer => const DevicePlusTextSharer();

  static KartuExporter get kartuExporter => const DeviceKartuExporter();

  static LeaderboardRepository get leaderboard => kDebugMode
      ? const DebugLeaderboardRepository()
      : const UnavailableLeaderboardRepository();

  static LeaderboardConsentStore get leaderboardConsent =>
      const SharedPreferencesLeaderboardConsentStore();
}
