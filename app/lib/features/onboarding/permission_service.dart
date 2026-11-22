import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionReport {
  const PermissionReport({
    required this.notificationGranted,
    required this.locationWhileInUse,
    required this.locationAlways,
    required this.locationServiceEnabled,
    required this.preciseLocation,
    required this.ignoringBatteryOptimizations,
    this.activityRecognitionGranted = false,
  });

  final bool notificationGranted;
  final bool locationWhileInUse;
  final bool locationAlways;
  final bool locationServiceEnabled;
  final bool preciseLocation;
  final bool ignoringBatteryOptimizations;
  final bool activityRecognitionGranted;

  bool get readyForBackground =>
      locationAlways &&
      locationServiceEnabled &&
      preciseLocation &&
      (!Platform.isAndroid || notificationGranted);
}

class PermissionService {
  const PermissionService();

  Future<PermissionReport> check() async {
    final notification =
        !Platform.isAndroid || await Permission.notification.isGranted;
    final whileInUse = await Permission.locationWhenInUse.isGranted;
    final always = await Permission.locationAlways.isGranted;
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    var precise = false;
    try {
      precise = await Geolocator.getLocationAccuracy() ==
          LocationAccuracyStatus.precise;
    } catch (_) {
      // Platform tanpa API akurasi dianggap belum presisi; pengguna diarahkan
      // memeriksa pengaturan.
    }
    var ignoringBattery = false;
    if (Platform.isAndroid) {
      try {
        ignoringBattery =
            await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      } catch (_) {
        ignoringBattery = false;
      }
    }
    var activityRecognition = false;
    try {
      activityRecognition = Platform.isAndroid
          ? await Permission.activityRecognition.isGranted
          : await Permission.sensors.isGranted;
    } catch (_) {
      activityRecognition = false;
    }
    return PermissionReport(
      notificationGranted: notification,
      locationWhileInUse: whileInUse,
      locationAlways: always,
      locationServiceEnabled: serviceEnabled,
      preciseLocation: precise,
      ignoringBatteryOptimizations: ignoringBattery,
      activityRecognitionGranted: activityRecognition,
    );
  }

  /// Meminta notifikasi (Android), aktivitas fisik, dan lokasi saat digunakan.
  /// Izin "selalu" harus diminta terpisah setelah izin dasar diberikan.
  Future<PermissionReport> requestCore() async {
    if (Platform.isAndroid) {
      await Permission.notification.request();
      try {
        await Permission.activityRecognition.request();
      } catch (_) {}
    }
    final whileInUse = await Permission.locationWhenInUse.request();
    if (whileInUse.isGranted) {
      await Permission.locationAlways.request();
    }
    return check();
  }

  Future<bool> requestActivityRecognition() async {
    try {
      final status = Platform.isAndroid
          ? await Permission.activityRecognition.request()
          : await Permission.sensors.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Pada Android 11+ sistem dapat menolak dialog dan mengarahkan ke setelan.
  /// Hasil selalu diverifikasi ulang, bukan diasumsikan berhasil.
  Future<PermissionReport> requestBackgroundLocation() async {
    final current = await Permission.locationWhenInUse.status;
    if (!current.isGranted) {
      await Permission.locationWhenInUse.request();
    }
    await Permission.locationAlways.request();
    return check();
  }

  Future<bool> openSettings() => openAppSettings();

  Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestIgnoreBatteryOptimization() async {
    if (!Platform.isAndroid) return false;
    try {
      return await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (_) {
      return false;
    }
  }

  Future<bool> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await FlutterForegroundTask
          .openIgnoreBatteryOptimizationSettings();
    } catch (_) {
      return false;
    }
  }
}
