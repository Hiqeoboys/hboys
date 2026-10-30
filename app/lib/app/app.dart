import 'package:flutter/material.dart';

import '../bootstrap.dart';
import '../design/app_theme.dart';
import '../design/theme_mode_controller.dart';
import 'router.dart';

class NamaApp extends StatelessWidget {
  const NamaApp({super.key, required this.config, this.themeController});

  final AppConfig config;

  /// Disuntikkan untuk uji; produksi memakai [ThemeModeController.instance].
  final ThemeModeController? themeController;

  @override
  Widget build(BuildContext context) {
    final controller = themeController ?? ThemeModeController.instance;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) => MaterialApp.router(
        title: 'Altracq',
        debugShowCheckedModeBanner: config.flavor != Flavor.prod,
        theme: altracqLightTheme,
        darkTheme: altracqDarkTheme,
        themeMode: controller.mode,
        routerConfig: altracqRouter,
      ),
    );
  }
}
