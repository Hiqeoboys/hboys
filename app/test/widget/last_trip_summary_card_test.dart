import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/motion/visual_effect_policy.dart';
import 'package:nama_app/features/home/last_trip_summary_card.dart';
import 'package:nama_app/features/kartu/domain/kartu_data.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

import '../support/real_font.dart';

const Key _cardKey = ValueKey<String>('ringkasan-perjalanan');

final DateTime _startedAtUtc = DateTime(2026, 10, 30, 7, 12).toUtc();

const List<KartuProfilePoint> _profile = <KartuProfilePoint>[
  KartuProfilePoint(0, 1500),
  KartuProfilePoint(0.5, 1900),
  KartuProfilePoint(1, 1700),
];

const List<Offset> _route = <Offset>[
  Offset(0.2, 0.9),
  Offset(0.5, 0.35),
  Offset(0.8, 0.1),
];

KartuData _data({
  List<KartuProfilePoint>? profile = _profile,
  double? peakFraction = 0.5,
  List<Offset>? route = _route,
}) =>
    KartuData(
      sessionId: 'sesi-1',
      startedAtUtc: _startedAtUtc,
      distanceM: 12840,
      movingSeconds: 25920,
      elevationGainM: 1140,
      profile: profile,
      peakFraction: peakFraction,
      route: route,
    );

Future<void> _pump(
  WidgetTester tester, {
  KartuData? data,
  String? mountain,
  String? unavailableReason,
  VoidCallback? onViewKartu,
  VisualEffectPolicy policy = VisualEffectPolicy.full,
}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: hiqeoLightTheme,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 358,
              child: VisualEffectPolicyScope(
                policy: policy,
                child: LastTripSummaryCard(
                  data: data,
                  mountain: mountain,
                  unavailableReason: unavailableReason,
                  onViewKartu: onViewKartu,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('tanpa riwayat, kartu menyatakan kosong apa adanya',
      (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('PENDAKIAN TERAKHIR'), findsOneWidget);
    expect(find.text('Belum ada riwayat pendakian'), findsOneWidget);
    expect(
      find.text('Ringkasan pendakian terakhirmu akan muncul di sini.'),
      findsOneWidget,
    );
    expect(find.text('Lihat kartu'), findsNothing);
    expect(find.text('JARAK'), findsNothing);
  });

  testWidgets('riwayat gagal dibaca memakai alasan jujur, bukan keadaan kosong',
      (tester) async {
    await _pump(
      tester,
      unavailableReason: 'Data pendakian lokal belum dapat dibuka.',
    );
    await tester.pumpAndSettle();

    expect(find.text('Riwayat belum dapat dibaca'), findsOneWidget);
    expect(find.text('Data pendakian lokal belum dapat dibuka.'), findsOneWidget);
    expect(find.text('Belum ada riwayat pendakian'), findsNothing);
  });

  testWidgets('ringkasan menampilkan nama gunung, tanggal, dan tiga angka',
      (tester) async {
    await _pump(tester, data: _data(), mountain: 'Gunung Gede');
    await tester.pumpAndSettle();

    expect(find.text('PENDAKIAN TERAKHIR'), findsOneWidget);
    expect(find.text('Gunung Gede'), findsOneWidget);
    expect(find.text('30 Okt 2026 · 07:12'), findsOneWidget);
    expect(find.text('JARAK'), findsOneWidget);
    expect(find.text('TANJAKAN'), findsOneWidget);
    expect(find.text('WAKTU'), findsOneWidget);
    expect(find.text('12,8 km'), findsOneWidget);
    expect(find.text('+1.140 m'), findsOneWidget);
    expect(find.text('07:12'), findsOneWidget);
    expect(find.text('PUNCAK'), findsOneWidget);
    expect(find.text('Lihat kartu'), findsOneWidget);
  });

  testWidgets('tanpa nama gunung, judul jatuh ke tanggal pendakian',
      (tester) async {
    await _pump(tester, data: _data());
    await tester.pumpAndSettle();

    expect(find.text('Pendakian 30 Okt 2026'), findsOneWidget);
  });

  testWidgets('angka menghitung naik lalu berhenti di nilai sebenarnya',
      (tester) async {
    await _pump(tester, data: _data(), mountain: 'Gunung Gede');

    await tester.pump();
    expect(find.text('12,8 km'), findsNothing, reason: 'hitung-naik belum jalan');

    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('12,8 km'), findsNothing);
    expect(find.text('07:12'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('12,8 km'), findsOneWidget);
    expect(find.text('07:12'), findsOneWidget);
  });

  testWidgets('hanya jejak rute dan profil elevasi yang digambar',
      (tester) async {
    await _pump(tester, data: _data());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('ringkasan-rute')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('ringkasan-elevasi')),
      findsOneWidget,
    );
    // Titik awal dan akhir rute tidak pernah digambar di Beranda.
    expect(
      find.descendant(of: find.byKey(_cardKey), matching: find.byType(CustomPaint)),
      findsNWidgets(2),
    );
  });

  testWidgets('tanpa profil elevasi, kartu berkata jujur dan tidak menggambar',
      (tester) async {
    await _pump(
      tester,
      data: _data(profile: null, peakFraction: null),
    );
    await tester.pumpAndSettle();

    expect(find.text('Profil elevasi belum tersedia'), findsOneWidget);
    expect(find.text('PUNCAK'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('ringkasan-elevasi')),
      findsNothing,
    );
  });

  testWidgets('ketinggian kartu berada di dalam sasaran 190-210 px',
      (tester) async {
    // Sasaran tinggi dihitung dengan huruf asli, bukan font uji Ahem.
    await loadPlusJakartaSans(tester);

    await _pump(tester, data: _data(), mountain: 'Gunung Gede Pangrango');
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(_cardKey)).height,
      inInclusiveRange(190, 210),
    );
  });

  testWidgets('tombol Lihat kartu memanggil pembuka kartu', (tester) async {
    var opened = 0;
    await _pump(tester, data: _data(), onViewKartu: () => opened++);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lihat kartu'));
    expect(opened, 1);
  });

  testWidgets('reduce motion langsung menampilkan nilai akhir', (tester) async {
    await _pump(
      tester,
      data: _data(),
      mountain: 'Gunung Gede',
      policy: const VisualEffectPolicy(
        powerProfile: PowerProfile.normal,
        reduceMotion: true,
        deviceTier: DeviceTier.capable,
      ),
    );

    await tester.pump();
    expect(find.text('12,8 km'), findsOneWidget);
    expect(find.text('07:12'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('data yang tiba belakangan memicu animasi masuk sekali',
      (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();
    expect(find.text('Belum ada riwayat pendakian'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 358,
                child: LastTripSummaryCard(data: _data(), mountain: 'Gunung Gede'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('12,8 km'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('12,8 km'), findsOneWidget);
  });

  testWidgets('label aksesibilitas tombol Lihat kartu terpasang', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await _pump(tester, data: _data(), onViewKartu: () {});
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.bySemanticsLabel('Lihat kartu'));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isEnabled, ui.Tristate.isTrue);
      expect(
        node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
        isTrue,
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets('tanpa sesi, tombol Lihat kartu mati bagi pembaca layar',
      (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await _pump(tester, data: _data());
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.bySemanticsLabel('Lihat kartu'));
      expect(node.flagsCollection.isEnabled, ui.Tristate.isFalse);
    } finally {
      handle.dispose();
    }
  });
}
