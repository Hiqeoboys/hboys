import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/gooey/gooey_layer.dart';
import 'package:nama_app/design/motion/visual_effect_policy.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

Widget policyApp(VisualEffectPolicy policy, Widget child) => MaterialApp(
      theme: hiqeoLightTheme,
      home: Scaffold(
        body: Center(
          child: VisualEffectPolicyScope(policy: policy, child: child),
        ),
      ),
    );

VisualEffectPolicy policy({
  PowerProfile power = PowerProfile.normal,
  bool reduceMotion = false,
  DeviceTier tier = DeviceTier.capable,
}) =>
    VisualEffectPolicy(
      powerProfile: power,
      reduceMotion: reduceMotion,
      deviceTier: tier,
    );

void main() {
  testWidgets('gooey menyala: bentuk dikaburkan lalu dipangkas alfanya',
      (tester) async {
    await tester.pumpWidget(
      policyApp(
        VisualEffectPolicy.full,
        const GooeyLayer(
          shapes: SizedBox(
            width: 120,
            height: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Color(0xFF313851)),
            ),
          ),
          child: Center(child: Text('Isi tajam')),
        ),
      ),
    );

    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(find.byType(ColorFiltered), findsOneWidget);
    expect(find.text('Isi tajam'), findsOneWidget);
  });

  testWidgets('konten tidak ikut dikaburkan', (tester) async {
    await tester.pumpWidget(
      policyApp(
        VisualEffectPolicy.full,
        const GooeyLayer(
          shapes: SizedBox(width: 120, height: 48),
          child: Center(child: Text('Isi tajam')),
        ),
      ),
    );

    expect(
      find.ancestor(
        of: find.text('Isi tajam'),
        matching: find.byType(ImageFiltered),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.text('Isi tajam'),
        matching: find.byType(ColorFiltered),
      ),
      findsNothing,
    );
  });

  testWidgets('gooey mati: bentuk tampil apa adanya, fungsi tetap',
      (tester) async {
    int taps = 0;
    for (final off in <VisualEffectPolicy>[
      policy(reduceMotion: true),
      policy(power: PowerProfile.saver),
      policy(power: PowerProfile.critical),
      policy(tier: DeviceTier.lowEnd),
    ]) {
      await tester.pumpWidget(
        policyApp(
          off,
          GooeyLayer(
            shapes: const SizedBox(width: 120, height: 48),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const Center(child: Text('Tekan')),
            ),
          ),
        ),
      );

      expect(find.byType(ImageFiltered), findsNothing, reason: '$off');
      expect(find.byType(ColorFiltered), findsNothing, reason: '$off');
      await tester.tap(find.text('Tekan'));
      expect(find.text('Tekan'), findsOneWidget, reason: '$off');
    }
    expect(taps, 4);
  });

  testWidgets('gooey menyala pun fungsi tidak bergantung pada efek',
      (tester) async {
    int taps = 0;
    await tester.pumpWidget(
      policyApp(
        VisualEffectPolicy.full,
        GooeyLayer(
          shapes: const SizedBox(width: 120, height: 48),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const Center(child: Text('Tekan')),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Tekan'));
    expect(taps, 1);
  });
}
