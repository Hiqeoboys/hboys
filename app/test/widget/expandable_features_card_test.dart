import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/gooey/gooey_layer.dart';
import 'package:nama_app/design/motion/visual_effect_policy.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/design/widgets/line_icons.dart';
import 'package:nama_app/features/home/expandable_features_card.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

const Key _cardKey = ValueKey<String>('semua-fitur');
const Key _toggleKey = ValueKey<String>('semua-fitur-toggle');

/// Tinggi terbuka: 64 + 4 baris x 140 + 3 celah x 12 + 16 alas.
const double _openHeight = 676;

const VisualEffectPolicy _reduceMotionPolicy = VisualEffectPolicy(
  powerProfile: PowerProfile.normal,
  reduceMotion: true,
  deviceTier: DeviceTier.capable,
);

const VisualEffectPolicy _saverPolicy = VisualEffectPolicy(
  powerProfile: PowerProfile.saver,
  reduceMotion: false,
  deviceTier: DeviceTier.capable,
);

List<FeatureEntry> _features(List<String> taps) => <FeatureEntry>[
      FeatureEntry(
        icon: HiqeoIcons.activity,
        title: 'Pelacakan',
        subtitle: 'Catat jalur',
        onTap: () => taps.add('pelacakan'),
      ),
      FeatureEntry(
        icon: HiqeoIcons.map,
        title: 'Peta offline',
        subtitle: 'Unduh area',
        onTap: () => taps.add('peta'),
      ),
      FeatureEntry(
        icon: HiqeoIcons.trail,
        title: 'Jalur terverifikasi',
        subtitle: 'Jalur resmi',
        onTap: () => taps.add('jalur'),
      ),
      FeatureEntry(
        icon: HiqeoIcons.compass,
        title: 'Kompas',
        subtitle: 'Arah dan kemiringan',
        onTap: () => taps.add('kompas'),
      ),
      FeatureEntry(
        icon: HiqeoIcons.group,
        title: 'Grup chat',
        subtitle: 'Teman satu grup',
        onTap: () => taps.add('grup'),
      ),
      FeatureEntry(
        icon: HiqeoIcons.pin,
        title: 'Lokasi terakhir',
        subtitle: 'Titik terakhir',
        onTap: () => taps.add('lokasi'),
      ),
      FeatureEntry(
        icon: HiqeoIcons.image,
        title: 'Kartu pendakian',
        subtitle: 'Foto dan ringkasan',
        onTap: () => taps.add('kartu'),
      ),
      FeatureEntry(
        icon: HiqeoIcons.warning,
        title: 'SOS',
        subtitle: 'Tekan-tahan 3 detik',
        onTap: () => taps.add('sos'),
        emphasis: true,
      ),
    ];

