import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/app/router.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/glass/glass_surface.dart';
import 'package:nama_app/design/motion/visual_effect_policy.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/design/widgets/hiqeo_nav_bar.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

import '../support/hiqeo_app_harness.dart';

Widget glassApp({
  VisualEffectPolicy? policy,
  GlassTier? tier,
  Widget? child,
  Color? tint,
  bool? blurEnabledOverride,
  ThemeData? theme,
  bool wrapBackdropGroup = false,
}) {
  Widget surface = GlassSurface(
    tier: tier,
    tint: tint,
    blurEnabledOverride: blurEnabledOverride,
    child: child ?? const Text('Isi kaca'),
  );
  if (wrapBackdropGroup) {
    surface = BackdropGroup(child: surface);
  }
  return MaterialApp(
    theme: theme ?? hiqeoLightTheme,
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

Color backdropFillColor(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(
      of: find.byType(GlassSurface),
      matching: find.byKey(const ValueKey<String>('glass-surface-fill')),
    ),
  );
  return (box.decoration as BoxDecoration).color!;
}

void main() {
  setUp(GlassConfig.resetForTesting);
  tearDown(GlassConfig.resetForTesting);

  testWidgets('tier panel dengan kebijakan penuh memakai blur sigma 22 + fill kaca transparan',
      (tester) async {
    await tester.pumpWidget(
      glassApp(policy: VisualEffectPolicy.full, tier: GlassTier.panel),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
    final blur = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(blur.filter.toString(), contains('22'));
    expect(backdropFillColor(tester), HiqeoColors.light.glassFill);
  });

  testWidgets('overlay pantulan memakai gradien vertikal simetris (tanpa miring)',
      (tester) async {
    await tester.pumpWidget(
      glassApp(policy: VisualEffectPolicy.full, tier: GlassTier.navbar),
    );

    final reflection = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('glass-surface-reflection')),
    );
    final grad = (reflection.decoration as BoxDecoration).gradient!
        as LinearGradient;
    expect(grad.begin, Alignment.topCenter);
    expect(grad.end, Alignment.bottomCenter);
    expect(grad.stops, const <double>[0.0, 0.6]);
    expect(grad.colors.first.a, closeTo(0.10, 0.01));
    expect(grad.colors.last.a, closeTo(0.0, 0.001));
  });

  testWidgets('tier card memakai surface solid tanpa BackdropFilter & pantulan',
      (tester) async {
    await tester.pumpWidget(
      glassApp(policy: VisualEffectPolicy.full, tier: GlassTier.card),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('glass-surface-reflection')),
      findsNothing,
    );
    expect(backdropFillColor(tester), HiqeoColors.light.surface);
  });

  testWidgets('tier overMap memakai glassFillMap 92% tanpa blur secara baku',
      (tester) async {
    await tester.pumpWidget(
      glassApp(
        policy: VisualEffectPolicy.full,
        tier: GlassTier.overMap,
        theme: hiqeoDarkTheme,
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(backdropFillColor(tester), HiqeoColors.dark.glassFillMap);
  });

  testWidgets('profil daya Hemat tetap menyalakan blur kaca; hanya Kritis mematikannya dengan fill aman',
      (tester) async {
    await tester.pumpWidget(
      glassApp(policy: policy(power: PowerProfile.saver), tier: GlassTier.panel),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(backdropFillColor(tester), HiqeoColors.light.glassFill);
    expect(find.text('Isi kaca'), findsOneWidget);

    await tester.pumpWidget(
      glassApp(policy: policy(power: PowerProfile.critical), tier: GlassTier.panel),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    expect(backdropFillColor(tester), HiqeoColors.light.glassFillSafe);
    expect(find.text('Isi kaca'), findsOneWidget);
  });

  testWidgets('perangkat lemah mematikan blur namun menjaga fill aman',
      (tester) async {
    await tester.pumpWidget(
      glassApp(policy: policy(tier: DeviceTier.lowEnd), tier: GlassTier.panel),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(backdropFillColor(tester), HiqeoColors.light.glassFillSafe);
    expect(find.text('Isi kaca'), findsOneWidget);
  });

  testWidgets('kurangi animasi tidak mematikan blur kaca', (tester) async {
    await tester.pumpWidget(
      glassApp(policy: policy(reduceMotion: true), tier: GlassTier.panel),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('kilau sisi atas tidak menerima sentuhan', (tester) async {
    await tester.pumpWidget(
      glassApp(policy: VisualEffectPolicy.full, tier: GlassTier.panel),
    );

    final highlight = find.byKey(const ValueKey<String>('glass-surface-highlight'));
    expect(highlight, findsOneWidget);
    expect(tester.widget<IgnorePointer>(highlight).ignoring, isTrue);
  });

  testWidgets('tint dicampur ke fill kaca', (tester) async {
    const tint = Color(0x99313851);
    await tester.pumpWidget(
      glassApp(
        policy: VisualEffectPolicy.full,
        tier: GlassTier.panel,
        tint: tint,
      ),
    );

    expect(
      backdropFillColor(tester),
      Color.alphaBlend(tint, HiqeoColors.light.glassFill),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('isi kaca menentukan ukuran permukaan', (tester) async {
    await tester.pumpWidget(
      glassApp(
        policy: VisualEffectPolicy.full,
        tier: GlassTier.panel,
        child: const SizedBox(width: 200, height: 64),
      ),
    );

    expect(tester.getSize(find.byType(GlassSurface)).height, 64);
    expect(tester.getSize(find.byType(GlassSurface)).width, 200);
  });

  testWidgets('navigasi bawah memakai GlassSurface setinggi 64 px',
      (tester) async {
    final GoRouter router = buildHiqeoRouter();
    await tester.pumpWidget(buildHiqeoTestApp(router: router));
    router.go('/beranda');
    await tester.pumpAndSettle();

    final glass = find.descendant(
      of: find.byType(HiqeoNavBar),
      matching: find.byKey(const ValueKey<String>('navbar-liquid-glass')),
    );
    expect(glass, findsOneWidget);
    expect(
      tester.getSize(find.byType(HiqeoNavBar)).height,
      HiqeoMetrics.navbarHeight,
    );
  });
}
