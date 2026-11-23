import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geo_utils/geo_utils.dart';

import '../../trails/data/gpx_loader.dart';
import 'indonesia_region_resolver.dart';
import 'map_package.dart';
import 'mountain_pack.dart';

/// Hasil parsing nama berkas GPX berformat `"NAMA GUNUNG VIA RUTE.gpx"`.
@immutable
class ParsedGpxFileName {
  const ParsedGpxFileName({
    required this.mountainId,
    required this.mountainName,
    required this.trailId,
    required this.trailName,
  });

  final String mountainId;
  final String mountainName;
  final String trailId;
  final String trailName;
}

class _DiscoveredTrail {
  const _DiscoveredTrail({
    required this.trail,
    required this.startLat,
    required this.startLon,
    required this.region,
  });

  final MapTrail trail;
  final double? startLat;
  final double? startLon;
  final String? region;
}

class _MutableMountainGroup {
  _MutableMountainGroup({
    required this.id,
    required this.name,
    required this.province,
    required this.elevationM,
    required this.sizeMb,
    required this.isDownloaded,
    this.fallbackBounds,
  });

  final String id;
  final String name;
  String province;
  int elevationM;
  int sizeMb;
  final bool isDownloaded;
  final GeoBounds? fallbackBounds;
  final Map<String, MapTrail> trailsById = <String, MapTrail>{};
}

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

  /// Mem-parsing nama berkas GPX berformat `"NAMA GUNUNG VIA RUTE.gpx"`.
  /// Pemisahan kata `VIA` bersifat case-insensitive.
  static ParsedGpxFileName parseGpxFilename(String assetPath) {
    final decoded = Uri.decodeFull(assetPath);
    final slash = math.max(decoded.lastIndexOf('/'), decoded.lastIndexOf('\\'));
    final fileName = slash >= 0 ? decoded.substring(slash + 1) : decoded;
    final stem = fileName
        .replaceFirst(RegExp(r'\.gpx$', caseSensitive: false), '')
        .trim();

    final viaMatch =
        RegExp(r'\s+via\s+', caseSensitive: false).firstMatch(stem);
    final String rawMountain;
    final String? rawTrail;
    if (viaMatch != null) {
      rawMountain = stem.substring(0, viaMatch.start).trim();
      rawTrail = stem.substring(viaMatch.end).trim();
    } else {
      rawMountain = stem;
      rawTrail = null;
    }

    final bareMountain = rawMountain
        .replaceFirst(
          RegExp(r'^(?:gunung|gn\.?|mt\.?)\s+', caseSensitive: false),
          '',
        )
        .trim();
    final safeMountain = bareMountain.isEmpty ? stem : bareMountain;
    final mountainId = _slugify(safeMountain);
    final mountainName = 'Gunung ${_toTitleCase(safeMountain)}';

    final String trailName;
    final String trailSlugPart;
    if (rawTrail == null || rawTrail.isEmpty) {
      trailName = 'Jalur Utama';
      trailSlugPart = 'utama';
    } else {
      final bareTrail = rawTrail
          .replaceFirst(RegExp(r'^via\s+', caseSensitive: false), '')
          .trim();
      final safeTrail = bareTrail.isEmpty ? rawTrail : bareTrail;
      trailName = 'Via ${_toTitleCase(safeTrail)}';
      trailSlugPart = _slugify(safeTrail);
    }

    return ParsedGpxFileName(
      mountainId: mountainId,
      mountainName: mountainName,
      trailId: '${mountainId}_$trailSlugPart',
      trailName: trailName,
    );
  }

  /// Memindai seluruh aset `.gpx` pada `assets/gpx/` dan `assets/routes/`
  /// dari `AssetManifest` Flutter secara otomatis.
  static Future<List<String>> discoverGpxAssetPaths({
    AssetBundle? bundle,
  }) async {
    final effectiveBundle = bundle ?? rootBundle;
    var candidates = <String>[];

    try {
      final manifest = await AssetManifest.loadFromAssetBundle(effectiveBundle);
      candidates = manifest.listAssets();
    } catch (_) {
      try {
        final raw = await effectiveBundle.loadString('AssetManifest.json');
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          candidates = decoded.keys.map((k) => k.toString()).toList();
        }
      } catch (_) {
        return const <String>[];
      }
    }

    final gpxPaths = <String>[];
    for (final rawPath in candidates) {
      final decoded = Uri.decodeFull(rawPath).replaceAll('\\', '/');
      final lower = decoded.toLowerCase();
      final inRoutesFolder =
          lower.startsWith('assets/gpx/') || lower.startsWith('assets/routes/');
      if (inRoutesFolder && lower.endsWith('.gpx')) {
        gpxPaths.add(decoded);
      }
    }

    // Prioritaskan `assets/routes/` jika ada nama berkas jalur identik di kedua folder.
    gpxPaths.sort((a, b) {
      final aRoutes = a.toLowerCase().startsWith('assets/routes/') ? 0 : 1;
      final bRoutes = b.toLowerCase().startsWith('assets/routes/') ? 0 : 1;
      if (aRoutes != bRoutes) return aRoutes.compareTo(bRoutes);
      return a.compareTo(b);
    });
    return List<String>.unmodifiable(gpxPaths);
  }

  /// Memindai dan menghidrasi seluruh jalur dari berkas GPX lokal
  /// (`assets/gpx/` dan `assets/routes/`) agar setiap file GPX baru langsung
  /// muncul otomatis di Peta dan Siapkan Pendakian.
  static Future<List<MountainPack>> loadHydratedPacks({
    Set<String> downloadedIds = const <String>{},
    AssetBundle? bundle,
  }) async {
    final discoveredPaths = await discoverGpxAssetPaths(bundle: bundle);
    final useOnlyDiscovered = bundle != null && discoveredPaths.isNotEmpty;
    final groups = <String, _MutableMountainGroup>{};

    if (!useOnlyDiscovered) {
      for (final pack in createDefaultPacks(downloadedIds: downloadedIds)) {
        final group = _MutableMountainGroup(
          id: pack.id,
          name: pack.name,
          province: pack.province,
          elevationM: pack.elevationM,
          sizeMb: pack.sizeMb,
          isDownloaded: downloadedIds.contains(pack.id),
          fallbackBounds: pack.package.offline.bounds,
        );
        for (final trail in pack.package.trails) {
          group.trailsById[trail.id] = trail;
        }
        groups[pack.id] = group;
      }
    }

    final existingAssetPaths = <String, _DiscoveredTrail>{};
    for (final assetPath in discoveredPaths) {
      final parsed = parseGpxFilename(assetPath);
      if (existingAssetPaths.containsKey(parsed.trailId)) continue;

      final discovered = await _loadTrailFromGpxAsset(
        assetPath: assetPath,
        parsed: parsed,
        bundle: bundle,
      );
      if (discovered == null) continue;
      existingAssetPaths[parsed.trailId] = discovered;

      final group = groups[parsed.mountainId];
      if (group == null) {
        final region = discovered.region ?? 'Indonesia';
        final elev = (discovered.trail.maxElevationM ?? 0).round();
        groups[parsed.mountainId] = _MutableMountainGroup(
          id: parsed.mountainId,
          name: parsed.mountainName,
          province: region,
          elevationM: elev,
          sizeMb: 36,
          isDownloaded: downloadedIds.contains(parsed.mountainId),
        )..trailsById[discovered.trail.id] = discovered.trail;
      } else {
        group.trailsById[discovered.trail.id] = discovered.trail;
        final elev = (discovered.trail.maxElevationM ?? 0).round();
        if (elev > group.elevationM) {
          group.elevationM = elev;
        }
        if ((group.province == 'Indonesia' || group.province.isEmpty) &&
            discovered.region != null) {
          group.province = discovered.region!;
        }
      }
    }

    // Jika mode standar tanpa bundle test, pastikan jalur bawaan tanpa entry
    // discoveredPaths yang berhasil juga tetap terhidrasi bila tersedia.
    if (!useOnlyDiscovered) {
      for (final group in groups.values) {
        for (final entry in group.trailsById.entries.toList()) {
          final trail = entry.value;
          final path = trail.gpxAssetPath;
          if (path == null || path.isEmpty) continue;
          if (existingAssetPaths.containsKey(trail.id)) continue;
          final reloaded = await _loadTrailFromGpxAsset(
            assetPath: path,
            parsed: ParsedGpxFileName(
              mountainId: group.id,
              mountainName: group.name,
              trailId: trail.id,
              trailName: trail.name,
            ),
            bundle: bundle,
          );
          if (reloaded != null) {
            group.trailsById[trail.id] = trail.copyWith(
              points: reloaded.trail.points,
              distanceM: (reloaded.trail.distanceM ?? 0) > 0
                  ? reloaded.trail.distanceM
                  : trail.distanceM,
              elevationGainM: (reloaded.trail.elevationGainM ?? 0) > 0
                  ? reloaded.trail.elevationGainM
                  : trail.elevationGainM,
              maxElevationM:
                  reloaded.trail.maxElevationM ?? trail.maxElevationM,
            );
          }
        }
      }
    }

    final hydrated = <MountainPack>[];
    for (final group in groups.values) {
      final hydratedTrails = group.trailsById.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (hydratedTrails.isEmpty) continue;

      double? minLat, maxLat, minLon, maxLon;
      var computedMaxElevation = group.elevationM;
      for (final trail in hydratedTrails) {
        final trailMaxEle = (trail.maxElevationM ?? 0).round();
        if (trailMaxEle > computedMaxElevation) {
          computedMaxElevation = trailMaxEle;
        }
        for (final p in trail.points) {
          minLat = minLat == null ? p.lat : math.min(minLat, p.lat);
          maxLat = maxLat == null ? p.lat : math.max(maxLat, p.lat);
          minLon = minLon == null ? p.lon : math.min(minLon, p.lon);
          maxLon = maxLon == null ? p.lon : math.max(maxLon, p.lon);
        }
      }

      // Margin kecil (~1,8 km) mengelilingi seluruh jalur gunung untuk offline tiles.
      const padDeg = 0.018;
      final bounds =
          (minLat != null && maxLat != null && minLon != null && maxLon != null)
              ? GeoBounds(
                  south: minLat - padDeg,
                  west: minLon - padDeg,
                  north: maxLat + padDeg,
                  east: maxLon + padDeg,
                )
              : (group.fallbackBounds ??
                  const GeoBounds(
                    south: -7.5,
                    west: 110.0,
                    north: -7.4,
                    east: 110.1,
                  ));

      final estimatedMb = group.sizeMb > 0 && group.fallbackBounds != null
          ? group.sizeMb
          : (((bounds.north - bounds.south) * (bounds.east - bounds.west)) *
                  18000)
              .round()
              .clamp(24, 90);

      hydrated.add(
        _buildMountain(
          id: group.id,
          name: group.name,
          province: group.province,
          elevationM: computedMaxElevation,
          sizeMb: estimatedMb,
          bounds: bounds,
          trails: hydratedTrails,
          isDownloaded: group.isDownloaded,
        ),
      );
    }

    hydrated.sort((a, b) => a.name.compareTo(b.name));
    return hydrated;
  }

  static Future<_DiscoveredTrail?> _loadTrailFromGpxAsset({
    required String assetPath,
    required ParsedGpxFileName parsed,
    AssetBundle? bundle,
  }) async {
    try {
      final route = await GpxLoader.loadAsset(
        assetPath,
        bundle: bundle,
        id: parsed.trailId,
        defaultName: parsed.trailName,
        simplifyToleranceM: 6.0,
      );
      final pts = route.simplifiedPositions.length >= 2
          ? route.simplifiedPositions
          : route.positions;
      if (pts.length < 2) return null;

      final start = pts.first;
      final region = IndonesiaRegionResolver.resolve(
        lat: start.lat,
        lon: start.lon,
        regionHint: route.regionHint,
        description: route.description,
      );
      final trail = _trail(
        id: parsed.trailId,
        name: parsed.trailName,
        gpxAssetPath: assetPath,
        distanceM: route.totalDistanceM,
        elevationGainM: route.totalElevationGainM,
        maxElevationM: route.maxElevationM ?? 0,
        points: pts,
      );
      return _DiscoveredTrail(
        trail: trail,
        startLat: start.lat,
        startLon: start.lon,
        region: region,
      );
    } catch (_) {
      return null;
    }
  }

  static String _slugify(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return normalized.isEmpty ? 'jalur' : normalized;
  }

  static String _toTitleCase(String value) {
    final words = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) return '';
    return words
        .map(
          (w) => w.length == 1
              ? w.toUpperCase()
              : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
        )
        .join(' ');
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
