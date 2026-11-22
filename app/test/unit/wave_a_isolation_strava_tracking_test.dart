import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/analytics/domain/sport_science_analytics.dart';
import 'package:nama_app/features/groups/application/group_selection.dart';
import 'package:nama_app/features/history/presentation/history_page.dart';
import 'package:nama_app/features/plus/domain/hike_analytics.dart';
import 'package:nama_app/features/preparation/application/packing_list_store.dart';
import 'package:nama_app/features/profile/application/body_metrics_store.dart';
import 'package:nama_app/features/profile/domain/profile_summary.dart';
import 'package:nama_app/features/social/data/social_unread_store.dart';
import 'package:nama_app/features/tracking/application/tracking_controller.dart';
import 'package:nama_app/features/tracking/application/tracking_status.dart';
import 'package:nama_app/features/tracking/domain/elevation_processor.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_engine.dart';
import 'package:nama_app/features/tracking/domain/tracking_repository.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';
import 'package:nama_app/features/tracking/presentation/tracking_page.dart';
import 'package:nama_app/features/tracking/presentation/widgets/elevation_sparkline.dart';
import 'package:nama_app/features/tracking/presentation/widgets/live_route_polyline_view.dart';
import 'package:nama_app/infrastructure/auth/active_account_scope.dart';
import 'package:nama_app/infrastructure/database/database_connection.dart';
import 'package:nama_app/infrastructure/database/repositories/drift_tracking_repository.dart';
import 'package:nama_app/infrastructure/location/pedometer_step_counter.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

final DateTime _t0 = DateTime.utc(2026, 11, 22, 6, 0);
const double _metersPerDegLat = 111195.0;

TrackPoint _pt({
  required double metersNorth,
  double metersEast = 0,
  required int sec,
  double accuracyM = 6,
  double? altitudeM,
  double? altitudeAccuracyM = 5,
  double? speedMps = 1.2,
}) {
  const baseLat = -6.9;
  final cosLat = math.cos(baseLat * math.pi / 180).abs();
  return TrackPoint(
    lat: baseLat + metersNorth / _metersPerDegLat,
    lon: 107.6 + metersEast / (_metersPerDegLat * cosLat),
    timestampUtc: _t0.add(Duration(seconds: sec)),
    accuracyM: accuracyM,
    altitudeM: altitudeM,
    altitudeAccuracyM: altitudeAccuracyM,
    speedMps: speedMps,
  );
}

class _FakeHistoryRepo implements TrackingRepository {
  _FakeHistoryRepo(this.sessions, this.pointsMap);
  final List<TrackingSession> sessions;
  final Map<String, List<TrackPoint>> pointsMap;

