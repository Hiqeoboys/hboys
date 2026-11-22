import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/plus/domain/cloud_backup_bundle.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';

void main() {
  test('menyederhanakan ribuan titik GPS menjadi bundel kompak <= 15 KB dan pulih utuh',
      () {
    final start = DateTime.utc(2026, 8, 17, 1, 0);
    final rawPoints = <TrackPoint>[
      for (var i = 0; i < 1200; i++)
        TrackPoint(
          lat: -6.894 + i * 0.00004 + math.sin(i / 15) * 0.00025,
          lon: 108.407 + i * 0.00003 + math.cos(i / 20) * 0.00025,
          altitudeM: 1200.0 + i * 1.4,
          accuracyM: 6.0,
          timestampUtc: start.add(Duration(seconds: i * 10)),
        ),
    ];
    final session = TrackingSession(
      id: 'sess-ciremai-1',
      startedAtUtc: start,
      endedAtUtc: start.add(const Duration(hours: 3, minutes: 20)),
      trailId: 'ciremai-apuy',
      distanceM: 9420.5,
      movingSeconds: 11200,
      elevationGainM: 1680.2,
      elevationLossM: 120.4,
      status: TrackingSessionStatus.completed,
      reachedSummit: true,
      mountainName: 'Gunung Ciremai',
      trailName: 'Via Apuy',
    );

    final simplified = simplifyTrackPoints(rawPoints);
    expect(simplified.length, lessThanOrEqualTo(350));
    expect(simplified.first.lat, rawPoints.first.lat);
    expect(simplified.last.lat, rawPoints.last.lat);

    final encoded = encodeSessionBundle(
      session,
      rawPoints,
      activityType: 'hiking',
    );
    expect(encoded.pointCount, lessThanOrEqualTo(350));
    expect(encoded.byteLength, lessThan(15 * 1024));

    final decoded = decodeSessionBundle(encoded.gzipBase64);
    expect(decoded, isNotNull);
    expect(decoded!.session.id, session.id);
    expect(decoded.session.mountainName, 'Gunung Ciremai');
    expect(decoded.session.trailName, 'Via Apuy');
    expect(decoded.session.reachedSummit, isTrue);
    expect(decoded.session.movingSeconds, 11200);
    expect(decoded.session.distanceM, closeTo(9420.5, 0.2));
    expect(decoded.activityType, 'hiking');
    expect(decoded.points.length, encoded.pointCount);
  });

  test('decodeSessionBundle mengembalikan null bila payload rusak', () {
    expect(decodeSessionBundle('bukan-base64-valid!!!'), isNull);
    expect(decodeSessionBundle(''), isNull);
  });
}
