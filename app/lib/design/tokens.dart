import 'package:flutter/material.dart';

/// Warna rancangan UI/UX Altracq untuk mode terang dan gelap.
///
/// Ambil lewat [AltracqColors.of] agar pilihan Terang/Gelap/Ikuti sistem
/// berlaku seragam; jangan menuliskan warna langsung di layar.
@immutable
class AltracqColors extends ThemeExtension<AltracqColors> {
  const AltracqColors({
    required this.brightness,
    required this.background,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.warning,
    required this.warningText,
    required this.hairline,
    required this.blobTopLeft,
    required this.blobBottomRight,
    required this.glassFill,
    required this.glassFillFallback,
    required this.glassBorder,
    required this.glassHighlight,
    required this.glassShadow,
  });

  /// Token mode terang sesuai rancangan.
  static const AltracqColors light = AltracqColors(
    brightness: Brightness.light,
    background: Color(0xFFF6F3ED),
    primary: Color(0xFF313851),
    onPrimary: Color(0xFFF6F3ED),
    secondary: Color(0xFFC2CBD3),
    surface: Color(0xFFFBF9F5),
    textPrimary: Color(0xFF313851),
    textSecondary: Color(0xFF5B6275),
    warning: Color(0xFFB3412F),
    warningText: Color(0xFFB3412F),
    hairline: Color(0x1A313851),
    blobTopLeft: Color(0xFFC2CBD3),
    blobBottomRight: Color(0x33313851),
    glassFill: Color(0x8CFBF9F5),
    glassFillFallback: Color(0xE6FBF9F5),
    glassBorder: Color(0xBFFFFFFF),
    glassHighlight: Color(0xFFFFFFFF),
    glassShadow: Color(0x1F313851),
  );

  /// Token mode gelap: palet terang dibalik.
  ///
  /// [warningText] diperingan dari [warning] karena #E0705C di atas #313851
  /// hanya 3,7:1; teks kecil butuh minimal 4,5:1. [surface] dan kedua blob
  /// tidak dirinci rancangan, dipilih sedikit lebih terang dari latar.
  static const AltracqColors dark = AltracqColors(
    brightness: Brightness.dark,
    background: Color(0xFF313851),
    primary: Color(0xFFF6F3ED),
    onPrimary: Color(0xFF313851),
    secondary: Color(0xFF4B5573),
    surface: Color(0xFF3B4462),
    textPrimary: Color(0xFFF6F3ED),
    textSecondary: Color(0xFFA9B0C2),
    warning: Color(0xFFE0705C),
    warningText: Color(0xFFF08E7C),
    hairline: Color(0x1FF6F3ED),
    blobTopLeft: Color(0xFF4B5573),
    blobBottomRight: Color(0x1FF6F3ED),
    glassFill: Color(0x14F6F3ED),
    glassFillFallback: Color(0x24F6F3ED),
    glassBorder: Color(0x2EF6F3ED),
    glassHighlight: Color(0x40F6F3ED),
    glassShadow: Color(0x59000000),
  );

  final Brightness brightness;
  final Color background;
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;

  /// Hanya untuk SOS dan baterai kritis.
  final Color warning;

  /// Varian [warning] yang aman untuk teks kecil.
  final Color warningText;

  final Color hairline;
  final Color blobTopLeft;
  final Color blobBottomRight;
  final Color glassFill;

  /// Dipakai saat efek blur dimatikan (perangkat lemah, profil daya Hemat/Kritis).
  final Color glassFillFallback;

  final Color glassBorder;
  final Color glassHighlight;
  final Color glassShadow;

  static AltracqColors of(BuildContext context) {
    final colors = Theme.of(context).extension<AltracqColors>();
    assert(colors != null, 'AltracqColors belum dipasang di tema.');
    return colors!;
  }

