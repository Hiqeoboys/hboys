import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/motion/visual_effect_policy.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/design/widgets/hiqeo_nav_bar.dart';
import 'package:nama_app/design/widgets/line_icons.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

import '../support/real_font.dart';

final List<HiqeoNavBarItem> _goldenItems = <HiqeoNavBarItem>[
  HiqeoNavBarItem(label: 'Beranda', icon: HiqeoIcons.home, route: '/beranda'),
  HiqeoNavBarItem(label: 'Peta', icon: HiqeoIcons.map, route: '/peta'),
  HiqeoNavBarItem(label: 'Track', icon: HiqeoIcons.activity, route: '/lacak'),
  HiqeoNavBarItem(label: 'Grup', icon: HiqeoIcons.group, route: '/grup'),
  HiqeoNavBarItem(label: 'Profil', icon: HiqeoIcons.user, route: '/profil'),
];

Widget _buildGoldenNavBar({
  required ThemeData theme,
  required int currentIndex,
  ValueChanged<int>? onTap,
  bool overMap = false,
}) {
  return MaterialApp(
    theme: theme,
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: theme.extension<HiqeoColors>()!.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: VisualEffectPolicyScope(
            policy: const VisualEffectPolicy(
              powerProfile: PowerProfile.normal,
              reduceMotion: false,
              deviceTier: DeviceTier.capable,
            ),
            child: HiqeoNavBar(
              currentIndex: currentIndex,
              items: _goldenItems,
              overMap: overMap,
              onTap: onTap ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
}

class _AnimatedGoldenHarness extends StatefulWidget {
  const _AnimatedGoldenHarness({
    required this.theme,
    required this.initialIndex,
  });

  final ThemeData theme;
  final int initialIndex;

  @override
  State<_AnimatedGoldenHarness> createState() => _AnimatedGoldenHarnessState();
}

class _AnimatedGoldenHarnessState extends State<_AnimatedGoldenHarness> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    return _buildGoldenNavBar(
      theme: widget.theme,
      currentIndex: _index,
      onTap: (target) => setState(() => _index = target),
    );
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('Golden Tests HiqeoNavBar 5 Tab (tanpa bercak putih)', () {
    const tabs = <String>['beranda', 'peta', 'track', 'grup', 'profil'];

    // Mode Terang (semua 5 posisi tab)
    for (int i = 0; i < 5; i++) {
      testWidgets('Golden navbar mode terang tab $i (${tabs[i]})',
          (tester) async {
        tester.view.physicalSize = const Size(390, 160);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await loadPlusJakartaSans(tester);

        await tester.pumpWidget(
          _buildGoldenNavBar(
            theme: hiqeoLightTheme,
            currentIndex: i,
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(HiqeoNavBar),
          matchesGoldenFile('goldens/nav_bar_light_tab$i.png'),
        );
      });
    }

    // Mode Gelap (semua 5 posisi tab)
    for (int i = 0; i < 5; i++) {
      testWidgets('Golden navbar mode gelap tab $i (${tabs[i]})',
          (tester) async {
        tester.view.physicalSize = const Size(390, 160);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await loadPlusJakartaSans(tester);

        await tester.pumpWidget(
          _buildGoldenNavBar(
            theme: hiqeoDarkTheme,
            currentIndex: i,
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(HiqeoNavBar),
          matchesGoldenFile('goldens/nav_bar_dark_tab$i.png'),
        );
      });
    }

    // Transisi di tengah gerak (frame 300 ms) mode terang
    testWidgets('Golden navbar frame tengah transisi 300 ms mode terang',
        (tester) async {
      tester.view.physicalSize = const Size(390, 160);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await loadPlusJakartaSans(tester);

      await tester.pumpWidget(
        _AnimatedGoldenHarness(
          theme: hiqeoLightTheme,
          initialIndex: 0,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Track'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await expectLater(
        find.byType(HiqeoNavBar),
        matchesGoldenFile('goldens/nav_bar_light_mid_transition.png'),
      );
      await tester.pumpAndSettle();
    });

    // Transisi di tengah gerak (frame 300 ms) mode gelap
    testWidgets('Golden navbar frame tengah transisi 300 ms mode gelap',
        (tester) async {
      tester.view.physicalSize = const Size(390, 160);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await loadPlusJakartaSans(tester);

      await tester.pumpWidget(
        _AnimatedGoldenHarness(
          theme: hiqeoDarkTheme,
          initialIndex: 1,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Grup'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await expectLater(
        find.byType(HiqeoNavBar),
        matchesGoldenFile('goldens/nav_bar_dark_mid_transition.png'),
      );
      await tester.pumpAndSettle();
    });
  });
}
