import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:nama_app/features/map/domain/track_geojson.dart';
import 'package:nama_app/features/map/domain/trail_guidance.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/trails/domain/off_trail_detector.dart';

void main() {
  // Jalur lurus ke timur di khatulistiwa, 1,1 km.
  const trail = [LatLng(0, 0), LatLng(0, 0.01)];
  // Titik ~ metersNorth meter di utara jalur.
  LatLng north(double meters) => LatLng(meters / 111195.0, 0.005);

  test('butuh beberapa titik beruntun untuk dinyatakan keluar jalur', () {
    final d = OffTrailDetector(trail: trail);
    expect(d.update(north(80)), TrailState.onTrail);
    expect(d.update(north(80)), TrailState.onTrail);
    expect(d.update(north(80)), TrailState.offTrail);
  });

  test('satu titik melenceng tidak memicu alarm', () {
    final d = OffTrailDetector(trail: trail);
    d.update(north(80));
    d.update(north(5));
    d.update(north(80));
    d.update(north(80));
    expect(d.state, TrailState.onTrail);
  });

  test('histeresis: harus kembali di bawah ambang masuk', () {
    final d = OffTrailDetector(trail: trail);
    for (var i = 0; i < 3; i++) {
      d.update(north(80));
    }
    expect(d.state, TrailState.offTrail);
    d.update(north(40)); // di antara ambang masuk (30) dan keluar (50)
    expect(d.state, TrailState.offTrail);
    d.update(north(10));
    expect(d.state, TrailState.onTrail);
  });

  test('panduan jalur memberi jarak dan bearing ke titik terdekat', () {
    final guidance = guidanceForTrail(trail, north(100));
    expect(guidance, isNotNull);
    expect(guidance!.distanceM, closeTo(100, 1.5));
    expect(guidance.point.lat, closeTo(0, 1e-9));
    expect(guidance.point.lon, closeTo(0.005, 1e-9));
    expect(guidance.bearingDeg, closeTo(180, 1));
    expect(
      guidanceForTrail(const [], north(100)),
      isNull,
    );
  });

  test('format jarak dan bearing panduan', () {
    expect(formatGuidanceDistance(0), '0 m');
    expect(formatGuidanceDistance(999.4), '999 m');
    expect(formatGuidanceDistance(1000), '1,0 km');
    expect(formatGuidanceDistance(1234), '1,2 km');
    expect(formatGuidanceDistance(12345), '12 km');
    expect(formatBearing(42.4), 'bearing 42°');
    expect(formatBearing(359.6), 'bearing 0°');
  });

  test('GeoJSON titik posisi kosong dan berisi', () {
    final empty = jsonDecode(trackPointToGeoJson(null));
    expect(empty['type'], 'FeatureCollection');
    expect(empty['features'], isEmpty);

    final point = TrackPoint(
      lat: -7.5,
      lon: 110.4,
      timestampUtc: DateTime.utc(2026, 10, 25),
      accuracyM: 5,
    );
    final data = jsonDecode(trackPointToGeoJson(point));
    final feature = (data['features'] as List).single as Map<String, dynamic>;
    expect(feature['geometry']['type'], 'Point');
    expect(feature['geometry']['coordinates'], <double>[110.4, -7.5]);
  });
}
