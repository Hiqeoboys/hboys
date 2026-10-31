import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/plus/presentation/advanced_analytics_page.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';

import '../support/plus_fixtures.dart';
import '../support/plus_widget_harness.dart';

TrackingSession _session(
  String id,
  DateTime startedAtUtc, {
  required double distanceM,
  required int movingSeconds,
  required double elevationGainM,
}) =>
    completedSession(
      id: id,
      startedAtUtc: startedAtUtc,
      distanceM: distanceM,
      movingSeconds: movingSeconds,
      elevationGainM: elevationGainM,
    );

List<TrackingSession> _sessions() => <TrackingSession>[
      _session(
        'a',
        DateTime.utc(2026, 9, 1, 2),
        distanceM: 12000,
        movingSeconds: 18000,
        elevationGainM: 900,
      ),
      _session(
        'b',
        DateTime.utc(2026, 8, 1, 2),
        distanceM: 8000,
        movingSeconds: 14400,
        elevationGainM: 700,
      ),
      _session(
        'c',
        DateTime.utc(2026, 7, 1, 2),
        distanceM: 5000,
        movingSeconds: 10800,
        elevationGainM: 500,
      ),
      _session(
        'd',
        DateTime.utc(2026, 6, 1, 2),
        distanceM: 3000,
        movingSeconds: 7200,
        elevationGainM: 300,
      ),
      _session(
        'e',
        DateTime.utc(2025, 9, 1, 2),
        distanceM: 10000,
        movingSeconds: 14400,
        elevationGainM: 800,
      ),
      _session(
        'f',
        DateTime.utc(2025, 8, 1, 2),
        distanceM: 6000,
        movingSeconds: 10800,
        elevationGainM: 400,
      ),
    ];

Future<void> _pump(
  WidgetTester tester, {
  FakeTrackingRepository? repository,
}) async {
  await pumpPlusPage(
    tester,
    AdvancedAnalyticsPage(
      repository: repository ?? FakeTrackingRepository(sessions: _sessions()),
      nowLocal: DateTime(2026, 10, 31, 8),
    ),
  );
}

void main() {
  testWidgets('menampilkan analitik dari sesi selesai tanpa kategori kecepatan',
      (tester) async {
    await _pump(tester);

    expect(find.text('Analitik lanjutan'), findsOneWidget);
    expect(find.text('Dari sesi selesai di HP ini'), findsOneWidget);
    expect(find.byKey(const ValueKey('analytics-range-tabs')), findsOneWidget);
    expect(find.text('Terakhir'), findsOneWidget);
    expect(find.text('Tahun ini'), findsOneWidget);
    expect(find.text('Semua'), findsOneWidget);
    expect(find.text('Lima pendakian selesai terbaru'), findsOneWidget);
    expect(find.text('5 pendakian'), findsOneWidget);
    expect(find.text('38,0 km'), findsOneWidget);
    expect(find.text('3.200 m'), findsOneWidget);
    expect(find.text('18j 00m'), findsOneWidget);

    expect(find.text('Pace per kemiringan'), findsOneWidget);
    expect(find.text('Menanjak'), findsOneWidget);
    expect(find.text('Datar'), findsOneWidget);
    expect(find.text('Menurun'), findsOneWidget);
    expect(find.text('Belum cukup data'), findsNWidgets(3));

    expect(find.text('Kecepatan vertikal'), findsOneWidget);
    expect(find.text('178 m/jam'), findsOneWidget);

    expect(find.text('Rekor pribadi'), findsOneWidget);
    expect(find.text('Jarak terjauh'), findsOneWidget);
    expect(find.text('12.0 km'), findsOneWidget);
    expect(find.text('Elevasi terbesar'), findsOneWidget);
    expect(find.text('900 m'), findsOneWidget);
    expect(find.text('Durasi bergerak'), findsOneWidget);
    expect(find.text('5.0 jam'), findsOneWidget);
    expect(
      find.text('Tanpa rekor kecepatan; keselamatan di atas persaingan.'),
      findsOneWidget,
    );

    expect(find.text('Analisis kelelahan'), findsOneWidget);
    expect(
      find.textContaining('Butuh sesi minimal 1 km dengan titik GPS cukup'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Tidak ada kategori kecepatan di Hiqeo. Analitik dipakai untuk '
        'mengenali pola dan kelelahan, bukan memeringkat pendaki.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('tab rentang mengganti himpunan sesi', (tester) async {
    await _pump(tester);

    expect(find.text('5 pendakian'), findsOneWidget);

    await tester.tap(find.text('Tahun ini'));
    await tester.pumpAndSettle();

    expect(find.text('Pendakian selesai tahun ini'), findsOneWidget);
    expect(find.text('4 pendakian'), findsOneWidget);
    expect(find.text('28,0 km'), findsOneWidget);
    expect(find.text('2.400 m'), findsOneWidget);
    expect(find.text('14j 00m'), findsOneWidget);

    await tester.tap(find.text('Semua'));
    await tester.pumpAndSettle();

    expect(find.text('Seluruh riwayat di HP ini'), findsOneWidget);
    expect(find.text('6 pendakian'), findsOneWidget);
    expect(find.text('44,0 km'), findsOneWidget);
    expect(find.text('3.600 m'), findsOneWidget);
    expect(find.text('21j 00m'), findsOneWidget);
  });

  testWidgets('mengganti rentang memakai crossfade singkat', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Tahun ini'));
    await tester.pump();

    expect(find.text('5 pendakian'), findsOneWidget);
    expect(find.text('4 pendakian'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('5 pendakian'), findsNothing);
    expect(find.text('4 pendakian'), findsOneWidget);
  });

  testWidgets('sheet bandingkan segmen menjelaskan katalog yang belum ada',
      (tester) async {
    await _pump(tester);

    final row = find.text('Bandingkan segmen jalur');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.text('Bandingkan segmen jalur'), findsNWidgets(2));
    expect(
      find.textContaining('katalog jalur terverifikasi per gunung'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Katalog itu belum terisi di build ini'),
      findsOneWidget,
    );
    expect(find.text('Mengerti'), findsOneWidget);

    await tester.tap(find.text('Mengerti'));
    await tester.pumpAndSettle();

    expect(find.text('Bandingkan segmen jalur'), findsOneWidget);
  });

  testWidgets('tanpa sesi selesai menampilkan keadaan kosong', (tester) async {
    await _pump(tester, repository: FakeTrackingRepository());

    expect(find.text('Belum ada pendakian'), findsOneWidget);
    expect(find.text('Mulai pendakian'), findsOneWidget);
    expect(find.text('Bandingkan segmen jalur'), findsNothing);
  });

  testWidgets('galat baca riwayat bisa dicoba lagi', (tester) async {
    final repository = FakeTrackingRepository(failSessions: true);
    await _pump(tester, repository: repository);

    expect(find.text('Analitik belum bisa dibuka'), findsOneWidget);
    expect(find.text('Riwayat pendakian belum dapat dibaca.'), findsOneWidget);

    repository.failSessions = false;
    repository.sessions = _sessions();
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();

    expect(repository.watchCalls, 2);
    expect(find.text('Analitik belum bisa dibuka'), findsNothing);
    expect(find.text('5 pendakian'), findsOneWidget);
  });
}
