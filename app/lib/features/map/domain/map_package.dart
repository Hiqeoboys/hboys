import 'dart:convert';
import 'dart:math' as math;

import 'package:geo_utils/geo_utils.dart';

/// Batas persegi dalam derajat. Lintas anti-meridian tidak didukung agar
/// perhitungan luas dan jumlah tile tetap deterministik.
class GeoBounds {
  const GeoBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  /// Batas lintang Web Mercator yang dipakai Mapbox.
  static const double maxMercatorLatitude = 85.05112878;

  bool get isValid =>
      south.isFinite &&
      west.isFinite &&
      north.isFinite &&
      east.isFinite &&
      south >= -maxMercatorLatitude &&
      north <= maxMercatorLatitude &&
      south < north &&
      west >= -180 &&
      west < east &&
      east <= 180;

  /// Luas bola bumi di dalam batas, kilometer persegi.
  double get areaKm2 {
    if (!isValid) return 0;
    final dLon = (east - west) * math.pi / 180;
    final sinNorth = math.sin(north * math.pi / 180);
    final sinSouth = math.sin(south * math.pi / 180);
    return earthRadiusM * earthRadiusM * dLon * (sinNorth - sinSouth) / 1e6;
  }

  LatLng get center => LatLng((south + north) / 2, (west + east) / 2);

  bool contains(LatLng point) =>
      point.lat >= south &&
      point.lat <= north &&
      point.lon >= west &&
      point.lon <= east;

  /// Poligon GeoJSON untuk opsi unduhan Mapbox (urutan lon, lat).
  Map<String, Object?> toGeoJsonPolygon() => {
        'type': 'Polygon',
        'coordinates': [
          [
            [west, south],
            [east, south],
            [east, north],
            [west, north],
            [west, south],
          ],
        ],
      };
}

/// Batas keras aplikasi. Batas per paket boleh lebih ketat, tidak boleh longgar.
class MapGuardrails {
  const MapGuardrails({
    this.minZoom = 8,
    this.maxZoom = 16,
    this.maxAreaKm2 = 250,
    this.maxTileCount = 5000,
  });

  final int minZoom;
  final int maxZoom;
  final double maxAreaKm2;
  final int maxTileCount;

  /// Batas kumulatif tile pack Mapbox, bukan jumlah tile. SDK menolak unduhan
  /// yang melewatinya; batas ini hanya ditampilkan, tidak bisa dihitung lokal.
  static const int mapboxTilePackLimit = 750;
}

class OfflineConfig {
  const OfflineConfig({
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
    required this.maxAreaKm2,
    required this.maxTiles,
  });

  final GeoBounds bounds;
  final int minZoom;
  final int maxZoom;
  final double maxAreaKm2;
  final int maxTiles;
}

class MapTrail {
  MapTrail({
    required this.id,
    required this.name,
    required this.source,
    required this.verified,
    required List<LatLng> points,
    this.verifiedAtUtc,
    this.verifiedBy,
    this.distanceM,
    this.elevationGainM,
    this.maxElevationM,
    this.gpxAssetPath,
  }) : points = List<LatLng>.unmodifiable(points);

  final String id;
  final String name;
  final String source;
  final bool verified;
  final DateTime? verifiedAtUtc;
  final String? verifiedBy;
  final List<LatLng> points;
  final double? distanceM;
  final double? elevationGainM;
  final double? maxElevationM;

  /// Path aset GPX internal (hanya untuk pemuatan rute lokal, JANGAN pernah
  /// ditampilkan di UI).
  final String? gpxAssetPath;

  MapTrail copyWith({
    List<LatLng>? points,
    double? distanceM,
    double? elevationGainM,
    double? maxElevationM,
    String? gpxAssetPath,
  }) =>
      MapTrail(
        id: id,
        name: name,
        source: source,
        verified: verified,
        verifiedAtUtc: verifiedAtUtc,
        verifiedBy: verifiedBy,
        points: points ?? this.points,
        distanceM: distanceM ?? this.distanceM,
        elevationGainM: elevationGainM ?? this.elevationGainM,
        maxElevationM: maxElevationM ?? this.maxElevationM,
        gpxAssetPath: gpxAssetPath ?? this.gpxAssetPath,
      );

  /// Hanya true bila data punya bukti verifikasi lapangan. Jangan pernah
  /// menampilkan label terverifikasi berdasarkan asumsi.
  bool get isVerified => verified;

