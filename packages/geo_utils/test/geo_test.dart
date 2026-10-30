import 'package:geo_utils/geo_utils.dart';
import 'package:test/test.dart';

void main() {
  test('jarak Bandung-Jakarta sekitar 116 km', () {
    const bandung = LatLng(-6.9175, 107.6191);
    const jakarta = LatLng(-6.2088, 106.8456);
    expect(distanceMeters(bandung, jakarta), closeTo(116200, 3000));
  });

  test('jarak titik yang sama adalah nol', () {
    const p = LatLng(-7, 107);
    expect(distanceMeters(p, p), 0);
  });

  test('bearing ke utara 0 dan ke timur 90', () {
    expect(bearingDegrees(const LatLng(0, 0), const LatLng(1, 0)), closeTo(0, 0.01));
    expect(bearingDegrees(const LatLng(0, 0), const LatLng(0, 1)), closeTo(90, 0.01));
  });

  test('jarak titik ke segmen', () {
    const a = LatLng(0, 0);
    const b = LatLng(0, 0.01);
    const p = LatLng(0.0009, 0.005); // sekitar 100 m di utara segmen
    expect(distanceToSegmentMeters(p, a, b), closeTo(100, 1.5));
  });

  test('titik di luar ujung segmen dihitung ke ujung terdekat', () {
    const a = LatLng(0, 0);
    const b = LatLng(0, 0.01);
    const p = LatLng(0, 0.011);
    expect(distanceToSegmentMeters(p, a, b), closeTo(111, 2));
  });

  test('polyline kosong menghasilkan infinity', () {
    expect(distanceToPolylineMeters(const LatLng(0, 0), const []), double.infinity);
  });

  test('format koordinat', () {
    const p = LatLng(-6.9175, 107.6191);
    expect(formatDecimal(p, digits: 4), '-6.9175, 107.6191');
    expect(formatDms(p), startsWith("6° 55'"));
    expect(formatDms(p), contains('S'));
    expect(formatDms(p), contains('E'));
  });
}
