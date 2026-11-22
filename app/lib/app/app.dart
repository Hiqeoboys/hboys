import 'package:flutter/material.dart';

import '../bootstrap.dart';
import '../core/brand/app_brand.dart';
import '../design/app_theme.dart';
import '../design/system_ui.dart';
import '../design/theme_mode_controller.dart';
import '../features/plus/application/plus_controller.dart';
import '../features/plus/application/plus_scope.dart';
import '../features/plus/plus_dependencies.dart';
import '../infrastructure/notifications/push_notification_overlay.dart';
import 'router.dart';

class NamaApp extends StatelessWidget {
  const NamaApp({
    super.key,
    required this.config,
    this.themeController,
    this.plusController,
  });

  final AppConfig config;

  /// Disuntikkan untuk uji; produksi memakai [ThemeModeController.instance].
  final ThemeModeController? themeController;

  /// Disuntikkan untuk uji; produksi memakai [PlusDependencies.controller].
  final PlusController? plusController;

  @override
  Widget build(BuildContext context) {
    final controller = themeController ?? ThemeModeController.instance;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) => PlusScope(
        controller: plusController ?? PlusDependencies.controller,
        child: MaterialApp.router(
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
            child: PushNotificationOverlayHost(
              router: hiqeoRouter,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}
