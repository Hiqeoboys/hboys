import 'dart:convert';
import 'dart:io';

import 'package:geo_utils/geo_utils.dart';

import '../../tracking/domain/track_point.dart';
import '../../tracking/domain/tracking_session.dart';

class EncodedSessionBundle {
  const EncodedSessionBundle({
    required this.gzipBase64,
    required this.byteLength,
    required this.pointCount,
  });

  final String gzipBase64;
  final int byteLength;
  final int pointCount;
}

class DecodedSessionBundle {
  const DecodedSessionBundle({
    required this.session,
    required this.points,
    this.activityType = 'hiking',
  });

  final TrackingSession session;
  final List<TrackPoint> points;
  final String activityType;
}

/// Menyederhanakan jejak GPS memakai Ramer–Douglas–Peucker (basis meter dari
/// `geo_utils`) agar ukuran cadangan cloud tetap ~5–15 KB per sesi.
List<TrackPoint> simplifyTrackPoints(
  List<TrackPoint> points, {
  double epsilonMeters = 8.0,
  int maxPoints = 350,
}) {
  if (points.length <= 2) return List<TrackPoint>.of(points);
  var simplified = _rdpIterative(points, epsilonMeters);
  if (simplified.length > maxPoints) {
    simplified = _rdpIterative(points, 18.0);
  }
  if (simplified.length > maxPoints) {
    final sampled = <TrackPoint>[simplified.first];
    final step = (simplified.length - 1) / (maxPoints - 1);
    for (var i = 1; i < maxPoints - 1; i++) {
      sampled.add(simplified[(i * step).round()]);
    }
    sampled.add(simplified.last);
    return sampled;
  }
  return simplified;
}

List<TrackPoint> _rdpIterative(List<TrackPoint> points, double epsilonMeters) {
  final n = points.length;
  final keep = List<bool>.filled(n, false);
  keep[0] = true;
  keep[n - 1] = true;

  final stack = <(int, int)>[(0, n - 1)];
  while (stack.isNotEmpty) {
    final (start, end) = stack.removeLast();
    if (end - start <= 1) continue;
    final a = LatLng(points[start].lat, points[start].lon);
    final b = LatLng(points[end].lat, points[end].lon);
    var maxDist = -1.0;
    var index = -1;
    for (var i = start + 1; i < end; i++) {
      final p = LatLng(points[i].lat, points[i].lon);
      final d = distanceToSegmentMeters(p, a, b);
      if (d > maxDist) {
        maxDist = d;
        index = i;
      }
    }
    if (index != -1 && maxDist > epsilonMeters) {
      keep[index] = true;
      stack.add((start, index));
      stack.add((index, end));
    }
  }

  return <TrackPoint>[
    for (var i = 0; i < n; i++)
      if (keep[i]) points[i],
  ];
}

double _round5(double v) => (v * 100000).roundToDouble() / 100000;
double _round1(double v) => (v * 10).roundToDouble() / 10;

/// Mengemas jejak GPS tersederhanakan menjadi polyline terkompresi (~3–8 KB)
/// untuk kolom `hike_sessions.route_polyline_b64` tanpa menyimpan ribuan baris.
EncodedSessionBundle? encodeSimplifiedRoutePolyline(
  List<TrackPoint> points, {
  double epsilonMeters = 8.0,
  int maxPoints = 250,
}) {
  if (points.length < 2) return null;
  final simplified = simplifyTrackPoints(
    points,
    epsilonMeters: epsilonMeters,
    maxPoints: maxPoints,
  );
  final packed = <List<num?>>[
    for (final pt in simplified)
      <num?>[
        _round5(pt.lat),
        _round5(pt.lon),
        pt.altitudeM == null ? null : _round1(pt.altitudeM!),
      ],
  ];
  final compressed = gzip.encode(utf8.encode(jsonEncode(packed)));
  return EncodedSessionBundle(
    gzipBase64: base64Encode(compressed),
    byteLength: compressed.length,
    pointCount: simplified.length,
  );
}

