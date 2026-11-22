import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Tingkatan permukaan kaca pada sistem desain Hiqeo.
///
/// - [navbar]: bilah navigasi bawah (maks 1 BackdropFilter + fill aman).
/// - [panel]: panel mengambang dan bottom sheet (BackdropFilter + fill aman).
/// - [card]: kartu daftar panjang (fill solid + border, TANPA BackdropFilter).
/// - [overMap]: panel dan kontrol di atas peta Mapbox (fill rapat 92%,
///   TANPA BackdropFilter kecuali [GlassConfig.enableOverMapBlur] diaktifkan).
enum GlassTier {
  navbar,
  panel,
  card,
  overMap,
}

/// Varian implementasi efek blur kaca hasil uji diagnosa perangkat.
enum GlassBlurVariant {
  /// V1: BackdropFilter polos (sigma 24).
  standard,

  /// V2: BackdropFilter + RepaintBoundary luar + ClipRRect dalam.
  repaintBoundaryClip,

  /// V3a: BackdropFilter dengan TileMode.mirror.
  tileModeMirror,

  /// V3b: BackdropFilter dengan TileMode.decal.
  tileModeDecal,

  /// V4: BackdropFilter.grouped dengan BackdropGroup.
  grouped,

  /// V5: Tanpa BackdropFilter, hanya fill aman.
  safeFillOnly,
}

/// Konfigurasi tunggal efek kaca seluruh aplikasi.
///
/// Pilihan varian akhir dapat diubah dengan satu konstanta [defaultVariant].
/// Tidak ada sakelar di Pengaturan; perangkat yang bermasalah otomatis jatuh
/// ke [GlassBlurVariant.safeFillOnly] lewat [detectFromDevice].
class GlassConfig {
  GlassConfig._();

  /// Satu konstanta untuk mengganti varian kaca standar seluruh aplikasi.
  static const GlassBlurVariant defaultVariant = GlassBlurVariant.standard;

  /// Aktifkan blur di atas peta Mapbox HANYA bila uji V6 (TextureView) terbukti
  /// bekerja mulus di perangkat target.
  static const bool enableOverMapBlur = false;

  /// Daftar fragmen model/perangkat (huruf kecil) yang harus langsung memakai
  /// fallback tanpa BackdropFilter berdasarkan hasil uji perangkat nyata.
  static const Set<String> fallbackDeviceModels = <String>{
    // Tambahkan fragmen model perangkat bermasalah setelah uji "Uji kaca",
    // misalnya: 'redmi 9', 'sm-a03', dst.
  };

  /// Versi Android SDK minimum yang mendukung blur BackdropFilter secara andal.
  /// Android < 8.0 (API 26) langsung memakai fallback fill aman.
  static const int minAndroidSdkForBlur = 26;

  static GlassBlurVariant _activeVariant = defaultVariant;
  static bool _overMapBlurEnabled = enableOverMapBlur;
  static String? _detectedDeviceLabel;
  static String? _detectedOsLabel;
  static bool _initialized = false;

  /// Varian blur yang sedang aktif pada sesi ini.
  static GlassBlurVariant get activeVariant => _activeVariant;

  /// Apakah blur pada tier [GlassTier.overMap] diaktifkan.
  static bool get overMapBlurEnabled => _overMapBlurEnabled;

  /// Label perangkat hasil deteksi [device_info_plus] (jika sudah dijalankan).
  static String? get detectedDeviceLabel => _detectedDeviceLabel;

  /// Label versi OS hasil deteksi [device_info_plus].
  static String? get detectedOsLabel => _detectedOsLabel;

  /// Mode build aplikasi saat ini.
  static String get buildModeLabel {
    if (kReleaseMode) return 'Release';
    if (kProfileMode) return 'Profile';
    return 'Debug';
  }

  /// Indikasi renderer aktif berdasarkan dukungan shader filter Impeller.
  static String get activeRendererLabel =>
      ui.ImageFilter.isShaderFilterSupported
          ? 'Impeller (shader filter aktif)'
          : 'Skia (atau Impeller nonaktif)';

  /// Menentukan apakah [tier] memakai BackdropFilter pada konfigurasi saat ini.
  static bool shouldUseBlur(GlassTier tier) {
    if (_activeVariant == GlassBlurVariant.safeFillOnly) return false;
    return switch (tier) {
      GlassTier.navbar => true,
      GlassTier.panel => true,
      GlassTier.card => false,
      GlassTier.overMap => _overMapBlurEnabled,
    };
  }

  /// Mode ubin (TileMode) untuk [ui.ImageFilter.blur] sesuai varian aktif.
  static ui.TileMode get activeTileMode => switch (_activeVariant) {
        GlassBlurVariant.tileModeMirror => ui.TileMode.mirror,
        GlassBlurVariant.tileModeDecal => ui.TileMode.decal,
        _ => ui.TileMode.clamp,
      };

  /// Memeriksa apakah perangkat perlu jatuh ke mode fill aman tanpa blur.
  @visibleForTesting
  static bool shouldFallbackForDevice({
    required String model,
    String? manufacturer,
    int? androidSdkInt,
  }) {
    if (androidSdkInt != null && androidSdkInt < minAndroidSdkForBlur) {
      return true;
    }
    final normalized =
        '${manufacturer ?? ''} $model'.trim().toLowerCase();
    for (final blocked in fallbackDeviceModels) {
      if (blocked.isNotEmpty && normalized.contains(blocked.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  /// Membaca model perangkat dan versi OS melalui `device_info_plus` lalu
  /// memilih varian blur secara otomatis. Aman dipanggil sekali saat startup.
  static Future<void> detectFromDevice({DeviceInfoPlugin? plugin}) async {
    if (_initialized) return;
    _initialized = true;
    if (kIsWeb) {
      _detectedDeviceLabel = 'Web';
      _detectedOsLabel = 'Browser';
      return;
    }
    try {
      final info = plugin ?? DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        _detectedDeviceLabel = '${android.manufacturer} ${android.model}'.trim();
        _detectedOsLabel =
            'Android ${android.version.release} (API ${android.version.sdkInt})';
        if (shouldFallbackForDevice(
          model: android.model,
          manufacturer: android.manufacturer,
          androidSdkInt: android.version.sdkInt,
        )) {
          _activeVariant = GlassBlurVariant.safeFillOnly;
        }
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        _detectedDeviceLabel = '${ios.name} (${ios.utsname.machine})'.trim();
        _detectedOsLabel = '${ios.systemName} ${ios.systemVersion}';
      } else {
        _detectedDeviceLabel = Platform.operatingSystem;
        _detectedOsLabel = Platform.operatingSystemVersion;
      }
    } catch (_) {
      // Tetap gunakan varian bawaan jika plugin tidak tersedia (mis. widget test).
    }
  }

  /// Menimpa konfigurasi kaca untuk pengujian unit/widget/golden.
  @visibleForTesting
  static void overrideForTesting({
    GlassBlurVariant? variant,
    bool? overMapBlur,
  }) {
    if (variant != null) _activeVariant = variant;
    if (overMapBlur != null) _overMapBlurEnabled = overMapBlur;
  }

  /// Mengembalikan konfigurasi kaca ke nilai bawaan setelah pengujian.
  @visibleForTesting
  static void resetForTesting() {
    _activeVariant = defaultVariant;
    _overMapBlurEnabled = enableOverMapBlur;
    _initialized = false;
  }
}
