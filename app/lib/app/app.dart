import 'package:flutter/material.dart';

import '../bootstrap.dart';
import '../core/brand/app_brand.dart';
import '../design/app_theme.dart';
import '../design/system_ui.dart';
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
        title: AppBrand.name,
        debugShowCheckedModeBanner: config.flavor != Flavor.prod,
        theme: hiqeoLightTheme,
        darkTheme: hiqeoDarkTheme,
        themeMode: controller.mode,
        routerConfig: hiqeoRouter,
        // Ikon status dan navigasi mengikuti tema aktif di semua rute,
        // termasuk Peta yang peta terangnya diredam di mode malam.
        builder: (context, child) => HiqeoSystemUiRegion(
          brightness: Theme.of(context).brightness,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
