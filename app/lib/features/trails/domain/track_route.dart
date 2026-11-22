import 'dart:math' as math;

import 'package:geo_utils/geo_utils.dart';

import '../../map/domain/map_package.dart';
import '../../tracking/domain/elevation_profile.dart';

/// Satu waypoint / pos pada rute jalur GPX.
class TrackWaypoint {
  const TrackWaypoint({
    required this.name,
    required this.lat,
    required this.lon,
    this.elevationM,
    this.distanceFromStartM = 0.0,
    this.symbol,
  });

  final String name;
  final double lat;
  final double lon;
  final double? elevationM;
  final double distanceFromStartM;
  final String? symbol;

  LatLng get position => LatLng(lat, lon);
}

/// Satu titik pada rute jalur (dari berkas GPX atau jalur terverifikasi).
class TrackRoutePoint {
  const TrackRoutePoint({
    required this.lat,
    required this.lon,
    this.ele,
    this.time,
  });

  final double lat;
  final double lon;
  final double? ele;
  final DateTime? time;

  LatLng get position => LatLng(lat, lon);
}

/// Hasil perhitungan statistik elevasi rute.
class ElevationStats {
  const ElevationStats({
    required this.gainM,
    required this.lossM,
    this.minElevationM,
    this.maxElevationM,
  });

  final double gainM;
  final double lossM;
  final double? minElevationM;
  final double? maxElevationM;
}

/// Model rute jalur yang independen dari UI. Dapat dipakai oleh halaman Peta,
/// simulasi lokasi pada halaman Track, maupun fitur Beranda / Jalur terverifikasi.
class TrackRoute {
  TrackRoute({
    required this.id,
    required this.name,
    required List<TrackRoutePoint> points,
    required List<TrackRoutePoint> simplifiedPoints,
    required this.totalDistanceM,
    required this.totalElevationGainM,
    required this.totalElevationLossM,
    required this.bounds,
    required List<double> elevationProfile,
    this.minElevationM,
    this.maxElevationM,
    List<TrackWaypoint> waypoints = const <TrackWaypoint>[],
  })  : points = List<TrackRoutePoint>.unmodifiable(points),
        simplifiedPoints = List<TrackRoutePoint>.unmodifiable(simplifiedPoints),
        elevationProfile = List<double>.unmodifiable(elevationProfile),
        waypoints = List<TrackWaypoint>.unmodifiable(waypoints);

  factory TrackRoute.fromPoints({
    required String id,
    required String name,
    required List<TrackRoutePoint> points,
    List<TrackWaypoint> waypoints = const <TrackWaypoint>[],
    double simplifyToleranceM = 5.0,
    double elevationThresholdM = 2.5,
    int elevationSmoothingWindow = 5,
  }) {
    final distanceM = computeHaversineDistanceM(points);
    final eleStats = computeElevationStats(
      points.map((p) => p.ele).toList(growable: false),
      thresholdM: elevationThresholdM,
      smoothingWindow: elevationSmoothingWindow,
    );
    final simplified = simplifyDouglasPeucker(
      points,
      toleranceM: simplifyToleranceM,
    );
    final bounds = computeRouteBounds(points);
    final profile = buildRouteElevationProfile(
      points,
      smoothing: elevationSmoothingWindow,
    );

    return TrackRoute(
      id: id,
      name: name,
      points: points,
      simplifiedPoints: simplified,
      totalDistanceM: distanceM,
      totalElevationGainM: eleStats.gainM,
      totalElevationLossM: eleStats.lossM,
      minElevationM: eleStats.minElevationM,
      maxElevationM: eleStats.maxElevationM,
      bounds: bounds,
      elevationProfile: profile,
      waypoints: waypoints,
    );
  }

  final String id;
  final String name;

  /// Daftar pos/waypoint bermakna dari `<wpt>` GPX yang diurutkan sepanjang jalur.
  final List<TrackWaypoint> waypoints;

  /// Titik asli lengkap untuk perhitungan metrik dan simulasi tracking.
  final List<TrackRoutePoint> points;

  /// Titik yang telah disederhanakan dengan Douglas-Peucker untuk digambar di peta.
  final List<TrackRoutePoint> simplifiedPoints;

