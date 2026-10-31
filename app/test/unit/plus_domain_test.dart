import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:nama_app/features/plus/domain/annual_recap.dart';
import 'package:nama_app/features/plus/domain/gpx_export.dart';
import 'package:nama_app/features/plus/domain/hike_analytics.dart';
import 'package:nama_app/features/plus/domain/route_estimate.dart';
import 'package:nama_app/features/plus/domain/route_weather.dart';
import 'package:nama_app/features/plus/infrastructure/plus_local_caches.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plus_fixtures.dart';

/// Sepuluh segmen pertama 30 detik, sepuluh segmen berikutnya 60 detik,
/// sehingga paruh kedua pasti lebih lambat. Jumlah titik ganjil membuat
/// pembagian paruh jatuh tepat di antara segmen, tanpa segmen batas.
List<TrackPoint> _fatiguePoints() {
  final points = <TrackPoint>[];
  var time = DateTime.utc(2026, 3, 1);
  for (var index = 0; index < 21; index++) {
    points.add(
      TrackPoint(
        lat: -6.8 + index * 0.001,
        lon: 106.8,
        altitudeM: 1000 + index * 10,
        timestampUtc: time,
        accuracyM: 5,
      ),
    );
    time = time.add(Duration(seconds: index < 10 ? 30 : 60));
  }
  return points;
}

/// Bujur yang jam matahari lokalnya dekat tengah hari, supaya hasil estimasi
/// tidak berubah menurut zona waktu mesin uji.
double _localLongitude() {
  final offset = DateTime(2026, 3, 20).timeZoneOffset.inMinutes / 60;
  return 15 * offset;
}

