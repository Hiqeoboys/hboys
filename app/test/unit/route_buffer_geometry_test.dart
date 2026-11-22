import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:nama_app/features/map/domain/map_package.dart';
import 'package:nama_app/features/map/domain/route_buffer_geometry.dart';

void main() {
  group('RouteBufferGeometry Tests', () {
    test('computeBufferPolygon mengembalikan poligon kosong jika rute kosong', () {
      final result = RouteBufferGeometry.computeBufferPolygon([]);
      expect(result['type'], 'Polygon');
      expect((result['coordinates'] as List).isEmpty, isTrue);
    });

    test('computeBufferPolygon titik tunggal menghasilkan poligon melingkar tertutup', () {
      final point = const LatLng(-6.915, 108.370);
      final result = RouteBufferGeometry.computeBufferPolygon([[point]], bufferMeters: 1500.0);

      expect(result['type'], 'Polygon');
      final coords = (result['coordinates'] as List).first as List;
      expect(coords.length, 13); // 12 sisi + titik penutup
      // Titik awal sama dengan titik akhir (cincin tertutup)
      expect(coords.first, equals(coords.last));
    });

    test('computeBufferPolygon jalur polyline menghasilkan poligon penyangga tertutup', () {
      final route = const [
        LatLng(-6.915, 108.370),
        LatLng(-6.910, 108.380),
        LatLng(-6.905, 108.390),
      ];

      final result = RouteBufferGeometry.computeBufferPolygon([route], bufferMeters: 1500.0);
      expect(result['type'], 'Polygon');
      final rings = result['coordinates'] as List;
      expect(rings.length, 1);

      final ring = rings.first as List;
      // Memiliki offset kiri, offset kanan, dan titik awal yang sama dengan akhir
      expect(ring.length, greaterThan(route.length * 2));
      expect(ring.first, equals(ring.last));
    });

    test('computeBufferPolygon multi-route menghasilkan MultiPolygon', () {
      final route1 = const [
        LatLng(-6.915, 108.370),
        LatLng(-6.910, 108.380),
      ];
      final route2 = const [
        LatLng(-6.890, 108.410),
        LatLng(-6.880, 108.420),
      ];

      final result = RouteBufferGeometry.computeBufferPolygon([route1, route2], bufferMeters: 1500.0);
      expect(result['type'], 'MultiPolygon');
      final multiPolygons = result['coordinates'] as List;
      expect(multiPolygons.length, 2);
    });

    test('computeBufferedBounds memperlebar batas secara simetris dan melingkupi titik asli', () {
      final points = const [
        LatLng(-6.915487, 108.370458),
        LatLng(-6.904885, 108.399639),
      ];

      final buffered = RouteBufferGeometry.computeBufferedBounds(points, bufferMeters: 1500.0);

      // Pastikan batas selatan lebih kecil dari minLat dan utara lebih besar dari maxLat
      expect(buffered.south, lessThan(-6.915487));
      expect(buffered.north, greaterThan(-6.904885));
      expect(buffered.west, lessThan(108.370458));
      expect(buffered.east, greaterThan(108.399639));

      for (final p in points) {
        expect(buffered.contains(p), isTrue);
      }
    });

    test('Estimasi ukuran offline dan guardrail bekerja sesuai batasan', () {
      const config = OfflineConfig(
        bounds: GeoBounds(
          south: -6.93,
          west: 108.37,
          north: -6.87,
          east: 108.43,
        ),
        minZoom: 9,
        maxZoom: 16,
        maxAreaKm2: 120,
        maxTiles: 3500,
      );

      final plan = OfflinePlan.evaluate(config);
      expect(plan.canDownload, isTrue);
      expect(plan.areaKm2, lessThan(120));
      expect(plan.tileEstimate?.total, lessThan(3500));
    });
  });
}