  double get effectiveDistanceM {
    if (distanceM != null) return distanceM!;
    if (points.length < 2) return 0;
    var total = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      total += distanceMeters(points[i], points[i + 1]);
    }
    return total;
  }

  Map<String, Object?> toGeoJsonFeature() => {
        'type': 'Feature',
        'properties': {
          'id': id,
          'name': name,
          'source': source,
          'verified': verified,
        },
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            for (final point in points) [point.lon, point.lat],
          ],
        },
      };
}

class MountainMapPackage {
  MountainMapPackage({
    required this.id,
    required this.name,
    required this.version,
    required this.dataDateUtc,
    required this.verified,
    required this.offline,
    required List<MapTrail> trails,
    this.verifiedAtUtc,
    this.verifiedBy,
    this.notes,
    this.province,
    this.elevationM,
    this.sizeMb,
    this.gpxAssetPath,
  }) : trails = List<MapTrail>.unmodifiable(trails);

  final String id;
  final String name;
  final int version;
  final DateTime dataDateUtc;
  final bool verified;
  final DateTime? verifiedAtUtc;
  final String? verifiedBy;
  final OfflineConfig offline;
  final List<MapTrail> trails;
  final String? notes;
  final String? province;
  final int? elevationM;
  final int? sizeMb;
  final String? gpxAssetPath;

  String get offlineRegionId => 'nama_$id';

  MapTrail? trailById(String id) {
    for (final trail in trails) {
      if (trail.id == id) return trail;
    }
    return null;
  }
}

class MapPackageCatalog {
  MapPackageCatalog(List<MountainMapPackage> packages)
      : packages = List<MountainMapPackage>.unmodifiable(packages);

  final List<MountainMapPackage> packages;

  bool get isEmpty => packages.isEmpty;
  bool get isNotEmpty => packages.isNotEmpty;

  MountainMapPackage? byId(String id) {
    for (final package in packages) {
      if (package.id == id) return package;
    }
    return null;
  }
}

class TileCountEstimate {
  TileCountEstimate(Map<int, int> perZoom)
      : perZoom = Map<int, int>.unmodifiable(perZoom);

  final Map<int, int> perZoom;

  int get total => perZoom.values.fold(0, (sum, count) => sum + count);
}

/// Estimasi deterministik jumlah alamat tile Web Mercator yang menutupi area.
/// Ini bukan jumlah aset unduhan: Mapbox mengelompokkan tile menjadi tile pack
/// dengan rentang zoom, dan ukuran byte hanya bisa diperkirakan SDK.
class TileCountEstimator {
  const TileCountEstimator._();

  static TileCountEstimate forBounds(
    GeoBounds bounds, {
    required int minZoom,
    required int maxZoom,
  }) {
    if (!bounds.isValid) {
      throw ArgumentError.value(bounds, 'bounds', 'Batas area tidak valid');
    }
    if (minZoom < 0 || maxZoom < minZoom || maxZoom > 22) {
      throw ArgumentError('Rentang zoom tidak valid: $minZoom..$maxZoom');
    }
    final counts = <int, int>{};
    for (var zoom = minZoom; zoom <= maxZoom; zoom++) {
      final tilesPerAxis = 1 << zoom;
      final xMin = _tileX(bounds.west, tilesPerAxis);
      final xMax = _tileX(bounds.east, tilesPerAxis);
      final yMin = _tileY(bounds.north, tilesPerAxis);
      final yMax = _tileY(bounds.south, tilesPerAxis);
      counts[zoom] = (xMax - xMin + 1) * (yMax - yMin + 1);
    }
    return TileCountEstimate(counts);
  }

  static int _tileX(double longitude, int tilesPerAxis) {
    final raw = ((longitude + 180) / 360 * tilesPerAxis).floor();
    if (raw < 0) return 0;
    if (raw >= tilesPerAxis) return tilesPerAxis - 1;
    return raw;
  }

  static int _tileY(double latitude, int tilesPerAxis) {
    final clamped = latitude.clamp(
      -GeoBounds.maxMercatorLatitude,
      GeoBounds.maxMercatorLatitude,
    );
    final radians = clamped * math.pi / 180;
    final mercator = math.log(math.tan(radians) + 1 / math.cos(radians));
    final raw = ((1 - mercator / math.pi) / 2 * tilesPerAxis).floor();
    if (raw < 0) return 0;
    if (raw >= tilesPerAxis) return tilesPerAxis - 1;
    return raw;
  }
}

