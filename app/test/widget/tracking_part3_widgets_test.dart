import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/history/presentation/history_page.dart';
import 'package:nama_app/features/home/last_trip_summary_card.dart';
import 'package:nama_app/features/kartu/domain/kartu_data.dart';
import 'package:nama_app/features/kartu/presentation/kartu_page.dart';
import 'package:nama_app/features/tracking/application/tracking_controller.dart';
import 'package:nama_app/features/tracking/application/tracking_status.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_diagnostics.dart';
import 'package:nama_app/features/tracking/domain/tracking_repository.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';
import 'package:nama_app/features/tracking/presentation/tracking_page.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

class _FakeRepo implements TrackingRepository {
  _FakeRepo(this._sessions, this._points);

  final List<TrackingSession> _sessions;
  final Map<String, List<TrackPoint>> _points;

  @override
  Stream<List<TrackingSession>> watchSessions() =>
      Stream<List<TrackingSession>>.value(_sessions);

  @override
  Future<List<TrackPoint>> points(String sessionId) async =>
      _points[sessionId] ?? const <TrackPoint>[];

  @override
  Future<TrackingSession?> findSession(String id) async {
    for (final s in _sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Future<TrackingSession?> findActiveSession() async => null;

  @override
  Future<void> saveSession(TrackingSession session) async {}

  @override
  Future<void> deleteSession(String id) async {}

  @override
  Future<void> addPoint(String sessionId, TrackPoint point) async {}

  @override
  Future<void> clearPoints(String sessionId) async {}

  @override
  Future<TrackPoint?> latestPoint(String sessionId) async => null;
}

final _startUtc = DateTime(2026, 11, 20, 6, 30).toUtc();

List<TrackPoint> _jogPoints() => <TrackPoint>[
      TrackPoint(
        lat: -6.900,
        lon: 107.600,
        altitudeM: 700,
        accuracyM: 5,
        timestampUtc: _startUtc,
      ),
      TrackPoint(
        lat: -6.902,
        lon: 107.603,
        altitudeM: 715,
        accuracyM: 5,
        timestampUtc: _startUtc.add(const Duration(minutes: 10)),
      ),
      TrackPoint(
        lat: -6.904,
        lon: 107.601,
        altitudeM: 708,
        accuracyM: 5,
        timestampUtc: _startUtc.add(const Duration(minutes: 20)),
      ),
    ];

TrackingSession _jogSession() => TrackingSession(
      id: 'jog-1',
      startedAtUtc: _startUtc,
      endedAtUtc: _startUtc.add(const Duration(minutes: 30)),
      distanceM: 5250,
      movingSeconds: 1800,
      elevationGainM: 42,
      elevationLossM: 38,
      status: TrackingSessionStatus.completed,
      activityType: TrackingSession.activityJogging,
    );

TrackingSession _hikeSession() => TrackingSession(
      id: 'hike-1',
      startedAtUtc: _startUtc.subtract(const Duration(days: 2)),
      endedAtUtc: _startUtc.subtract(const Duration(days: 2, hours: -5)),
      distanceM: 11200,
      movingSeconds: 14400,
      elevationGainM: 980,
      status: TrackingSessionStatus.completed,
      reachedSummit: true,
      mountainName: 'Gunung Gede',
      trailName: 'Via Cibodas',
      activityType: TrackingSession.activityHiking,
    );

void main() {
  testWidgets(
      'banner hemat baterai TIDAK muncul karena false-positive baterai/akurasi bila OS power save mati',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final diag = TrackingDiagnostics()..avgAccuracyM = 85;
    final status = TrackingStatus(
      sessionId: 's1',
      sessionStatus: TrackingSessionStatus.active,
      startedAtUtc: _startUtc,
      distanceM: 1200,
      movingSeconds: 600,
      elapsedSeconds: 620,
      elevationGainM: 20,
      elevationLossM: 5,
      isMoving: true,
      pointCount: 12,
      profile: PowerProfile.critical,
      lastValidFixAtUtc: _startUtc,
      diagnostics: diag,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: Scaffold(
          body: TrackingView(
            phase: TrackingPhase.recording,
            status: status,
            permissionReady: true,
            profile: PowerProfile.critical,
            isPowerSaveMode: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Mode hemat baterai aktif, akurasi GPS bisa menurun'),
      findsNothing,
    );
  });

  testWidgets('modal Mulai tracking menampilkan pilihan Hiking dan Jogging',
      (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await showTrackingModeChoiceModal(context);
              },
              child: const Text('Buka pilihan'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Buka pilihan'));
    await tester.pumpAndSettle();
    expect(find.text('Hiking'), findsOneWidget);
    expect(find.text('Jogging'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('tracking-mode-jogging')));
    await tester.pumpAndSettle();
    expect(picked, TrackingSession.activityJogging);

    await tester.tap(find.text('Buka pilihan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('tracking-mode-hiking')));
    await tester.pumpAndSettle();
    expect(picked, TrackingSession.activityHiking);
  });

  testWidgets(
      'HistoryPage memisahkan tab Pendakian dan Riwayat Jogging serta menampilkan garis rute di detail jogging',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeRepo(
      <TrackingSession>[_hikeSession(), _jogSession()],
      <String, List<TrackPoint>>{'jog-1': _jogPoints()},
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: HistoryPage(repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    // Tab Pendakian aktif awalnya
    expect(find.text('Gunung Gede'), findsOneWidget);
    expect(find.text('Sampai puncak'), findsOneWidget);
    expect(find.textContaining('Jogging '), findsNothing);

    // Pindah ke tab Riwayat Jogging
    await tester.tap(find.byKey(const ValueKey<String>('history-tab-jogging')));
    await tester.pumpAndSettle();
    expect(find.text('Gunung Gede'), findsNothing);
    expect(find.text('Sampai puncak'), findsNothing);
    expect(find.text('Jogging 20 Nov 2026'), findsOneWidget);

    // Buka detail jogging -> menampilkan statistik & garis rute tanpa badge puncak
    await tester.tap(find.byKey(const ValueKey<String>('history-item-jog-1')));
    await tester.pumpAndSettle();
    expect(find.text('Detail jogging'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('history-jogging-route')), findsOneWidget);
    expect(find.text('Sampai puncak'), findsNothing);
    expect(find.text('Belum sampai puncak'), findsNothing);
    expect(find.text('Lihat kartu'), findsOneWidget);
  });

  testWidgets(
      'Kartu Beranda dan KartuPage mendukung sesi Jogging dengan rute GPS dan sakelar sembunyikan titik awal/akhir',
      (tester) async {
    tester.view.physicalSize = const Size(390, 960);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final jog = _jogSession();
    final pts = _jogPoints();
    final data = KartuData.fromSession(jog, pts)!;

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: Scaffold(
          body: LastTripSummaryCard(data: data, onViewKartu: () {}),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('JOGGING TERAKHIR'), findsOneWidget);
    expect(find.text('Jogging 20 Nov 2026'), findsOneWidget);
    expect(find.text('PUNCAK'), findsNothing);
    expect(find.text('Lihat kartu'), findsOneWidget);

    final repo = _FakeRepo(
      <TrackingSession>[jog],
      <String, List<TrackPoint>>{'jog-1': pts},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: KartuPage(repository: repo, sessionId: 'jog-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('kartu-profile')), findsOneWidget);
    expect(find.text('TERTINGGI'), findsOneWidget);
    expect(find.text('Sembunyikan titik awal dan akhir'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('kartu-start-marker')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('kartu-hide-endpoints')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('kartu-start-marker')), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('kartu-style-peta')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('kartu-route')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('kartu-start-marker')), findsNothing);
  });
}