void main() {
  group('personalPaceKmh', () {
    test('memakai median dan mengabaikan sesi pendek, terlalu cepat, aktif',
        () {
      final sessions = <TrackingSession>[
        completedSession(
          id: 'lambat',
          startedAtUtc: DateTime.utc(2026, 1, 1),
          distanceM: 1000,
          movingSeconds: 1800,
        ),
        completedSession(
          id: 'sedang',
          startedAtUtc: DateTime.utc(2026, 2, 1),
          distanceM: 2000,
          movingSeconds: 1800,
        ),
        completedSession(
          id: 'cepat',
          startedAtUtc: DateTime.utc(2026, 3, 1),
          distanceM: 3000,
          movingSeconds: 1800,
        ),
        completedSession(
          id: 'terlalu-pendek',
          startedAtUtc: DateTime.utc(2026, 4, 1),
          distanceM: 400,
          movingSeconds: 1000,
        ),
        completedSession(
          id: 'gps-meloncat',
          startedAtUtc: DateTime.utc(2026, 5, 1),
          distanceM: 2000,
          movingSeconds: 100,
        ),
        completedSession(
          id: 'terlalu-lambat',
          startedAtUtc: DateTime.utc(2026, 6, 1),
          distanceM: 1000,
          movingSeconds: 7200,
        ),
        TrackingSession(
          id: 'masih-jalan',
          startedAtUtc: DateTime.utc(2026, 7, 1),
          distanceM: 2000,
          movingSeconds: 1800,
        ),
      ];

      expect(personalPaceKmh(sessions), closeTo(4.0, 0.0001));
      expect(personalPaceKmh(const <TrackingSession>[]), isNull);
    });

    test('median genap memakai rata-rata dua nilai tengah', () {
      final sessions = <TrackingSession>[
        completedSession(
          id: 'a',
          startedAtUtc: DateTime.utc(2026, 1, 1),
          distanceM: 1000,
          movingSeconds: 1800,
        ),
        completedSession(
          id: 'b',
          startedAtUtc: DateTime.utc(2026, 2, 1),
          distanceM: 3000,
          movingSeconds: 1800,
        ),
      ];
      expect(personalPaceKmh(sessions), closeTo(4.0, 0.0001));
    });
  });

  group('rute dan matahari', () {
    test('routeDistanceM menjumlahkan jarak antar titik', () {
      expect(routeDistanceM(const <LatLng>[]), 0);
      expect(routeDistanceM(<LatLng>[const LatLng(0, 0)]), 0);
      final two = <LatLng>[const LatLng(0, 0), const LatLng(0, 0.001)];
      expect(routeDistanceM(two), closeTo(111.2, 1));
      final three = <LatLng>[
        const LatLng(0, 0),
        const LatLng(0, 0.001),
        const LatLng(0, 0.002),
      ];
      expect(routeDistanceM(three), closeTo(222.4, 1));
    });

    test('routeCenter memakai rata-rata dan null bila kosong', () {
      expect(routeCenter(const <LatLng>[]), isNull);
      final center = routeCenter(<LatLng>[
        const LatLng(0, 0),
        const LatLng(2, 4),
      ]);
      expect(center, isNotNull);
      expect(center!.lat, closeTo(1, 1e-9));
      expect(center.lon, closeTo(2, 1e-9));
    });

    test('estimatedSunset di ekuinoks sekitar pukul 18.0', () {
      final sunset = estimatedSunset(
        dateLocal: DateTime(2026, 3, 20),
        latitude: 0,
        longitude: _localLongitude(),
      );
      expect(sunset, isNotNull);
      expect(sunset!.hour, 18);
      expect(sunset.minute, inInclusiveRange(0, 25));
    });

    test('estimatedSunset null saat matahari tidak terbenam (kutub)', () {
      expect(
        estimatedSunset(
          dateLocal: DateTime(2026, 6, 21),
          latitude: 80,
          longitude: 0,
        ),
        isNull,
      );
    });
  });

  group('HikeAnalytics', () {
    test('kosong bila tidak ada sesi', () {
      const analytics = HikeAnalytics.empty();
      expect(analytics.isEmpty, isTrue);
      expect(analytics.sampleCount, 0);
      expect(analytics.slopePaces, isEmpty);
      expect(analytics.records, isEmpty);
      expect(analytics.fatigue.hasData, isFalse);
      expect(analytics.verticalSpeedMPerHour, isNull);
    });

    test('menghitung total, pace kemiringan, rekor, dan kelelahan', () {
      final session = completedSession(
        id: 's1',
        startedAtUtc: DateTime.utc(2026, 3, 1),
        distanceM: 2210,
        movingSeconds: 1080,
        elevationGainM: 200,
      );
      final analytics = HikeAnalytics.build(<HikeSample>[
        HikeSample(session: session, points: _fatiguePoints()),
      ]);

      expect(analytics.sampleCount, 1);
      expect(analytics.distanceM, 2210);
      expect(analytics.movingSeconds, 1080);
      expect(analytics.elevationGainM, 200);
      expect(
        analytics.verticalSpeedMPerHour,
        closeTo(200 / (1080 / 3600), 0.01),
      );

      final uphill =
          analytics.slopePaces.firstWhere((p) => p.kind == SlopeKind.uphill);
      expect(uphill.hasData, isTrue);
      expect(uphill.distanceM, closeTo(2223.9, 3));
      expect(uphill.movingSeconds, 900);
      expect(
        uphill.secondsPerKm,
        closeTo(900 / (uphill.distanceM / 1000), 0.01),
      );
      for (final pace in analytics.slopePaces) {
        if (pace.kind == SlopeKind.uphill) continue;
        expect(pace.hasData, isFalse);
        expect(pace.secondsPerKm, isNull);
      }

      expect(
        analytics.records.map((record) => record.label).toList(),
        <String>['Jarak terjauh', 'Elevasi terbesar', 'Durasi bergerak'],
      );
      expect(analytics.records[0].value, '2.2 km');
      expect(analytics.records[1].value, '200 m');
      expect(analytics.records[2].value, '0.3 jam');
      expect(analytics.records[0].occurredAtUtc, session.startedAtUtc);

      expect(analytics.fatigue.hasData, isTrue);
      expect(analytics.fatigue.sessionsUsed, 1);
      expect(analytics.fatigue.slowdownPercent, closeTo(100, 0.01));
    });

    test('sesi tanpa titik tetap punya rekor tetapi tanpa kelelahan', () {
      final session = completedSession(
        id: 's2',
        startedAtUtc: DateTime.utc(2026, 4, 1),
        distanceM: 800,
        movingSeconds: 600,
        elevationGainM: 50,
      );
      final analytics = HikeAnalytics.build(<HikeSample>[
        HikeSample(session: session, points: const <TrackPoint>[]),
      ]);

      expect(analytics.isEmpty, isFalse);
      expect(analytics.fatigue.hasData, isFalse);
      expect(analytics.fatigue.slowdownPercent, isNull);
      expect(analytics.records[0].value, '0.8 km');
      for (final pace in analytics.slopePaces) {
        expect(pace.hasData, isFalse);
      }
    });
  });

  group('AnnualRecap', () {
    final nowLocal = DateTime(2026, 10, 31, 12);

    HikeSample sample({
      required String id,
      required DateTime startedLocal,
      required double distanceM,
      required int movingSeconds,
      required double gainM,
      required double topAltitudeM,
      TrackingSessionStatus status = TrackingSessionStatus.completed,
    }) {
      final session = TrackingSession(
        id: id,
        startedAtUtc: startedLocal.toUtc(),
        endedAtUtc: startedLocal.add(const Duration(hours: 2)).toUtc(),
        distanceM: distanceM,
        movingSeconds: movingSeconds,
        elevationGainM: gainM,
        status: status,
      );
      final points = samplePoints(
        count: 3,
        startUtc: DateTime.utc(2026, 3, 1),
        startAltitudeM: topAltitudeM - 200,
        stepAltitudeM: 100,
      );
      return HikeSample(session: session, points: points);
    }

    final currentA = sample(
      id: 'a',
      startedLocal: DateTime(2026, 3, 1, 7),
      distanceM: 5000,
      movingSeconds: 3600,
      gainM: 100,
      topAltitudeM: 1700,
    );
    final currentB = sample(
      id: 'b',
      startedLocal: DateTime(2026, 6, 1, 7),
      distanceM: 3000,
      movingSeconds: 3600,
      gainM: 600,
      topAltitudeM: 2200,
    );

    test('memisahkan tahun berjalan, pembanding, dan sesi lain', () {
      final recap = AnnualRecap.build(
        samples: <HikeSample>[
          currentA,
          currentB,
          sample(
            id: 'lalu-dalam-periode',
            startedLocal: DateTime(2025, 10, 31, 12),
            distanceM: 1000,
            movingSeconds: 1800,
            gainM: 40,
            topAltitudeM: 1200,
          ),
          sample(
            id: 'lalu-di-luar-periode',
            startedLocal: DateTime(2025, 11, 1, 12),
            distanceM: 9000,
            movingSeconds: 3600,
            gainM: 500,
            topAltitudeM: 2500,
          ),
          sample(
            id: 'dua-tahun-lalu',
            startedLocal: DateTime(2024, 5, 1, 7),
            distanceM: 20000,
            movingSeconds: 7200,
            gainM: 900,
            topAltitudeM: 3000,
          ),
          sample(
            id: 'masih-aktif',
            startedLocal: DateTime(2026, 9, 1, 7),
            distanceM: 99999,
            movingSeconds: 99999,
            gainM: 9999,
            topAltitudeM: 9999,
            status: TrackingSessionStatus.active,
          ),
        ],
        nowLocal: nowLocal,
      );

      expect(recap.year, 2026);
      expect(recap.sessionCount, 2);
      expect(recap.distanceM, 8000);
      expect(recap.movingSeconds, 7200);
      expect(recap.elevationGainM, 700);
      expect(recap.previousSessionCount, 1);
      expect(recap.previousDistanceM, 1000);
      expect(recap.sessionDelta, 1);
      expect(recap.distanceChangePercent, closeTo(700, 1e-9));
      expect(
        recap.comparisonEndLocal,
        DateTime(2025, 10, 31, 23, 59, 59, 999),
      );
      expect(recap.highestAltitudeM, 2200);
      expect(
        recap.highestAltitudeAtUtc,
        currentB.points.last.timestampUtc,
      );
      expect(recap.hardestAtUtc, currentB.session.startedAtUtc);
      expect(recap.hardestDistanceM, 3000);
      expect(recap.hardestElevationGainM, 600);
      expect(recap.route, isNotNull);
      expect(recap.route!.length, 3);
      expect(recap.routeStart, isNotNull);
      expect(recap.routeEnd, isNotNull);
      expect(recap.isEmpty, isFalse);
    });

    test('kosong bila tidak ada sesi selesai tahun ini', () {
      final recap = AnnualRecap.build(
        samples: const <HikeSample>[],
        nowLocal: nowLocal,
      );
      expect(recap.isEmpty, isTrue);
      expect(recap.sessionCount, 0);
      expect(recap.previousSessionCount, 0);
      expect(recap.distanceChangePercent, isNull);
      expect(recap.highestAltitudeM, isNull);
      expect(recap.hardestAtUtc, isNull);
      expect(recap.route, isNull);
      expect(recap.routeStart, isNull);
      expect(recap.routeEnd, isNull);
    });

    test('barFraction membatasi 0..1 dan tidak membagi nol', () {
      expect(AnnualRecap.barFraction(5, 10), 0.5);
      expect(AnnualRecap.barFraction(10, 5), 1.0);
      expect(AnnualRecap.barFraction(0, 0), 0.0);
      expect(AnnualRecap.barFraction(0.5, 0), 0.5);
    });
  });

  group('RouteEstimate', () {
    final lon = _localLongitude();
    final twoPointRoute = <LatLng>[LatLng(0, lon), LatLng(0, lon + 0.01)];

    test('null bila titik kurang, pace tidak ada, atau rute terlalu pendek',
        () {
      final now = DateTime(2026, 3, 20, 6);
      expect(
        RouteEstimate.build(
          routeName: 'A',
          points: const <LatLng>[],
          nowLocal: now,
          paceKmh: 2,
        ),
        isNull,
      );
      expect(
        RouteEstimate.build(
          routeName: 'A',
          points: const <LatLng>[LatLng(0, 0)],
          nowLocal: now,
          paceKmh: 2,
        ),
        isNull,
      );
      expect(
        RouteEstimate.build(
          routeName: 'A',
          points: twoPointRoute,
          nowLocal: now,
          paceKmh: null,
        ),
        isNull,
      );
      expect(
        RouteEstimate.build(
          routeName: 'A',
          points: twoPointRoute,
          nowLocal: now,
          paceKmh: 0,
        ),
        isNull,
      );
      expect(
        RouteEstimate.build(
          routeName: 'A',
          points: <LatLng>[LatLng(0, lon), LatLng(0, lon + 0.0004)],
          nowLocal: now,
          paceKmh: 2,
        ),
        isNull,
      );
    });

    test('menghitung garis waktu, istirahat, dan perlengkapan', () {
      final now = DateTime(2026, 3, 20, 6);
      final estimate = RouteEstimate.build(
        routeName: 'Gunung Uji',
        points: twoPointRoute,
        nowLocal: now,
        paceKmh: 2,
      );

      expect(estimate, isNotNull);
      expect(estimate!.distanceM, closeTo(1112, 2));
      expect(estimate.startLocal, now);
      expect(
        estimate.ascent.inSeconds,
        (estimate.distanceM / 1000 / 2 * 3600).round(),
      );
      expect(
        estimate.breaks.inMinutes,
        (estimate.ascent.inSeconds / 3600 * 10).round(),
      );
      expect(estimate.descent.inSeconds, (estimate.ascent.inSeconds * 0.75).round());
      expect(estimate.summitRest, RouteEstimate.summitRestDefault);
      expect(
        estimate.arrivalLocal,
        now.add(estimate.ascent).add(estimate.breaks),
      );
      expect(estimate.fitsBeforeSunset, isTrue);
      expect(estimate.sunsetLocal, isNotNull);
      expect(estimate.turnAroundLocal, isNotNull);
      expect(
        estimate.turnAroundLocal,
        estimate.sunsetLocal!
            .subtract(estimate.descent)
            .subtract(RouteEstimate.safetyBuffer),
      );

      expect(
        estimate.timeline.map((point) => point.label).toList(),
        <String>[
          'Mulai naik',
          'Perkiraan tiba di puncak',
          'Batas putar balik',
          'Matahari terbenam',
        ],
      );
      expect(estimate.timeline.any((point) => point.warning), isFalse);
      expect(estimate.gear, contains('Air 1 liter'));
      expect(estimate.gear, isNot(contains('Trekking pole')));
      expect(
        estimate.gear,
        isNot(contains('Lampu cadangan untuk turun gelap')),
      );
      expect(estimate.summaryText, contains('Estimasi Gunung Uji (Hiqeo)'));
      expect(
        estimate.summaryText,
        contains('Kecepatan jelajah pribadi: 2.0 km/jam'),
      );
      expect(estimate.summaryText, contains('perkiraan'));
    });

    test('rute panjang menambah trekking pole dan air', () {
      final estimate = RouteEstimate.build(
        routeName: 'Gunung Panjang',
        points: <LatLng>[LatLng(0, lon), LatLng(0, lon + 0.08)],
        nowLocal: DateTime(2026, 3, 20, 6),
        paceKmh: 3,
      );

      expect(estimate, isNotNull);
      expect(estimate!.distanceM, greaterThanOrEqualTo(8000));
      expect(estimate.gear, contains('Trekking pole'));
      expect(estimate.gear, contains('Air 4 liter'));
      expect(estimate.fitsBeforeSunset, isTrue);
    });

    test('memperingatkan bila tidak muat sebelum gelap', () {
      final estimate = RouteEstimate.build(
        routeName: 'Gunung Malam',
        points: twoPointRoute,
        nowLocal: DateTime(2026, 3, 20, 23),
        paceKmh: 2,
      );

      expect(estimate, isNotNull);
      expect(estimate!.fitsBeforeSunset, isFalse);
      expect(
        estimate.timeline
            .firstWhere((point) => point.label == 'Perkiraan tiba di puncak')
            .warning,
        isTrue,
      );
      expect(
        estimate.timeline
            .firstWhere((point) => point.label == 'Batas putar balik')
            .warning,
        isTrue,
      );
      expect(estimate.gear, contains('Lampu cadangan untuk turun gelap'));
    });

    test('posisi kutub tidak mengarang waktu matahari terbenam', () {
      final estimate = RouteEstimate.build(
        routeName: 'Gunung Kutub',
        points: <LatLng>[const LatLng(80, 0), const LatLng(80, 0.01)],
        nowLocal: DateTime(2026, 6, 21, 6),
        paceKmh: 2,
      );

      expect(estimate, isNotNull);
      expect(estimate!.sunsetLocal, isNull);
      expect(estimate.turnAroundLocal, isNull);
      expect(estimate.fitsBeforeSunset, isNull);
      expect(estimate.timeline.length, 2);
      expect(
        estimate.gear,
        isNot(contains('Lampu cadangan untuk turun gelap')),
      );
    });
  });

  group('GpxDocument', () {
    final session = completedSession(
      id: 'gpx',
      startedAtUtc: DateTime(2026, 3, 1, 8, 30).toUtc(),
      distanceM: 500,
      movingSeconds: 600,
    );
    final realPoints = <TrackPoint>[
      TrackPoint(
        lat: -6.8,
        lon: 106.8,
        altitudeM: 1500,
        timestampUtc: DateTime.utc(2026, 3, 1, 0),
        accuracyM: 5,
      ),
      TrackPoint(
        lat: -6.801,
        lon: 106.8012,
        timestampUtc: DateTime.utc(2026, 3, 1, 0, 1),
        accuracyM: 5,
      ),
      TrackPoint(
        lat: -6.802,
        lon: 106.8024,
        altitudeM: 1512.34,
        timestampUtc: DateTime.utc(2026, 3, 1, 0, 2),
        accuracyM: 5,
      ),
    ];

    test('menulis GPX 1.1 dengan nama bawaan dan merek Hiqeo', () {
      final xml = GpxDocument.build(session: session, points: realPoints);
      expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(xml, contains('<gpx version="1.1" creator="Hiqeo"'));
      expect(xml, contains('<name>Pendakian 01/03/2026</name>'));
      expect(xml, contains('<trkpt lat="-6.800000" lon="106.800000">'));
      expect(xml, contains('<trkpt lat="-6.801000" lon="106.801200">'));
      expect(xml, contains('<ele>1500.0</ele>'));
      expect(xml, contains('<ele>1512.3</ele>'));
      expect(xml, contains('<time>2026-03-01T00:00:00.000Z</time>'));
      expect('<ele>'.allMatches(xml).length, 2);
      expect(xml.trimRight(), endsWith('</gpx>'));
    });

    test('nama kustom di-escape di metadata dan trek', () {
      final xml = GpxDocument.build(
        session: session,
        points: realPoints,
        name: 'Gunung <A> & "B" \'C\'',
      );
      const escaped =
          'Gunung &lt;A&gt; &amp; &quot;B&quot; &apos;C&apos;';
      expect('<name>$escaped</name>'.allMatches(xml).length, 2);
      expect(xml, isNot(contains('<A>')));
    });
  });

  group('SharedPreferencesRouteWeatherCache', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('menyimpan dan membaca kembali prakiraan dengan nama berspasi', () async {
      const cache = SharedPreferencesRouteWeatherCache();
      final forecast = weatherForecast(
        routeName: 'Gunung Gede via Cibodas',
        fetchedAtUtc: DateTime.utc(2026, 10, 31, 1),
        source: bmkgSource,
      );

      await cache.write(forecast);
      final restored = await cache.read('Gunung Gede via Cibodas');

      expect(restored, isNotNull);
      expect(restored!.routeName, 'Gunung Gede via Cibodas');
      expect(restored.source, bmkgSource);
      expect(restored.isOfficial, isTrue);
      expect(restored.fetchedAtUtc, forecast.fetchedAtUtc);
      expect(restored.days, hasLength(2));
      expect(restored.days.first.hours, hasLength(5));
      expect(restored.days.first.posts, hasLength(2));
      expect(restored.days.first.posts.first.altitudeM, 1500);

      final preferences = await SharedPreferences.getInstance();
      final encoded = base64Url.encode(utf8.encode('Gunung Gede via Cibodas'));
      expect(
        preferences.containsKey(
          '${SharedPreferencesRouteWeatherCache.keyPrefix}$encoded',
        ),
        isTrue,
      );
    });

    test('nama rute berbeda tidak saling menimpa', () async {
      const cache = SharedPreferencesRouteWeatherCache();
      await cache.write(
        weatherForecast(
          routeName: 'Gunung A',
          fetchedAtUtc: DateTime.utc(2026, 10, 31),
        ),
      );

      expect(await cache.read('Gunung B'), isNull);
      expect(await cache.read('Gunung A'), isNotNull);
    });

    test('entri rusak atau tidak ada dibaca sebagai null', () async {
      const cache = SharedPreferencesRouteWeatherCache();
      expect(await cache.read('Belum Ada'), isNull);

      final encoded = base64Url.encode(utf8.encode('Rusak'));
      SharedPreferences.setMockInitialValues(<String, Object>{
        '${SharedPreferencesRouteWeatherCache.keyPrefix}$encoded':
            '{bukan json',
      });
      expect(await cache.read('Rusak'), isNull);
    });
  });
}
