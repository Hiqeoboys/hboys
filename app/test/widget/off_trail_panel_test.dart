import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:nama_app/features/map/domain/map_package.dart';
import 'package:nama_app/features/map/presentation/off_trail_panel.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';

final _trail = MapTrail(
  id: 'utama',
  name: 'Jalur Utama',
  source: 'uji lapangan',
  verified: false,
  points: const [
    LatLng(-7.5, 110.4),
    LatLng(-7.49, 110.41),
  ],
);

TrackPoint _point({
  required double lat,
  required int second,
}) {
  return TrackPoint(
    lat: lat,
    lon: 110.4,
    timestampUtc: DateTime.utc(2026, 10, 25, 1, 0, second),
    accuracyM: 5,
  );
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('menunggu GPS sebelum ada titik pertama', (tester) async {
    await tester.pumpWidget(_app(OffTrailPanel(
      trail: _trail,
      latestPoint: null,
    )));

    expect(find.text('Jalur Utama'), findsOneWidget);
    expect(find.text('Menunggu GPS'), findsOneWidget);
    expect(find.textContaining('belum terverifikasi lapangan'), findsOneWidget);
  });

  testWidgets('tanpa jalur memberi petunjuk pemilihan', (tester) async {
    await tester.pumpWidget(_app(const OffTrailPanel(
      trail: null,
      latestPoint: null,
    )));

    expect(
      find.text('Pilih paket dan jalur untuk mengaktifkan deteksi.'),
      findsOneWidget,
    );
  });

  testWidgets('tiga titik jauh memicu keluar jalur lalu kembali', (tester) async {
    await tester.pumpWidget(_app(OffTrailPanel(
      trail: _trail,
      latestPoint: _point(lat: -7.5, second: 0),
    )));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('off-trail-status'))).data,
      'Di jalur',
    );

    for (var index = 1; index <= 3; index++) {
      await tester.pumpWidget(_app(OffTrailPanel(
        trail: _trail,
        latestPoint: _point(lat: -7.501, second: index),
      )));
      await tester.pump();
    }

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('off-trail-status'))).data,
      'Di luar jalur',
    );
    expect(find.textContaining('m dari jalur'), findsOneWidget);

    await tester.pumpWidget(_app(OffTrailPanel(
      trail: _trail,
      latestPoint: _point(lat: -7.5, second: 4),
    )));
    await tester.pump();

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('off-trail-status'))).data,
      'Di jalur',
    );
  });

  testWidgets('jalur terverifikasi memakai badge terverifikasi', (tester) async {
    final verified = MapTrail(
      id: 'aman',
      name: 'Jalur Aman',
      source: 'tim verifikasi',
      verified: true,
      verifiedAtUtc: DateTime.utc(2026, 9, 1),
      verifiedBy: 'Tim',
      points: const [
        LatLng(-7.5, 110.4),
        LatLng(-7.49, 110.41),
      ],
    );
    await tester.pumpWidget(_app(OffTrailPanel(
      trail: verified,
      latestPoint: _point(lat: -7.5, second: 0),
    )));

    expect(find.text('Terverifikasi'), findsOneWidget);
    expect(find.text('Belum terverifikasi'), findsNothing);
  });
}
