import 'package:geolocator/geolocator.dart';

import '../../tracking/application/tracking_controller.dart';

class SosFix {
  const SosFix({required this.lat, required this.lon, this.accuracyM});

  final double lat;
  final double lon;
  final int? accuracyM;
}

abstract interface class SosLocationProvider {
  /// Mengembalikan `null` bila tidak ada posisi nyata yang tersedia. Tidak
  /// pernah mengarang koordinat.
  Future<SosFix?> locate();
}

/// Urutan sumber: titik terakhir sesi rekaman yang aktif, posisi terakhir
/// perangkat, lalu perbaikan GPS baru. Semua galat diperlakukan sebagai
/// "tidak ada posisi" agar SOS tidak pernah menyimpan koordinat palsu.
class DeviceSosLocationProvider implements SosLocationProvider {
  const DeviceSosLocationProvider({
    this.currentFixTimeout = const Duration(seconds: 10),
  });

  final Duration currentFixTimeout;

  @override
  Future<SosFix?> locate() async {
    try {
      final latest = await TrackingController.instance.latestRecordedPoint();
      if (latest != null) {
        return SosFix(
          lat: latest.lat,
          lon: latest.lon,
          accuracyM: _accuracy(latest.accuracyM),
        );
      }
    } catch (_) {
      // Lanjut ke sumber berikutnya.
    }

    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) return _fromPosition(lastKnown);
    } catch (_) {
      // Lanjut ke perbaikan baru.
    }

    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: currentFixTimeout,
        ),
      );
      return _fromPosition(position);
    } catch (_) {
      return null;
    }
  }

  static SosFix _fromPosition(Position position) => SosFix(
        lat: position.latitude,
        lon: position.longitude,
        accuracyM: _accuracy(position.accuracy),
      );

  static int _accuracy(double meters) =>
      meters.isFinite && meters >= 0 ? meters.round() : 0;
}
