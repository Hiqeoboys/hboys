import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
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
}