  /// Jarak total Haversine dalam meter.
  final double totalDistanceM;

  /// Total tanjakan (meter) dari elevasi terhaluskan dengan ambang histeresis.
  final double totalElevationGainM;

  /// Total turunan (meter) dari elevasi terhaluskan dengan ambang histeresis.
  final double totalElevationLossM;

  final double? minElevationM;
  final double? maxElevationM;
  final GeoBounds bounds;

  /// Deret sampel elevasi terhaluskan untuk komponen grafik profil ketinggian.
  final List<double> elevationProfile;

  bool get isEmpty => points.isEmpty;
  bool get isNotEmpty => points.isNotEmpty;

  TrackRoutePoint? get startPoint => points.isEmpty ? null : points.first;
  TrackRoutePoint? get endPoint => points.isEmpty ? null : points.last;

  /// Titik puncak rute (elevasi tertinggi; jatuh ke titik akhir jika tanpa `<ele>`).
  TrackRoutePoint? get summitPoint {
    if (points.isEmpty) return null;
    TrackRoutePoint? highest;
    for (final pt in points) {
      if (pt.ele != null &&
          (highest == null || highest.ele == null || pt.ele! > highest.ele!)) {
        highest = pt;
      }
    }
    return highest ?? points.last;
  }

  /// Membalik urutan koordinat rute dari puncak kembali ke titik awal (mode turun).
  TrackRoute reversed({String? suffix}) {
    final reversedPts = points.reversed.toList(growable: false);
    return TrackRoute.fromPoints(
      id: '${id}_turun',
      name: suffix == null ? name : '$name $suffix',
      points: reversedPts,
    );
  }

  List<LatLng> get positions =>
      <LatLng>[for (final point in points) point.position];

  List<LatLng> get simplifiedPositions =>
      <LatLng>[for (final point in simplifiedPoints) point.position];

  /// Mengonversi ke [MapTrail] agar dapat dipakai ulang oleh fitur jalur
  /// terverifikasi atau paket peta gunung.
  MapTrail toMapTrail({
    String source = 'GPX',
    bool verified = false,
    DateTime? verifiedAtUtc,
    String? verifiedBy,
  }) {
    return MapTrail(
      id: id,
      name: name,
      source: source,
      verified: verified,
      verifiedAtUtc: verifiedAtUtc,
      verifiedBy: verifiedBy,
      points: simplifiedPositions.length >= 2 ? simplifiedPositions : positions,
    );
  }
}

/// Menghitung jarak total Haversine (meter) sepanjang daftar [points].
double computeHaversineDistanceM(List<TrackRoutePoint> points) {
  if (points.length < 2) return 0.0;
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += distanceMeters(points[i - 1].position, points[i].position);
  }
  return total;
}

/// Menghitung total tanjakan, turunan, serta elevasi min/maks.
///
/// Elevasi dihaluskan terlebih dahulu dengan rata-rata bergerak [smoothingWindow]
/// titik, lalu dihitung memakai histeresis berambang [thresholdM] (default 2,5 m)
/// agar noise mikro tidak terhitung sebagai tanjakan/turunan palsu.
ElevationStats computeElevationStats(
  List<double?> rawElevations, {
  double thresholdM = 2.5,
  int smoothingWindow = 5,
}) {
  final valid = <double>[
    for (final ele in rawElevations)
      if (ele != null && ele.isFinite) ele,
  ];
  if (valid.isEmpty) {
    return const ElevationStats(gainM: 0.0, lossM: 0.0);
  }

  final minEle = valid.reduce(math.min);
  final maxEle = valid.reduce(math.max);
  if (valid.length < 2) {
    return ElevationStats(
      gainM: 0.0,
      lossM: 0.0,
      minElevationM: minEle,
      maxElevationM: maxEle,
    );
  }

  final smoothed = movingAverage(valid, smoothingWindow);
  var anchor = smoothed.first;
  var gain = 0.0;
  var loss = 0.0;

  for (var i = 1; i < smoothed.length; i++) {
    final diff = smoothed[i] - anchor;
    if (diff >= thresholdM) {
      gain += diff;
      anchor = smoothed[i];
    } else if (diff <= -thresholdM) {
      loss += -diff;
      anchor = smoothed[i];
    }
  }

  return ElevationStats(
    gainM: gain,
    lossM: loss,
    minElevationM: minEle,
    maxElevationM: maxEle,
  );
}