Future<void> _pump(
  WidgetTester tester, {
  required List<FeatureEntry> features,
  VisualEffectPolicy policy = VisualEffectPolicy.full,
  double leading = 0,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: hiqeoLightTheme,
      home: Scaffold(
        body: VisualEffectPolicyScope(
          policy: policy,
          child: ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              SizedBox(height: leading),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: HiqeoSpacing.lg,
                ),
                child: ExpandableFeaturesCard(key: _cardKey, features: features),
              ),
              const SizedBox(height: 400),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double _cardHeight(WidgetTester tester) =>
    tester.getSize(find.byKey(_cardKey)).height;

void main() {
  testWidgets('tertutup: satu baris 64 px tanpa satu pun kartu fitur',
      (tester) async {
    final taps = <String>[];
    await _pump(tester, features: _features(taps));

    expect(_cardHeight(tester), 64);
    expect(find.text('Semua fitur'), findsOneWidget);
    expect(find.byType(FeatureTile), findsNothing);
    // Kosong berarti tidak ada gesekan atau blur yang bekerja diam-diam.
    expect(find.byType(GooeyLayer), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets('mengetuk di bawah baris tertutup tidak menekan kartu fitur',
      (tester) async {
    final taps = <String>[];
    await _pump(tester, features: _features(taps));

    final card = tester.getRect(find.byKey(_cardKey));
    await tester.tapAt(Offset(card.center.dx, card.bottom + 80));
    await tester.pumpAndSettle();

    expect(taps, isEmpty);
    expect(_cardHeight(tester), 64, reason: 'ketukan di luar kartu tidak membuka');
  });

  testWidgets('terbuka: grid 8 kartu setinggi 676 px dan aksi bekerja',
      (tester) async {
    final taps = <String>[];
    await _pump(tester, features: _features(taps));

    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();

    expect(_cardHeight(tester), _openHeight);
    expect(find.byType(FeatureTile), findsNWidgets(8));
    expect(find.text('Semua fitur'), findsOneWidget);

    await tester.tap(find.text('Pelacakan'));
    expect(taps, <String>['pelacakan']);
  });

  testWidgets('menutup lagi mengembalikan baris 64 px', (tester) async {
    final taps = <String>[];
    await _pump(tester, features: _features(taps));

    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();
    expect(_cardHeight(tester), _openHeight);

    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();

    expect(_cardHeight(tester), 64);
    expect(find.byType(FeatureTile), findsNothing);
    expect(find.byType(GooeyLayer), findsNothing);
  });

  testWidgets('lapisan cair hanya hidup selama morph, lalu dibuang',
      (tester) async {
    final taps = <String>[];
    await _pump(tester, features: _features(taps));

    await tester.tap(find.byKey(_toggleKey));
    await tester.pump();
    expect(find.byType(GooeyLayer), findsNothing, reason: 't = 0 masih kaca');

    /// 165 ms dari 550 ms berarti t = 0,3: bentuk cair penuh.
    await tester.pump(const Duration(milliseconds: 165));
    expect(find.byType(GooeyLayer), findsOneWidget);
    expect(find.byType(ImageFiltered), findsWidgets);

    await tester.pumpAndSettle();
    expect(find.byType(GooeyLayer), findsNothing, reason: 'kaca tajam');
    expect(find.byType(ImageFiltered), findsNothing);

    // Arah sebaliknya juga melewati bentuk cair lalu berhenti di kaca.
    await tester.tap(find.byKey(_toggleKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 165));
    expect(find.byType(GooeyLayer), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(GooeyLayer), findsNothing);
  });

  testWidgets('setelah terbuka kartu digulir sampai terlihat utuh',
      (tester) async {
    final taps = <String>[];
    await _pump(tester, features: _features(taps), leading: 700);

    final before = tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;
    expect(before, 0);

    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();

    final card = tester.getRect(find.byKey(_cardKey));
    expect(card.top, greaterThanOrEqualTo(0));
    expect(card.bottom, lessThanOrEqualTo(844.5));
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      greaterThan(0),
    );
  });

  testWidgets('pembaca layar tahu keadaan buka-tutup dan nama tombolnya',
      (tester) async {
    final handle = tester.ensureSemantics();
    try {
      final taps = <String>[];
      await _pump(tester, features: _features(taps));

      var node = tester.getSemantics(find.byKey(_toggleKey));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isExpanded, ui.Tristate.isFalse);
      expect(find.bySemanticsLabel('Tampilkan semua fitur'), findsOneWidget);
      expect(find.bySemanticsLabel('Pelacakan. Catat jalur'), findsNothing);

      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();

      node = tester.getSemantics(find.byKey(_toggleKey));
      expect(node.flagsCollection.isExpanded, ui.Tristate.isTrue);
      expect(find.bySemanticsLabel('Sembunyikan semua fitur'), findsOneWidget);
      expect(find.bySemanticsLabel('Pelacakan. Catat jalur'), findsOneWidget);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('reduce motion membuka tanpa cair dan tanpa blur',
      (tester) async {
    final taps = <String>[];
    await _pump(
      tester,
      features: _features(taps),
      policy: _reduceMotionPolicy,
    );

    await tester.tap(find.byKey(_toggleKey));
    await tester.pump();
    await tester.pump(HiqeoMotion.screenFade);

    expect(_cardHeight(tester), _openHeight, reason: 'selesai dalam 260 ms');
    expect(find.byType(GooeyLayer), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byType(FeatureTile), findsNWidgets(8));
  });

  testWidgets('profil daya Hemat tetap melipat tanpa cair dan blur',
      (tester) async {
    final taps = <String>[];
    await _pump(tester, features: _features(taps), policy: _saverPolicy);

    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();

    expect(_cardHeight(tester), _openHeight);
    expect(find.byType(GooeyLayer), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
  });
}
