import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:geo_utils/geo_utils.dart';

import '../../trails/data/gpx_loader.dart';
import 'map_package.dart';
import 'mountain_pack.dart';

/// Katalog gunung resmi Hiqeo yang 100% bersumber dari berkas GPX lokal
/// di `assets/gpx`. Path berkas GPX bersifat internal dan tidak pernah
/// ditampilkan di antarmuka pengguna — UI hanya menampilkan Nama Gunung
/// dan Nama Via Jalur.
class MountainPackData {
  const MountainPackData._();

  static final DateTime _catalogDate = DateTime.utc(2026, 10, 1);

  /// Daftar seluruh paket gunung lokal (sinkron dengan titik awal/puncak nyata
  /// dan batas area bounding box gunung agar Mapbox Offline hanya mengunduh
  /// wilayah gunung terkait).
  static List<MountainPack> createDefaultPacks({
    Set<String> downloadedIds = const <String>{},
  }) {
    return <MountainPack>[
      _buildMountain(
        id: 'ciremai',
        name: 'Gunung Ciremai',
        province: 'Jawa Barat',
        elevationM: 3078,
        sizeMb: 42,
        bounds: const GeoBounds(
          south: -6.935,
          west: 108.350,
          north: -6.875,
          east: 108.425,
        ),
        trails: <MapTrail>[
          _trail(
            id: 'ciremai_apuy',
            name: 'Via Apuy',
            gpxAssetPath: 'assets/gpx/CIREMAI VIA APUY.gpx',
            distanceM: 5900,
            elevationGainM: 1580,
            maxElevationM: 3078,
            points: const <LatLng>[
              LatLng(-6.9149, 108.3709),
              LatLng(-6.9060, 108.3880),
              LatLng(-6.8974, 108.4050),
            ],
          ),
        ],
        isDownloaded: downloadedIds.contains('ciremai'),
      ),
      _buildMountain(
        id: 'gede',
        name: 'Gunung Gede',
        province: 'Jawa Barat',
        elevationM: 2958,
        sizeMb: 46,
        bounds: const GeoBounds(
          south: -6.810,
          west: 106.960,
          north: -6.735,
          east: 107.030,
        ),
        trails: <MapTrail>[
          _trail(
            id: 'gede_putri',
            name: 'Via Putri',
            gpxAssetPath: 'assets/gpx/GEDE VIA PUTRI.gpx',
            distanceM: 6400,
            elevationGainM: 1410,
            maxElevationM: 2958,
            points: const <LatLng>[
              LatLng(-6.7556, 107.0100),
              LatLng(-6.7730, 106.9960),
              LatLng(-6.7899, 106.9831),
            ],
          ),
        ],
        isDownloaded: downloadedIds.contains('gede'),
      ),
      _buildMountain(
        id: 'kerinci',
        name: 'Gunung Kerinci',
        province: 'Jambi',
        elevationM: 3805,
        sizeMb: 54,
        bounds: const GeoBounds(
          south: -1.770,
          west: 101.235,
          north: -1.675,
          east: 101.290,
        ),
        trails: <MapTrail>[
          _trail(
            id: 'kerinci_kersik_tuo',
            name: 'Via Kersik Tuo',
            gpxAssetPath: 'assets/gpx/KERINCI VIA KERSIK TUO.gpx',
            distanceM: 8400,
            elevationGainM: 2020,
            maxElevationM: 3805,
            points: const <LatLng>[
              LatLng(-1.7507, 101.2595),
              LatLng(-1.7240, 101.2620),
              LatLng(-1.6973, 101.2647),
            ],
          ),
        ],
        isDownloaded: downloadedIds.contains('kerinci'),
      ),
      _buildMountain(
        id: 'merbabu',
        name: 'Gunung Merbabu',
        province: 'Jawa Tengah',
        elevationM: 3145,
        sizeMb: 52,
        bounds: const GeoBounds(
          south: -7.505,
          west: 110.385,
          north: -7.435,
          east: 110.480,
        ),
        trails: <MapTrail>[
          _trail(
            id: 'merbabu_selo',
            name: 'Via Selo',
            gpxAssetPath: 'assets/gpx/MERBABU VIA SELO.gpx',
            distanceM: 5600,
            elevationGainM: 1290,
            maxElevationM: 3145,
            points: const <LatLng>[
              LatLng(-7.4836, 110.4594),
              LatLng(-7.4680, 110.4500),
              LatLng(-7.4537, 110.4406),
            ],
          ),
          _trail(
            id: 'merbabu_suwanting',
            name: 'Via Suwanting',
            gpxAssetPath: 'assets/gpx/MERBABU VIA SUWANTING.gpx',
            distanceM: 6300,
            elevationGainM: 1640,
            maxElevationM: 3145,
            points: const <LatLng>[
              LatLng(-7.4705, 110.4045),
              LatLng(-7.4620, 110.4220),
              LatLng(-7.4540, 110.4396),
            ],
          ),
        ],
        isDownloaded: downloadedIds.contains('merbabu'),
      ),
      _buildMountain(
        id: 'prau',
        name: 'Gunung Prau',
        province: 'Jawa Tengah',
        elevationM: 2590,
        sizeMb: 28,
        bounds: const GeoBounds(
          south: -7.230,
          west: 109.905,
          north: -7.175,
          east: 109.955,
        ),
        trails: <MapTrail>[
          _trail(
            id: 'prau_patak_banteng',
            name: 'Via Patak Banteng',
            gpxAssetPath: 'assets/gpx/PRAU VIA PATAK BANTENG.gpx',
            distanceM: 2600,
            elevationGainM: 600,
            maxElevationM: 2590,
            points: const <LatLng>[
              LatLng(-7.2093, 109.9259),
              LatLng(-7.2030, 109.9290),
              LatLng(-7.1972, 109.9322),
            ],
          ),
        ],
        isDownloaded: downloadedIds.contains('prau'),
      ),
      _buildMountain(
        id: 'rinjani',
        name: 'Gunung Rinjani',
        province: 'Nusa Tenggara Barat',
        elevationM: 3726,
        sizeMb: 74,
        bounds: const GeoBounds(
          south: -8.435,
          west: 116.430,
          north: -8.325,
          east: 116.520,
        ),
        trails: <MapTrail>[
          _trail(
            id: 'rinjani_sembalun',
            name: 'Via Sembalun',
            gpxAssetPath: 'assets/gpx/RINJANI VIA SEMBALUN.gpx',
            distanceM: 12100,
            elevationGainM: 2640,
            maxElevationM: 3726,
            points: const <LatLng>[
              LatLng(-8.3476, 116.4953),
              LatLng(-8.3800, 116.4760),
              LatLng(-8.4117, 116.4581),
            ],
          ),
        ],
        isDownloaded: downloadedIds.contains('rinjani'),
      ),
      _buildMountain(
        id: 'sindoro',
        name: 'Gunung Sindoro',
        province: 'Jawa Tengah',
        elevationM: 3153,
        sizeMb: 44,
        bounds: const GeoBounds(
          south: -7.360,
          west: 109.975,
          north: -7.280,
          east: 110.055,
        ),
        trails: <MapTrail>[
          _trail(
            id: 'sindoro_kledung',
            name: 'Via Kledung',
            gpxAssetPath: 'assets/gpx/SINDORO VIA KLEDUNG.gpx',
            distanceM: 7300,
            elevationGainM: 1740,
            maxElevationM: 3153,
            points: const <LatLng>[
              LatLng(-7.3400, 110.0322),
              LatLng(-7.3210, 110.0150),
              LatLng(-7.3019, 109.9975),
            ],
          ),
        ],
        isDownloaded: downloadedIds.contains('sindoro'),
      ),
      _buildMountain(
        id: 'slamet',
        name: 'Gunung Slamet',
        province: 'Jawa Tengah',
        elevationM: 3428,
        sizeMb: 48,
        bounds: const GeoBounds(
          south: -7.260,
          west: 109.200,
          north: -7.205,
          east: 109.290,
        ),
        trails: <MapTrail>[
          _trail(
            id: 'slamet_bambangan',
            name: 'Via Bambangan',
            gpxAssetPath: 'assets/gpx/SLAMET VIA BAMBANGAN.gpx',
            distanceM: 7100,
            elevationGainM: 1950,
            maxElevationM: 3428,
            points: const <LatLng>[
              LatLng(-7.2261, 109.2658),
              LatLng(-7.2330, 109.2430),
              LatLng(-7.2393, 109.2204),
            ],
          ),
        ],
        isDownloaded: downloadedIds.contains('slamet'),
      ),
      _buildMountain(
        id: 'sumbing',
        name: 'Gunung Sumbing',
        province: 'Jawa Tengah',
        elevationM: 3371,
        sizeMb: 56,
        bounds: const GeoBounds(
          south: -7.405,
          west: 110.015,
          north: -7.335,
          east: 110.095,
        ),
        trails: <MapTrail>[
          _trail(
            id: 'sumbing_gajah_mungkur',
            name: 'Via Gajah Mungkur',
            gpxAssetPath: 'assets/gpx/SUMBING VIA GAJAH MUNGKUR.gpx',
            distanceM: 5800,
            elevationGainM: 1620,
            maxElevationM: 3371,
            points: const <LatLng>[
              LatLng(-7.3837, 110.0380),
              LatLng(-7.3835, 110.0550),
              LatLng(-7.3834, 110.0713),
            ],
          ),
          _trail(
            id: 'sumbing_garung',
            name: 'Via Garung',
            gpxAssetPath: 'assets/gpx/SUMBING VIA GARUNG.gpx',
            distanceM: 6900,
            elevationGainM: 1870,
            maxElevationM: 3371,
            points: const <LatLng>[
              LatLng(-7.3536, 110.0344),
              LatLng(-7.3680, 110.0520),
              LatLng(-7.3834, 110.0713),
            ],
          ),
        ],
        isDownloaded: downloadedIds.contains('sumbing'),
      ),
    ];
  }

