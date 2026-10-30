import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:nama_app/features/map/domain/map_package.dart';
import 'package:nama_app/features/map/domain/track_geojson.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';

const trailAssetPath = 'assets/map_packs/gunung_uji.trails.geojson';

Map<String, Object?> packJson() => {
      'pack_id': 'gunung_uji',
      'name': 'Gunung Uji',
      'version': 1,
      'data_date': '2026-10-01',
      'verified': false,
      'trails': trailAssetPath,
      'offline': {
        'bounds': {
          'south': -7.55,
          'west': 110.35,
          'north': -7.45,
          'east': 110.45,
        },
        'min_zoom': 10,
        'max_zoom': 14,
        'max_area_km2': 250,
        'max_tiles': 5000,
      },
    };

Map<String, Object?> trailFeature({
  bool verified = false,
  List<List<double>> coordinates = const [
    [110.40, -7.50],
    [110.41, -7.49],
  ],
}) =>
    {
      'type': 'Feature',
      'properties': {
        'id': 'utama',
        'name': 'Jalur Utama',
        'source': 'GPX komunitas uji',
        'verified': verified,
      },
      'geometry': {
        'type': 'LineString',
        'coordinates': coordinates,
      },
    };

String catalogWith(Map<String, Object?> pack) =>
    jsonEncode({
      'packs': [pack],
    });

String trailsWith(List<Map<String, Object?>> features) =>
    jsonEncode({
      'type': 'FeatureCollection',
      'features': features,
    });

Future<MapPackageCatalog> parseCatalog(
  String catalog, {
  String? trails,
  MapGuardrails guardrails = const MapGuardrails(),
}) {
  return MapPackageParser.parseCatalog(
    catalog,
    loadAsset: (path) async {
      if (path != trailAssetPath || trails == null) {
        throw StateError('Aset tidak tersedia: $path');
      }
      return trails;
    },
    guardrails: guardrails,
  );
}

Matcher formatError(String fragment) => throwsA(
      isA<MapPackageFormatException>().having(
        (error) => error.message,
        'message',
        contains(fragment),
      ),
    );

