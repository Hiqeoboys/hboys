import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'app/app.dart';
import 'features/tracking/application/tracking_controller.dart';
import 'infrastructure/supabase/supabase_services.dart';
import 'infrastructure/tracking/tracking_foreground_service.dart';

enum Flavor { dev, staging, prod }

class AppConfig {
  const AppConfig({required this.flavor, this.meshEnabled = false});

  final Flavor flavor;

  /// Feature flag: mesh BLE baru dinyalakan setelah spike Fase 0 lulus.
  final bool meshEnabled;
}

Future<void> bootstrap(Flavor flavor) async {
  WidgetsFlutterBinding.ensureInitialized();
  const mapboxToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
  if (mapboxToken.isNotEmpty &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    MapboxOptions.setAccessToken(mapboxToken);
  }
  if (Platform.isAndroid) {
    TrackingForegroundService.initialize();
  }
  // Tanpa kredensial Supabase, langkah ini tidak melakukan apa pun dan fitur
  // grup tetap nonaktif. Tidak ada panggilan jaringan saat inisialisasi.
  await SupabaseServices.initialize();
  // TODO(tim): inisialisasi urut -> notifikasi, pemantau konektivitas, error
  // handler.
  runApp(NamaApp(config: AppConfig(flavor: flavor)));
  // Memulihkan sesi yang masih aktif, termasuk setelah proses aplikasi mati.
  unawaited(TrackingController.instance.initialize());
}
