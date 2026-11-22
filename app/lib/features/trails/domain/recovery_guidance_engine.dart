import 'dart:math' as math;

import 'package:geo_utils/geo_utils.dart';

import '../../tracking/domain/track_point.dart';
import 'guidance_config.dart';
import 'guidance_state.dart';
import 'track_route.dart';

/// Mesin logika murni pemandu rute kembali ke jalur utama melalui jejak rekaman.
///
/// Logika murni Dart tanpa dependensi Flutter UI agar mudah diuji secara
/// deterministik dengan jam/titik palsu.
class RecoveryGuidanceEngine {
  RecoveryGuidanceEngine({
    this.config = const GuidanceConfig(),
  });

  final GuidanceConfig config;

  TrackRoute? _route;
  List<double> _cumulativeRouteDistancesM = const <double>[0.0];
  double _totalRouteDistanceM = 0.0;

  // Status internal
  bool _isOffRoute = false;
  DateTime? _offRouteCandidateSince;
  DateTime? _returnCandidateSince;
  double? _lastProgressDistanceM;
  int? _lastSegmentIndex;
  double? _initialRemainingTrailM;
  double? _initialStraightLineDistM;
  int? _cachedAnchorIndex;
  TrackPoint? _cachedAnchorPoint;

  bool get isOffRoute => _isOffRoute;
  double? get lastProgressDistanceM => _lastProgressDistanceM;

  /// Menetapkan rute acuan utama dan mengkalkulasi jarak kumulatif segmen.
  void setRoute(TrackRoute? route) {
    _route = route;
    if (route == null || route.points.isEmpty) {
      _cumulativeRouteDistancesM = const <double>[0.0];
      _totalRouteDistanceM = 0.0;
      reset();
      return;
    }

    final pts = route.points;
    final cum = List<double>.filled(pts.length, 0.0);
    var sum = 0.0;
    for (var i = 1; i < pts.length; i++) {
      sum += distanceMeters(pts[i - 1].position, pts[i].position);
      cum[i] = sum;
    }
    _cumulativeRouteDistancesM = cum;
    _totalRouteDistanceM = sum;
    reset();
  }

  /// Mengosongkan status pemanduan (dwell timer, jejak, dan indeks segmen).
  void reset() {
    _isOffRoute = false;
    _offRouteCandidateSince = null;
    _returnCandidateSince = null;
    _lastProgressDistanceM = null;
    _lastSegmentIndex = null;
    _initialRemainingTrailM = null;
    _initialStraightLineDistM = null;
    _cachedAnchorIndex = null;
    _cachedAnchorPoint = null;
  }