  /// Menghidrasi seluruh jalur dari berkas GPX lokal (`assets/gpx/*.gpx`)
  /// sehingga koordinat, jarak, tanjakan, elevasi maks, dan bounding box
  /// berasal langsung dari berkas GPX sebenarnya.
  static Future<List<MountainPack>> loadHydratedPacks({
    Set<String> downloadedIds = const <String>{},
    AssetBundle? bundle,
  }) async {
    final basePacks = createDefaultPacks(downloadedIds: downloadedIds);
    final hydrated = <MountainPack>[];

    for (final pack in basePacks) {
      final hydratedTrails = <MapTrail>[];
      double? minLat, maxLat, minLon, maxLon;

      for (final trail in pack.package.trails) {
        final assetPath = trail.gpxAssetPath;
        if (assetPath == null || assetPath.isEmpty) {
          hydratedTrails.add(trail);
          continue;
        }
        try {
          final route = await GpxLoader.loadAsset(
            assetPath,
            bundle: bundle,
            id: trail.id,
            defaultName: trail.name,
            simplifyToleranceM: 6.0,
          );
          final pts = route.simplifiedPositions.length >= 2
              ? route.simplifiedPositions
              : route.positions;
          if (pts.length >= 2) {
            for (final p in pts) {
              minLat = minLat == null ? p.lat : math.min(minLat, p.lat);
              maxLat = maxLat == null ? p.lat : math.max(maxLat, p.lat);
              minLon = minLon == null ? p.lon : math.min(minLon, p.lon);
              maxLon = maxLon == null ? p.lon : math.max(maxLon, p.lon);
            }
            hydratedTrails.add(
              trail.copyWith(
                points: pts,
                distanceM: route.totalDistanceM > 0
                    ? route.totalDistanceM
                    : trail.distanceM,
                elevationGainM: route.totalElevationGainM > 0
                    ? route.totalElevationGainM
                    : trail.elevationGainM,
                maxElevationM: route.maxElevationM ?? trail.maxElevationM,
              ),
            );
          } else {
            hydratedTrails.add(trail);
          }
        } catch (_) {
          hydratedTrails.add(trail);
        }
      }

      // Tambahkan margin kecil (~1,8 km) mengelilingi seluruh jalur gunung
      // agar Mapbox Offline hanya mengunduh kotak area sekitar gunung saja.
      const padDeg = 0.018;
      final bounds = (minLat != null &&
              maxLat != null &&
              minLon != null &&
              maxLon != null)
          ? GeoBounds(
              south: minLat - padDeg,
              west: minLon - padDeg,
              north: maxLat + padDeg,
              east: maxLon + padDeg,
            )
          : pack.package.offline.bounds;

      final updatedPkg = MountainMapPackage(
        id: pack.package.id,
        name: pack.package.name,
        version: pack.package.version,
        dataDateUtc: pack.package.dataDateUtc,
        verified: pack.package.verified,
        verifiedAtUtc: pack.package.verifiedAtUtc,
        verifiedBy: pack.package.verifiedBy,
        notes: pack.package.notes,
        province: pack.package.province,
        elevationM: pack.package.elevationM,
        sizeMb: pack.package.sizeMb,
        gpxAssetPath: hydratedTrails.first.gpxAssetPath,
        offline: OfflineConfig(
          bounds: bounds,
          minZoom: pack.package.offline.minZoom,
          maxZoom: pack.package.offline.maxZoom,
          maxAreaKm2: pack.package.offline.maxAreaKm2,
          maxTiles: pack.package.offline.maxTiles,
        ),
        trails: hydratedTrails,
      );

      hydrated.add(
        MountainPack(
          id: pack.id,
          name: pack.name,
          province: pack.province,
          elevationM: pack.elevationM,
          trailCount: hydratedTrails.length,
          sizeMb: pack.sizeMb,
          package: updatedPkg,
          status: pack.status,
          progress: pack.progress,
          version: pack.version,
          gpxAssetPath: hydratedTrails.first.gpxAssetPath,
        ),
      );
    }

    return hydrated;
  }