enum OfflineViolationCode {
  invalidBounds,
  invalidZoomRange,
  zoomOutOfGuardrails,
  areaAbovePackageLimit,
  areaAboveGuardrail,
  tilesAbovePackageLimit,
  tilesAboveGuardrail,
  packageLimitAboveGuardrail,
}

class OfflineViolation {
  const OfflineViolation(this.code, this.message);

  final OfflineViolationCode code;
  final String message;

  @override
  String toString() => message;
}

class OfflinePlan {
  OfflinePlan._({
    required this.config,
    required this.areaKm2,
    required this.tileEstimate,
    required this.violations,
  });

  final OfflineConfig config;
  final double areaKm2;
  final TileCountEstimate? tileEstimate;
  final List<OfflineViolation> violations;

  bool get canDownload => violations.isEmpty;
  int get tileCount => tileEstimate?.total ?? 0;

  factory OfflinePlan.evaluate(
    OfflineConfig config, {
    MapGuardrails guardrails = const MapGuardrails(),
  }) {
    final violations = <OfflineViolation>[];
    final bounds = config.bounds;
    final areaKm2 = bounds.isValid ? bounds.areaKm2 : 0.0;

    if (!bounds.isValid) {
      violations.add(const OfflineViolation(
        OfflineViolationCode.invalidBounds,
        'Batas area paket tidak valid.',
      ));
    }
    if (config.minZoom > config.maxZoom) {
      violations.add(const OfflineViolation(
        OfflineViolationCode.invalidZoomRange,
        'Zoom minimum paket lebih besar dari zoom maksimum.',
      ));
    }
    if (config.minZoom < guardrails.minZoom ||
        config.maxZoom > guardrails.maxZoom) {
      violations.add(OfflineViolation(
        OfflineViolationCode.zoomOutOfGuardrails,
        'Zoom ${config.minZoom}-${config.maxZoom} di luar batas aplikasi '
        '${guardrails.minZoom}-${guardrails.maxZoom}.',
      ));
    }
    if (config.maxAreaKm2 > guardrails.maxAreaKm2) {
      violations.add(OfflineViolation(
        OfflineViolationCode.packageLimitAboveGuardrail,
        'Batas area paket ${config.maxAreaKm2.toStringAsFixed(1)} km² '
        'melebihi batas aplikasi ${guardrails.maxAreaKm2.toStringAsFixed(1)} km².',
      ));
    }
    if (config.maxTiles > guardrails.maxTileCount) {
      violations.add(OfflineViolation(
        OfflineViolationCode.packageLimitAboveGuardrail,
        'Batas tile paket ${config.maxTiles} melebihi batas aplikasi '
        '${guardrails.maxTileCount}.',
      ));
    }

    TileCountEstimate? tileEstimate;
    if (bounds.isValid) {
      tileEstimate = TileCountEstimator.forBounds(
        bounds,
        minZoom: config.minZoom,
        maxZoom: config.maxZoom,
      );
      if (areaKm2 > config.maxAreaKm2) {
        violations.add(OfflineViolation(
          OfflineViolationCode.areaAbovePackageLimit,
          'Area ${areaKm2.toStringAsFixed(1)} km² melebihi batas paket '
          '${config.maxAreaKm2.toStringAsFixed(1)} km².',
        ));
      }
      if (areaKm2 > guardrails.maxAreaKm2) {
        violations.add(OfflineViolation(
          OfflineViolationCode.areaAboveGuardrail,
          'Area ${areaKm2.toStringAsFixed(1)} km² melebihi batas aplikasi '
          '${guardrails.maxAreaKm2.toStringAsFixed(1)} km².',
        ));
      }
      final tiles = tileEstimate.total;
      if (tiles > config.maxTiles) {
        violations.add(OfflineViolation(
          OfflineViolationCode.tilesAbovePackageLimit,
          'Perkiraan $tiles tile melebihi batas paket ${config.maxTiles}.',
        ));
      }
      if (tiles > guardrails.maxTileCount) {
        violations.add(OfflineViolation(
          OfflineViolationCode.tilesAboveGuardrail,
          'Perkiraan $tiles tile melebihi batas aplikasi '
          '${guardrails.maxTileCount}.',
        ));
      }
    }

    return OfflinePlan._(
      config: config,
      areaKm2: areaKm2,
      tileEstimate: tileEstimate,
      violations: List<OfflineViolation>.unmodifiable(violations),
    );
  }
}