  /// Memproses satu fix GPS dan jejak terekam terbaru, lalu menghasilkan [GuidanceState].
  ///
  /// Bila [isExplicitRequest] bernilai true (mis. pengguna baru saja menekan tombol petunjuk),
  /// evaluasi dilakukan secara instan tanpa menunggu dwell timer [GuidanceConfig.offRouteDwell].
  GuidanceState update({
    required TrackPoint? fix,
    required List<TrackPoint> recordedTrail,
    DateTime? nowUtc,
    bool isExplicitRequest = false,
  }) {
    final route = _route;
    if (route == null || route.points.isEmpty) {
      return const GuidanceUnavailable(GuidanceUnavailableReason.noRoute);
    }

    if (fix == null) {
      return const GuidanceUnavailable(GuidanceUnavailableReason.waitingGps);
    }

    final now = nowUtc ?? fix.timestampUtc;

    // Periksa fix basi: bila umur data GPS melebihi batas waktu staleFixSeconds
    final fixAgeSec = now.difference(fix.timestampUtc).inMilliseconds / 1000.0;
    if (fixAgeSec > config.staleFixSeconds) {
      return const GuidanceUnavailable(GuidanceUnavailableReason.waitingGps);
    }

    // 1. Hitung jarak ke jalur utama dengan preferensi jendela switchback
    final match = _findClosestPointOnRoute(fix.position);
    final distToRouteM = match.distanceM;
    final accuracy = fix.accuracyM;

    final offThreshold = config.offRouteThresholdM(accuracy);
    final returnThreshold = config.returnThresholdM(accuracy);

    // 2. Evaluasi histeresis dan dwell time keadaan
    if (isExplicitRequest) {
      // Permintaan eksplisit: tentukan status seketika tanpa jeda dwell
      if (distToRouteM > offThreshold) {
        _isOffRoute = true;
        _offRouteCandidateSince = null;
        _returnCandidateSince = null;
        _initialRemainingTrailM = null;
        _initialStraightLineDistM = null;
      } else {
        _isOffRoute = false;
        _offRouteCandidateSince = null;
        _returnCandidateSince = null;
        _lastProgressDistanceM = match.routeDistanceM;
        _lastSegmentIndex = match.segmentIndex;
        _initialStraightLineDistM = null;
        _cachedAnchorIndex = null;
        _cachedAnchorPoint = null;
        return GuidanceOnRoute(distToRouteM);
      }
    } else if (!_isOffRoute) {
      // Sedang OnRoute
      if (distToRouteM > offThreshold) {
        _offRouteCandidateSince ??= now;
        final dwell = now.difference(_offRouteCandidateSince!);
        if (dwell >= config.offRouteDwell) {
          // Terkonfirmasi KELUAR JALUR
          _isOffRoute = true;
          _offRouteCandidateSince = null;
          _returnCandidateSince = null;
          _initialRemainingTrailM = null;
          _initialStraightLineDistM = null;
        }
      } else {
        _offRouteCandidateSince = null;
      }

      if (!_isOffRoute) {
        _lastProgressDistanceM = match.routeDistanceM;
        _lastSegmentIndex = match.segmentIndex;
        _initialStraightLineDistM = null;
        return GuidanceOnRoute(distToRouteM);
      }
    } else {
      // Sedang OffRoute
      if (distToRouteM <= returnThreshold) {
        _returnCandidateSince ??= now;
        final dwell = now.difference(_returnCandidateSince!);
        if (dwell >= config.returnDwell) {
          // Terkonfirmasi KEMBALI KE JALUR
          _isOffRoute = false;
          _offRouteCandidateSince = null;
          _returnCandidateSince = null;
          _initialRemainingTrailM = null;
          _initialStraightLineDistM = null;
          _lastProgressDistanceM = match.routeDistanceM;
          _lastSegmentIndex = match.segmentIndex;
          _cachedAnchorIndex = null;
          _cachedAnchorPoint = null;
          return const GuidanceReturned();
        }
      } else {
        _returnCandidateSince = null;
      }
    }

    // 3. Mode Pemanduan Keluar Jalur: cari anchor pada jejak rekaman
    return _buildOffRouteGuidance(
      fix: fix,
      distToRouteM: distToRouteM,
      recordedTrail: recordedTrail,
    );
  }

