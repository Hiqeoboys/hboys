import 'package:flutter/material.dart';

/// Tipografi Plus Jakarta Sans (400/500/700/800) sesuai rancangan.
class AltracqTypography {
  const AltracqTypography._();

  static const String family = 'PlusJakartaSans';

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight bold = FontWeight.w700;
  static const FontWeight extraBold = FontWeight.w800;

  static const TextTheme textTheme = TextTheme(
    displayLarge: TextStyle(
      fontSize: 40,
      fontWeight: extraBold,
      height: 1.1,
      letterSpacing: -0.8,
    ),
    displayMedium: TextStyle(
      fontSize: 32,
      fontWeight: extraBold,
      height: 1.15,
      letterSpacing: -0.6,
    ),
    displaySmall: TextStyle(
      fontSize: 26,
      fontWeight: extraBold,
      height: 1.2,
      letterSpacing: -0.4,
    ),
    headlineMedium: TextStyle(
      fontSize: 22,
      fontWeight: bold,
      height: 1.25,
      letterSpacing: -0.2,
    ),
    headlineSmall: TextStyle(
      fontSize: 20,
      fontWeight: bold,
      height: 1.3,
      letterSpacing: -0.2,
    ),
    titleLarge: TextStyle(fontSize: 18, fontWeight: bold, height: 1.35),
    titleMedium: TextStyle(fontSize: 16, fontWeight: bold, height: 1.4),
    titleSmall: TextStyle(fontSize: 15, fontWeight: medium, height: 1.4),
    bodyLarge: TextStyle(fontSize: 16, fontWeight: regular, height: 1.5),
    bodyMedium: TextStyle(fontSize: 14, fontWeight: regular, height: 1.5),
    bodySmall: TextStyle(fontSize: 13, fontWeight: regular, height: 1.45),
    labelLarge: TextStyle(fontSize: 15, fontWeight: bold, height: 1.3),
    labelMedium: TextStyle(fontSize: 13, fontWeight: medium, height: 1.35),
    labelSmall: TextStyle(
      fontSize: 11,
      fontWeight: bold,
      height: 1.3,
      letterSpacing: 0.8,
    ),
  );

  /// Gaya label kecil kapital (mis. "PUNCAK", "CEDERA") pada rancangan.
  static TextStyle overline(Color color) => TextStyle(
        fontSize: 11,
        fontWeight: bold,
        letterSpacing: 1.1,
        height: 1.3,
        color: color,
      );
}
