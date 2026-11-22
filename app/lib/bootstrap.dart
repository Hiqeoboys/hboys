import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'design/system_ui.dart';
import 'infrastructure/network/hiqeo_http_overrides.dart';

enum Flavor { dev, staging, prod }

class AppConfig {
  const AppConfig({required this.flavor, this.meshEnabled = false});

  final Flavor flavor;

  /// Feature flag: mesh BLE baru dinyalakan setelah spike Fase 0 lulus.
  final bool meshEnabled;
}

/// Entry point ringan tanpa `await`: langsung menggambar [StartupGateScreen]
/// pada frame pertama agar serah-terima dari Android native splash mulus.
void bootstrap(Flavor flavor) {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    HttpOverrides.global = HiqeoHttpOverrides();
  }
  SystemChrome.setSystemUIOverlayStyle(hiqeoOverlayStyle(Brightness.dark));
  if (!kIsWeb && Platform.isAndroid) {
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  }
  runApp(NamaApp(config: AppConfig(flavor: flavor)));
}
