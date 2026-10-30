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

  test('closestPointOnPolyline memproyeksikan ke segmen terdekat', () {
    const line = [LatLng(0, 0), LatLng(0, 0.01)];
    final point = closestPointOnPolyline(const LatLng(0.001, 0.004), line);
    expect(point.lat, closeTo(0, 1e-9));
    expect(point.lon, closeTo(0.004, 1e-9));
  });

  test('closestPointOnPolyline memakai ujung terdekat di luar segmen', () {
    const line = [LatLng(0, 0), LatLng(0, 0.01)];
    final point = closestPointOnPolyline(const LatLng(0.002, 0.02), line);
    expect(point.lat, closeTo(0, 1e-9));
    expect(point.lon, closeTo(0.01, 1e-9));
  });

  test('closestPointOnPolyline satu titik mengembalikan titik itu', () {
    const line = [LatLng(-7.5, 110.4)];
    expect(
      closestPointOnPolyline(const LatLng(-7.4, 110.5), line).toString(),
      line.first.toString(),
    );
  });

  test('closestPointOnPolyline menolak jalur kosong', () {
    expect(
      () => closestPointOnPolyline(const LatLng(0, 0), const []),
      throwsArgumentError,
    );
  });

  test('format koordinat', () {
    const p = LatLng(-6.9175, 107.6191);
    expect(formatDecimal(p, digits: 4), '-6.9175, 107.6191');
    expect(formatDms(p), startsWith("6° 55'"));
    expect(formatDms(p), contains('S'));
    expect(formatDms(p), contains('E'));
  });
}
