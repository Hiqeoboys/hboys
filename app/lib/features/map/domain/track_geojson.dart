import 'dart:convert';

import '../../tracking/domain/track_point.dart';
import 'map_package.dart';

String trailsToGeoJson(List<MapTrail> trails) {
  return jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (final trail in trails) trail.toGeoJsonFeature(),
    ],
  });
}

/// Titik terakhir rekaman sebagai Point, atau koleksi kosong bila belum ada
/// titik. Mapbox menolak geometri Point tanpa koordinat.
String trackPointToGeoJson(TrackPoint? point) {
  if (point == null) {
    return jsonEncode({
      'type': 'FeatureCollection',
      'features': <Object?>[],
    });
  }
  return jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'properties': <String, Object?>{},
        'geometry': {
          'type': 'Point',
          'coordinates': [point.lon, point.lat],
        },
      },
    ],
  });
}

/// Jejak rekaman sebagai satu LineString. Kurang dari dua titik menghasilkan
/// koleksi kosong agar Mapbox tidak menerima geometri tidak valid.
String trackPointsToGeoJson(List<TrackPoint> points) {
  if (points.length < 2) {
    return jsonEncode({
      'type': 'FeatureCollection',
      'features': <Object?>[],
    });
  }
  return jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'properties': {'point_count': points.length},
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            for (final point in points) [point.lon, point.lat],
          ],
        },
      },
    ],
  });
}
