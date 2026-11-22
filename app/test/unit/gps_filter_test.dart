import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/tracking/domain/gps_filter.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';

final t0 = DateTime.utc(2027, 6, 1, 8);

TrackPoint fix(double lat, double lon, int seconds, {double acc = 5}) => TrackPoint(
      lat: lat,
      lon: lon,
      timestampUtc: t0.add(Duration(seconds: seconds)),
      accuracyM: acc,
    );

void main() {
  test('menolak akurasi buruk', () {
    final f = GpsFilter();
    expect(f.accept(fix(-6.9, 107.6, 0, acc: 60)), isNull);
    expect(f.accept(fix(-6.9, 107.6, 1, acc: 10)), isNotNull);
  });

  test('menolak lompatan tidak wajar', () {
    final f = GpsFilter()..accept(fix(-6.9, 107.6, 0));
    expect(f.accept(fix(-6.8, 107.7, 5)), isNull); // ~15 km dalam 5 detik
  });

  test('menerima pergerakan wajar', () {
    final f = GpsFilter()..accept(fix(-6.9, 107.6, 0));
    expect(f.accept(fix(-6.89995, 107.6, 5)), isNotNull); // ~5,5 m
  });

  test('titik acuan direset setelah penolakan beruntun', () {
    final f = GpsFilter()..accept(fix(-6.9, 107.6, 0));
    for (var i = 1; i <= 5; i++) {
      expect(f.accept(fix(-6.8, 107.7, i * 5)), isNull);
    }
    expect(f.accept(fix(-6.8, 107.7, 30)), isNotNull);
  });

  test('menolak timestamp mundur atau sama', () {
    final f = GpsFilter()..accept(fix(-6.9, 107.6, 10));
    expect(f.accept(fix(-6.9, 107.6, 10)), isNull);
    expect(f.accept(fix(-6.9, 107.6, 5)), isNull);
  });
}