  GuidanceState _buildOffRouteGuidance({
    required TrackPoint fix,
    required double distToRouteM,
    required List<TrackPoint> recordedTrail,
  }) {
    final currentPosition = fix.position;
    // Abaikan titik dengan akurasi lebih buruk dari trailMaxAccuracyM
    final validPoints = recordedTrail
        .where((p) => p.accuracyM <= config.trailMaxAccuracyM)
        .toList(growable: false);

    if (validPoints.isEmpty) {
      // Jejak kosong -> fallback garis lurus
      _cachedAnchorIndex = null;
      _cachedAnchorPoint = null;
      return _buildStraightLineGuidance(
        currentPosition,
        distToRouteM,
        accuracyM: fix.accuracyM,
      );
    }

    // Cari ANCHOR: titik jejak terbaru ke belakang yang pernah berjarak <= ambang dari jalur utama
    int? anchorIndex;
    if (_cachedAnchorIndex != null &&
        _cachedAnchorIndex! < validPoints.length &&
        _cachedAnchorPoint != null) {
      final cachedPt = validPoints[_cachedAnchorIndex!];
      if (cachedPt.timestampUtc == _cachedAnchorPoint!.timestampUtc) {
        anchorIndex = _cachedAnchorIndex;
      }
    }

    if (anchorIndex == null) {
      for (var i = validPoints.length - 1; i >= 0; i--) {
        final pt = validPoints[i];
        final ptMatch = _findClosestPointOnRoute(pt.position);
        final ptThreshold = config.offRouteThresholdM(pt.accuracyM);
        if (ptMatch.distanceM <= ptThreshold) {
          anchorIndex = i;
          _cachedAnchorIndex = i;
          _cachedAnchorPoint = pt;
          break;
        }
      }
    }

    if (anchorIndex == null) {
      // Anchor tidak ditemukan (tidak pernah dekat jalur utama) -> fallback garis lurus
      _cachedAnchorIndex = null;
      _cachedAnchorPoint = null;
      return _buildStraightLineGuidance(
        currentPosition,
        distToRouteM,
        accuracyM: fix.accuracyM,
      );
    }

    // Bangun jejak mundur dari posisi sekarang sampai anchor
    final rawGuidePoints = <LatLng>[
      currentPosition,
      for (var i = validPoints.length - 1; i >= anchorIndex; i--)
        validPoints[i].position,
    ];

    // Resample tiap trailResampleM (5 m)
    final resampledPath = resamplePolyline(
      rawGuidePoints,
      intervalM: config.trailResampleM,
    );

    // Sederhanakan dengan Douglas-Peucker (4 m)
    final guidePath = simplifyLatLngDouglasPeucker(
      resampledPath,
      toleranceM: config.simplifyToleranceM,
    );

    if (guidePath.length < 2) {
      return _buildStraightLineGuidance(
        currentPosition,
        distToRouteM,
        accuracyM: fix.accuracyM,
      );
    }

    // Jejak yang bisa diikuti tersedia -> hapus status garis lurus
    _initialStraightLineDistM = null;

    // Hitung jarak kumulatif sepanjang guidePath
    final guideCumDist = List<double>.filled(guidePath.length, 0.0);
    var guideTotalM = 0.0;
    for (var i = 1; i < guidePath.length; i++) {
      guideTotalM += distanceMeters(guidePath[i - 1], guidePath[i]);
      guideCumDist[i] = guideTotalM;
    }

    // 4. Tentukan target: titik pada guidePath sekitar lookaheadM (25 m) di depan posisi
    var targetIdx = 1;
    for (var i = 1; i < guidePath.length; i++) {
      if (guideCumDist[i] >= config.lookaheadM) {
        targetIdx = i;
        break;
      }
      targetIdx = i;
    }

    // Bila jarak ke target < targetReachedM (12 m), maju ke titik berikutnya
    while (targetIdx < guidePath.length - 1 &&
        distanceMeters(currentPosition, guidePath[targetIdx]) <
            config.targetReachedM) {
      targetIdx++;
    }

    final targetPoint = guidePath[targetIdx];
    final distToNextM = distanceMeters(currentPosition, targetPoint);
    final bearingDeg = bearingDegrees(currentPosition, targetPoint);

    // Panjang jejak tersisa dari target ke anchor ditambah jarak ke target
    final remainingFromTarget = guideTotalM - guideCumDist[targetIdx];
    final remainingTrailM = distToNextM + remainingFromTarget;

    // 5. Hitung progress: 1 - remainingTrailM / initialRemainingTrailM
    if (_initialRemainingTrailM == null || _initialRemainingTrailM! <= 0) {
      _initialRemainingTrailM = remainingTrailM;
    }
    final progress = _initialRemainingTrailM! <= 0
        ? 1.0
        : (1.0 - (remainingTrailM / _initialRemainingTrailM!))
            .clamp(0.0, 1.0)
            .toDouble();

    return GuidanceFollowingTrail(
      bearingDeg: bearingDeg,
      distToNextM: distToNextM,
      remainingTrailM: remainingTrailM,
      offRouteM: distToRouteM,
      progress: progress,
      targetPoint: targetPoint,
      guidePath: guidePath,
    );
  }

