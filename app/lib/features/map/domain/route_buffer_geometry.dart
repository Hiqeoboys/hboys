import 'dart:math' as math;

import 'package:geo_utils/geo_utils.dart';

import 'map_package.dart';

/// Utilitas kalkulasi geometri buffer di kiri-kanan jalur GPX (default 1.500 m)
/// untuk parameter unduhan TileRegion Mapbox.
class RouteBufferGeometry {
  const RouteBufferGeometry._();

  static const double metersPerDegreeLat = 111320.0;

  /// Menghitung poligon GeoJSON penyangga (buffer) untuk daftar jalur (list of routes).
  ///
  /// Setiap jalur diekspansi selebar [bufferMeters] ke kiri dan ke kanan,
  /// menghasilkan poligon GeoJSON bertipe `Polygon` atau `MultiPolygon`.
  static Map<String, dynamic> computeBufferPolygon(
    List<List<LatLng>> routes, {
    double bufferMeters = 1500.0,
  }) {
    final validRoutes = routes.where((r) => r.isNotEmpty).toList();
    if (validRoutes.isEmpty) {
      return const {
        'type': 'Polygon',
        'coordinates': <List<List<double>>>[],
      };
    }

    final polygonRings = <List<List<double>>>[];
    for (final route in validRoutes) {
      final ring = _bufferSingleRoute(route, bufferMeters);
      if (ring.isNotEmpty) {
        polygonRings.add(ring);
      }
    }

    if (polygonRings.isEmpty) {
      return const {
        'type': 'Polygon',
        'coordinates': <List<List<double>>>[],
      };
    }

    if (polygonRings.length == 1) {
      return {
        'type': 'Polygon',
        'coordinates': [polygonRings.first],
      };
    }

    return {
      'type': 'MultiPolygon',
      'coordinates': polygonRings.map((ring) => [ring]).toList(),
    };
  }

  /// Menghitung batas [GeoBounds] yang sudah diperlebar sejauh [bufferMeters].
  static GeoBounds computeBufferedBounds(
    List<LatLng> points, {
    double bufferMeters = 1500.0,
  }) {
    if (points.isEmpty) {
      return const GeoBounds(south: 0, west: 0, north: 0, east: 0);
    }

    double minLat = points.first.lat;
    double maxLat = points.first.lat;
    double minLon = points.first.lon;
    double maxLon = points.first.lon;

    for (final p in points) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lon < minLon) minLon = p.lon;
      if (p.lon > maxLon) maxLon = p.lon;
    }

    final midLat = (minLat + maxLat) / 2.0;
    final dLat = bufferMeters / metersPerDegreeLat;
    final cosLat = math.cos(midLat * math.pi / 180.0).abs().clamp(0.01, 1.0);
    final dLon = bufferMeters / (metersPerDegreeLat * cosLat);

    return GeoBounds(
      south: (minLat - dLat).clamp(-GeoBounds.maxMercatorLatitude, GeoBounds.maxMercatorLatitude),
      west: (minLon - dLon).clamp(-180.0, 180.0),
      north: (maxLat + dLat).clamp(-GeoBounds.maxMercatorLatitude, GeoBounds.maxMercatorLatitude),
      east: (maxLon + dLon).clamp(-180.0, 180.0),
    );
  }

  static List<List<double>> _bufferSingleRoute(
    List<LatLng> points,
    double bufferMeters,
  ) {
    if (points.isEmpty) return const [];

    if (points.length == 1) {
      // Titik tunggal: buat poligon lingkaran 12 sisi
      return _circleAroundPoint(points.first, bufferMeters);
    }

    final leftOffsets = <List<double>>[];
    final rightOffsets = <List<double>>[];

    for (var i = 0; i < points.length; i++) {
      final current = points[i];
      final cosLat = math.cos(current.lat * math.pi / 180.0).abs().clamp(0.01, 1.0);
      final metersPerDegLon = metersPerDegreeLat * cosLat;

      double nx = 0.0;
      double ny = 0.0;

      if (i == 0) {
        final next = points[i + 1];
        final dx = (next.lon - current.lon) * metersPerDegLon;
        final dy = (next.lat - current.lat) * metersPerDegreeLat;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len > 0) {
          nx = -dy / len;
          ny = dx / len;
        }
      } else if (i == points.length - 1) {
        final prev = points[i - 1];
        final dx = (current.lon - prev.lon) * metersPerDegLon;
        final dy = (current.lat - prev.lat) * metersPerDegreeLat;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len > 0) {
          nx = -dy / len;
          ny = dx / len;
        }
      } else {
        final prev = points[i - 1];
        final next = points[i + 1];

        final dx1 = (current.lon - prev.lon) * metersPerDegLon;
        final dy1 = (current.lat - prev.lat) * metersPerDegreeLat;
        final len1 = math.sqrt(dx1 * dx1 + dy1 * dy1);

        final dx2 = (next.lon - current.lon) * metersPerDegLon;
        final dy2 = (next.lat - current.lat) * metersPerDegreeLat;
        final len2 = math.sqrt(dx2 * dx2 + dy2 * dy2);

        var n1x = 0.0, n1y = 0.0;
        if (len1 > 0) {
          n1x = -dy1 / len1;
          n1y = dx1 / len1;
        }
        var n2x = 0.0, n2y = 0.0;
        if (len2 > 0) {
          n2x = -dy2 / len2;
          n2y = dx2 / len2;
        }

        final avgX = (n1x + n2x) / 2.0;
        final avgY = (n1y + n2y) / 2.0;
        final avgLen = math.sqrt(avgX * avgX + avgY * avgY);
        if (avgLen > 0.001) {
          nx = avgX / avgLen;
          ny = avgY / avgLen;
        } else {
          nx = n1x;
          ny = n1y;
        }
      }

      final dLat = (ny * bufferMeters) / metersPerDegreeLat;
      final dLon = (nx * bufferMeters) / metersPerDegLon;

      leftOffsets.add([current.lon + dLon, current.lat + dLat]);
      rightOffsets.add([current.lon - dLon, current.lat - dLat]);
    }

    final ring = <List<double>>[];
    ring.addAll(leftOffsets);
    ring.addAll(rightOffsets.reversed);
    if (ring.isNotEmpty) {
      ring.add(ring.first);
    }

    return ring;
  }

  static List<List<double>> _circleAroundPoint(LatLng point, double radiusMeters) {
    const numPoints = 12;
    final ring = <List<double>>[];
    final cosLat = math.cos(point.lat * math.pi / 180.0).abs().clamp(0.01, 1.0);
    final metersPerDegLon = metersPerDegreeLat * cosLat;

    for (var i = 0; i < numPoints; i++) {
      final angle = (i * 2 * math.pi) / numPoints;
      final dx = radiusMeters * math.cos(angle);
      final dy = radiusMeters * math.sin(angle);
      final lat = point.lat + (dy / metersPerDegreeLat);
      final lon = point.lon + (dx / metersPerDegLon);
      ring.add([lon, lat]);
    }
    ring.add(ring.first);
    return ring;
  }
}
