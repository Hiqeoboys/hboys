import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/app/router.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/glass/glass_surface.dart';
import 'package:nama_app/design/motion/visual_effect_policy.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/design/widgets/altracq_nav_bar.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

import '../support/altracq_app_harness.dart';

Widget glassApp({
  VisualEffectPolicy? policy,
  Widget? child,
  Color? tint,
}) {
  final surface = GlassSurface(
    tint: tint,
    child: child ?? const Text('Isi kaca'),
  );
  return MaterialApp(
    theme: altracqLightTheme,
    home: Scaffold(
      body: Center(
        child: policy == null
            ? surface
            : VisualEffectPolicyScope(policy: policy, child: surface),
      ),
    ),
  );
}

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

Color backdropColor(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byType(GlassSurface),
      matching: find.byType(Container),
    ),
  );
  return (container.decoration! as BoxDecoration).color!;
}

void main() {
  testWidgets('kebijakan penuh memakai blur dan saturasi', (tester) async {
    await tester.pumpWidget(glassApp(policy: VisualEffectPolicy.full));

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(ColorFiltered), findsOneWidget);
    final blur = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(blur.filter.toString(), contains('18'));
    expect(backdropColor(tester), AltracqColors.light.glassFill);
  });

  testWidgets('tanpa scope, kaca dianggap perangkat mampu', (tester) async {
    await tester.pumpWidget(glassApp());

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(ColorFiltered), findsOneWidget);
  });

  testWidgets('profil daya Hemat dan Kritis memakai isi pekat tanpa blur',
      (tester) async {
    for (final power in <PowerProfile>[
      PowerProfile.saver,
      PowerProfile.critical,
    ]) {
      await tester.pumpWidget(glassApp(policy: policy(power: power)));

      expect(find.byType(BackdropFilter), findsNothing, reason: '$power');
      expect(find.byType(ColorFiltered), findsNothing, reason: '$power');
      expect(backdropColor(tester), AltracqColors.light.glassFillFallback);
      expect(find.text('Isi kaca'), findsOneWidget, reason: '$power');
    }
  });

  testWidgets('perangkat lemah memakai isi pekat tanpa blur', (tester) async {
    await tester.pumpWidget(
      glassApp(policy: policy(tier: DeviceTier.lowEnd)),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(backdropColor(tester), AltracqColors.light.glassFillFallback);
    expect(find.text('Isi kaca'), findsOneWidget);
  });

  testWidgets('kurangi animasi tidak mematikan blur kaca', (tester) async {
    await tester.pumpWidget(glassApp(policy: policy(reduceMotion: true)));

    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('kilau sisi atas tidak menerima sentuhan', (tester) async {
    await tester.pumpWidget(glassApp(policy: VisualEffectPolicy.full));

    final highlight = find.descendant(
      of: find.byType(GlassSurface),
      matching: find.byType(IgnorePointer),
    );
    expect(highlight, findsOneWidget);
    expect(tester.widget<IgnorePointer>(highlight).ignoring, isTrue);
  });

  testWidgets('tint dicampur ke isi kaca tanpa mengganti warna dasar',
      (tester) async {
    const tint = Color(0x99313851);
    await tester.pumpWidget(
      glassApp(policy: VisualEffectPolicy.full, tint: tint),
    );

    expect(
      backdropColor(tester),
      Color.alphaBlend(tint, AltracqColors.light.glassFill),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('tanpa blur, tint tetap dicampur ke isi pekat', (tester) async {
    const tint = Color(0x99313851);
    await tester.pumpWidget(
      glassApp(
        policy: policy(power: PowerProfile.saver),
        tint: tint,
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(
      backdropColor(tester),
      Color.alphaBlend(tint, AltracqColors.light.glassFillFallback),
    );
  });

  testWidgets('isi kaca menentukan ukuran permukaan', (tester) async {
    await tester.pumpWidget(
      glassApp(
        policy: VisualEffectPolicy.full,
        child: const SizedBox(width: 200, height: 64),
      ),
    );

    expect(tester.getSize(find.byType(GlassSurface)).height, 64);
    expect(tester.getSize(find.byType(GlassSurface)).width, 200);
  });

  testWidgets('navigasi bawah memakai permukaan kaca setinggi 64 px',
      (tester) async {
    final GoRouter router = buildAltracqRouter();
    await tester.pumpWidget(buildAltracqTestApp(router: router));
    router.go('/beranda');
    await tester.pumpAndSettle();

    final glass = find.descendant(
      of: find.byType(AltracqNavBar),
      matching: find.byType(GlassSurface),
    );
    expect(glass, findsOneWidget);
    expect(
      tester.getSize(find.byType(AltracqNavBar)).height,
      AltracqMetrics.navbarHeight,
    );
  });
}
