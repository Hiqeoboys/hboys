import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/gooey/gooey_layer.dart';
import 'package:nama_app/design/motion/visual_effect_policy.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/design/widgets/altracq_nav_bar.dart';
import 'package:nama_app/features/shell/altracq_shell.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

const ValueKey<String> blobKey = ValueKey<String>('navbar-blob');

VisualEffectPolicy policy({
  PowerProfile power = PowerProfile.normal,
  bool reduceMotion = false,
  DeviceTier tier = DeviceTier.capable,
}) =>
    VisualEffectPolicy(
      powerProfile: power,
      reduceMotion: reduceMotion,
      deviceTier: tier,
    );

class _Harness extends StatefulWidget {
  const _Harness({
    required this.policy,
    this.initialIndex = 0,
    this.onTap,
  });

  final VisualEffectPolicy policy;
  final int initialIndex;
  final ValueChanged<int>? onTap;

  @override
  State<_Harness> createState() => _HarnessState();
}

/// Satu instance tema untuk seluruh uji. Getter [altracqLightTheme] membuat
/// ThemeData baru tiap panggilan; bila MaterialApp dibangun ulang dengan
/// instance baru, AnimatedTheme bawaan MaterialApp ikut beranimasi dan
/// mengaburkan pemeriksaan "tidak ada animasi".
final ThemeData _lightTheme = altracqLightTheme;