void main() {
  group('GeoBounds', () {
    test('menghitung luas bola untuk kotak kecil', () {
      const bounds = GeoBounds(
        south: 0,
        west: 0,
        north: 0.01,
        east: 0.01,
      );
      expect(bounds.isValid, isTrue);
      expect(bounds.areaKm2, closeTo(1.237, 0.01));
      expect(bounds.center.lat, closeTo(0.005, 1e-9));
      expect(bounds.center.lon, closeTo(0.005, 1e-9));
    });

    test('menolak batas terbalik dan lintas anti-meridian', () {
      expect(
        const GeoBounds(south: 1, west: 0, north: 0, east: 1).isValid,
        isFalse,
      );
      expect(
        const GeoBounds(south: 0, west: 170, north: 1, east: -170).isValid,
        isFalse,
      );
      expect(
        const GeoBounds(south: -90, west: 0, north: 0, east: 1).isValid,
        isFalse,
      );
    });

    test('poligon GeoJSON memakai urutan lon,lat dan tertutup', () {
      const bounds = GeoBounds(south: -7.5, west: 110.4, north: -7.4, east: 110.5);
      final polygon = bounds.toGeoJsonPolygon();
      expect(polygon['type'], 'Polygon');
      final ring = (polygon['coordinates'] as List).single as List;
      expect(ring.first, [110.4, -7.5]);
      expect(ring.last, [110.4, -7.5]);
    });
  });

  group('TileCountEstimator', () {
    test('menghitung tile dunia dan belahan pada zoom 0-1', () {
      const bounds = GeoBounds(south: -10, west: -10, north: 10, east: 10);
      final estimate = TileCountEstimator.forBounds(
        bounds,
        minZoom: 0,
        maxZoom: 1,
      );
      expect(estimate.perZoom, {0: 1, 1: 4});
      expect(estimate.total, 5);
    });

    test('jumlah tile bertambah pada zoom lebih tinggi', () {
      const bounds = GeoBounds(south: -7.55, west: 110.35, north: -7.45, east: 110.45);
      final estimate = TileCountEstimator.forBounds(
        bounds,
        minZoom: 10,
        maxZoom: 14,
      );
      expect(estimate.perZoom.keys, [10, 11, 12, 13, 14]);
      for (var zoom = 11; zoom <= 14; zoom++) {
        expect(
          estimate.perZoom[zoom]!,
          greaterThanOrEqualTo(estimate.perZoom[zoom - 1]!),
        );
      }
    });

    test('menolak rentang zoom terbalik', () {
      const bounds = GeoBounds(south: 0, west: 0, north: 1, east: 1);
      expect(
        () => TileCountEstimator.forBounds(bounds, minZoom: 10, maxZoom: 9),
        throwsArgumentError,
      );
    });
  });

  group('OfflinePlan', () {
    OfflineConfig config({
      GeoBounds bounds = const GeoBounds(
        south: -7.55,
        west: 110.35,
        north: -7.45,
        east: 110.45,
      ),
      int minZoom = 10,
      int maxZoom = 14,
      double maxAreaKm2 = 250,
      int maxTiles = 5000,
    }) =>
        OfflineConfig(
          bounds: bounds,
          minZoom: minZoom,
          maxZoom: maxZoom,
          maxAreaKm2: maxAreaKm2,
          maxTiles: maxTiles,
        );

    test('paket yang wajar dapat diunduh', () {
      final plan = OfflinePlan.evaluate(config());
      expect(plan.canDownload, isTrue, reason: plan.violations.join(' '));
      expect(plan.areaKm2, greaterThan(100));
      expect(plan.tileCount, greaterThan(0));
    });

    test('menolak area di atas batas paket', () {
      final plan = OfflinePlan.evaluate(config(maxAreaKm2: 50));
      expect(plan.canDownload, isFalse);
      expect(
        plan.violations.map((violation) => violation.code),
        contains(OfflineViolationCode.areaAbovePackageLimit),
      );
    });

    test('menolak area di atas batas aplikasi', () {
      final plan = OfflinePlan.evaluate(config(
        bounds: const GeoBounds(south: -1, west: 100, north: 0, east: 101),
      ));
      expect(plan.canDownload, isFalse);
      expect(
        plan.violations.map((violation) => violation.code),
        contains(OfflineViolationCode.areaAboveGuardrail),
      );
    });

    test('menolak zoom di luar batas aplikasi', () {
      final plan = OfflinePlan.evaluate(config(minZoom: 5, maxZoom: 17));
      expect(plan.canDownload, isFalse);
      expect(
        plan.violations.map((violation) => violation.code),
        contains(OfflineViolationCode.zoomOutOfGuardrails),
      );
    });

    test('menolak jumlah tile di atas batas paket', () {
      final plan = OfflinePlan.evaluate(config(maxTiles: 1));
      expect(plan.canDownload, isFalse);
      expect(
        plan.violations.map((violation) => violation.code),
        contains(OfflineViolationCode.tilesAbovePackageLimit),
      );
    });

    test('menolak batas paket yang lebih longgar dari batas aplikasi', () {
      final plan = OfflinePlan.evaluate(config(
        maxAreaKm2: 1000,
        maxTiles: 100000,
      ));
      expect(plan.canDownload, isFalse);
      expect(
        plan.violations
            .where((violation) =>
                violation.code == OfflineViolationCode.packageLimitAboveGuardrail)
            .length,
        2,
      );
    });

    test('menolak batas area tidak valid', () {
      final plan = OfflinePlan.evaluate(config(
        bounds: const GeoBounds(south: 1, west: 110, north: 0, east: 111),
      ));
      expect(plan.canDownload, isFalse);
      expect(plan.tileEstimate, isNull);
      expect(
        plan.violations.map((violation) => violation.code),
        contains(OfflineViolationCode.invalidBounds),
      );
    });
  });

  group('MapPackageParser', () {
    test('memuat katalog dan GeoJSON jalur', () async {
      final catalog = await parseCatalog(
        catalogWith(packJson()),
        trails: trailsWith([trailFeature()]),
      );

      expect(catalog.packages, hasLength(1));
      final package = catalog.packages.single;
      expect(package.id, 'gunung_uji');
      expect(package.name, 'Gunung Uji');
      expect(package.version, 1);
      expect(package.dataDateUtc, DateTime.utc(2026, 10, 1));
      expect(package.verified, isFalse);
      expect(package.offlineRegionId, 'nama_gunung_uji');
      expect(package.trails, hasLength(1));

      final trail = package.trails.single;
      expect(trail.id, 'utama');
      expect(trail.source, 'GPX komunitas uji');
      expect(trail.verified, isFalse);
      expect(trail.isVerified, isFalse);
      expect(trail.points, hasLength(2));
      expect(catalog.byId('gunung_uji'), same(package));
    });

    test('katalog kosong valid', () async {
      final catalog = await parseCatalog('{"packs": []}');
      expect(catalog.isEmpty, isTrue);
    });

    test('menolak pack_id ganda', () async {
      final catalog = jsonEncode({
        'packs': [packJson(), packJson()],
      });
      await expectLater(
        parseCatalog(catalog, trails: trailsWith([trailFeature()])),
        formatError('ganda'),
      );
    });

    test('menolak zoom di luar batas aplikasi', () async {
      final pack = packJson();
      (pack['offline'] as Map<String, Object?>)['min_zoom'] = 5;
      await expectLater(
        parseCatalog(catalogWith(pack), trails: trailsWith([trailFeature()])),
        formatError('zoom harus'),
      );
    });

    test('menolak batas paket yang melebihi batas aplikasi', () async {
      final pack = packJson();
      (pack['offline'] as Map<String, Object?>)['max_area_km2'] = 500;
      await expectLater(
        parseCatalog(catalogWith(pack), trails: trailsWith([trailFeature()])),
        formatError('max_area_km2'),
      );
    });

    test('menolak area paket yang melebihi batasnya sendiri', () async {
      final pack = packJson();
      (pack['offline'] as Map<String, Object?>)['max_area_km2'] = 50;
      await expectLater(
        parseCatalog(catalogWith(pack), trails: trailsWith([trailFeature()])),
        formatError('melebihi batas paket'),
      );
    });

    test('menolak jalur di luar batas area offline', () async {
      await expectLater(
        parseCatalog(
          catalogWith(packJson()),
          trails: trailsWith([
            trailFeature(coordinates: const [
              [111.0, -7.5],
              [111.1, -7.49],
            ]),
          ]),
        ),
        formatError('keluar dari batas area offline'),
      );
    });

    test('menolak geometri bukan LineString', () async {
      final feature = trailFeature();
      (feature['geometry'] as Map<String, Object?>)['type'] = 'Point';
      await expectLater(
        parseCatalog(
          catalogWith(packJson()),
          trails: trailsWith([feature]),
        ),
        formatError('LineString'),
      );
    });

    test('menolak jalur tanpa bukti verifikasi', () async {
      final feature = trailFeature(verified: true);
      await expectLater(
        parseCatalog(
          catalogWith(packJson()),
          trails: trailsWith([feature]),
        ),
        formatError('verified_at'),
      );
    });

    test('menerima jalur terverifikasi yang punya bukti', () async {
      final feature = trailFeature(verified: true);
      (feature['properties'] as Map<String, Object?>)
        ..['verified_at'] = '2026-10-02T08:00:00Z'
        ..['verified_by'] = 'Tim Uji';
      final catalog = await parseCatalog(
        catalogWith(packJson()),
        trails: trailsWith([feature]),
      );
      final trail = catalog.packages.single.trails.single;
      expect(trail.isVerified, isTrue);
      expect(trail.verifiedAtUtc, DateTime.utc(2026, 10, 2, 8));
      expect(trail.verifiedBy, 'Tim Uji');
    });

    test('menolak id jalur ganda', () async {
      await expectLater(
        parseCatalog(
          catalogWith(packJson()),
          trails: trailsWith([trailFeature(), trailFeature()]),
        ),
        formatError('ganda'),
      );
    });

    test('menolak koleksi jalur kosong', () async {
      await expectLater(
        parseCatalog(
          catalogWith(packJson()),
          trails: trailsWith(const []),
        ),
        formatError('minimal satu jalur'),
      );
    });

    test('menolak aset jalur yang tidak ada', () async {
      await expectLater(
        parseCatalog(catalogWith(packJson())),
        formatError('gagal memuat'),
      );
    });

    test('menolak JSON rusak', () async {
      await expectLater(
        parseCatalog('{"packs": ['),
        formatError('JSON tidak valid'),
      );
    });
  });

  group('GeoJSON peta', () {
    test('jalur mempertahankan status verifikasi apa adanya', () {
      final trail = MapTrail(
        id: 'utama',
        name: 'Jalur Utama',
        source: 'uji',
        verified: false,
        points: const [LatLng(-7.5, 110.4), LatLng(-7.49, 110.41)],
      );
      final decoded = jsonDecode(trailsToGeoJson([trail])) as Map<String, Object?>;
      final features = decoded['features'] as List;
      final feature = features.single as Map<String, Object?>;
      final properties = feature['properties'] as Map<String, Object?>;
      expect(properties['verified'], isFalse);
      final geometry = feature['geometry'] as Map<String, Object?>;
      expect(geometry['type'], 'LineString');
      expect((geometry['coordinates'] as List).first, [110.4, -7.5]);
    });

    test('jejak kurang dari dua titik menjadi koleksi kosong', () {
      final point = TrackPoint(
        lat: -7.5,
        lon: 110.4,
        timestampUtc: DateTime.utc(2026, 10, 25),
        accuracyM: 5,
      );
      final empty = jsonDecode(trackPointsToGeoJson([point]));
      expect((empty as Map<String, Object?>)['features'], isEmpty);
    });

    test('jejak dua titik menjadi LineString', () {
      final points = [
        TrackPoint(
          lat: -7.5,
          lon: 110.4,
          timestampUtc: DateTime.utc(2026, 10, 25, 1),
          accuracyM: 5,
        ),
        TrackPoint(
          lat: -7.49,
          lon: 110.41,
          timestampUtc: DateTime.utc(2026, 10, 25, 1, 1),
          accuracyM: 5,
        ),
      ];
      final decoded =
          jsonDecode(trackPointsToGeoJson(points)) as Map<String, Object?>;
      final feature = (decoded['features'] as List).single as Map<String, Object?>;
      expect((feature['properties'] as Map)['point_count'], 2);
      final geometry = feature['geometry'] as Map<String, Object?>;
      expect(
        geometry['coordinates'],
        [
          [110.4, -7.5],
          [110.41, -7.49],
        ],
      );
    });
  });
}
