import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/analytics/domain/sport_science_analytics.dart';
import 'package:nama_app/features/history/presentation/history_page.dart';
import 'package:nama_app/features/kartu/domain/kartu_data.dart';
import 'package:nama_app/features/kartu/presentation/kartu_card.dart';
import 'package:nama_app/features/plus/domain/hike_analytics.dart';
import 'package:nama_app/features/plus/domain/trail_segment_comparison.dart';
import 'package:nama_app/features/plus/presentation/advanced_analytics_page.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_repository.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';
import 'package:nama_app/features/trails/domain/track_route.dart';

class _MemoryTrackingRepo implements TrackingRepository {
  _MemoryTrackingRepo({
    required this.sessions,
    required this.pointsBySession,
  });

  final List<TrackingSession> sessions;
  final Map<String, List<TrackPoint>> pointsBySession;

  @override
  Future<void> addPoint(String sessionId, TrackPoint point) async {}

  @override
  Future<void> clearPoints(String sessionId) async {}

  @override
  Future<void> deleteSession(String id) async {}

  @override
  Future<TrackingSession?> findActiveSession() async => null;

  @override
  Future<TrackingSession?> findSession(String id) async {
    for (final s in sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Future<TrackPoint?> latestPoint(String sessionId) async {
    final pts = pointsBySession[sessionId];
    return (pts == null || pts.isEmpty) ? null : pts.last;
  }

  @override
  Future<List<TrackPoint>> points(String sessionId) async =>
      pointsBySession[sessionId] ?? const <TrackPoint>[];

  @override
  Future<void> saveSession(TrackingSession session) async {}

  @override
  Stream<List<TrackingSession>> watchSessions() =>
      Stream<List<TrackingSession>>.value(sessions);
}

List<TrackPoint> _buildRealisticHikeTrack({
  required DateTime startUtc,
  double paceFactor = 1.0,
  double secondHalfFatigueFactor = 1.0,
  bool includePauseGap = true,
  bool includeHighAltitude = true,
}) {
  // ~2.4 km total track moving north in ~50m steps with varied climb, flat, descent.
  // 1 degree lat ~= 111,111 m -> 50 m ~= 0.00045 deg.
  const stepLat = 0.00045;
  final points = <TrackPoint>[];
  var t = startUtc;
  var lat = -6.75;
  var alt = includeHighAltitude ? 2150.0 : 1200.0;

  points.add(
    TrackPoint(
      lat: lat,
      lon: 106.95,
      timestampUtc: t,
      accuracyM: 4,
      altitudeM: alt,
      speedMps: 1.0,
    ),
  );

  // Segment steps (48 intervals x ~50 m ~= 2.4 km):
  // 0..19: Uphill steep (+12..+18 m per 50m -> +300 m)
  // 20..25: Flat ridge (~0 m change)
  // 26..35: Uphill second half (+15 m per 50m) with optional fatigue slow down
  // 36..47: Downhill (-18 m per 50m -> -216 m)
  for (var i = 1; i <= 48; i++) {
    lat += stepLat;
    double stepEle;
    if (i <= 20) {
      stepEle = 16.0;
    } else if (i <= 26) {
      stepEle = 0.4;
    } else if (i <= 36) {
      stepEle = 14.0;
    } else {
      stepEle = -18.0;
    }
    alt += stepEle;

    if (includePauseGap && i == 24) {
      // Berhenti / istirahat 180 detik
      t = t.add(const Duration(seconds: 180));
      points.add(
        TrackPoint(
          lat: lat,
          lon: 106.95,
          timestampUtc: t,
          accuracyM: 4,
          altitudeM: alt,
          speedMps: 0.0,
        ),
      );
      continue;
    }

    final halfFactor = i > 24 ? secondHalfFatigueFactor : 1.0;
    final dtSec = (40.0 * paceFactor * halfFactor).round();
    t = t.add(Duration(seconds: dtSec));
    points.add(
      TrackPoint(
        lat: lat,
        lon: 106.95,
        timestampUtc: t,
        accuracyM: 4,
        altitudeM: alt,
        speedMps: 50.0 / dtSec,
      ),
    );
  }
  return points;
}

Future<Uint8List> _createSolidPngBytes() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 8, 8),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  final image = await recorder.endRecording().toImage(8, 8);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  group('#17 KartuCard photo scrim & TERTINGGI full label', () {
    testWidgets(
      'KartuCard menampilkan scrim hanya saat foto dipasang dan TERTINGGI tidak terpotong di lebar sempit',
      (tester) async {
        final pngBytes = await tester.runAsync(_createSolidPngBytes);
        final kartuJogging = KartuData(
          sessionId: 'jog-scrim',
          startedAtUtc: DateTime.utc(2026, 11, 1, 6),
          distanceM: 5400,
          movingSeconds: 1900,
          elevationGainM: 120,
          activityType: TrackingSession.activityJogging,
          profile: const <KartuProfilePoint>[
            KartuProfilePoint(0.0, 50),
            KartuProfilePoint(0.45, 170),
            KartuProfilePoint(1.0, 80),
          ],
          peakFraction: 0.45,
          route: const <Offset>[Offset(0, 1), Offset(0.5, 0.2), Offset(1, 0.6)],
        );

        // Tanpa foto -> tidak ada kartu-photo-scrim, TERTINGGI tampil penuh
        await tester.pumpWidget(
          MaterialApp(
            theme: hiqeoDarkTheme,
            home: Scaffold(
              body: SizedBox(
                width: 280,
                height: 350,
                child: KartuCard(
                  data: kartuJogging,
                  style: KartuStyle.profil,
                  hideEndpoints: false,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byKey(const ValueKey<String>('kartu-photo-scrim')), findsNothing);
        expect(find.text('TERTINGGI'), findsOneWidget);

        // Dengan foto -> kartu-photo & kartu-photo-scrim tampil
        await tester.pumpWidget(
          MaterialApp(
            theme: hiqeoDarkTheme,
            home: Scaffold(
              body: SizedBox(
                width: 280,
                height: 350,
                child: KartuCard(
                  data: kartuJogging,
                  style: KartuStyle.profil,
                  hideEndpoints: false,
                  photoBytes: pngBytes,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byKey(const ValueKey<String>('kartu-photo')), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('kartu-photo-scrim')), findsOneWidget);
        expect(find.text('TERTINGGI'), findsOneWidget);
      },
    );
  });

  group('#18 Bandingkan segmen jalur', () {
    test(
      'mengelompokkan pos GPX serta menghitung selisih durasi antar-sesi dan sorotan 1-sesi',
      () {
        final tOlder = DateTime.utc(2026, 10, 10, 1);
        final ptsOlder = _buildRealisticHikeTrack(
          startUtc: tOlder,
          paceFactor: 1.25,
        );
        final sOlder = TrackingSession(
          id: 'gede-old',
          startedAtUtc: tOlder,
          endedAtUtc: ptsOlder.last.timestampUtc,
          mountainName: 'Gunung Gede',
          trailName: 'Cibodas',
          trailId: 'gede-cibodas',
          distanceM: 2400,
          movingSeconds: 2300,
          elevationGainM: 460,
          elevationLossM: 216,
          status: TrackingSessionStatus.completed,
        );

        final tNew = DateTime.utc(2026, 11, 10, 1);
        final ptsNew = _buildRealisticHikeTrack(
          startUtc: tNew,
          paceFactor: 0.9,
        );
        final sNew = TrackingSession(
          id: 'gede-new',
          startedAtUtc: tNew,
          endedAtUtc: ptsNew.last.timestampUtc,
          mountainName: 'Gunung Gede',
          trailName: 'Cibodas',
          trailId: 'gede-cibodas',
          distanceM: 2400,
          movingSeconds: 1700,
          elevationGainM: 460,
          elevationLossM: 216,
          status: TrackingSessionStatus.completed,
        );

        final tSingle = DateTime.utc(2026, 9, 1, 1);
        final ptsSingle = _buildRealisticHikeTrack(startUtc: tSingle);
        final sSingle = TrackingSession(
          id: 'merbabu-1',
          startedAtUtc: tSingle,
          endedAtUtc: ptsSingle.last.timestampUtc,
          mountainName: 'Gunung Merbabu',
          trailName: 'Selo',
          trailId: 'merbabu-selo',
          distanceM: 2400,
          movingSeconds: 1900,
          elevationGainM: 460,
          elevationLossM: 216,
          status: TrackingSessionStatus.completed,
        );

        final groups = TrailSegmentComparisonBuilder.buildGroups(
          <HikeSample>[
            HikeSample(session: sOlder, points: ptsOlder),
            HikeSample(session: sNew, points: ptsNew),
            HikeSample(session: sSingle, points: ptsSingle),
          ],
          waypointsByRouteKey: const <String, List<TrackWaypoint>>{
            'trail:gede-cibodas': <TrackWaypoint>[
              TrackWaypoint(
                name: 'Pos 1 Panyangcangan',
                lat: -6.75,
                lon: 106.95,
                distanceFromStartM: 700,
              ),
              TrackWaypoint(
                name: 'Kandang Badak',
                lat: -6.74,
                lon: 106.95,
                distanceFromStartM: 1600,
              ),
              TrackWaypoint(
                name: 'Puncak',
                lat: -6.73,
                lon: 106.95,
                distanceFromStartM: 2400,
              ),
            ],
          },
        );

        expect(groups, hasLength(2));
        // Multi-session diurutkan paling atas
        final gedeGroup = groups.first;
        expect(gedeGroup.hasMultiSessionComparison, isTrue);
        expect(gedeGroup.usedWaypoints, isTrue);
        expect(gedeGroup.segments.map((s) => s.label), <String>[
          'Start – Pos 1 Panyangcangan',
          'Pos 1 Panyangcangan – Kandang Badak',
          'Kandang Badak – Puncak',
        ]);
        expect(gedeGroup.totalDeltaSeconds, isNotNull);
        expect(gedeGroup.totalDeltaSeconds!, lessThan(0)); // Sesi baru lebih cepat
        for (final seg in gedeGroup.segments) {
          expect(seg.latest.distanceM, greaterThan(0));
          expect(seg.deltaSeconds, lessThan(0));
        }

        // Single-session merbabu menyoroti segmen terberat vs paling stabil
        final merbabuGroup = groups[1];
        expect(merbabuGroup.hasMultiSessionComparison, isFalse);
        expect(merbabuGroup.segments, hasLength(4));
        expect(merbabuGroup.hardestSegmentIndex, isNotNull);
        expect(merbabuGroup.mostStableSegmentIndex, isNotNull);
      },
    );
  });

  group('#19 Sport Scientist & Sport Doctor Analytics', () {
    test('Single-session menghitung 4 irisan medan, KM split GAP, dan Pandolf kcal', () {
      final start = DateTime.utc(2026, 11, 15, 0);
      final pts = _buildRealisticHikeTrack(
        startUtc: start,
        includePauseGap: true,
        secondHalfFatigueFactor: 1.35,
      );
      final session = TrackingSession(
        id: 'sess-1',
        startedAtUtc: start,
        endedAtUtc: pts.last.timestampUtc,
        mountainName: 'Gunung Semeru',
        trailName: 'Ranu Pani',
        distanceM: 2400,
        movingSeconds: 1850,
        elevationGainM: 460,
        elevationLossM: 216,
        status: TrackingSessionStatus.completed,
      );

      final report = SessionSportScienceReport.fromSession(
        session: session,
        points: pts,
        weightKg: 70,
        packKg: 6,
      );

      // 4 irisan waktu: Menanjak, Datar, Menurun, Berhenti
      expect(report.terrain.uphillSeconds, greaterThan(0));
      expect(report.terrain.flatSeconds, greaterThan(0));
      expect(report.terrain.downhillSeconds, greaterThan(0));
      expect(report.terrain.stoppedSeconds, greaterThanOrEqualTo(180));
      final pctSum = report.terrain.uphillPct +
          report.terrain.flatPct +
          report.terrain.downhillPct +
          report.terrain.stoppedPct;
      expect(pctSum, closeTo(100.0, 0.1));

      // KM split: 2 km penuh + trailing partial >= 250 m -> minimal 2 split
      expect(report.kmSplits.hasData, isTrue);
      expect(report.kmSplits.splits.length, greaterThanOrEqualTo(2));
      expect(report.kmSplits.averageGapSecondsPerKm, isNotNull);
      // KM 1 menanjak penuh -> GAP lebih cepat daripada pace mentah
      final km1 = report.kmSplits.splits.first;
      expect(km1.elevationGainM, greaterThan(100));
      expect(km1.gapSecondsPerKm, lessThan(km1.paceSecondsPerKm));

      // Pandolf/ACSM recovery & hidrasi
      expect(report.recovery.totalKcal, greaterThan(150));
      expect(report.recovery.fluidReplacementMl, greaterThanOrEqualTo(250));
      expect(report.recovery.recoveryNote, isNotEmpty);
    });

    test('Cross-session menghitung ACWR, beban eksentrik, zona ketinggian >2500, VAM, & GAP fatigue drift', () {
      final nowLocal = DateTime(2026, 11, 22, 10);
      final samples = <HikeSample>[];

      // 3 minggu lalu + 2 minggu lalu + 1 minggu lalu + 7 hari terakhir (lonjakan berat)
      for (final daysAgo in <int>[25, 22, 18, 11, 4, 2, 1]) {
        final start = nowLocal.subtract(Duration(days: daysAgo)).toUtc();
        final isRecentSpike = daysAgo <= 7;
        final pts = _buildRealisticHikeTrack(
          startUtc: start,
          secondHalfFatigueFactor: 1.45,
          includeHighAltitude: true, // mencicipi zona 1850 -> >2500 mdpl
        );
        samples.add(
          HikeSample(
            session: TrackingSession(
              id: 's-$daysAgo',
              startedAtUtc: start,
              endedAtUtc: pts.last.timestampUtc,
              mountainName: 'Gunung Prau',
              distanceM: isRecentSpike ? 14000 : 5000,
              movingSeconds: isRecentSpike ? 16000 : 7200,
              elevationGainM: isRecentSpike ? 1200 : 300,
              elevationLossM: isRecentSpike ? 1100 : 280,
              status: TrackingSessionStatus.completed,
            ),
            points: pts,
          ),
        );
      }

      final cross = CrossSessionSportScienceReport.build(
        allSamples: samples,
        rangeSamples: samples,
        nowLocal: nowLocal,
      );

      // Beban akut 7 hari jauh lebih tinggi -> ACWR > 1.5 (highRisk)
      expect(cross.acwr.ratio, isNotNull);
      expect(cross.acwr.ratio!, greaterThan(1.5));
      expect(cross.acwr.zone, AcwrZone.highRisk);

      // Beban eksentrik terisi
      expect(cross.eccentricDownhill.totalElevationLossM, greaterThan(3000));
      expect(cross.eccentricDownhill.avgDescentSpeedMPerHour, isNotNull);
      expect(cross.eccentricDownhill.bars, isNotEmpty);

      // Zona ketinggian terisi termasuk >2500 mdpl & VAM
      expect(cross.altitudeVam.hasAltitudeData, isTrue);
      expect(cross.altitudeVam.above2500Seconds, greaterThan(0));
      expect(cross.altitudeVam.steepVamMPerHour, greaterThan(100));

      // Fatigue drift positif (paruh kedua diperlambat 1.45x)
      expect(cross.fatigueDrift.hasData, isTrue);
      expect(cross.fatigueDrift.driftPercent!, greaterThan(10));
    });

    testWidgets(
      'HistoryDetailPage merender 3 kartu Sport Scientist dan AdvancedAnalyticsPage merender 4 metrik + perbandingan segmen',
      (tester) async {
        final start = DateTime.utc(2026, 11, 20, 1);
        final pts = _buildRealisticHikeTrack(
          startUtc: start,
          secondHalfFatigueFactor: 1.3,
        );
        final s1 = TrackingSession(
          id: 'hist-1',
          startedAtUtc: start,
          endedAtUtc: pts.last.timestampUtc,
          mountainName: 'Gunung Gede',
          trailName: 'Putri',
          distanceM: 2400,
          movingSeconds: 1900,
          elevationGainM: 460,
          elevationLossM: 216,
          status: TrackingSessionStatus.completed,
          reachedSummit: true,
        );
        final repo = _MemoryTrackingRepo(
          sessions: <TrackingSession>[s1],
          pointsBySession: <String, List<TrackPoint>>{'hist-1': pts},
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: hiqeoDarkTheme,
            home: HistoryDetailPage(session: s1, repository: repo),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('history-terrain-donut-card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('history-km-split-card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('history-recovery-card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('sport-science-disclaimer')),
          findsOneWidget,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: hiqeoDarkTheme,
            home: AdvancedAnalyticsPage(
              repository: repo,
              nowLocal: DateTime(2026, 11, 22, 10),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('analytics-acwr-card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('analytics-eccentric-card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('analytics-altitude-vam-card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('analytics-fatigue-drift-card')),
          findsOneWidget,
        );
      },
    );
  });
}
