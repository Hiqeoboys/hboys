import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

/// Tema Material 3 yang seluruh warnanya berasal dari [HiqeoColors].
ThemeData buildHiqeoTheme(HiqeoColors colors) {
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
    fontFamily: HiqeoTypography.family,
    textTheme: HiqeoTypography.textTheme.apply(
      fontFamily: HiqeoTypography.family,
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
      titleTextStyle: HiqeoTypography.textTheme.titleLarge
          ?.copyWith(color: colors.textPrimary),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.textPrimary,
        minimumSize: const Size(HiqeoMetrics.minTouchTarget, HiqeoMetrics.minTouchTarget),
        textStyle: HiqeoTypography.textTheme.labelLarge,
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

ThemeData get hiqeoLightTheme => buildHiqeoTheme(HiqeoColors.light);

ThemeData get hiqeoDarkTheme => buildHiqeoTheme(HiqeoColors.dark);
