import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/gooey/gooey_selector.dart';
import 'package:nama_app/design/gooey/gooey_switch.dart';
import 'package:nama_app/design/tokens.dart';

import '../support/real_font.dart';

const List<String> _days = <String>['Sabtu', 'Minggu', 'Senin'];

Widget _planCard(
  BuildContext context,
  GooeySelectorItemState state,
  HiqeoColors colors, {
  required String title,
  required String detail,
  required String price,
  required double height,
}) {
  final theme = Theme.of(context);
  final foreground =
      Color.lerp(colors.textSecondary, colors.onPrimary, state.coverage)!;
  return Container(
    height: height,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(HiqeoRadius.card),
      border: Border.all(
        color: state.selected ? Colors.transparent : colors.glassBorder,
      ),
    ),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: foreground.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        Text(
          price,
          style: theme.textTheme.titleSmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

Widget _gallery(ThemeData theme, HiqeoColors colors) {
  return MaterialApp(
    theme: theme,
    home: Scaffold(
      backgroundColor: colors.background,
      body: Center(
        child: SizedBox(
          width: 328,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Tab hari',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              GooeySelector<String>(
                axis: Axis.horizontal,
                selected: 'Minggu',
                gap: 4,
                onChanged: (_) {},
                items: <GooeySelectorItem<String>>[
                  for (final day in _days)
                    GooeySelectorItem<String>(
                      value: day,
                      semanticsLabel: day,
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Paket',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              GooeySelector<String>(
                axis: Axis.vertical,
                selected: 'Tahunan',
                gap: 8,
                borderRadius: HiqeoRadius.card,
                itemPadding: EdgeInsets.zero,
                onChanged: (_) {},
                items: <GooeySelectorItem<String>>[
                  GooeySelectorItem<String>(
                    value: 'Tahunan',
                    semanticsLabel: 'Tahunan',
                    builder: (context, state) => _planCard(
                      context,
                      state,
                      colors,
                      title: 'Tahunan',
                      detail: 'Rp149.000 per tahun',
                      price: 'PALING PAS',
                      height: 72,
                    ),
                  ),
                  GooeySelectorItem<String>(
                    value: 'Pelajar',
                    semanticsLabel: 'Pelajar',
                    builder: (context, state) => _planCard(
                      context,
                      state,
                      colors,
                      title: 'Pelajar',
                      detail: 'Rp79.000 per tahun',
                      price: 'HEMAT',
                      height: 72,
                    ),
                  ),
                  GooeySelectorItem<String>(
                    value: 'Tiket',
                    semanticsLabel: 'Tiket',
                    builder: (context, state) => _planCard(
                      context,
                      state,
                      colors,
                      title: 'Tiket 7 hari',
                      detail: 'Rp29.900 sekali naik',
                      price: '',
                      height: 64,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  GooeySwitch(
                    value: true,
                    semanticsLabel: 'Cadangkan otomatis',
                    onChanged: (_) {},
                  ),
                  const SizedBox(width: 24),
                  GooeySwitch(
                    value: false,
                    semanticsLabel: 'Tampilkan saya di papan',
                    onChanged: (_) {},
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: HiqeoColors.dark.background,
                  borderRadius: BorderRadius.circular(HiqeoRadius.card),
                  border: Border.all(
                    color: HiqeoColors.dark.glassBorder,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Sembunyikan lokasi di kartu',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: HiqeoColors.dark.textPrimary,
                        ),
                      ),
                    ),
                    GooeySwitch(
                      value: true,
                      semanticsLabel: 'Sembunyikan lokasi',
                      style: GooeySwitchStyle.recap(HiqeoColors.dark),
                      onChanged: (_) {},
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

Future<void> _pumpGallery(
  WidgetTester tester,
  ThemeData theme,
  HiqeoColors colors,
) async {
  await loadPlusJakartaSans(tester);
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_gallery(theme, colors));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('golden komponen gooey mode terang', (tester) async {
    await _pumpGallery(tester, hiqeoLightTheme, HiqeoColors.light);
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/gooey_components_light.png'),
    );
  });

  testWidgets('golden komponen gooey mode malam', (tester) async {
    await _pumpGallery(tester, hiqeoDarkTheme, HiqeoColors.dark);
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/gooey_components_dark.png'),
    );
  });
}
