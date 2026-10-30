import 'dart:io';

import 'package:geolocator/geolocator.dart';

import '../../features/tracking/application/tracking_runtime.dart';
import '../../features/tracking/domain/track_point.dart';
import '../power/power_profile_manager.dart';

/// Sumber GPS nyata. Android memakai foreground service dari
/// flutter_foreground_task; iOS memakai background location mode.
class GeolocatorTrackingSource implements TrackingLocationSource {
  const GeolocatorTrackingSource();

  @override
  Future<TrackingAccess> checkAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return TrackingAccess.serviceDisabled;
    }
    return switch (await Geolocator.checkPermission()) {
      LocationPermission.always => TrackingAccess.granted,
      LocationPermission.whileInUse => TrackingAccess.whileInUse,
      LocationPermission.denied => TrackingAccess.denied,
      LocationPermission.deniedForever => TrackingAccess.deniedForever,
      LocationPermission.unableToDetermine => TrackingAccess.unableToDetermine,
    };
  }

  @override
  Stream<TrackPoint> positions(PowerProfileConfig config) {
    final accuracy = switch (config.gpsInterval.inSeconds) {
      <= 5 => LocationAccuracy.best,
      <= 15 => LocationAccuracy.high,
      _ => LocationAccuracy.medium,
    };

    final settings = Platform.isAndroid
        // TaskHandler berjalan tanpa Activity; pemeriksaan setelan Google Play
        // Services butuh Activity untuk dialog resolusi, sehingga stream langsung
        // gagal dengan LocationServiceDisabledException. LocationManager tidak
        // memerlukan Activity dan cukup memakai provider GPS.
        ? AndroidSettings(
            forceLocationManager: true,
            accuracy: accuracy,
            distanceFilter: 0,
            intervalDuration: config.gpsInterval,
          )
        : AppleSettings(
            accuracy: accuracy,
            distanceFilter: 0,
            activityType: ActivityType.fitness,
            pauseLocationUpdatesAutomatically: false,
            showBackgroundLocationIndicator: true,
            allowBackgroundLocationUpdates: true,
          );

    return Geolocator.getPositionStream(locationSettings: settings)
        .map(_toTrackPoint);
  }

  TrackPoint _toTrackPoint(Position position) => TrackPoint(
        lat: position.latitude,
        lon: position.longitude,
        timestampUtc: position.timestamp.toUtc(),
        accuracyM: position.accuracy,
        altitudeM: position.hasAltitude ? position.altitude : null,
        speedMps:
            position.hasSpeed && position.speed >= 0 ? position.speed : null,
      );
}