/// Mengemas sesi dan jejak titik tersederhanakan ke JSON terkompresi gzip+base64.
EncodedSessionBundle encodeSessionBundle(
  TrackingSession session,
  List<TrackPoint> points, {
  String? activityType,
}) {
  final resolvedActivity =
      TrackingSession.normalizeActivityType(activityType ?? session.activityType);
  final simplified = simplifyTrackPoints(points);
  final startUtc = session.startedAtUtc.toUtc();
  final packedPoints = <List<num?>>[
    for (final pt in simplified)
      <num?>[
        _round5(pt.lat),
        _round5(pt.lon),
        pt.altitudeM == null ? null : _round1(pt.altitudeM!),
        pt.timestampUtc.toUtc().difference(startUtc).inSeconds,
      ],
  ];

  final payload = <String, Object?>{
    'v': 1,
    'id': session.id,
    'st': startUtc.toIso8601String(),
    'et': session.endedAtUtc?.toUtc().toIso8601String(),
    'gid': session.groupId,
    'tid': session.trailId,
    'dm': _round1(session.distanceM),
    'ms': session.movingSeconds,
    'eg': _round1(session.elevationGainM),
    'el': _round1(session.elevationLossM),
    'rs': session.reachedSummit,
    'mn': session.mountainName,
    'tn': session.trailName,
    'at': resolvedActivity,
    'pts': packedPoints,
  };

  final compressed = gzip.encode(utf8.encode(jsonEncode(payload)));
  return EncodedSessionBundle(
    gzipBase64: base64Encode(compressed),
    byteLength: compressed.length,
    pointCount: simplified.length,
  );
}

/// Membongkar bundel JSON gzip+base64 dari `cloud_session_backups`.
/// Mengembalikan `null` bila payload rusak atau versi tidak dikenal.
DecodedSessionBundle? decodeSessionBundle(String gzipBase64) {
  try {
    final gzBytes = base64Decode(gzipBase64);
    final raw = utf8.decode(gzip.decode(gzBytes));
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;

    final id = decoded['id']?.toString() ?? '';
    final startedAt = DateTime.tryParse(decoded['st']?.toString() ?? '')?.toUtc();
    if (id.isEmpty || startedAt == null) return null;
    final endedAt = DateTime.tryParse(decoded['et']?.toString() ?? '')?.toUtc();
    final activity =
        TrackingSession.normalizeActivityType(decoded['at']?.toString());

    final session = TrackingSession(
      id: id,
      startedAtUtc: startedAt,
      endedAtUtc: endedAt,
      groupId: decoded['gid']?.toString(),
      trailId: decoded['tid']?.toString(),
      distanceM: (decoded['dm'] as num?)?.toDouble() ?? 0,
      movingSeconds: (decoded['ms'] as num?)?.toInt() ?? 0,
      elevationGainM: (decoded['eg'] as num?)?.toDouble() ?? 0,
      elevationLossM: (decoded['el'] as num?)?.toDouble() ?? 0,
      status: TrackingSessionStatus.completed,
      reachedSummit: activity == TrackingSession.activityHiking &&
          decoded['rs'] == true,
      mountainName: decoded['mn']?.toString(),
      trailName: decoded['tn']?.toString(),
      activityType: activity,
    );

    final points = <TrackPoint>[];
    final rawPts = decoded['pts'];
    if (rawPts is List) {
      for (final item in rawPts) {
        if (item is! List || item.length < 4) continue;
        final lat = (item[0] as num?)?.toDouble();
        final lon = (item[1] as num?)?.toDouble();
        final alt = (item[2] as num?)?.toDouble();
        final dtSec = (item[3] as num?)?.toInt();
        if (lat == null || lon == null || dtSec == null) continue;
        points.add(
          TrackPoint(
            lat: lat,
            lon: lon,
            altitudeM: alt,
            accuracyM: 10.0,
            timestampUtc: startedAt.add(Duration(seconds: dtSec)),
          ),
        );
      }
    }

    return DecodedSessionBundle(
      session: session,
      points: points,
      activityType: activity,
    );
  } catch (_) {
    return null;
  }
}
