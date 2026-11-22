import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';

import '../../features/tracking/application/tracking_runtime.dart';
import '../../features/tracking/domain/track_point.dart';
import '../power/power_profile_manager.dart';
import 'barometer_altitude.dart';

/// Sumber GPS nyata. Android memakai foreground service dari
/// flutter_foreground_task; iOS memakai background location mode.
///
/// Selama merekam, pengaturan lokasi selalu akurasi tertinggi dengan
/// distanceFilter 0; hanya interval yang mengikuti profil daya (1 detik pada
/// Normal/Hemat). Profil daya tidak lagi menurunkan akurasi GPS, supaya jarak
/// dan pace tidak rusak saat baterai di bawah 40%.
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
    final settings = Platform.isAndroid
        // TaskHandler berjalan tanpa Activity; pemeriksaan setelan Google Play
        // Services butuh Activity untuk dialog resolusi, sehingga stream langsung
        // gagal dengan LocationServiceDisabledException. LocationManager tidak
        // memerlukan Activity dan cukup memakai provider GPS.
        ? AndroidSettings(
            forceLocationManager: true,
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
            intervalDuration: config.gpsInterval,
          )
        : AppleSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
            activityType: ActivityType.fitness,
            pauseLocationUpdatesAutomatically: false,
            showBackgroundLocationIndicator: true,
            allowBackgroundLocationUpdates: true,
          );

    final barometer = BarometerAltitude();
    StreamSubscription<Position>? subscription;
    late final StreamController<TrackPoint> controller;
    controller = StreamController<TrackPoint>(
      onListen: () {
        barometer.start();
        subscription = Geolocator.getPositionStream(locationSettings: settings)
            .listen(
          (position) => controller.add(_toTrackPoint(position, barometer)),
          onError: controller.addError,
          onDone: () => unawaited(controller.close()),
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () async {
        await subscription?.cancel();
        await barometer.stop();
      },
    );
    return controller.stream;
  }

  TrackPoint _toTrackPoint(Position position, BarometerAltitude barometer) {
    final baroAltitude = barometer.altitudeFor(position);
    final double? altitude =
        baroAltitude ?? (position.hasAltitude ? position.altitude : null);
    final double? altitudeAccuracy = baroAltitude != null
        ? BarometerAltitude.reportedAccuracyM
        : (position.hasAltitudeAccuracy && position.altitudeAccuracy > 0
            ? position.altitudeAccuracy
            : null);
    return TrackPoint(
      lat: position.latitude,
      lon: position.longitude,
      timestampUtc: position.timestamp.toUtc(),
      accuracyM: position.accuracy,
      altitudeM: altitude,
      altitudeAccuracyM: altitudeAccuracy,
      speedMps:
          position.hasSpeed && position.speed >= 0 ? position.speed : null,
      heading: position.heading.isFinite &&
              position.heading >= 0 &&
              position.heading <= 360
          ? position.heading
          : null,
      speedAccuracyMps: position.hasSpeedAccuracy && position.speedAccuracy > 0
          ? position.speedAccuracy
          : null,
      isMocked: position.isMocked,
      receivedAtUtc: DateTime.now().toUtc(),
    );
  }
}