class MapPackageFormatException implements Exception {
  MapPackageFormatException(this.message);

  final String message;

  @override
  String toString() => 'Paket peta tidak valid: $message';
}

class MapPackageParser {
  const MapPackageParser._();

  static final RegExp _packIdPattern = RegExp(r'^[a-z0-9][a-z0-9_]{0,63}$');
  static final RegExp _trailIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$');

  static Future<MapPackageCatalog> parseCatalog(
    String catalogJson, {
    required Future<String> Function(String assetPath) loadAsset,
    MapGuardrails guardrails = const MapGuardrails(),
  }) async {
    final root = _expectObject(_decode(catalogJson, 'catalog.json'), 'catalog');
    final rawPacks = _expectList(root['packs'], 'packs');
    final packages = <MountainMapPackage>[];
    final seenPackIds = <String>{};

    for (var i = 0; i < rawPacks.length; i++) {
      final path = 'packs[$i]';
      final entry = _parseEntry(_expectObject(rawPacks[i], path), path, guardrails);
      if (!seenPackIds.add(entry.id)) {
        throw MapPackageFormatException('$path: pack_id "${entry.id}" ganda.');
      }

      String trailsJson;
      try {
        trailsJson = await loadAsset(entry.trailsAsset);
      } catch (error) {
        throw MapPackageFormatException(
          '$path: gagal memuat "${entry.trailsAsset}": $error',
        );
      }
      final trails = _parseTrails(trailsJson, entry.trailsAsset);
      for (final trail in trails) {
        for (final point in trail.points) {
          if (!entry.offline.bounds.contains(point)) {
            throw MapPackageFormatException(
              '$path: jalur "${trail.id}" keluar dari batas area offline.',
            );
          }
        }
      }

      final package = MountainMapPackage(
        id: entry.id,
        name: entry.name,
        version: entry.version,
        dataDateUtc: entry.dataDateUtc,
        verified: entry.verified,
        verifiedAtUtc: entry.verifiedAtUtc,
        verifiedBy: entry.verifiedBy,
        notes: entry.notes,
        offline: entry.offline,
        trails: trails,
      );
      final plan = OfflinePlan.evaluate(package.offline, guardrails: guardrails);
      if (!plan.canDownload) {
        throw MapPackageFormatException(
          '$path: ${plan.violations.map((violation) => violation.message).join(' ')}',
        );
      }
      packages.add(package);
    }

    return MapPackageCatalog(packages);
  }

  static _PackEntry _parseEntry(
    Map<String, Object?> json,
    String path,
    MapGuardrails guardrails,
  ) {
    final id = _expectString(json['pack_id'], '$path.pack_id');
    if (!_packIdPattern.hasMatch(id)) {
      throw MapPackageFormatException(
        '$path.pack_id: hanya huruf kecil, angka, dan garis bawah (maks. 64).',
      );
    }
    final name = _expectString(json['name'], '$path.name');
    final version = _expectInt(json['version'], '$path.version');
    if (version <= 0) {
      throw MapPackageFormatException('$path.version: harus lebih dari 0.');
    }
    final dataDateUtc = _expectUtcTimestamp(json['data_date'], '$path.data_date');
    final verified = _expectBool(json['verified'], '$path.verified');
    final verifiedAt = json['verified_at'];
    final verifiedBy = json['verified_by'];
    DateTime? verifiedAtUtc;
    String? verifiedByName;
    if (verified) {
      verifiedAtUtc =
          _expectUtcTimestamp(verifiedAt, '$path.verified_at');
      verifiedByName = _expectString(verifiedBy, '$path.verified_by');
    } else if (verifiedAt != null || verifiedBy != null) {
      throw MapPackageFormatException(
        '$path: verified=false tidak boleh punya verified_at/verified_by.',
      );
    }

    final trailsAsset = _expectString(json['trails'], '$path.trails');
    final offline = _parseOffline(json['offline'], '$path.offline', guardrails);
    final notes = json['notes'] == null
        ? null
        : _expectString(json['notes'], '$path.notes');

    return _PackEntry(
      id: id,
      name: name,
      version: version,
      dataDateUtc: dataDateUtc,
      verified: verified,
      verifiedAtUtc: verifiedAtUtc,
      verifiedBy: verifiedByName,
      trailsAsset: trailsAsset,
      offline: offline,
      notes: notes,
    );
  }