  @override
  Future<void> addPoint(String sessionId, TrackPoint point) async {}
  @override
  Future<void> clearPoints(String sessionId) async {}
  @override
  Future<void> deleteSession(String id) async {}
  @override
  Future<TrackingSession?> findActiveSession() async => null;
  @override
  Future<TrackingSession?> findSession(String id) async => null;
  @override
  Future<TrackPoint?> latestPoint(String sessionId) async => null;
  @override
  Future<List<TrackPoint>> points(String sessionId) async =>
      pointsMap[sessionId] ?? const <TrackPoint>[];
  @override
  Future<void> saveSession(TrackingSession session) async {}
  @override
  Stream<List<TrackingSession>> watchSessions() =>
      Stream<List<TrackingSession>>.value(sessions);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ActiveAccountScope.setActiveUserId(null);
  });

  tearDown(() {
    ActiveAccountScope.setActiveUserId(null);
  });

  group('#3 Total Local Data Isolation Per Account', () {
    test('SQLite DriftTrackingRepository mempartisi ketat sesi antar-akun',
        () async {
      final db = openInMemoryAppDatabase();
      final repo = DriftTrackingRepository(db);
      addTearDown(() async {
        repo.disposeDatabaseRegistration();
        await db.close();
      });

      // Login sebagai @amadeus lalu simpan 1 sesi pendakian
      ActiveAccountScope.setActiveUserId('user-amadeus');
      await repo.saveSession(
        TrackingSession(
          id: 'sesi-amadeus-1',
          startedAtUtc: _t0,
          endedAtUtc: _t0.add(const Duration(hours: 1)),
          mountainName: 'Gunung Gede',
          distanceM: 5400,
          movingSeconds: 3600,
          elevationGainM: 420,
          status: TrackingSessionStatus.completed,
        ),
      );

      final amadeusSessions = await repo.watchSessions().first;
      expect(amadeusSessions, hasLength(1));
      expect(amadeusSessions.first.ownerUserId, 'user-amadeus');

      // Ganti akun ke @hiqeo -> nol total, tidak boleh bocor!
      ActiveAccountScope.setActiveUserId('user-hiqeo');
      final hiqeoSessions = await repo.watchSessions().first;
      expect(hiqeoSessions, isEmpty);
      expect(await repo.findSession('sesi-amadeus-1'), isNull);
      expect(
        ProfileSummary.fromSessions(hiqeoSessions).hikeCountLabel,
        '0',
      );
      expect(
        ProfileSummary.fromSessions(hiqeoSessions).distanceLabel,
        '0 km',
      );
      expect(
        ProfileSummary.fromSessions(hiqeoSessions).elevationGainLabel,
        '0 m',
      );

      // Logout ke guest -> sesi @amadeus tetap terisolasi
      ActiveAccountScope.setActiveUserId(null);
      expect(await repo.watchSessions().first, isEmpty);

      // Login kembali sebagai @amadeus -> sesi tetap utuh
      ActiveAccountScope.setActiveUserId('user-amadeus');
      final restored = await repo.watchSessions().first;
      expect(restored.map((s) => s.id), <String>['sesi-amadeus-1']);
    });

    test('Store preferensi (Packing, BodyMetrics, SocialGroups, Unread) terisolasi per akun',
        () async {
      final packing = PackingListStore();
      final metrics = BodyMetricsStore();
      final groups = SocialGroupsStore();
      var unreadUser = 'user-amadeus';
      final unread = SocialUnreadStore(
        currentUserIdProvider: () => unreadUser,
      );

      // Akun A
      ActiveAccountScope.setActiveUserId('user-amadeus');
      await packing.toggleSelectItem('carrier');
      await metrics.update(weightKg: 72, heightCm: 175);
      await groups.markGroupDeleted('del-group-a');
      await unread.markGroupRead('room-1', at: _t0, lastMessageId: 'msg-a');

      // Pindah ke Akun B & reset
      ActiveAccountScope.setActiveUserId('user-hiqeo');
      unreadUser = 'user-hiqeo';
      await packing.resetForAccountChange();
      await metrics.resetForAccountChange();
      await groups.resetForAccountChange();
      unread.clearForAccountChange();

      expect(packing.selectedIds, isEmpty);
      expect(metrics.hasCustomWeight, isFalse);
      expect(groups.deletedGroupIds, isEmpty);
      expect((await unread.getGroupReadCursor('room-1')).hasCursor, isFalse);

      // Kembali ke Akun A -> data Akun A masih ada tanpa tercampur Akun B
      ActiveAccountScope.setActiveUserId('user-amadeus');
      unreadUser = 'user-amadeus';
      await packing.resetForAccountChange();
      await metrics.resetForAccountChange();
      await groups.resetForAccountChange();
      expect(packing.selectedIds, contains('carrier'));
      expect(metrics.weightKg, 72);
      expect(groups.deletedGroupIds, contains('del-group-a'));
      expect((await unread.getGroupReadCursor('room-1')).lastReadMessageId, 'msg-a');
    });
  });

  group('#4 Konsistensi Statistik Profil vs Riwayat & Analitik', () {
    test('ProfileSummary hanya menjumlahkan sesi Hiking selesai yang valid',
        () {
      final sessions = <TrackingSession>[
        TrackingSession(
          id: 'hike-valid',
          startedAtUtc: _t0,
          distanceM: 400,
          movingSeconds: 600,
          elevationGainM: 34,
          status: TrackingSessionStatus.completed,
        ),
        TrackingSession(
          id: 'jog-valid',
          startedAtUtc: _t0.add(const Duration(days: 1)),
          distanceM: 1200,
          movingSeconds: 420,
          elevationGainM: 9,
          activityType: TrackingSession.activityJogging,
          status: TrackingSessionStatus.completed,
        ),
        TrackingSession(
          id: 'hike-empty-aborted',
          startedAtUtc: _t0.add(const Duration(days: 2)),
          distanceM: 0,
          movingSeconds: 0,
          elevationGainM: 0,
          status: TrackingSessionStatus.completed,
        ),
      ];

      final summary = ProfileSummary.fromSessions(sessions);
      expect(summary.hikeCount, 1);
      expect(summary.distanceM, 400);
      expect(summary.elevationGainM, 34); // TIDAK menjadi 34 + 9 = 43!
      expect(summary.distanceLabel, '0,4 km');
      expect(summary.elevationGainLabel, '34 m');

      final hikingForHistory = validCompletedHikingSessions(sessions);
      final historyElevationSum = hikingForHistory.fold<double>(
        0,
        (acc, s) => acc + canonicalSessionElevationGain(s),
      );
      expect(historyElevationSum, summary.elevationGainM);
    });
  });

  group('#5 Tampilan Rute GPS Mode Jogging & Kartu Riwayat Jogging', () {
    testWidgets(
      'TrackingView mode jogging merender LiveRoutePolylineView sebagai pengganti grafik elevasi',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: hiqeoLightTheme,
            home: Scaffold(
              body: TrackingView(
                phase: TrackingPhase.recording,
                profile: PowerProfile.normal,
                permissionReady: true,
                activityType: TrackingSession.activityJogging,
                status: TrackingStatus(
                  sessionId: 'jog-1',
                  sessionStatus: TrackingSessionStatus.active,
                  startedAtUtc: _t0,
                  distanceM: 1250,
                  movingSeconds: 420,
                  elapsedSeconds: 430,
                  elevationGainM: 4,
                  elevationLossM: 3,
                  isMoving: true,
                  pointCount: 25,
                  profile: PowerProfile.normal,
                  paceSecPerKm: 336,
                  verticalSpeedMph: 0,
                  lastValidFixAtUtc: _t0.add(const Duration(seconds: 420)),
                  activityType: TrackingSession.activityJogging,
                ),
                routePoints: const <Offset>[
                  Offset(0.1, 0.9),
                  Offset(0.5, 0.5),
                  Offset(0.9, 0.2),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('tracking-jogging-live-route')),
          findsOneWidget,
        );
        expect(find.byType(MonotoneElevationSparkline), findsNothing);
        expect(find.text('Rute GPS'), findsOneWidget);
        expect(find.text('Mode Jogging'), findsOneWidget);
      },
    );

    testWidgets(
      'HistoryPage tab Jogging menampilkan kartu pratinjau rute GPS',
      (tester) async {
        final jogSession = TrackingSession(
          id: 'jog-hist-1',
          startedAtUtc: _t0,
          endedAtUtc: _t0.add(const Duration(minutes: 25)),
          distanceM: 3200,
          movingSeconds: 1200,
          elevationGainM: 12,
          activityType: TrackingSession.activityJogging,
          status: TrackingSessionStatus.completed,
        );
        final repo = _FakeHistoryRepo(
          <TrackingSession>[jogSession],
          <String, List<TrackPoint>>{
            'jog-hist-1': <TrackPoint>[
              _pt(metersNorth: 0, metersEast: 0, sec: 0, altitudeM: 700),
              _pt(metersNorth: 300, metersEast: 200, sec: 120, altitudeM: 702),
              _pt(metersNorth: 600, metersEast: 500, sec: 240, altitudeM: 700),
            ],
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: hiqeoLightTheme,
            home: HistoryPage(repository: repo),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey<String>('history-tab-jogging')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('history-jogging-route-preview-jog-hist-1')),
          findsOneWidget,
        );
        expect(find.byType(LiveRoutePolylineView), findsOneWidget);
      },
    );
  });

  group('#6 Strava Calculation Engine, Step Anti-Spike, & Sport Science Guard',
      () {
    test('Diam & menggerakkan HP naik-turun menjaga distance=0, movingTime=0, ascent=0',
        () {
      final engine = TrackingEngine();
      TrackingSnapshot? last;
      for (var s = 0; s <= 90; s += 2) {
        final altSwing = 850.0 + (s.isEven ? 12.0 : -12.0);
        engine.onFix(
          _pt(
            metersNorth: s.isEven ? 0.0 : 0.7, // drift GPS kecil < 2.5 m
            sec: s,
            accuracyM: 6,
            speedMps: 0.0,
            altitudeM: altSwing,
            altitudeAccuracyM: 4,
          ),
        );
        last = engine.latestSnapshot;
      }

      expect(last, isNotNull);
      expect(last!.distanceM, 0);
      expect(last.movingTime, Duration.zero);
      expect(last.gainM, 0);
      expect(last.lossM, 0);
      expect(last.verticalSpeedMph, 0);
      expect(last.isMoving, isFalse);
    });

    test('Jalan datar 300 m dengan noise altitud GPS +/-6 m tetap 0 m tanjakan',
        () {
      final engine = TrackingEngine();
      TrackingSnapshot? last;
      for (var s = 0; s <= 240; s += 3) {
        final wave = math.sin(s * 0.7) * 6.0;
        last = engine.onFix(
              _pt(
                metersNorth: s * 1.25,
                sec: s,
                accuracyM: 7,
                speedMps: 1.25,
                altitudeM: 500.0 + wave,
              ),
            ) ??
            last;
      }

      expect(last, isNotNull);
      expect(last!.distanceM, closeTo(300, 3));
      expect(last.gainM, 0);
      expect(last.lossM, 0);
      expect(last.verticalSpeedMph, 0);
      expect(ElevationProcessor().thresholdM, ElevationProcessor.gpsThresholdM);
      expect(
        ElevationProcessor(useBarometer: true).thresholdM,
        ElevationProcessor.barometerThresholdM,
      );
    });

    test(
        'PedometerStepCounter mengabaikan batch flush 2 detik awal dan lonjakan diam > 4 saat GPS berhenti',
        () async {
      final ctrl = StreamController<int>();
      addTearDown(ctrl.close);
      var clockNow = _t0;
      final counter = PedometerStepCounter(
        stepStreamOverride: ctrl.stream,
        persistBaseline: false,
        clockNowUtc: () => clockNow,
        calibrationWindow: const Duration(seconds: 2),
      );
      addTearDown(counter.dispose);

      // Mulai sambil GPS masih diam
      counter.syncSession(
        sessionId: 'sesi-anti-spike',
        activityPermissionGranted: true,
        isGpsMoving: false,
      );

      ctrl.add(10000);
      await Future<void>.delayed(Duration.zero);
      expect(counter.sensorSteps, 0);

      // Hardware Android flush +25 langkah dalam 1 detik pertama -> harus di-rebase ke 0
      clockNow = _t0.add(const Duration(seconds: 1));
      ctrl.add(10025);
      await Future<void>.delayed(Duration.zero);
      expect(counter.sensorSteps, 0);

      // Setelah kalibrasi (dt = 10 s), GPS masih 0 m/s tapi ada lonjakan +12 langkah -> tetap 0
      clockNow = _t0.add(const Duration(seconds: 10));
      ctrl.add(10037);
      await Future<void>.delayed(Duration.zero);
      expect(counter.sensorSteps, 0);

      // Sekarang GPS benar-benar bergerak -> langkah berikutnya dihitung akurat
      counter.syncSession(
        sessionId: 'sesi-anti-spike',
        activityPermissionGranted: true,
        isGpsMoving: true,
      );
      clockNow = _t0.add(const Duration(seconds: 25));
      ctrl.add(10137);
      await Future<void>.delayed(Duration.zero);
      expect(counter.sensorSteps, 100);
    });

    test(
        'SportScienceAnalytics mengembalikan null (tampil —) untuk VAM & Kec. Turun pada jalan datar/singkat',
        () {
      final flatPoints = <TrackPoint>[
        for (var s = 0; s <= 180; s += 5)
          _pt(
            metersNorth: s * 1.4,
            sec: s,
            speedMps: 1.4,
            altitudeM: 100.0 + math.sin(s * 0.5) * 2.5,
          ),
      ];
      final flatSession = TrackingSession(
        id: 'flat-jog-or-walk',
        startedAtUtc: _t0,
        endedAtUtc: _t0.add(const Duration(seconds: 180)),
        distanceM: 252,
        movingSeconds: 180,
        elevationGainM: 4,
        elevationLossM: 5,
        status: TrackingSessionStatus.completed,
      );
      final report = CrossSessionSportScienceReport.build(
        allSamples: <HikeSample>[
          HikeSample(session: flatSession, points: flatPoints),
        ],
        rangeSamples: <HikeSample>[
          HikeSample(session: flatSession, points: flatPoints),
        ],
        nowLocal: DateTime(2026, 11, 22, 10),
      );

      expect(report.altitudeVam.steepVamMPerHour, isNull);
      expect(report.eccentricDownhill.avgDescentSpeedMPerHour, isNull);
      expect(
        report.eccentricDownhill.kneeLoadLabel.toLowerCase(),
        isNot(contains('tinggi')),
      );
    });
  });
}