/// Menyederhanakan daftar titik menggunakan algoritma Ramer-Douglas-Peucker
/// dengan toleransi jarak tegak lurus [toleranceM] dalam meter.
List<TrackRoutePoint> simplifyDouglasPeucker(
  List<TrackRoutePoint> points, {
  double toleranceM = 5.0,
}) {
  if (points.length <= 2 || toleranceM <= 0) {
    return List<TrackRoutePoint>.of(points);
  }

  final keep = List<bool>.filled(points.length, false);
  keep[0] = true;
  keep[points.length - 1] = true;

  // Stack iteratif pasangan indeks (start, end) agar aman untuk ribuan titik.
  final stack = <(int, int)>[(0, points.length - 1)];
  while (stack.isNotEmpty) {
    final (start, end) = stack.removeLast();
    if (end - start <= 1) continue;

    var maxDistM = -1.0;
    var splitIndex = -1;
    final a = points[start].position;
    final b = points[end].position;

    for (var i = start + 1; i < end; i++) {
      final distM = distanceToSegmentMeters(points[i].position, a, b);
      if (distM > maxDistM) {
        maxDistM = distM;
        splitIndex = i;
      }
    }

    if (maxDistM > toleranceM && splitIndex != -1) {
      keep[splitIndex] = true;
      stack.add((start, splitIndex));
      stack.add((splitIndex, end));
    }
  }

  return <TrackRoutePoint>[
    for (var i = 0; i < points.length; i++)
      if (keep[i]) points[i],
  ];
}

/// Menghitung kotak pembatas ([GeoBounds]) dari daftar titik rute.
/// Bila semua titik identik atau hanya satu titik, diberi bantalan kecil (~100 m)
/// agar `bounds.isValid` tetap bernilai true saat mengarahkan kamera peta.
GeoBounds computeRouteBounds(List<TrackRoutePoint> points) {
  if (points.isEmpty) {
    return const GeoBounds(
      south: -6.91,
      west: 108.39,
      north: -6.89,
      east: 108.41,
    );
  }
  var south = points.first.lat;
  var north = points.first.lat;
  var west = points.first.lon;
  var east = points.first.lon;

  for (var i = 1; i < points.length; i++) {
    final p = points[i];
    if (p.lat < south) south = p.lat;
    if (p.lat > north) north = p.lat;
    if (p.lon < west) west = p.lon;
    if (p.lon > east) east = p.lon;
  }

  const minSpanDeg = 0.001;
  if ((north - south) < minSpanDeg) {
    south -= minSpanDeg / 2;
    north += minSpanDeg / 2;
  }
  if ((east - west) < minSpanDeg) {
    west -= minSpanDeg / 2;
    east += minSpanDeg / 2;
  }

  return GeoBounds(
    south: south,
    west: west,
    north: north,
    east: east,
  );
}

/// Membangun deret profil ketinggian yang dihaluskan untuk grafik rute.
List<double> buildRouteElevationProfile(
  List<TrackRoutePoint> points, {
  double distanceStepM = 20,
  int smoothing = 5,
  int maxSamples = 120,
}) {
  final samples = <double>[];
  TrackRoutePoint? previous;
  var distanceSinceKept = 0.0;
  var hasKept = false;

  for (final point in points) {
    final ele = point.ele;
    if (ele == null || !ele.isFinite) continue;
    if (previous != null) {
      distanceSinceKept += distanceMeters(previous.position, point.position);
    }
    previous = point;
    if (!hasKept || distanceSinceKept >= distanceStepM) {
      samples.add(ele);
      hasKept = true;
      distanceSinceKept = 0.0;
    }
  }

  // Pastikan titik terakhir yang memiliki elevasi ikut tercakup.
  for (var i = points.length - 1; i >= 0; i--) {
    final lastEle = points[i].ele;
    if (lastEle != null && lastEle.isFinite) {
      if (samples.isNotEmpty && samples.last != lastEle) {
        samples.add(lastEle);
      }
      break;
    }
  }

  final smoothed = movingAverage(samples, smoothing);
  return downsample(smoothed, maxSamples);
}

