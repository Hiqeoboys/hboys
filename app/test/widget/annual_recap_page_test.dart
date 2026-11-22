import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/plus/application/plus_controller.dart';
import 'package:nama_app/features/plus/presentation/annual_recap_page.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
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
        DateTime.utc(2026, 3, 1, 2),
        distanceM: 5000,
        movingSeconds: 3600,
        elevationGainM: 100,
      ),
      _session(
        'b',
        DateTime.utc(2026, 6, 1, 2),
        distanceM: 3000,
        movingSeconds: 3600,
        elevationGainM: 600,
      ),
      _session(
        'lalu',
        DateTime.utc(2025, 10, 31, 5),
        distanceM: 1000,
        movingSeconds: 1800,
        elevationGainM: 50,
      ),
      _session(
        'luar-periode',
        DateTime.utc(2025, 11, 1, 2),
        distanceM: 9000,
        movingSeconds: 3600,
        elevationGainM: 500,
      ),
    ];

Map<String, List<TrackPoint>> _points() => <String, List<TrackPoint>>{
      'a': samplePoints(
        count: 5,
        startUtc: DateTime.utc(2026, 3, 1, 1),
        startAltitudeM: 1600,
        stepAltitudeM: 25,
      ),
      'b': samplePoints(
        count: 3,
        startUtc: DateTime.utc(2026, 6, 1, 1),
        startAltitudeM: 2180,
        stepAltitudeM: 10,
      ),
    };

FakeTrackingRepository _repository({bool failSessions = false}) =>
    FakeTrackingRepository(
      sessions: _sessions(),
      pointsBySession: _points(),
      failSessions: failSessions,
    );

Future<void> _pump(
  WidgetTester tester, {
  FakeTrackingRepository? repository,
  RecordingKartuExporter? exporter,
  PlusController? controller,
}) async {
  await pumpPlusPage(
    tester,
    AnnualRecapPage(
      repository: repository ?? _repository(),
      exporter: exporter ?? RecordingKartuExporter(),
      nowLocal: DateTime(2026, 10, 31, 8),
    ),
    controller: controller,
  );
}

void main() {
  testWidgets('kartu rekap memuat ringkasan tahun dan rute dengan penanda',
      (tester) async {
    await _pump(tester);

    expect(find.text('HIQEO · REKAP TAHUNAN'), findsOneWidget);
    expect(find.text('Rekap 2026'), findsOneWidget);
    expect(find.text('Pendakian'), findsOneWidget);
    expect(find.text('Jarak'), findsOneWidget);
    expect(find.text('Tanjakan'), findsOneWidget);
    expect(find.text('8,0 km'), findsNWidgets(2));
    expect(find.text('700 m'), findsOneWidget);

    expect(find.text('DIBANDINGKAN 2025'), findsOneWidget);
    expect(find.text('s.d. 31 Okt'), findsOneWidget);
    expect(find.text('2 (+1)'), findsOneWidget);
    expect(find.text('1,0 km'), findsOneWidget);

    expect(find.text('GUNUNG TERTINGGI'), findsOneWidget);
    expect(find.text('2.200 m'), findsOneWidget);
    expect(find.text('Titik GPS tertinggi · 1 Jun'), findsOneWidget);
    expect(find.text('PENDAKIAN TERBERAT'), findsOneWidget);
    expect(find.text('1 Jun'), findsOneWidget);
    expect(find.text('3,0 km · 600 m naik'), findsOneWidget);

    expect(find.text('RUTE TAHUN INI'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('recap-start-marker')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('recap-end-marker')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Lokasi hanya disembunyikan di gambar kartu'),
      findsOneWidget,
    );
    expect(find.text('Bagikan kartu'), findsOneWidget);
    expect(find.text('Sembunyikan lokasi di kartu'), findsOneWidget);
  });

  testWidgets('saklar menyembunyikan penanda lokasi tanpa menghapus rute',
      (tester) async {
    await _pump(tester);

    final switchFinder = find.byKey(
      const ValueKey<String>('recap-location-switch'),
    );

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('recap-start-marker')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('recap-end-marker')),
      findsNothing,
    );
    expect(find.text('RUTE TAHUN INI'), findsOneWidget);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('recap-start-marker')),
      findsOneWidget,
    );
  });

  testWidgets('bagikan kartu mengirim PNG dengan nama berkas tahun rekap',
      (tester) async {
    final exporter = RecordingKartuExporter();
    await _pump(tester, exporter: exporter);

    await tester.tap(find.text('Bagikan kartu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(exporter.captures, 1);
    expect(exporter.sharedFileName, 'hiqeo-rekap-2026.png');
    expect(exporter.sharedBytes, isNotNull);
    expect(find.text('Kartu siap dibagikan.'), findsOneWidget);
  });

  testWidgets('kegagalan membuat dan membagikan kartu dijelaskan',
      (tester) async {
    await _pump(
      tester,
      exporter: RecordingKartuExporter(captureResult: false),
    );

    await tester.tap(find.text('Bagikan kartu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Kartu belum bisa dibuat. Coba lagi.'), findsOneWidget);
  });

  testWidgets('lembar berbagi kartu tidak tersedia memberi pesan',
      (tester) async {
    await _pump(
      tester,
      exporter: RecordingKartuExporter(shareResult: false),
    );

    await tester.tap(find.text('Bagikan kartu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Lembar berbagi belum bisa dibuka di perangkat ini.'),
      findsOneWidget,
    );
  });

  testWidgets('lencana puncak hanya tampil bila flag aktif', (tester) async {
    final withBadges = await buildPlusController(peakBadges: true);
    await _pump(tester, controller: withBadges);

    expect(find.text('LENCANA PUNCAK'), findsOneWidget);
    expect(
      find.text(
        'Lencana puncak akan terbuka secara bertahap seiring bertambahnya '
        'daftar gunung yang didukung.',
      ),
      findsOneWidget,
    );

    final semantics = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel('Lencana puncak 1, terkunci'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Lencana puncak 5, terkunci'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('lencana puncak tidak tampil tanpa flag', (tester) async {
    await _pump(tester);

    expect(find.text('LENCANA PUNCAK'), findsNothing);
    expect(find.textContaining('Katalog puncak terverifikasi'), findsNothing);
  });

  testWidgets('tanpa sesi tahun ini menampilkan keadaan kosong', (tester) async {
    final repository = FakeTrackingRepository(
      sessions: <TrackingSession>[
        _session(
          'lama',
          DateTime.utc(2024, 5, 1, 2),
          distanceM: 4000,
          movingSeconds: 3600,
          elevationGainM: 200,
        ),
      ],
    );
    await _pump(tester, repository: repository);

    expect(find.text('Belum ada pendakian di 2026'), findsOneWidget);
    expect(find.text('Mulai pendakian'), findsOneWidget);
    expect(find.text('Bagikan kartu'), findsNothing);
    expect(find.text('Sembunyikan lokasi di kartu'), findsNothing);
  });

  testWidgets('galat baca riwayat bisa dicoba lagi', (tester) async {
    final repository = _repository(failSessions: true);
    await _pump(tester, repository: repository);

    expect(find.text('Rekap belum bisa dibuka'), findsOneWidget);
    expect(find.text('Riwayat pendakian belum dapat dibaca.'), findsOneWidget);

    repository.failSessions = false;
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();

    expect(repository.watchCalls, 2);
    expect(find.text('Rekap belum bisa dibuka'), findsNothing);
    expect(find.text('Rekap 2026'), findsOneWidget);
  });
}