  static OfflineConfig _parseOffline(
    Object? raw,
    String path,
    MapGuardrails guardrails,
  ) {
    final json = _expectObject(raw, path);
    final boundsJson = _expectObject(json['bounds'], '$path.bounds');
    final bounds = GeoBounds(
      south: _expectDouble(boundsJson['south'], '$path.bounds.south'),
      west: _expectDouble(boundsJson['west'], '$path.bounds.west'),
      north: _expectDouble(boundsJson['north'], '$path.bounds.north'),
      east: _expectDouble(boundsJson['east'], '$path.bounds.east'),
    );
    if (!bounds.isValid) {
      throw MapPackageFormatException(
        '$path.bounds: batas tidak valid (selatan < utara, barat < timur, '
        'dalam batas Web Mercator).',
      );
    }
    final minZoom = _expectInt(json['min_zoom'], '$path.min_zoom');
    final maxZoom = _expectInt(json['max_zoom'], '$path.max_zoom');
    if (minZoom > maxZoom) {
      throw MapPackageFormatException(
        '$path: min_zoom tidak boleh lebih besar dari max_zoom.',
      );
    }
    if (minZoom < guardrails.minZoom || maxZoom > guardrails.maxZoom) {
      throw MapPackageFormatException(
        '$path: zoom harus dalam ${guardrails.minZoom}-${guardrails.maxZoom}.',
      );
    }
    final maxAreaKm2 =
        _expectDouble(json['max_area_km2'], '$path.max_area_km2');
    if (maxAreaKm2 <= 0 || maxAreaKm2 > guardrails.maxAreaKm2) {
      throw MapPackageFormatException(
        '$path.max_area_km2: harus > 0 dan <= '
        '${guardrails.maxAreaKm2.toStringAsFixed(1)}.',
      );
    }
    final maxTiles = _expectInt(json['max_tiles'], '$path.max_tiles');
    if (maxTiles <= 0 || maxTiles > guardrails.maxTileCount) {
      throw MapPackageFormatException(
        '$path.max_tiles: harus > 0 dan <= ${guardrails.maxTileCount}.',
      );
    }

    final config = OfflineConfig(
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
      maxAreaKm2: maxAreaKm2,
      maxTiles: maxTiles,
    );
    final plan = OfflinePlan.evaluate(config, guardrails: guardrails);
    if (!plan.canDownload) {
      throw MapPackageFormatException(
        '$path: ${plan.violations.map((violation) => violation.message).join(' ')}',
      );
    }
    return config;
  }

  static List<MapTrail> _parseTrails(String raw, String source) {
    final root = _expectObject(_decode(raw, source), source);
    if (root['type'] != 'FeatureCollection') {
      throw MapPackageFormatException('$source: harus FeatureCollection.');
    }
    final features = _expectList(root['features'], '$source.features');
    if (features.isEmpty) {
      throw MapPackageFormatException('$source: minimal satu jalur.');
    }
    final trails = <MapTrail>[];
    final seenIds = <String>{};
    for (var i = 0; i < features.length; i++) {
      final path = '$source.features[$i]';
      final feature = _expectObject(features[i], path);
      if (feature['type'] != 'Feature') {
        throw MapPackageFormatException('$path: harus Feature.');
      }
      final properties =
          _expectObject(feature['properties'], '$path.properties');
      final id = _expectString(properties['id'], '$path.properties.id');
      if (!_trailIdPattern.hasMatch(id)) {
        throw MapPackageFormatException(
          '$path.properties.id: format id jalur tidak valid.',
        );
      }
      if (!seenIds.add(id)) {
        throw MapPackageFormatException('$path: id jalur "$id" ganda.');
      }
      final name = _expectString(properties['name'], '$path.properties.name');
      final trailSource =
          _expectString(properties['source'], '$path.properties.source');
      final verified =
          _expectBool(properties['verified'], '$path.properties.verified');
      final verifiedAt = properties['verified_at'];
      final verifiedBy = properties['verified_by'];
      DateTime? verifiedAtUtc;
      String? verifiedByName;
      if (verified) {
        verifiedAtUtc =
            _expectUtcTimestamp(verifiedAt, '$path.properties.verified_at');
        verifiedByName =
            _expectString(verifiedBy, '$path.properties.verified_by');
      } else if (verifiedAt != null || verifiedBy != null) {
        throw MapPackageFormatException(
          '$path: verified=false tidak boleh punya verified_at/verified_by.',
        );
      }
      final points = _parseLine(feature['geometry'], '$path.geometry');
      trails.add(MapTrail(
        id: id,
        name: name,
        source: trailSource,
        verified: verified,
        verifiedAtUtc: verifiedAtUtc,
        verifiedBy: verifiedByName,
        points: points,
      ));
    }
    return trails;
  }