class _HarnessState extends State<_Harness> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: _lightTheme,
      home: Scaffold(
        body: const SizedBox.expand(),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.all(16),
          child: VisualEffectPolicyScope(
            policy: widget.policy,
            child: AltracqNavBar(
              currentIndex: _index,
              items: AltracqShell.navItems,
              onTap: (index) {
                widget.onTap?.call(index);
                setState(() => _index = index);
              },
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> pumpNav(
  WidgetTester tester,
  VisualEffectPolicy visualPolicy, {
  int initialIndex = 0,
  ValueChanged<int>? onTap,
}) async {
  await tester.pumpWidget(
    _Harness(
      policy: visualPolicy,
      initialIndex: initialIndex,
      onTap: onTap,
    ),
  );
  await tester.pumpAndSettle();
}

NavBarBlobPainter blobPainter(WidgetTester tester) =>
    tester.widget<CustomPaint>(find.byKey(blobKey)).painter!
        as NavBarBlobPainter;

double cellWidthOf(WidgetTester tester) =>
    tester.getSize(find.byType(AltracqNavBar)).width /
    AltracqShell.navItems.length;

void main() {
  testWidgets('saat diam blob berupa satu pill tajam tanpa filter',
      (tester) async {
    await pumpNav(tester, VisualEffectPolicy.full);

    expect(find.byKey(blobKey), findsOneWidget);
    expect(find.byType(GooeyLayer), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
    final painter = blobPainter(tester);
    expect(painter.headCenter, moreOrLessEquals(painter.tailCenter));
    expect(painter.headCenter, moreOrLessEquals(cellWidthOf(tester) / 2));
    expect(painter.color, AltracqColors.light.primary);
  });

  testWidgets('selama bergerak hanya ada satu bentuk cair', (tester) async {
    await pumpNav(tester, VisualEffectPolicy.full);
    final cell = cellWidthOf(tester);

    await tester.tap(find.text('Peta'));
    await tester.pump();
    expect(find.byType(GooeyLayer), findsNothing, reason: 't = 0 belum cair');

    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(GooeyLayer), findsOneWidget);
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GooeyLayer),
        matching: find.byKey(blobKey),
      ),
      findsOneWidget,
    );
    final mid = blobPainter(tester);
    expect(mid.headCenter, greaterThan(mid.tailCenter));
    expect(mid.tailCenter, greaterThan(cell / 2));

    await tester.pumpAndSettle();
    expect(find.byType(GooeyLayer), findsNothing);
    final rest = blobPainter(tester);
    expect(rest.headCenter, moreOrLessEquals(rest.tailCenter));
    expect(rest.headCenter, moreOrLessEquals(cell * 1.5));
  });

  testWidgets('lompatan lintas tab memanjang, bukan terlepas',
      (tester) async {
    await pumpNav(tester, VisualEffectPolicy.full);
    final cell = cellWidthOf(tester);

    await tester.tap(find.text('Profil'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(GooeyLayer), findsOneWidget);
    final mid = blobPainter(tester);
    expect(
      mid.headCenter - mid.tailCenter,
      greaterThan(cell * 0.7),
      reason: 'satu blob memanjang melintasi tab di antaranya',
    );
    expect(mid.tailCenter, greaterThan(cell / 2));

    await tester.pumpAndSettle();
    final rest = blobPainter(tester);
    expect(rest.headCenter, moreOrLessEquals(cell * 4.5));
    expect(find.byType(GooeyLayer), findsNothing);
  });

  test('pantulan kepala tidak melebihi lima persen', () {
    var maxValue = 0.0;
    for (var i = 0; i <= 1000; i++) {
      final value = navBarHeadProgress(i / 1000);
      if (value > maxValue) maxValue = value;
    }
    expect(maxValue, greaterThan(1.0), reason: 'pegas tetap memantul sedikit');
    expect(maxValue, lessThanOrEqualTo(1.05));
    expect(navBarHeadProgress(1), moreOrLessEquals(1));
    expect(navBarTailProgress(1), moreOrLessEquals(1));
  });

  test('ekor menyusul dan tidak pernah mendahului kepala', () {
    for (var i = 0; i <= 1000; i++) {
      final t = i / 1000;
      expect(
        navBarTailProgress(t),
        lessThanOrEqualTo(navBarHeadProgress(t) + 1e-9),
        reason: 't = $t',
      );
      expect(navBarTailProgress(t), lessThanOrEqualTo(1.0 + 1e-9));
    }
  });

  test('warna tab mengikuti bagian yang tertutup blob', () {
    // Blob diam di atas tab pertama.
    expect(
      navBarCoverage(
        tabCenter: 0,
        headCenter: 0,
        tailCenter: 0,
        pillWidth: 66,
      ),
      1,
    );
    expect(
      navBarCoverage(
        tabCenter: 80,
        headCenter: 0,
        tailCenter: 0,
        pillWidth: 66,
      ),
      0,
    );
    // Blob di tengah jalan menutup sebagian kedua tab.
    final first = navBarCoverage(
      tabCenter: 0,
      headCenter: 40,
      tailCenter: 40,
      pillWidth: 66,
    );
    final second = navBarCoverage(
      tabCenter: 80,
      headCenter: 40,
      tailCenter: 40,
      pillWidth: 66,
    );
    expect(first, greaterThan(0));
    expect(first, lessThan(1));
    expect(second, moreOrLessEquals(first));
  });

  testWidgets('kurangi animasi: geser lurus tanpa cair', (tester) async {
    await pumpNav(tester, policy(reduceMotion: true));
    final cell = cellWidthOf(tester);

    await tester.tap(find.text('Peta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));

    expect(find.byType(GooeyLayer), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
    final mid = blobPainter(tester);
    expect(mid.headCenter, moreOrLessEquals(mid.tailCenter),
        reason: 'satu pill tanpa tarikan ekor');
    expect(mid.headCenter, greaterThan(cell / 2));
    expect(mid.headCenter, lessThan(cell * 1.5));

    await tester.pumpAndSettle();
    expect(
      blobPainter(tester).headCenter,
      moreOrLessEquals(cell * 1.5),
    );
  });

  testWidgets('profil daya Hemat: memanjang tetapi tanpa filter',
      (tester) async {
    await pumpNav(tester, policy(power: PowerProfile.saver));
    final cell = cellWidthOf(tester);

    await tester.tap(find.text('Peta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(GooeyLayer), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
    final mid = blobPainter(tester);
    expect(mid.headCenter, greaterThan(mid.tailCenter));

    await tester.pumpAndSettle();
    expect(blobPainter(tester).headCenter, moreOrLessEquals(cell * 1.5));
  });

  testWidgets('mengetuk tab aktif tidak memulai animasi', (tester) async {
    final taps = <int>[];
    await pumpNav(tester, VisualEffectPolicy.full, onTap: taps.add);
    final before = blobPainter(tester);

    await tester.tap(find.text('Beranda'));
    await tester.pump();

    expect(taps, <int>[0]);
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byType(GooeyLayer), findsNothing);
    final after = blobPainter(tester);
    expect(after.headCenter, before.headCenter);
    expect(after.tailCenter, before.tailCenter);
  });

  testWidgets('setiap tab tetap tombol berlabel dengan tab aktif terpilih',
      (tester) async {
    await pumpNav(tester, VisualEffectPolicy.full);
    final handle = tester.ensureSemantics();

    for (final label in <String>['Beranda', 'Peta', 'Lacak', 'Grup', 'Profil']) {
      final node = tester.getSemantics(find.text(label));
      expect(node.flagsCollection.isButton, isTrue, reason: label);
      expect(node.label, label);
    }
    expect(
      tester.getSemantics(find.text('Beranda')).flagsCollection.isSelected,
      ui.Tristate.isTrue,
    );

    handle.dispose();
  });
}
