import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/glass/hiqeo_liquid_glass.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/design/widgets/hiqeo_nav_bar.dart';
import 'package:nama_app/design/widgets/line_icons.dart';

import '../support/contrast.dart';

final List<HiqeoNavBarItem> _items = <HiqeoNavBarItem>[
  HiqeoNavBarItem(label: 'Beranda', icon: HiqeoIcons.home, route: '/beranda'),
  HiqeoNavBarItem(label: 'Peta', icon: HiqeoIcons.map, route: '/peta'),
  HiqeoNavBarItem(label: 'Track', icon: HiqeoIcons.activity, route: '/lacak'),
  HiqeoNavBarItem(label: 'Grup', icon: HiqeoIcons.group, route: '/grup'),
  HiqeoNavBarItem(label: 'Profil', icon: HiqeoIcons.user, route: '/profil'),
];

Widget _navbarApp({required ThemeData theme, required bool overMap}) {
  return MaterialApp(
    theme: theme,
    home: Scaffold(
      bottomNavigationBar: HiqeoNavBar(
        currentIndex: 1,
        items: _items,
        overMap: overMap,
        onTap: (_) {},
      ),
    ),
  );
}

Color _labelColor(WidgetTester tester, String label) {
  final text = tester.widget<Text>(
    find.descendant(
      of: find.byType(HiqeoNavBar),
      matching: find.text(label),
    ),
  );
  return text.style!.color!;
}

void main() {
  final HiqeoColors dark = hiqeoDarkTheme.extension<HiqeoColors>()!;
  final HiqeoColors light = hiqeoLightTheme.extension<HiqeoColors>()!;

  testWidgets('navbar memakai HiqeoLiquidGlassSurface di mode gelap & terang',
      (tester) async {
    for (final theme in <ThemeData>[hiqeoLightTheme, hiqeoDarkTheme]) {
      final expectedColors = theme.extension<HiqeoColors>()!;
      await tester.pumpWidget(_navbarApp(theme: theme, overMap: true));
      await tester.pumpAndSettle();

      final glass = tester.widget<HiqeoLiquidGlassSurface>(
        find.descendant(
          of: find.byType(HiqeoNavBar),
          matching: find.byKey(const ValueKey<String>('navbar-liquid-glass')),
        ),
      );
      expect(glass.overMap, isTrue);
      expect(_labelColor(tester, 'Peta'), expectedColors.textPrimary);
    }
  });

  testWidgets('lensa aktif tidak memiliki BackdropFilter sendiri (hanya 1 pada pill)',
      (tester) async {
    for (final theme in <ThemeData>[hiqeoLightTheme, hiqeoDarkTheme]) {
      await tester.pumpWidget(_navbarApp(theme: theme, overMap: false));
      expect(
        find.byKey(const ValueKey<String>('navbar-lens')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('navbar-lens')),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(HiqeoNavBar),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('navbar memiliki 5 tab interaktif termasuk Track di tengah',
      (tester) async {
    int tapped = -1;
    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: Scaffold(
          bottomNavigationBar: HiqeoNavBar(
            currentIndex: 0,
            items: _items,
            onTap: (i) => tapped = i,
          ),
        ),
      ),
    );

    for (final label in const <String>[
      'Beranda',
      'Peta',
      'Track',
      'Grup',
      'Profil',
    ]) {
      expect(
        find.descendant(
          of: find.byType(HiqeoNavBar),
          matching: find.bySemanticsLabel(label),
        ),
        findsOneWidget,
      );
    }

    await tester.tap(
      find.descendant(
        of: find.byType(HiqeoNavBar),
        matching: find.bySemanticsLabel('Track'),
      ),
    );
    await tester.pump();
    expect(tapped, 2);
  });

  test('fill aman navbar menjaga kontras teks ≥4,5:1 di atas latar gelap & terang',
      () {
    for (final bg in <Color>[Colors.black, Colors.white]) {
      final lightBehind = Color.alphaBlend(light.glassFillSafe, bg);
      expect(
        contrastRatio(light.textPrimary, lightBehind),
        greaterThanOrEqualTo(4.5),
      );
      final darkBehind = Color.alphaBlend(dark.glassFillSafe, bg);
      expect(
        contrastRatio(dark.textPrimary, darkBehind),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}
