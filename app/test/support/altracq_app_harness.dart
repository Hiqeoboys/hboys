import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/app/router.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/theme_mode_controller.dart';

/// Membungkus aplikasi dengan router dan pengendali tema terpisah untuk uji.
Widget buildAltracqTestApp({
  GoRouter? router,
  ThemeModeController? themeController,
}) {
  final controller =
      themeController ?? ThemeModeController(store: InMemoryThemeModeStore());
  return ListenableBuilder(
    listenable: controller,
    builder: (context, child) => MaterialApp.router(
      theme: altracqLightTheme,
      darkTheme: altracqDarkTheme,
      themeMode: controller.mode,
      routerConfig: router ?? buildAltracqRouter(),
    ),
  );
}
