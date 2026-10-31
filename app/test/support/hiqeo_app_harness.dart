import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/app/router.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/theme_mode_controller.dart';

/// Membungkus aplikasi dengan router dan pengendali tema terpisah untuk uji.
Widget buildHiqeoTestApp({
  GoRouter? router,
  ThemeModeController? themeController,
}) {
  final controller =
      themeController ?? ThemeModeController(store: InMemoryThemeModeStore());
  return ListenableBuilder(
    listenable: controller,
    builder: (context, child) => MaterialApp.router(
      theme: hiqeoLightTheme,
      darkTheme: hiqeoDarkTheme,
      themeMode: controller.mode,
      routerConfig: router ?? buildHiqeoRouter(),
    ),
  );
}
