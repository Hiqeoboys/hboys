import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:gpx/gpx.dart';

import '../domain/track_route.dart';

/// Pembaca berkas GPX dari Flutter assets maupun string XML menggunakan paket `gpx`.
///
/// Menangani:
/// - Berkas tanpa informasi elevasi (`<ele>`) atau waktu (`<time>`)
/// - Beberapa track (`<trk>`) dan beberapa segmen (`<trkseg>`)
/// - Elemen route (`<rte>` / `<rtept>`) selain track (`<trk>` / `<trkpt>`)
class GpxLoader {
  const GpxLoader._();

  static const String defaultGpxAssetPath = 'assets/gpx/CIREMAI VIA APUY.gpx';

  static final Map<String, TrackRoute> _assetCache = <String, TrackRoute>{};
  static final Map<String, Future<TrackRoute>> _inFlightAssets =
      <String, Future<TrackRoute>>{};

  /// Memuat dan mem-parsing berkas GPX dari `assets` di isolate latar belakang.
  static Future<TrackRoute> loadAsset(
    String assetPath, {
    AssetBundle? bundle,
    String? id,
    String defaultName = 'Jalur GPX',
    double simplifyToleranceM = 5.0,
    double elevationThresholdM = 2.5,
  }) {
    final routeId = id ?? _idFromPath(assetPath);
    final cacheKey =
        '$assetPath|$routeId|$defaultName|$simplifyToleranceM|$elevationThresholdM';
    final cached = bundle == null ? _assetCache[cacheKey] : null;
    if (cached != null) {
      return Future<TrackRoute>.value(cached);
    }
    if (bundle == null) {
      final inFlight = _inFlightAssets[cacheKey];
      if (inFlight != null) return inFlight;
    }

    final future = _loadAssetUncached(
      assetPath: assetPath,
      bundle: bundle,
      routeId: routeId,
      defaultName: defaultName,
      simplifyToleranceM: simplifyToleranceM,
      elevationThresholdM: elevationThresholdM,
      cacheKey: bundle == null ? cacheKey : null,
    );
    if (bundle == null) {
      _inFlightAssets[cacheKey] = future;
    }
    return future;
  }

  static Future<TrackRoute> _loadAssetUncached({
    required String assetPath,
    required AssetBundle? bundle,
    required String routeId,
    required String defaultName,
    required double simplifyToleranceM,
    required double elevationThresholdM,
    required String? cacheKey,
  }) async {
    try {
      final effectiveBundle = bundle ?? rootBundle;
      final xmlString = await effectiveBundle.loadString(assetPath);
      final route = await Isolate.run(
        () => parseString(
          xmlString,
          id: routeId,
          defaultName: defaultName,
          simplifyToleranceM: simplifyToleranceM,
          elevationThresholdM: elevationThresholdM,
        ),
      );
      if (cacheKey != null) {
        if (_assetCache.length >= 24) {
          _assetCache.remove(_assetCache.keys.first);
        }
        _assetCache[cacheKey] = route;
      }
      return route;
    } finally {
      if (cacheKey != null) {
        unawaited(_inFlightAssets.remove(cacheKey));
      }
    }
  }

