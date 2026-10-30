import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/design/typography.dart';

import '../support/contrast.dart';

void main() {
  const light = AltracqColors.light;
  const dark = AltracqColors.dark;

  group('kontras token memenuhi 4,5:1 untuk teks', () {
    test('mode terang', () {
      expect(contrastRatio(light.textPrimary, light.background), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(light.textSecondary, light.background), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(light.warningText, light.background), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(light.onPrimary, light.primary), greaterThanOrEqualTo(4.5));
    });

    test('mode gelap', () {
      expect(contrastRatio(dark.textPrimary, dark.background), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(dark.textSecondary, dark.background), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(dark.warningText, dark.background), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(dark.onPrimary, dark.primary), greaterThanOrEqualTo(4.5));
    });
  });

  test('warna rancangan tidak berubah', () {
    expect(light.background, const Color(0xFFF6F3ED));
    expect(light.primary, const Color(0xFF313851));
    expect(light.secondary, const Color(0xFFC2CBD3));
    expect(light.surface, const Color(0xFFFBF9F5));
    expect(light.warning, const Color(0xFFB3412F));
    expect(dark.background, const Color(0xFF313851));
    expect(dark.primary, const Color(0xFFF6F3ED));
    expect(dark.secondary, const Color(0xFF4B5573));
    expect(dark.textSecondary, const Color(0xFFA9B0C2));
    expect(dark.warning, const Color(0xFFE0705C));
  });

  test('tema membawa extension dan bobot tipografi rancangan', () {
    final theme = altracqLightTheme;
    expect(theme.extension<AltracqColors>(), light);
    expect(AltracqTypography.textTheme.displayLarge?.fontWeight, FontWeight.w800);
    expect(AltracqTypography.textTheme.labelLarge?.fontWeight, FontWeight.w700);
    expect(altracqDarkTheme.brightness, Brightness.dark);
    expect(altracqDarkTheme.scaffoldBackgroundColor, const Color(0xFF313851));
  });

  testWidgets('teks memakai Plus Jakarta Sans dari tema', (tester) async {
    late String? family;
    await tester.pumpWidget(
      MaterialApp(
        theme: altracqLightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              family = DefaultTextStyle.of(context).style.fontFamily;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(family, AltracqTypography.family);
  });

  testWidgets('AltracqColors.of membaca token dari tema aktif', (tester) async {
    late AltracqColors resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: altracqDarkTheme,
        home: Builder(
          builder: (context) {
            resolved = AltracqColors.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(resolved, dark);
    expect(resolved.brightness, Brightness.dark);
  });
}
