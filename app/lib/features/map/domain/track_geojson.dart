import 'dart:convert';

import 'package:geo_utils/geo_utils.dart';

import '../../tracking/domain/track_point.dart';
import '../../trails/domain/track_route.dart';
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

/// Rute GPX yang sudah disederhanakan dengan Douglas-Peucker sebagai GeoJSON
/// `LineString` untuk digambar pada layer peta.
String trackRouteLineToGeoJson(TrackRoute? route) {
  final drawPoints = route == null
      ? const <TrackRoutePoint>[]
      : (route.simplifiedPoints.length >= 2
          ? route.simplifiedPoints
          : route.points);
  if (drawPoints.length < 2) {
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
        'properties': {
          'id': route!.id,
          'name': route.name,
          'point_count': drawPoints.length,
        },
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            for (final point in drawPoints) [point.lon, point.lat],
          ],
        },
      },
    ],
  });
}

/// Titik penanda awal atau akhir jalur GPX sebagai GeoJSON `Point`.
String trackRouteMarkerToGeoJson(
  TrackRoutePoint? point, {
  required String role,
}) {
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
        'properties': {
          'role': role,
          if (point.ele != null) 'ele': point.ele,
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [point.lon, point.lat],
        },
      },
    ],
  });
}

/// Daftar LatLng sebagai GeoJSON LineString untuk lintasan panduan dan garis lurus.
String latLngsToGeoJsonLine(List<LatLng>? points) {
  if (points == null || points.length < 2) {
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
          'type': 'LineString',
          'coordinates': [
            for (final p in points) [p.lon, p.lat],
          ],
        },
      },
    ],
  });
}

/// Titik koordinat LatLng tunggal sebagai GeoJSON Point untuk penanda target.
String latLngToGeoJsonPoint(LatLng? point) {
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
