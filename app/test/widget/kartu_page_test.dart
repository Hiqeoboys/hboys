import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/kartu/application/kartu_exporter.dart';
import 'package:nama_app/features/kartu/application/kartu_photo_picker.dart';
import 'package:nama_app/features/kartu/presentation/kartu_card.dart';
import 'package:nama_app/features/kartu/presentation/kartu_page.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_repository.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';

final _startedAtUtc = DateTime(2026, 10, 30, 7, 12).toUtc();

class _FakeTrackingRepository implements TrackingRepository {
  _FakeTrackingRepository({
    required List<TrackingSession> sessions,
    Map<String, List<TrackPoint>> points = const <String, List<TrackPoint>>{},
  })  : _sessions = sessions,
        _points = points;

  final List<TrackingSession> _sessions;
  final Map<String, List<TrackPoint>> _points;
  bool failSessions = false;

  @override
  Stream<List<TrackingSession>> watchSessions() => failSessions
      ? Stream<List<TrackingSession>>.error(StateError('basis data rusak'))
      : Stream<List<TrackingSession>>.value(_sessions);

  @override
  Future<List<TrackPoint>> points(String sessionId) async =>
      _points[sessionId] ?? const <TrackPoint>[];

  @override
  Future<void> saveSession(TrackingSession session) async {}

  @override
  Future<TrackingSession?> findSession(String id) async {
    for (final session in _sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  @override
  Future<TrackingSession?> findActiveSession() async => null;

  @override
  Future<void> deleteSession(String id) async {}

  @override
  Future<void> addPoint(String sessionId, TrackPoint point) async {}

  @override
  Future<TrackPoint?> latestPoint(String sessionId) async => null;
}

class _FakeExporter implements KartuExporter {
  Uint8List? png = Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10]);
  bool saveResult = true;
  bool shareResult = true;
  int captures = 0;
  final List<String> savedNames = <String>[];
  final List<String> sharedNames = <String>[];

  @override
  Future<Uint8List?> capturePng(GlobalKey boundaryKey) async {
    captures++;
    return png;
  }

  @override
  Future<bool> savePng(Uint8List bytes, String fileName) async {
    savedNames.add(fileName);
    return saveResult;
  }

  @override
  Future<bool> sharePng(Uint8List bytes, String fileName) async {
    sharedNames.add(fileName);
    return shareResult;
  }
}

class _FakePhotoPicker implements KartuPhotoPicker {
  _FakePhotoPicker(this.bytes);

  final Uint8List? bytes;
  int calls = 0;

  @override
  Future<Uint8List?> pick() async {
    calls++;
    return bytes;
  }
}

class _Harness {
  _Harness({
    required this.repository,
    required this.exporter,
    required this.photoPicker,
  });

  final _FakeTrackingRepository repository;
  final _FakeExporter exporter;
  final _FakePhotoPicker photoPicker;
}

TrackingSession _session({
  String id = 'sesi-1',
  TrackingSessionStatus status = TrackingSessionStatus.completed,
  DateTime? startedAtUtc,
  double distanceM = 12840,
  int movingSeconds = 25920,
  double elevationGainM = 1140,
}) =>
    TrackingSession(
      id: id,
      startedAtUtc: startedAtUtc ?? _startedAtUtc,
      endedAtUtc: (startedAtUtc ?? _startedAtUtc).add(
        const Duration(hours: 8),
      ),
      distanceM: distanceM,
      movingSeconds: movingSeconds,
      elevationGainM: elevationGainM,
      status: status,
    );

List<TrackPoint> _points() => <TrackPoint>[
      TrackPoint(
        lat: -6.800,
        lon: 106.800,
        timestampUtc: _startedAtUtc,
        accuracyM: 8,
        altitudeM: 1500,
      ),
      TrackPoint(
        lat: -6.799,
        lon: 106.800,
        timestampUtc: _startedAtUtc.add(const Duration(minutes: 30)),
        accuracyM: 8,
        altitudeM: 1900,
      ),
      TrackPoint(
        lat: -6.798,
        lon: 106.800,
        timestampUtc: _startedAtUtc.add(const Duration(minutes: 60)),
        accuracyM: 8,
        altitudeM: 1800,
      ),
      TrackPoint(
        lat: -6.797,
        lon: 106.800,
        timestampUtc: _startedAtUtc.add(const Duration(minutes: 90)),
        accuracyM: 8,
        altitudeM: 1700,
      ),
    ];

