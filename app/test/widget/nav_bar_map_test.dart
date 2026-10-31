import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/glass/glass_surface.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/design/widgets/hiqeo_nav_bar.dart';
import 'package:nama_app/design/widgets/line_icons.dart';
import 'package:nama_app/features/map/presentation/map_page.dart';

import '../support/contrast.dart';

final List<HiqeoNavBarItem> _items = <HiqeoNavBarItem>[
  HiqeoNavBarItem(label: 'Beranda', icon: HiqeoIcons.home, route: '/beranda'),
  HiqeoNavBarItem(label: 'Peta', icon: HiqeoIcons.map, route: '/peta'),
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

Color _backdrop(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byType(GlassSurface),
      matching: find.byType(Container),
    ),
  );
  return (container.decoration! as BoxDecoration).color!;
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

Color _composite(HiqeoColors colors, Color fill, Color map) {
  final dimmed = Color.alphaBlend(
    colors.background.withValues(alpha: mapDimOpacityFor(Brightness.dark)),
    map,
  );
  return Color.alphaBlend(fill, dimmed);
}

void main() {
  final HiqeoColors dark = hiqeoDarkTheme.extension<HiqeoColors>()!;
  final HiqeoColors light = hiqeoLightTheme.extension<HiqeoColors>()!;

  test('tint kaca peta hanya menyala di mode gelap', () {
    expect(navBarMapTint(light), isNull);
    expect(
      navBarMapTint(dark),
      dark.background.withValues(alpha: navBarMapTintAlpha),
    );
  });

  test('label diam di atas peta memakai teks utama', () {
    expect(
      navBarLabelColor(colors: dark, overMap: true, coverage: 0),
      dark.textPrimary,
    );
    expect(
      navBarLabelColor(colors: dark, overMap: false, coverage: 0),
      dark.textSecondary,
    );
    expect(
      navBarLabelColor(colors: dark, overMap: true, coverage: 1),
      dark.onPrimary,
    );
  });

  testWidgets('navbar di atas peta mode gelap memakai tint dan label utama',
      (tester) async {
    await tester.pumpWidget(_navbarApp(theme: hiqeoDarkTheme, overMap: true));

    expect(
      _backdrop(tester),
      Color.alphaBlend(navBarMapTint(dark)!, dark.glassFill),
    );
    expect(_labelColor(tester, 'Beranda'), dark.textPrimary);
    expect(_labelColor(tester, 'Peta'), dark.onPrimary);
  });

  testWidgets('navbar di luar peta tetap memakai isi kaca dan label sekunder',
      (tester) async {
    await tester.pumpWidget(
      _navbarApp(theme: hiqeoDarkTheme, overMap: false),
    );

    expect(_backdrop(tester), dark.glassFill);
    expect(_labelColor(tester, 'Beranda'), dark.textSecondary);
  });

  test('label peta tetap ≥4,5:1 di atas peta tergelap dan terang', () {
    final fill = Color.alphaBlend(navBarMapTint(dark)!, dark.glassFill);

    for (final map in <Color>[Colors.black, Colors.white]) {
      final behind = _composite(dark, fill, map);
      expect(
        contrastRatio(dark.textPrimary, behind),
        greaterThanOrEqualTo(4.5),
        reason: 'peta $map',
      );
    }
    // Teks sekunder tidak cukup di atas peta terang; karena itu label Peta
    // memakai teks utama.
    expect(
      contrastRatio(
        dark.textSecondary,
        _composite(dark, fill, const Color(0xFFFFFFFF)),
      ),
      lessThan(4.5),
    );
  });

  test('label peta mode terang ≥4,5:1 di atas peta terang', () {
    final fill = Color.alphaBlend(light.glassFill, const Color(0xFFFFFFFF));

    expect(
      contrastRatio(light.textPrimary, fill),
      greaterThanOrEqualTo(4.5),
    );
  });
}
