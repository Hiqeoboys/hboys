import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:nama_app/features/plus/application/plus_navigation.dart';
import 'package:nama_app/features/plus/presentation/route_estimate_page.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';

import '../support/plus_fixtures.dart';
import '../support/plus_widget_harness.dart';

/// Bujur yang membuat matahari terbenam jatuh sekitar pukul 18.00 waktu lokal
/// mesin uji, sehingga hasil estimasi tidak bergantung zona waktu.
double _localLongitude() =>
    15 * DateTime(2026, 3, 20).timeZoneOffset.inMinutes / 60;

List<LatLng> _routePoints({double lengthDegrees = 0.01}) => <LatLng>[
      LatLng(0, _localLongitude()),
      LatLng(0, _localLongitude() + lengthDegrees),
    ];

PlusRouteContext _route({List<LatLng>? points}) => PlusRouteContext(
      name: 'Rute Uji',
      points: points ?? _routePoints(),
    );

FakeTrackingRepository _repository({bool failSessions = false}) =>
    FakeTrackingRepository(
      sessions: <TrackingSession>[
        completedSession(
          id: 'sesi-1',
          startedAtUtc: DateTime.utc(2026, 2, 1, 1),
          distanceM: 3000,
          movingSeconds: 3600,
          elevationGainM: 150,
        ),
      ],
      failSessions: failSessions,
    );

void main() {
  testWidgets('menampilkan estimasi dari sesi selesai dan membagikan ringkasan',
      (tester) async {
    final repository = _repository();
    final sharer = RecordingTextSharer();

    await pumpPlusPage(
      tester,
      RouteEstimatePage(
        route: _route(),
        repository: repository,
        sharer: sharer,
        nowLocal: DateTime(2026, 3, 20, 6),
      ),
    );

    expect(find.text('Estimasi & itinerary'), findsOneWidget);
    expect(find.text('Rute Uji'), findsOneWidget);
    expect(find.text('PERKIRAAN TIBA DI PUNCAK'), findsOneWidget);
    expect(
      find.textContaining('1,1 km · mulai 06.00 · kecepatan pribadi 3,0 km/jam'),
      findsOneWidget,
    );
    expect(find.text('GARIS WAKTU'), findsOneWidget);
    expect(find.text('Mulai naik'), findsOneWidget);
    expect(find.text('Perkiraan tiba di puncak'), findsOneWidget);
    expect(find.text('Batas putar balik'), findsWidgets);
    expect(find.text('Matahari terbenam'), findsWidgets);
    expect(find.text('ITINERARY'), findsOneWidget);
    expect(find.text('Naik ke puncak'), findsOneWidget);
    expect(find.text('Istirahat di puncak'), findsOneWidget);
    expect(find.text('Turun ke titik awal'), findsOneWidget);
    expect(find.text('PERLENGKAPAN'), findsOneWidget);
    expect(find.text('Headlamp dan baterai cadangan'), findsOneWidget);
    expect(
      find.textContaining('Dengan kecepatan ini, perjalanan tidak muat'),
      findsNothing,
    );

    await tester.tap(find.text('Bagikan ke grup'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(sharer.calls, 1);
    expect(sharer.lastSubject, 'Estimasi Rute Uji');
    expect(sharer.lastText, contains('Estimasi Rute Uji (Hiqeo)'));
    expect(
      find.text('Ringkasan siap dibagikan ke grup.'),
      findsOneWidget,
    );
  });

  testWidgets('tanpa sesi selesai meminta menyelesaikan pendakian dahulu',
      (tester) async {
    await pumpPlusPage(
      tester,
      RouteEstimatePage(
        route: _route(),
        repository: FakeTrackingRepository(),
        sharer: RecordingTextSharer(),
        nowLocal: DateTime(2026, 3, 20, 6),
      ),
    );

    expect(find.text('Belum ada kecepatan pribadi'), findsOneWidget);
    expect(
      find.text(
        'Selesaikan minimal satu pendakian agar Hiqeo tahu kecepatan '
        'jelajahmu. Estimasi tidak memakai kecepatan pendaki lain.',
      ),
      findsOneWidget,
    );
    expect(find.text('Mulai pendakian'), findsOneWidget);
    expect(find.text('Bagikan ke grup'), findsNothing);
  });

  testWidgets('rute terlalu pendek dijelaskan tanpa tindakan', (tester) async {
    await pumpPlusPage(
      tester,
      RouteEstimatePage(
        route: _route(points: _routePoints(lengthDegrees: 0.0001)),
        repository: _repository(),
        sharer: RecordingTextSharer(),
        nowLocal: DateTime(2026, 3, 20, 6),
      ),
    );

    expect(find.text('Belum ada kecepatan pribadi'), findsOneWidget);
    expect(
      find.text('Rute ini terlalu pendek untuk diestimasi.'),
      findsOneWidget,
    );
    expect(find.text('Mulai pendakian'), findsNothing);
    expect(find.text('Bagikan ke grup'), findsNothing);
  });

  testWidgets('rute tanpa jalur tidak membaca riwayat pendakian',
      (tester) async {
    final repository = _repository();

    await pumpPlusPage(
      tester,
      RouteEstimatePage(
        route: _route(points: const <LatLng>[]),
        repository: repository,
        sharer: RecordingTextSharer(),
        nowLocal: DateTime(2026, 3, 20, 6),
      ),
    );

    expect(repository.watchCalls, 0);
    expect(find.text('Rute belum punya jalur'), findsOneWidget);
    expect(find.text('Buka Peta'), findsOneWidget);
    expect(
      find.textContaining('Rute Uji belum punya titik jalur'),
      findsOneWidget,
    );
  });

  testWidgets('galat baca riwayat bisa dicoba lagi', (tester) async {
    final repository = _repository(failSessions: true);

    await pumpPlusPage(
      tester,
      RouteEstimatePage(
        route: _route(),
        repository: repository,
        sharer: RecordingTextSharer(),
        nowLocal: DateTime(2026, 3, 20, 6),
      ),
    );

    expect(find.text('Estimasi belum bisa dibuat'), findsOneWidget);
    expect(
      find.text('Riwayat pendakian belum dapat dibaca.'),
      findsOneWidget,
    );

    repository.failSessions = false;
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();

    expect(repository.watchCalls, 2);
    expect(find.text('Estimasi belum bisa dibuat'), findsNothing);
    expect(find.text('GARIS WAKTU'), findsOneWidget);
  });

  testWidgets('mulai malam memunculkan peringatan gelap dan lampu cadangan',
      (tester) async {
    await pumpPlusPage(
      tester,
      RouteEstimatePage(
        route: _route(),
        repository: _repository(),
        sharer: RecordingTextSharer(),
        nowLocal: DateTime(2026, 3, 20, 23),
      ),
    );

    expect(
      find.text(
        'Dengan kecepatan ini, perjalanan tidak muat sebelum gelap. '
        'Mulai lebih pagi atau pilih target yang lebih dekat.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Lampu cadangan untuk turun gelap'),
      findsOneWidget,
    );
    expect(find.text('Trekking pole'), findsNothing);
  });

  testWidgets('lembar berbagi tidak tersedia memberi pesan yang jelas',
      (tester) async {
    await pumpPlusPage(
      tester,
      RouteEstimatePage(
        route: _route(),
        repository: _repository(),
        sharer: RecordingTextSharer(result: false),
        nowLocal: DateTime(2026, 3, 20, 6),
      ),
    );

    await tester.tap(find.text('Bagikan ke grup'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Lembar berbagi tidak tersedia di perangkat ini.'),
      findsOneWidget,
    );
  });
}
