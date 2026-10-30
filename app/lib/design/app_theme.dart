import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

/// Tema Material 3 yang seluruh warnanya berasal dari [AltracqColors].
ThemeData buildAltracqTheme(AltracqColors colors) {
  final scheme = ColorScheme(
    brightness: colors.brightness,
    primary: colors.primary,
    onPrimary: colors.onPrimary,
    primaryContainer: colors.secondary,
    onPrimaryContainer: colors.textPrimary,
    secondary: colors.secondary,
    onSecondary: colors.textPrimary,
    surface: colors.surface,
    onSurface: colors.textPrimary,
    onSurfaceVariant: colors.textSecondary,
    outline: colors.hairline,
    outlineVariant: colors.hairline,
    error: colors.warning,
    onError: colors.surface,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: colors.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.background,
    canvasColor: colors.background,
    fontFamily: AltracqTypography.family,
    textTheme: AltracqTypography.textTheme.apply(
      fontFamily: AltracqTypography.family,
      bodyColor: colors.textPrimary,
      displayColor: colors.textPrimary,
    ),
    extensions: <ThemeExtension<dynamic>>[colors],
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerTheme: DividerThemeData(
      color: colors.hairline,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: colors.textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: AltracqTypography.textTheme.titleLarge
          ?.copyWith(color: colors.textPrimary),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.textPrimary,
        minimumSize: const Size(AltracqMetrics.minTouchTarget, AltracqMetrics.minTouchTarget),
        textStyle: AltracqTypography.textTheme.labelLarge,
      ),
    ),
    iconTheme: IconThemeData(color: colors.textPrimary, size: 24),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.primary,
      linearTrackColor: colors.hairline,
      circularTrackColor: Colors.transparent,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.onPrimary
            : colors.surface,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.primary
            : colors.hairline,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
  );
}

ThemeData get altracqLightTheme => buildAltracqTheme(AltracqColors.light);

ThemeData get altracqDarkTheme => buildAltracqTheme(AltracqColors.dark);
