import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/map/domain/indonesia_region_resolver.dart';
import 'package:nama_app/features/map/domain/mountain_pack_data.dart';

class _FakeGpxAssetBundle extends CachingAssetBundle {
  _FakeGpxAssetBundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.json') {
      final manifest = <String, List<String>>{
        for (final path in files.keys) path: <String>[path],
      };
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(manifest)));
      return ByteData.sublistView(bytes);
    }
    if (key == 'AssetManifest.bin') {
      final manifest = <String, List<Map<String, Object>>>{
        for (final path in files.keys)
          path: <Map<String, Object>>[
            <String, Object>{'asset': path},
          ],
      };
      final data = const StandardMessageCodec().encodeMessage(manifest)!;
      return data;
    }
    final text = files[key] ?? files[Uri.decodeFull(key)];
    if (text == null) {
      throw Exception('Asset not found: $key');
    }
    final bytes = Uint8List.fromList(utf8.encode(text));
    return ByteData.sublistView(bytes);
  }
}

String _sampleGpx({
  required double startLat,
  required double startLon,
  required double startEle,
  required double summitLat,
  required double summitLon,
  required double summitEle,
  String? extraXml = '',
}) {
  final midLat = (startLat + summitLat) / 2;
  final midLon = (startLon + summitLon) / 2;
  final midEle = (startEle + summitEle) / 2;
  return '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test">
  <metadata>
    <name>Sample</name>
    $extraXml
  </metadata>
  <wpt lat="$summitLat" lon="$summitLon">
    <ele>$summitEle</ele>
    <name>PUNCAK</name>
  </wpt>
  <trk>
    <trkseg>
      <trkpt lat="$startLat" lon="$startLon"><ele>$startEle</ele></trkpt>
      <trkpt lat="$midLat" lon="$midLon"><ele>$midEle</ele></trkpt>
      <trkpt lat="$summitLat" lon="$summitLon"><ele>$summitEle</ele></trkpt>
    </trkseg>
  </trk>
</gpx>''';
}

void main() {
  group('GPX Auto-Discovery & Region Resolver', () {
    test('parseGpxFilename memecah separator VIA case-insensitive & awalan Gunung', () {
      final a = MountainPackData.parseGpxFilename(
        'assets/routes/GUNUNG GEDE VIA PUTRI.gpx',
      );
      expect(a.mountainId, 'gede');
      expect(a.mountainName, 'Gunung Gede');
      expect(a.trailId, 'gede_putri');
      expect(a.trailName, 'Via Putri');

      final b = MountainPackData.parseGpxFilename(
        'assets/gpx/CIKURAY%20via%20pamancar.gpx',
      );
      expect(b.mountainId, 'cikuray');
      expect(b.mountainName, 'Gunung Cikuray');
      expect(b.trailId, 'cikuray_pamancar');
      expect(b.trailName, 'Via Pamancar');

      final c = MountainPackData.parseGpxFilename(
        'assets/gpx/SEMERU VIA RANU PANI.gpx',
      );
      expect(c.mountainId, 'semeru');
      expect(c.mountainName, 'Gunung Semeru');
      expect(c.trailId, 'semeru_ranu_pani');
      expect(c.trailName, 'Via Ranu Pani');
    });

    test('IndonesiaRegionResolver memetakan koordinat gunung & fallback metadata', () {
      expect(
        IndonesiaRegionResolver.resolve(lat: -7.3043, lon: 107.8812),
        'Garut, Jawa Barat',
      );
      expect(
        IndonesiaRegionResolver.resolve(lat: -8.0180, lon: 112.9449),
        'Lumajang, Jawa Timur',
      );
      expect(
        IndonesiaRegionResolver.resolve(lat: -1.7507, lon: 101.2595),
        'Kerinci, Jambi',
      );
      expect(
        IndonesiaRegionResolver.resolve(lat: -8.3476, lon: 116.4953),
        'Lombok Timur, Nusa Tenggara Barat',
      );
      expect(
        IndonesiaRegionResolver.resolve(
          lat: 0.0,
          lon: 0.0,
          regionHint: 'Toraja, Sulawesi Selatan',
        ),
        'Toraja, Sulawesi Selatan',
      );
    });

    test('loadHydratedPacks menggrupkan gunung otomatis dari assets/routes & assets/gpx', () async {
      final bundle = _FakeGpxAssetBundle(<String, String>{
        'assets/routes/GUNUNG PRAU VIA DIENG.gpx': _sampleGpx(
          startLat: -7.2110,
          startLon: 109.9080,
          startEle: 2050,
          summitLat: -7.1972,
          summitLon: 109.9322,
          summitEle: 2590,
        ),
        'assets/routes/GUNUNG PRAU VIA PATAK BANTENG.gpx': _sampleGpx(
          startLat: -7.2093,
          startLon: 109.9259,
          startEle: 1990,
          summitLat: -7.1972,
          summitLon: 109.9322,
          summitEle: 2590,
        ),
        'assets/gpx/CIKURAY VIA PAMANCAR.gpx': _sampleGpx(
          startLat: -7.304364,
          startLon: 107.881245,
          startEle: 1533,
          summitLat: -7.322553,
          summitLon: 107.859813,
          summitEle: 2806.5,
        ),
      });

      final packs = await MountainPackData.loadHydratedPacks(bundle: bundle);
      expect(packs.length, 2);

      final cikuray = packs.firstWhere((p) => p.id == 'cikuray');
      expect(cikuray.name, 'Gunung Cikuray');
      expect(cikuray.province, 'Garut, Jawa Barat');
      expect(cikuray.elevationM, 2807);
      expect(cikuray.trailCount, 1);
      expect(cikuray.package.trails.first.name, 'Via Pamancar');
      expect(cikuray.package.trails.first.distanceM, greaterThan(2000));
      expect(cikuray.package.trails.first.elevationGainM, greaterThan(1000));
      expect(cikuray.package.trails.first.points.length, greaterThanOrEqualTo(2));

      final prau = packs.firstWhere((p) => p.id == 'prau');
      expect(prau.name, 'Gunung Prau');
      expect(prau.province, 'Wonosobo, Jawa Tengah');
      expect(prau.trailCount, 2);
      expect(
        prau.package.trails.map((t) => t.name).toList(),
        <String>['Via Dieng', 'Via Patak Banteng'],
      );
    });
  });
}
