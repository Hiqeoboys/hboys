import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/app/router.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/theme_mode_controller.dart';
import 'package:nama_app/features/plus/application/plus_controller.dart';
import 'package:nama_app/features/plus/application/plus_scope.dart';

/// Membungkus aplikasi dengan router dan pengendali tema terpisah untuk uji.
Widget buildHiqeoTestApp({
  GoRouter? router,
  ThemeModeController? themeController,
  PlusController? plusController,
}) {
  final controller =
      themeController ?? ThemeModeController(store: InMemoryThemeModeStore());
  final app = ListenableBuilder(
    listenable: controller,
    builder: (context, child) => MaterialApp.router(
      theme: hiqeoLightTheme,
      darkTheme: hiqeoDarkTheme,
      themeMode: controller.mode,
      routerConfig: router ?? buildHiqeoRouter(),
    ),
  );
  if (plusController == null) return app;
  return PlusScope(controller: plusController, child: app);
}
