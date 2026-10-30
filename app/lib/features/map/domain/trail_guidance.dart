import 'package:geo_utils/geo_utils.dart';

/// Perkiraan jarak dan arah dari posisi pengguna ke titik terdekat sebuah
/// jalur. Bukan panduan navigasi resmi dan bukan alarm keselamatan.
class TrailGuidance {
  const TrailGuidance({
    required this.distanceM,
    required this.bearingDeg,
    required this.point,
  });

  final double distanceM;
  final double bearingDeg;
  final LatLng point;
}

TrailGuidance? guidanceForTrail(List<LatLng> trail, LatLng position) {
  if (trail.isEmpty) return null;
  final point = closestPointOnPolyline(position, trail);
  return TrailGuidance(
    distanceM: distanceMeters(position, point),
    bearingDeg: bearingDegrees(position, point),
    point: point,
  );
}

String formatGuidanceDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  final km = meters / 1000;
  return '${km.toStringAsFixed(km >= 10 ? 0 : 1).replaceAll('.', ',')} km';
}

String formatBearing(double degrees) =>
    'bearing ${degrees.round() % 360}°';