  GuidanceStraightLine _buildStraightLineGuidance(
    LatLng currentPosition,
    double distToRouteM, {
    double? accuracyM,
  }) {
    // Mode garis lurus aktif, hapus progres jejak mundur
    _initialRemainingTrailM = null;

    final match = _findClosestPointOnRoute(currentPosition);
    final targetPoint = match.projectedPoint;
    final bearingDeg = bearingDegrees(currentPosition, targetPoint);

    if (_initialStraightLineDistM == null || _initialStraightLineDistM! <= 0) {
      _initialStraightLineDistM = distToRouteM;
    }
    final initial = _initialStraightLineDistM!;
    final progress = initial <= 0.0
        ? 1.0
        : (1.0 - (distToRouteM / initial)).clamp(0.0, 1.0).toDouble();

    return GuidanceStraightLine(
      bearingDeg: bearingDeg,
      distToRouteM: distToRouteM,
      progress: progress,
      targetPoint: targetPoint,
      accuracyM: accuracyM,
    );
  }

  /// Mencari segmen terdekat dengan preferensi jendela progres di sekitar posisi terakhir
  /// untuk mencegah salah cocok pada switchback (kelokan tajam).
  _RouteProjection _findClosestPointOnRoute(LatLng p) {
    final route = _route;
    if (route == null || route.points.length < 2) {
      final only = route?.points.firstOrNull?.position ?? p;
      return _RouteProjection(
        projectedPoint: only,
        distanceM: distanceMeters(p, only),
        routeDistanceM: 0.0,
        segmentIndex: 0,
      );
    }

    final pts = route.points;
    final cum = _cumulativeRouteDistancesM;
    final lastSeg = _lastSegmentIndex;
    final lastDist = _lastProgressDistanceM;

    // 1. Prioritas Segmen Berurutan (Immediate Neighbors):
    // Jika pendaki sebelumnya berada di segmen `lastSeg`, cek segmen [lastSeg, lastSeg + 1, lastSeg - 1].
    // Jika jarak ke segmen terdekat dalam grup ini masih dalam ambang keluar jalur (<= offRouteMinM),
    // pertahankan segmen tersebut agar tidak melompat ke segmen seberang switchback!
    if (lastSeg != null && lastSeg < pts.length - 1) {
      final immediateIndices = <int>{
        lastSeg,
        if (lastSeg + 1 < pts.length - 1) lastSeg + 1,
        if (lastSeg - 1 >= 0) lastSeg - 1,
      };

      var bestImmDist = double.infinity;
      _RouteProjection? bestImmProj;

      for (final i in immediateIndices) {
        final proj =
            _projectOnSegment(p, pts[i].position, pts[i + 1].position, i);
        if (proj.distanceM < bestImmDist) {
          bestImmDist = proj.distanceM;
          bestImmProj = proj;
        }
      }

      if (bestImmProj != null && bestImmDist <= config.offRouteMinM) {
        return bestImmProj;
      }
    }

    // 2. Jika di luar segmen langsung, cari dalam jendela jarak kumulatif
    if (lastDist != null) {
      final winMin = math.max(0.0, lastDist - config.switchbackWindowMeters);
      final winMax = math.min(
          _totalRouteDistanceM, lastDist + config.switchbackWindowMeters);

      var bestWinDist = double.infinity;
      _RouteProjection? bestWinProj;

      for (var i = 0; i < pts.length - 1; i++) {
        final segStart = cum[i];
        final segEnd = cum[i + 1];
        // Periksa apakah segmen ini beririsan dengan jendela progres
        if (segEnd < winMin || segStart > winMax) continue;

        final proj =
            _projectOnSegment(p, pts[i].position, pts[i + 1].position, i);
        if (proj.distanceM < bestWinDist) {
          bestWinDist = proj.distanceM;
          bestWinProj = proj;
        }
      }

      // Jika jarak dalam jendela masih wajar (tidak melompat jauh), utamakan jendela ini
      if (bestWinProj != null && bestWinDist <= config.offRouteMinM * 1.5) {
        return bestWinProj;
      }
    }

    // 2. Evaluasi seluruh segmen jika belum ada progres atau di luar jendela
    var bestDist = double.infinity;
    late _RouteProjection bestProj;

    for (var i = 0; i < pts.length - 1; i++) {
      final proj =
          _projectOnSegment(p, pts[i].position, pts[i + 1].position, i);
      if (proj.distanceM < bestDist) {
        bestDist = proj.distanceM;
        bestProj = proj;
      }
    }

    return bestProj;
  }

