import 'dart:math' as math;

const double earthRadiusM = 6371008.8;

class LatLng {
  const LatLng(this.lat, this.lon);
  final double lat;
  final double lon;

  @override
  String toString() => 'LatLng($lat, $lon)';
}

double _rad(double degrees) => degrees * math.pi / 180;

/// Jarak lingkaran-besar (haversine) dalam meter.
double distanceMeters(LatLng a, LatLng b) {
  final dLat = _rad(b.lat - a.lat);
  final dLon = _rad(b.lon - a.lon);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * earthRadiusM * math.asin(math.min(1.0, math.sqrt(h)));
}

/// Arah awal dari [from] ke [to], 0..360 derajat searah jarum jam dari utara sebenarnya.
double bearingDegrees(LatLng from, LatLng to) {
  final phi1 = _rad(from.lat);
  final phi2 = _rad(to.lat);
  final dLon = _rad(to.lon - from.lon);
  final y = math.sin(dLon) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Jarak titik [p] ke segmen a-b dalam meter, memakai proyeksi lokal
/// (akurat untuk jarak pendek seperti deteksi keluar jalur).
double distanceToSegmentMeters(LatLng p, LatLng a, LatLng b) {
  const metersPerDegree = earthRadiusM * math.pi / 180;
  final cosLat = math.cos(_rad(p.lat));
  double x(LatLng q) => (q.lon - p.lon) * cosLat * metersPerDegree;
  double y(LatLng q) => (q.lat - p.lat) * metersPerDegree;

  final ax = x(a), ay = y(a), bx = x(b), by = y(b);
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  var t = 0.0;
  if (len2 > 0) {
    t = ((-ax) * dx + (-ay) * dy) / len2; // p berada di titik asal
  }
  t = t.clamp(0.0, 1.0).toDouble();
  final cx = ax + t * dx;
  final cy = ay + t * dy;
  return math.sqrt(cx * cx + cy * cy);
}

/// Jarak terdekat titik ke polyline. Mengembalikan infinity jika [line] kosong.
double distanceToPolylineMeters(LatLng p, List<LatLng> line) {
  if (line.isEmpty) return double.infinity;
  if (line.length == 1) return distanceMeters(p, line.first);
  var best = double.infinity;
  for (var i = 0; i < line.length - 1; i++) {
    final d = distanceToSegmentMeters(p, line[i], line[i + 1]);
    if (d < best) best = d;
  }
  return best;
}