  static List<LatLng> _parseLine(Object? raw, String path) {
    final geometry = _expectObject(raw, path);
    if (geometry['type'] != 'LineString') {
      throw MapPackageFormatException('$path: jalur harus LineString.');
    }
    final rawCoordinates = _expectList(geometry['coordinates'], '$path.coordinates');
    if (rawCoordinates.length < 2) {
      throw MapPackageFormatException('$path: minimal dua koordinat.');
    }
    final points = <LatLng>[];
    for (var i = 0; i < rawCoordinates.length; i++) {
      final coordinatePath = '$path.coordinates[$i]';
      final coordinate = _expectList(rawCoordinates[i], coordinatePath);
      if (coordinate.length < 2) {
        throw MapPackageFormatException('$coordinatePath: butuh lon dan lat.');
      }
      final lon = _expectDouble(coordinate[0], '$coordinatePath[0]');
      final lat = _expectDouble(coordinate[1], '$coordinatePath[1]');
      if (lat < -GeoBounds.maxMercatorLatitude ||
          lat > GeoBounds.maxMercatorLatitude ||
          lon < -180 ||
          lon > 180) {
        throw MapPackageFormatException(
          '$coordinatePath: koordinat di luar jangkauan Web Mercator.',
        );
      }
      points.add(LatLng(lat, lon));
    }
    final first = points.first;
    final hasDistinctPoint =
        points.any((point) => point.lat != first.lat || point.lon != first.lon);
    if (!hasDistinctPoint) {
      throw MapPackageFormatException('$path: semua koordinat identik.');
    }
    return points;
  }

  static Object? _decode(String raw, String source) {
    try {
      return jsonDecode(raw);
    } on FormatException catch (error) {
      throw MapPackageFormatException('$source: JSON tidak valid (${error.message}).');
    }
  }

  static Map<String, Object?> _expectObject(Object? value, String path) {
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String) {
          throw MapPackageFormatException('$path: kunci JSON harus string.');
        }
        result[key] = entry.value;
      }
      return result;
    }
    throw MapPackageFormatException('$path: harus objek JSON.');
  }

  static List<Object?> _expectList(Object? value, String path) {
    if (value is List) return value;
    throw MapPackageFormatException('$path: harus array JSON.');
  }

  static String _expectString(Object? value, String path) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    throw MapPackageFormatException('$path: harus string tidak kosong.');
  }

  static bool _expectBool(Object? value, String path) {
    if (value is bool) return value;
    throw MapPackageFormatException('$path: harus boolean.');
  }

  static int _expectInt(Object? value, String path) {
    if (value is int) return value;
    throw MapPackageFormatException('$path: harus bilangan bulat.');
  }

  static double _expectDouble(Object? value, String path) {
    if (value is num && value.isFinite) return value.toDouble();
    throw MapPackageFormatException('$path: harus angka.');
  }

  static DateTime _expectUtcTimestamp(Object? value, String path) {
    final raw = _expectString(value, path);
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      throw MapPackageFormatException('$path: tanggal/waktu tidak valid.');
    }
    if (parsed.isUtc) return parsed;
    return DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    );
  }
}

class _PackEntry {
  _PackEntry({
    required this.id,
    required this.name,
    required this.version,
    required this.dataDateUtc,
    required this.verified,
    required this.verifiedAtUtc,
    required this.verifiedBy,
    required this.trailsAsset,
    required this.offline,
    required this.notes,
  });

  final String id;
  final String name;
  final int version;
  final DateTime dataDateUtc;
  final bool verified;
  final DateTime? verifiedAtUtc;
  final String? verifiedBy;
  final String trailsAsset;
  final OfflineConfig offline;
  final String? notes;
}