Future<_Harness> _pump(
  WidgetTester tester, {
  List<TrackingSession>? sessions,
  Uint8List? photoBytes,
  bool failSessions = false,
  String? sessionId,
}) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final list = sessions ?? <TrackingSession>[_session()];
  final repository = _FakeTrackingRepository(
    sessions: list,
    points: <String, List<TrackPoint>>{
      for (final session in list) session.id: _points(),
    },
  )..failSessions = failSessions;
  final exporter = _FakeExporter();
  final photoPicker = _FakePhotoPicker(photoBytes);

  await tester.pumpWidget(
    MaterialApp(
      theme: hiqeoLightTheme,
      home: KartuPage(
        repository: repository,
        exporter: exporter,
        photoPicker: photoPicker,
        sessionId: sessionId,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(
    repository: repository,
    exporter: exporter,
    photoPicker: photoPicker,
  );
}

Future<void> _tapAndPump(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey<String>(key)));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('tanpa sesi selesai, layar jujur dan tombol ekspor mati',
      (tester) async {
    final harness = await _pump(
      tester,
      sessions: <TrackingSession>[
        _session(id: 'aktif', status: TrackingSessionStatus.active),
      ],
    );

    expect(find.text('Belum ada pendakian selesai'), findsOneWidget);
    expect(find.byType(KartuCard), findsNothing);
    await _tapAndPump(tester, 'kartu-save');
    await _tapAndPump(tester, 'kartu-share');
    await _tapAndPump(tester, 'kartu-photo-change');
    expect(harness.exporter.captures, 0);
    expect(harness.exporter.savedNames, isEmpty);
    expect(harness.exporter.sharedNames, isEmpty);
    expect(harness.photoPicker.calls, 0);
  });

  testWidgets('menampilkan metrik dan profil dari sesi yang tersimpan',
      (tester) async {
    await _pump(tester);

    expect(find.byKey(const ValueKey('kartu-card-profil')), findsOneWidget);
    expect(find.text('JARAK'), findsOneWidget);
    expect(find.text('TANJAKAN'), findsOneWidget);
    expect(find.text('WAKTU'), findsOneWidget);
    expect(find.text('12,8 km'), findsNWidgets(2));
    expect(find.text('+1.140 m'), findsOneWidget);
    expect(find.text('07:12'), findsOneWidget);
    expect(find.text('HIQEO · 30 OKT 2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('kartu-profile')), findsOneWidget);
    expect(find.byKey(const ValueKey('kartu-start-marker')), findsOneWidget);
    expect(find.byKey(const ValueKey('kartu-end-marker')), findsOneWidget);
  });

  testWidgets('memilih sesi selesai terbaru dan mengabaikan sesi aktif',
      (tester) async {
    await _pump(
      tester,
      sessions: <TrackingSession>[
        _session(
          id: 'lama',
          distanceM: 5000,
          startedAtUtc: DateTime(2026, 10, 1, 7).toUtc(),
        ),
        _session(
          id: 'baru',
          distanceM: 12840,
          startedAtUtc: DateTime(2026, 10, 29, 7).toUtc(),
        ),
        _session(
          id: 'aktif',
          status: TrackingSessionStatus.active,
          distanceM: 9999,
          startedAtUtc: DateTime(2026, 10, 30, 7).toUtc(),
        ),
      ],
    );

    expect(find.text('12,8 km'), findsNWidgets(2));
    expect(find.text('5,0 km'), findsNothing);
    expect(find.text('10,0 km'), findsNothing);
  });

  testWidgets('tiga gaya kartu bisa dipilih', (tester) async {
    await _pump(tester);

    await _tapAndPump(tester, 'kartu-style-tengah');
    expect(find.byKey(const ValueKey('kartu-card-tengah')), findsOneWidget);

    await _tapAndPump(tester, 'kartu-style-peta');
    expect(find.byKey(const ValueKey('kartu-card-peta')), findsOneWidget);
    expect(find.byKey(const ValueKey('kartu-route')), findsOneWidget);

    await _tapAndPump(tester, 'kartu-style-profil');
    expect(find.byKey(const ValueKey('kartu-card-profil')), findsOneWidget);
  });

  testWidgets('sembunyikan titik awal dan akhir melepas penanda',
      (tester) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('kartu-start-marker')), findsOneWidget);

    await _tapAndPump(tester, 'kartu-hide-endpoints');
    expect(find.byKey(const ValueKey('kartu-start-marker')), findsNothing);
    expect(find.byKey(const ValueKey('kartu-end-marker')), findsNothing);

    await _tapAndPump(tester, 'kartu-style-peta');
    expect(find.byKey(const ValueKey('kartu-route')), findsOneWidget);
    expect(find.byKey(const ValueKey('kartu-start-marker')), findsNothing);
    expect(find.byKey(const ValueKey('kartu-end-marker')), findsNothing);
  });

  testWidgets('simpan PNG menangkap kartu dan mengirim nama berkas lokal',
      (tester) async {
    final harness = await _pump(tester);

    await _tapAndPump(tester, 'kartu-save');

    expect(harness.exporter.captures, 1);
    expect(harness.exporter.savedNames, <String>[
      'hiqeo-kartu-20261030-0712.png',
    ]);
    expect(find.text('PNG tersimpan di Pictures/Hiqeo.'), findsOneWidget);
  });

  testWidgets('simpan gagal memakai pesan jujur tanpa klaim tersimpan',
      (tester) async {
    final harness = await _pump(tester);
    harness.exporter.saveResult = false;

    await _tapAndPump(tester, 'kartu-save');

    expect(
      find.text('PNG gagal disimpan. Coba Bagikan.'),
      findsOneWidget,
    );
    expect(find.textContaining('tersimpan di Pictures'), findsNothing);
  });

  testWidgets('gambar gagal dibuat tidak mengklaim berkas tersimpan',
      (tester) async {
    final harness = await _pump(tester);
    harness.exporter.png = null;

    await _tapAndPump(tester, 'kartu-save');

    expect(find.text('PNG gagal dibuat. Coba lagi.'), findsOneWidget);
    expect(harness.exporter.savedNames, isEmpty);
  });

  testWidgets('bagikan membuka lembar berbagi tanpa klaim terkirim',
      (tester) async {
    final harness = await _pump(tester);

    await _tapAndPump(tester, 'kartu-share');

    expect(harness.exporter.captures, 1);
    expect(harness.exporter.sharedNames, <String>[
      'hiqeo-kartu-20261030-0712.png',
    ]);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('terkirim'), findsNothing);
    expect(find.textContaining('dibagikan'), findsNothing);
  });

  testWidgets('lembar berbagi tidak tersedia memakai pesan jujur',
      (tester) async {
    final harness = await _pump(tester);
    harness.exporter.shareResult = false;

    await _tapAndPump(tester, 'kartu-share');

    expect(
      find.text('Berbagi tidak tersedia di perangkat ini.'),
      findsOneWidget,
    );
  });

  testWidgets('ganti foto memakai pemilih galeri yang disuntikkan',
      (tester) async {
    final harness = await _pump(tester);

    await _tapAndPump(tester, 'kartu-photo-change');

    expect(harness.photoPicker.calls, 1);
    expect(find.byKey(const ValueKey('kartu-photo')), findsNothing);
  });

  testWidgets('sesi yang diminta dari Beranda dipakai, bukan yang terbaru',
      (tester) async {
    await _pump(
      tester,
      sessions: <TrackingSession>[
        _session(
          id: 'lama',
          distanceM: 5000,
          startedAtUtc: DateTime(2026, 10, 1, 7).toUtc(),
        ),
        _session(id: 'baru', distanceM: 12840),
      ],
      sessionId: 'lama',
    );

    expect(find.text('5,0 km'), findsNWidgets(2));
    expect(find.text('12,8 km'), findsNothing);
  });

  testWidgets('sesi yang diminta tetapi tidak ada berkata jujur',
      (tester) async {
    await _pump(tester, sessionId: 'hilang');

    expect(find.text('Sesi yang diminta tidak ada di HP ini.'), findsOneWidget);
    expect(find.text('Belum ada pendakian selesai'), findsNothing);
    expect(find.byType(KartuCard), findsNothing);
  });

  testWidgets('sesi yang diminta tetapi belum selesai juga ditolak',
      (tester) async {
    await _pump(
      tester,
      sessions: <TrackingSession>[
        _session(id: 'aktif', status: TrackingSessionStatus.active),
      ],
      sessionId: 'aktif',
    );

    expect(find.text('Sesi yang diminta tidak ada di HP ini.'), findsOneWidget);
    expect(find.byType(KartuCard), findsNothing);
  });

  testWidgets('gagal membaca basis data menampilkan coba lagi', (tester) async {
    final harness = await _pump(tester, failSessions: true);

    expect(find.text('Kartu belum bisa dibuat'), findsOneWidget);
    expect(find.text('Data pendakian gagal dibaca dari HP ini.'), findsOneWidget);
    expect(find.byType(KartuCard), findsNothing);

    harness.repository.failSessions = false;
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();
    expect(find.byType(KartuCard), findsOneWidget);
  });
}