  @override
  AltracqColors copyWith({
    Brightness? brightness,
    Color? background,
    Color? primary,
    Color? onPrimary,
    Color? secondary,
    Color? surface,
    Color? textPrimary,
    Color? textSecondary,
    Color? warning,
    Color? warningText,
    Color? hairline,
    Color? blobTopLeft,
    Color? blobBottomRight,
    Color? glassFill,
    Color? glassFillFallback,
    Color? glassBorder,
    Color? glassHighlight,
    Color? glassShadow,
  }) {
    return AltracqColors(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      secondary: secondary ?? this.secondary,
      surface: surface ?? this.surface,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      warning: warning ?? this.warning,
      warningText: warningText ?? this.warningText,
      hairline: hairline ?? this.hairline,
      blobTopLeft: blobTopLeft ?? this.blobTopLeft,
      blobBottomRight: blobBottomRight ?? this.blobBottomRight,
      glassFill: glassFill ?? this.glassFill,
      glassFillFallback: glassFillFallback ?? this.glassFillFallback,
      glassBorder: glassBorder ?? this.glassBorder,
      glassHighlight: glassHighlight ?? this.glassHighlight,
      glassShadow: glassShadow ?? this.glassShadow,
    );
  }

  @override
  AltracqColors lerp(covariant ThemeExtension<AltracqColors>? other, double t) {
    if (other is! AltracqColors) return this;
    return AltracqColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: Color.lerp(background, other.background, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningText: Color.lerp(warningText, other.warningText, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      blobTopLeft: Color.lerp(blobTopLeft, other.blobTopLeft, t)!,
      blobBottomRight: Color.lerp(blobBottomRight, other.blobBottomRight, t)!,
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      glassFillFallback: Color.lerp(glassFillFallback, other.glassFillFallback, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      glassHighlight: Color.lerp(glassHighlight, other.glassHighlight, t)!,
      glassShadow: Color.lerp(glassShadow, other.glassShadow, t)!,
    );
  }
}

/// Jarak antar elemen. Skala 4 px.
class AltracqSpacing {
  const AltracqSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: lg);
}

/// Sudut pembulatan.
class AltracqRadius {
  const AltracqRadius._();

  static const double card = 18;
  static const double floating = 16;
  static const double hero = 28;
  static const double navbar = 32;
  static const double pill = 999;
}

/// Ukuran tetap dari rancangan.
class AltracqMetrics {
  const AltracqMetrics._();

  static const double navbarHeight = 64;
  static const double navbarInset = 16;
  static const double minTouchTarget = 44;
  static const double iconStroke = 1.8;
  static const double navbarPillWidth = 66;
  static const double navbarPillHeight = 52;
  static const double buttonPairGap = 12;

  /// Jarak dari tepi bawah layar ke atas navbar mengambang: tinggi navbar,
  /// inset 16 px, dan inset sistem (gestur atau tombol navigasi).
  ///
  /// Dipakai untuk padding bawah isi tab supaya tidak tertutup navbar.
  static double floatingBottomInset(double systemInset) =>
      navbarHeight + navbarInset + systemInset;
}

/// Parameter liquid glass.
class AltracqGlass {
  const AltracqGlass._();

  /// `backdrop-filter: blur(18px)` pada rancangan = deviasi standar 18.
  static const double blurSigma = 18;
  static const double saturation = 1.7;
  static const double borderWidth = 1;

  /// Kilau putih 1 px di sisi atas kaca.
  static const double highlightWidth = 1;

  static BoxShadow shadow(AltracqColors colors) => BoxShadow(
        color: colors.glassShadow,
        blurRadius: 24,
        offset: const Offset(0, 8),
      );
}

/// Parameter gooey (metaball): bentuk dikaburkan lalu alfa dipangkas dengan
/// alfa' = alfa * [alphaScale] + [alphaShift], sehingga tepi kabur menyatu
/// menjadi jembatan cair.
///
/// [ColorFilter.matrix] bekerja pada kanal 0–255, bukan 0–1 seperti filter CSS.
/// Nilai CSS `alpha' = alpha * 20 - 9` karena itu setara geseran -9 × 255.
class AltracqGooey {
  const AltracqGooey._();

  static const double blurSigma = 6;
  static const double alphaScale = 20;
  static const double alphaShift = -2295;
}

/// Durasi dan kurva animasi.
class AltracqMotion {
  const AltracqMotion._();

  static const Duration fast = Duration(milliseconds: 140);
  static const Duration press = Duration(milliseconds: 180);
  static const Duration spring = Duration(milliseconds: 420);
  static const Duration screenFade = Duration(milliseconds: 260);

  static const Curve standard = Curves.easeOutCubic;
}
