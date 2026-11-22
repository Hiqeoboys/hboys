import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/motion/visual_effect_policy.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/design/widgets/line_icons.dart';
import 'package:nama_app/features/home/expandable_features_card.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

const Key _cardKey = ValueKey<String>('semua-fitur');
const Key _toggleKey = ValueKey<String>('semua-fitur-toggle');

/// Tinggi terbuka untuk 4 kartu (2 baris): 52 + 2 baris x 132 + 1 celah x 10 + 16 alas = 342.
const double _openHeight = 342;
const double _collapsedHeight = ExpandableFeaturesCard.collapsedHeight;

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
        icon: HiqeoIcons.mountain,
        title: 'Hiqeo Plus',
        subtitle: 'Cuaca rute & analitik',
        onTap: () => taps.add('plus'),
      ),
      FeatureEntry(
        icon: HiqeoIcons.trail,
        title: 'Petunjuk jalur',
        subtitle: 'Peta & pos pendakian',
        onTap: () => taps.add('peta'),
      ),
      FeatureEntry(
        icon: HiqeoIcons.pin,
        title: 'Lokasi terakhir',
        subtitle: 'Posisi tiap anggota',
        onTap: () => taps.add('lokasi'),
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
                child:
                    ExpandableFeaturesCard(key: _cardKey, features: features),
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
  testWidgets('tertutup: satu baris 52 px tanpa satu pun kartu fitur terlihat',
      (tester) async {
    final taps = <String>[];
    await _pump(tester, features: _features(taps));

    expect(_cardHeight(tester), _collapsedHeight);
    expect(find.text('Fitur utama'), findsOneWidget);
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
    expect(_cardHeight(tester), _collapsedHeight,
        reason: 'ketukan di luar kartu tidak membuka');
  });

  testWidgets('terbuka: grid 4 kartu setinggi 342 px dan aksi bekerja',
      (tester) async {
    final taps = <String>[];
    await _pump(tester, features: _features(taps));

    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();

    expect(_cardHeight(tester), _openHeight);
    expect(find.byType(FeatureTile), findsNWidgets(4));
    expect(find.text('Fitur utama'), findsOneWidget);

    await tester.tap(find.text('Hiqeo Plus'));
    expect(taps, <String>['plus']);
  });

  testWidgets('menutup lagi mengembalikan baris 52 px', (tester) async {
    final taps = <String>[];
    await _pump(tester, features: _features(taps));

    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();
    expect(_cardHeight(tester), _openHeight);

    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();

    expect(_cardHeight(tester), _collapsedHeight);
  });

  testWidgets('selama animasi reveal tidak ada filter blur jank',
      (tester) async {
    final taps = <String>[];
    await _pump(tester, features: _features(taps));

    await tester.tap(find.byKey(_toggleKey));
    await tester.pump();
    expect(find.byType(ImageFiltered), findsNothing);

    await tester.pump(const Duration(milliseconds: 190));
    expect(find.byType(ImageFiltered), findsNothing);

    await tester.pumpAndSettle();
    expect(find.byType(ImageFiltered), findsNothing);
    expect(_cardHeight(tester), _openHeight);

    await tester.tap(find.byKey(_toggleKey));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ImageFiltered), findsNothing);
    await tester.pumpAndSettle();
    expect(_cardHeight(tester), _collapsedHeight);
  });

  testWidgets('setelah terbuka kartu digulir sampai terlihat utuh',
      (tester) async {
    final taps = <String>[];
    await _pump(tester, features: _features(taps), leading: 700);

    final before =
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;
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
      expect(find.bySemanticsLabel('Tampilkan fitur utama'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Hiqeo Plus'),
        findsNothing,
      );

      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();

      node = tester.getSemantics(find.byKey(_toggleKey));
      expect(node.flagsCollection.isExpanded, ui.Tristate.isTrue);
      expect(find.bySemanticsLabel('Sembunyikan fitur utama'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Hiqeo Plus'),
        findsOneWidget,
      );
      expect(find.text('Cuaca rute & analitik'), findsNothing);
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
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byType(FeatureTile), findsNWidgets(4));
  });

  testWidgets('profil daya Hemat tetap melipat tanpa cair dan blur',
      (tester) async {
    final taps = <String>[];
    await _pump(tester, features: _features(taps), policy: _saverPolicy);

    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();

    expect(_cardHeight(tester), _openHeight);
    expect(find.byType(ImageFiltered), findsNothing);
  });
}
