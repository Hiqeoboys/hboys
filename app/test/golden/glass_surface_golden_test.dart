import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/glass/glass_surface.dart';
import 'package:nama_app/design/motion/visual_effect_policy.dart';
import 'package:nama_app/design/tokens.dart';

import '../support/real_font.dart';

/// Latar bergaris kontras tinggi + teks untuk membuktikan teks di belakang
/// kaca tidak terbaca pada versi tanpa blur (fill aman) maupun dengan blur.
Widget _stripedTextBackdrop(HiqeoColors colors) {
  return Stack(
    fit: StackFit.expand,
    children: <Widget>[
      Column(
        children: <Widget>[
          for (var i = 0; i < 8; i++)
            Expanded(
              child: ColoredBox(
                color: i.isEven
                    ? colors.primary.withValues(alpha: 0.25)
                    : colors.warning.withValues(alpha: 0.22),
              ),
            ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (var i = 0; i < 6; i++)
              Text(
                'FITUR UTAMA • PETA OFFLINE • GUNUNG CIREMAI #$i',
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

Widget _tierShowcase({
  required ThemeData theme,
  required bool blurEnabled,
}) {
  final colors = theme.extension<HiqeoColors>()!;
  return MaterialApp(
    theme: theme,
    debugShowCheckedModeBanner: false,
    home: VisualEffectPolicyScope(
      policy: VisualEffectPolicy.full,
      child: BackdropGroup(
        child: Scaffold(
          backgroundColor: colors.background,
          body: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              _stripedTextBackdrop(colors),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final entry in const <(GlassTier, String)>[
                      (GlassTier.navbar, 'Tier: navbar'),
                      (GlassTier.panel, 'Tier: panel'),
                      (GlassTier.card, 'Tier: card (solid)'),
                      (GlassTier.overMap, 'Tier: overMap (92%)'),
                    ])
                      GlassSurface(
                        tier: entry.$1,
                        padding: const EdgeInsets.all(16),
                        blurEnabledOverride:
                            entry.$1 == GlassTier.card ? false : blurEnabled,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              entry.$2,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                            ),
                            Text(
                              blurEnabled && entry.$1 != GlassTier.card
                                  ? 'Blur aktif'
                                  : 'Fill aman',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(GlassConfig.resetForTesting);
  tearDown(GlassConfig.resetForTesting);

  group('Golden Tests GlassSurface semua tier (terang & gelap, blur ON & OFF)',
      () {
    test('alfa fill aman menjamin teks di belakang tidak terbaca tanpa blur', () {
      expect(HiqeoColors.light.glassFillSafe.a, closeTo(0.86, 0.01));
      expect(HiqeoColors.dark.glassFillSafe.a, closeTo(0.82, 0.01));
      expect(HiqeoColors.light.glassFillMap.a, closeTo(0.92, 0.01));
      expect(HiqeoColors.dark.glassFillMap.a, closeTo(0.92, 0.01));
      expect(HiqeoColors.light.surface.a, 1.0);
      expect(HiqeoColors.dark.surface.a, 1.0);
    });

    for (final mode in <(String, ThemeData)>[
      ('light', hiqeoLightTheme),
      ('dark', hiqeoDarkTheme),
    ]) {
      for (final blur in const <bool>[true, false]) {
        final suffix = blur ? 'blur_on' : 'blur_off';
        testWidgets('GlassSurface ${mode.$1} $suffix', (tester) async {
          tester.view.physicalSize = const Size(390, 560);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await loadPlusJakartaSans(tester);
          await tester.pumpWidget(
            _tierShowcase(theme: mode.$2, blurEnabled: blur),
          );
          await tester.pumpAndSettle();

          await expectLater(
            find.byType(Scaffold),
            matchesGoldenFile('goldens/glass_tiers_${mode.$1}_$suffix.png'),
          );
        });
      }
    }
  });
}
