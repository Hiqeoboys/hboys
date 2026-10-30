import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/motion/visual_effect_policy.dart';
import 'package:nama_app/design/widgets/altracq_nav_bar.dart';
import 'package:nama_app/features/shell/altracq_shell.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

Widget navApp(VisualEffectPolicy policy, {required int currentIndex, ValueChanged<int>? onTap}) =>
    MaterialApp(
      theme: altracqLightTheme,
      home: Scaffold(
        body: const SizedBox.expand(),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.all(16),
          child: VisualEffectPolicyScope(
            policy: policy,
            child: AltracqNavBar(
              currentIndex: currentIndex,
              items: AltracqShell.navItems,
              onTap: onTap ?? (_) {},
            ),
          ),
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
  testWidgets('tab aktif mendapat lapisan cair saat gooey menyala',
      (tester) async {
    await tester.pumpWidget(
      navApp(VisualEffectPolicy.full, currentIndex: 0),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ImageFiltered), findsOneWidget);
    // Ambang alfa membungkus blur; kaca navigasi punya ColorFiltered sendiri.
    expect(
      find.ancestor(
        of: find.byType(ImageFiltered),
        matching: find.byType(ColorFiltered),
      ),
      findsOneWidget,
    );

    // Gelembung 20 px dan tetesan 12 px ikut digambar.
    final circles = tester
        .widgetList<Container>(find.byType(Container))
        .where(
          (container) =>
              container.constraints?.minWidth ==
              container.constraints?.maxWidth,
        )
        .map((container) => container.constraints?.maxWidth)
        .toList();
    expect(circles, contains(20));
    expect(circles, contains(12));
  });

  testWidgets('gooey mati: pill biasa dan tab tetap berpindah',
      (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(
      navApp(policy(reduceMotion: true), currentIndex: 0, onTap: taps.add),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ImageFiltered), findsNothing);
    await tester.tap(find.text('Peta'));
    expect(taps, <int>[1]);
  });

  testWidgets('profil daya Hemat mematikan cair di navigasi', (tester) async {
    await tester.pumpWidget(
      navApp(policy(power: PowerProfile.saver), currentIndex: 2),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets('jejak tab ujung tidak keluar dari navigasi', (tester) async {
    await tester.pumpWidget(
      navApp(VisualEffectPolicy.full, currentIndex: 4),
    );
    await tester.pumpAndSettle();

    final nav = tester.getRect(find.byType(AltracqNavBar));
    final gooey = tester.getRect(find.byType(ImageFiltered));
    expect(gooey.left, greaterThanOrEqualTo(nav.left));
    expect(gooey.right, lessThanOrEqualTo(nav.right));
  });
}
