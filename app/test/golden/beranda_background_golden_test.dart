import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/app/router.dart';
import 'package:nama_app/design/theme_mode_controller.dart';

import '../support/hiqeo_app_harness.dart';
import '../support/real_font.dart';

void main() {
  testWidgets('Golden Beranda dengan latar aura baru mode terang', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await loadPlusJakartaSans(tester);

    final router = buildHiqeoRouter();
    router.go('/beranda');

    await tester.pumpWidget(
      buildHiqeoTestApp(
        router: router,
        themeController: ThemeModeController(
          store: InMemoryThemeModeStore(ThemeMode.light),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/beranda_aura_light.png'),
    );
  });

  testWidgets('Golden Beranda dengan latar aura baru mode gelap', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await loadPlusJakartaSans(tester);

    final router = buildHiqeoRouter();
    router.go('/beranda');

    await tester.pumpWidget(
      buildHiqeoTestApp(
        router: router,
        themeController: ThemeModeController(
          store: InMemoryThemeModeStore(ThemeMode.dark),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/beranda_aura_dark.png'),
    );
  });
}