  _RouteProjection _projectOnSegment(
    LatLng p,
    LatLng a,
    LatLng b,
    int segIdx,
  ) {
    const metersPerDegree = earthRadiusM * math.pi / 180.0;
    final cosLat = math.cos(p.lat * math.pi / 180.0);
    double x(LatLng q) => (q.lon - p.lon) * cosLat * metersPerDegree;
    double y(LatLng q) => (q.lat - p.lat) * metersPerDegree;

    final ax = x(a), ay = y(a), bx = x(b), by = y(b);
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    var t = 0.0;
    if (len2 > 0) {
      t = ((-ax) * dx + (-ay) * dy) / len2;
    }
    t = t.clamp(0.0, 1.0).toDouble();

    final projX = ax + t * dx;
    final projY = ay + t * dy;
    final distM = math.sqrt(projX * projX + projY * projY);
    final projPoint = LatLng(
      p.lat + projY / metersPerDegree,
      p.lon + (cosLat.abs() > 1e-6 ? projX / (cosLat * metersPerDegree) : 0.0),
    );

    final segStartDist = _cumulativeRouteDistancesM[segIdx];
    final segLen = distanceMeters(a, b);
    final routeDistM = segStartDist + t * segLen;

    return _RouteProjection(
      projectedPoint: projPoint,
      distanceM: distM,
      routeDistanceM: routeDistM,
      segmentIndex: segIdx,
    );
  }
}

class _RouteProjection {
  const _RouteProjection({
    required this.projectedPoint,
    required this.distanceM,
    required this.routeDistanceM,
    required this.segmentIndex,
  });

  final LatLng projectedPoint;
  final double distanceM;
  final double routeDistanceM;
  final int segmentIndex;
}

/// Menginterpolasi ulang polyline sehingga memiliki titik-titik dengan jarak tetap [intervalM].
List<LatLng> resamplePolyline(
  List<LatLng> points, {
  required double intervalM,
}) {
  if (points.length <= 1 || intervalM <= 0) {
    return List<LatLng>.of(points);
  }

  final cum = List<double>.filled(points.length, 0.0);
  var totalLen = 0.0;
  for (var i = 1; i < points.length; i++) {
    totalLen += distanceMeters(points[i - 1], points[i]);
    cum[i] = totalLen;
  }

  if (totalLen <= intervalM) {
    return <LatLng>[points.first, points.last];
  }

  final result = <LatLng>[points.first];
  var targetDist = intervalM;
  var segIdx = 0;

  while (targetDist < totalLen && segIdx < points.length - 1) {
    while (segIdx < points.length - 1 && cum[segIdx + 1] < targetDist) {
      segIdx++;
    }
    if (segIdx >= points.length - 1) break;

    final p0 = points[segIdx];
    final p1 = points[segIdx + 1];
    final segStart = cum[segIdx];
    final segLen = cum[segIdx + 1] - segStart;
    final t =
        segLen > 0 ? ((targetDist - segStart) / segLen).clamp(0.0, 1.0) : 0.0;

    final lat = p0.lat + t * (p1.lat - p0.lat);
    final lon = p0.lon + t * (p1.lon - p0.lon);
    result.add(LatLng(lat, lon));

    targetDist += intervalM;
  }

  if (distanceMeters(result.last, points.last) > 0.5) {
    result.add(points.last);
  }

  return result;
}

/// Menyederhanakan daftar titik [LatLng] dengan Ramer-Douglas-Peucker.
List<LatLng> simplifyLatLngDouglasPeucker(
  List<LatLng> points, {
  double toleranceM = 4.0,
}) {
  if (points.length <= 2 || toleranceM <= 0) {
    return List<LatLng>.of(points);
  }

  final keep = List<bool>.filled(points.length, false);
  keep[0] = true;
  keep[points.length - 1] = true;

  final stack = <(int, int)>[(0, points.length - 1)];
  while (stack.isNotEmpty) {
    final (start, end) = stack.removeLast();
    if (end - start <= 1) continue;

    var maxDistM = -1.0;
    var splitIndex = -1;
    final a = points[start];
    final b = points[end];

    for (var i = start + 1; i < end; i++) {
      final distM = distanceToSegmentMeters(points[i], a, b);
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

  return <LatLng>[
    for (var i = 0; i < points.length; i++)
      if (keep[i]) points[i],
  ];
}