  /// Mem-parsing string XML GPX menjadi [TrackRoute].
  static TrackRoute parseString(
    String xmlString, {
    String id = 'gpx_route',
    String defaultName = 'Jalur GPX',
    double simplifyToleranceM = 5.0,
    double elevationThresholdM = 2.5,
  }) {
    final gpx = GpxReader().fromString(xmlString);
    final points = <TrackRoutePoint>[];
    String? resolvedName;

    // 1. Baca semua <trk> dan <trkseg>
    for (final trk in gpx.trks) {
      if (resolvedName == null && (trk.name?.trim().isNotEmpty ?? false)) {
        resolvedName = trk.name!.trim();
      }
      for (final seg in trk.trksegs) {
        for (final pt in seg.trkpts) {
          final converted = _convertWpt(pt);
          if (converted != null) {
            points.add(converted);
          }
        }
      }
    }

    // 2. Bila tidak ada titik pada <trk> (atau berkas memakai <rte>), baca <rte>
    if (points.isEmpty) {
      for (final rte in gpx.rtes) {
        if (resolvedName == null && (rte.name?.trim().isNotEmpty ?? false)) {
          resolvedName = rte.name!.trim();
        }
        for (final pt in rte.rtepts) {
          final converted = _convertWpt(pt);
          if (converted != null) {
            points.add(converted);
          }
        }
      }
    } else {
      // Jika file memiliki <trk> sekaligus <rte> tambahan yang terpisah,
      // tetap utamakan <trk> agar titik tidak terduplikasi, namun ambil nama
      // dari <rte> bila <trk> tidak bernama.
      if (resolvedName == null) {
        for (final rte in gpx.rtes) {
          if (rte.name?.trim().isNotEmpty ?? false) {
            resolvedName = rte.name!.trim();
            break;
          }
        }
      }
    }

    // 3. Fallback ke <wpt> bila <trk> dan <rte> sama-sama kosong
    if (points.isEmpty) {
      for (final wpt in gpx.wpts) {
        final converted = _convertWpt(wpt);
        if (converted != null) {
          points.add(converted);
        }
      }
    }

    // 4. Fallback nama dari metadata GPX atau defaultName
    if (resolvedName == null || resolvedName.isEmpty) {
      final metaName = gpx.metadata?.name?.trim();
      resolvedName =
          (metaName != null && metaName.isNotEmpty) ? metaName : defaultName;
    }

    final waypoints = _extractWaypoints(gpx.wpts, points);

    return TrackRoute.fromPoints(
      id: id,
      name: resolvedName,
      points: points,
      waypoints: waypoints,
      simplifyToleranceM: simplifyToleranceM,
      elevationThresholdM: elevationThresholdM,
    );
  }

  static List<TrackWaypoint> _extractWaypoints(
    List<Wpt> rawWpts,
    List<TrackRoutePoint> points,
  ) {
    if (rawWpts.isEmpty) return const <TrackWaypoint>[];
    final cumulative = <double>[0.0];
    for (var i = 1; i < points.length; i++) {
      cumulative.add(
        cumulative.last +
            distanceMeters(points[i - 1].position, points[i].position),
      );
    }

    final result = <TrackWaypoint>[];
    for (final wpt in rawWpts) {
      final lat = wpt.lat;
      final lon = wpt.lon;
      final name = wpt.name?.trim();
      if (lat == null ||
          lon == null ||
          !lat.isFinite ||
          !lon.isFinite ||
          name == null ||
          name.isEmpty) {
        continue;
      }
      if (lat < -90 || lat > 90 || lon < -180 || lon > 180) continue;

      double? ele = (wpt.ele != null && wpt.ele!.isFinite) ? wpt.ele : null;
      var distFromStart = 0.0;
      if (points.isNotEmpty) {
        final wptPos = LatLng(lat, lon);
        var bestIdx = 0;
        var bestDist = double.infinity;
        for (var i = 0; i < points.length; i++) {
          final d = distanceMeters(wptPos, points[i].position);
          if (d < bestDist) {
            bestDist = d;
            bestIdx = i;
          }
        }
        distFromStart = cumulative[bestIdx];
        ele ??= points[bestIdx].ele;
      }

      result.add(
        TrackWaypoint(
          name: name,
          lat: lat,
          lon: lon,
          elevationM: ele,
          distanceFromStartM: distFromStart,
          symbol: wpt.sym?.trim(),
        ),
      );
    }
    result.sort(
      (a, b) => a.distanceFromStartM.compareTo(b.distanceFromStartM),
    );
    return List<TrackWaypoint>.unmodifiable(result);
  }

  static TrackRoutePoint? _convertWpt(Wpt wpt) {
    final lat = wpt.lat;
    final lon = wpt.lon;
    if (lat == null || lon == null || !lat.isFinite || !lon.isFinite) {
      return null;
    }
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      return null;
    }
    final ele = (wpt.ele != null && wpt.ele!.isFinite) ? wpt.ele : null;
    final time = wpt.time?.toUtc();
    return TrackRoutePoint(
      lat: lat,
      lon: lon,
      ele: ele,
      time: time,
    );
  }

  static String _idFromPath(String path) {
    final slash = path.lastIndexOf('/');
    final base = slash >= 0 ? path.substring(slash + 1) : path;
    final dot = base.lastIndexOf('.');
    final stem = dot > 0 ? base.substring(0, dot) : base;
    return stem.isEmpty ? 'gpx_route' : stem;
  }
}