  static MapTrail _trail({
    required String id,
    required String name,
    required String gpxAssetPath,
    required double distanceM,
    required double elevationGainM,
    required double maxElevationM,
    required List<LatLng> points,
  }) =>
      MapTrail(
        id: id,
        name: name,
        source: 'Jalur Lokal Hiqeo',
        verified: true,
        verifiedAtUtc: _catalogDate,
        verifiedBy: 'Tim Pemetaan Hiqeo',
        distanceM: distanceM,
        elevationGainM: elevationGainM,
        maxElevationM: maxElevationM,
        points: points,
        gpxAssetPath: gpxAssetPath,
      );

  static MountainPack _buildMountain({
    required String id,
    required String name,
    required String province,
    required int elevationM,
    required int sizeMb,
    required GeoBounds bounds,
    required List<MapTrail> trails,
    required bool isDownloaded,
  }) {
    final offline = OfflineConfig(
      bounds: bounds,
      minZoom: 10,
      maxZoom: 15,
      maxAreaKm2: 180,
      maxTiles: 3600,
    );
    final firstGpx = trails.isNotEmpty ? trails.first.gpxAssetPath : null;
    final package = MountainMapPackage(
      id: id,
      name: name,
      version: 1,
      dataDateUtc: _catalogDate,
      verified: true,
      verifiedAtUtc: _catalogDate,
      verifiedBy: 'Tim Pemetaan Hiqeo',
      offline: offline,
      trails: trails,
      province: province,
      elevationM: elevationM,
      sizeMb: sizeMb,
      gpxAssetPath: firstGpx,
    );

    return MountainPack(
      id: id,
      name: name,
      province: province,
      elevationM: elevationM,
      trailCount: trails.length,
      sizeMb: sizeMb,
      package: package,
      status: isDownloaded
          ? MountainDownloadStatus.downloaded
          : MountainDownloadStatus.notDownloaded,
      gpxAssetPath: firstGpx,
    );
  }
}
