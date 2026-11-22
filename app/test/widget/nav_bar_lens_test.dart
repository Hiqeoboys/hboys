import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/motion/visual_effect_policy.dart';
import 'package:nama_app/design/widgets/hiqeo_nav_bar.dart';
import 'package:nama_app/design/widgets/line_icons.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

import '../support/real_font.dart';

final List<HiqeoNavBarItem> _testNavItems = <HiqeoNavBarItem>[
  HiqeoNavBarItem(label: 'Beranda', icon: HiqeoIcons.home, route: '/beranda'),
  HiqeoNavBarItem(label: 'Peta', icon: HiqeoIcons.map, route: '/peta'),
  HiqeoNavBarItem(label: 'Track', icon: HiqeoIcons.activity, route: '/lacak'),
  HiqeoNavBarItem(label: 'Grup', icon: HiqeoIcons.group, route: '/grup'),
  HiqeoNavBarItem(label: 'Profil', icon: HiqeoIcons.user, route: '/profil'),
];

Widget _buildNavBarHarness({
  int initialIndex = 0,
  ValueChanged<int>? onTap,
  bool reduceMotion = false,
  ThemeData? theme,
  double screenWidth = 390,
}) {
  return MaterialApp(
    theme: theme ?? hiqeoLightTheme,
    home: Scaffold(
      body: const SizedBox.expand(),
      bottomNavigationBar: MediaQuery(
        data: MediaQueryData(
          size: Size(screenWidth, 844),
          disableAnimations: reduceMotion,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: _StatefulHarness(
            initialIndex: initialIndex,
            onTap: onTap,
            reduceMotion: reduceMotion,
          ),
        ),
      ),
    ),
  );
}

class _StatefulHarness extends StatefulWidget {
  const _StatefulHarness({
    required this.initialIndex,
    this.onTap,
    this.reduceMotion = false,
  });

  final int initialIndex;
  final ValueChanged<int>? onTap;
  final bool reduceMotion;

  @override
  State<_StatefulHarness> createState() => _StatefulHarnessState();
}

class _StatefulHarnessState extends State<_StatefulHarness> {
  late int _currentIndex = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    return VisualEffectPolicyScope(
      policy: VisualEffectPolicy(
        powerProfile: PowerProfile.normal,
        reduceMotion: widget.reduceMotion,
        deviceTier: DeviceTier.capable,
      ),
      child: HiqeoNavBar(
        currentIndex: _currentIndex,
        items: _testNavItems,
        onTap: (index) {
          widget.onTap?.call(index);
          setState(() => _currentIndex = index);
        },
      ),
    );
  }
}

Finder _tabSemantics(String label) => find.descendant(
      of: find.byType(HiqeoNavBar),
      matching: find.bySemanticsLabel(label),
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('HiqeoNavBar Lensa Kaca Widget Tests', () {
    testWidgets('ketukan berpindah tab memanggil callback segera tanpa menunggu 600 ms',
        (tester) async {
      await loadPlusJakartaSans(tester);
      int? tappedIndex;

      await tester.pumpWidget(
        _buildNavBarHarness(
          initialIndex: 0,
          onTap: (index) => tappedIndex = index,
        ),
      );
      await tester.pumpAndSettle();

      expect(tappedIndex, isNull);

      // Ketuk tab Peta
      await tester.tap(_tabSemantics('Peta'));
      // Verifikasi callback dipanggil seketika pada frame ketukan (tanpa pump durasi)
      expect(tappedIndex, 1);

      // Animasi sedang berjalan (600 ms)
      expect(tester.hasRunningAnimations, isTrue);

      // Jalankan sisa animasi hingga selesai
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('ketukan berturut-turut cepat (Peta ke Grup ke Profil) tidak melompat',
        (tester) async {
      await loadPlusJakartaSans(tester);
      final tappedList = <int>[];

      await tester.pumpWidget(
        _buildNavBarHarness(
          initialIndex: 0,
          onTap: (index) => tappedList.add(index),
        ),
      );
      await tester.pumpAndSettle();

      // Ketuk Peta (indeks 1)
      await tester.tap(_tabSemantics('Peta'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tappedList, <int>[1]);
      expect(tester.hasRunningAnimations, isTrue);

      // Ketuk Grup (indeks 3) di tengah transisi
      await tester.tap(_tabSemantics('Grup'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tappedList, <int>[1, 3]);
      expect(tester.hasRunningAnimations, isTrue);

      // Ketuk Profil (indeks 4) di tengah transisi
      await tester.tap(_tabSemantics('Profil'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tappedList, <int>[1, 3, 4]);
      expect(tester.hasRunningAnimations, isTrue);

      // Biarkan seluruh animasi selesai dengan lancar
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('slot tengah adalah tab Track interaktif tanpa logo non-interaktif',
        (tester) async {
      await loadPlusJakartaSans(tester);
      int? tappedIndex;

      await tester.pumpWidget(
        _buildNavBarHarness(
          initialIndex: 0,
          onTap: (index) => tappedIndex = index,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(HiqeoNavBar),
          matching: find.bySemanticsLabel('Hiqeo'),
        ),
        findsNothing,
      );

      await tester.tap(_tabSemantics('Track'));
      await tester.pump();
      expect(tappedIndex, 2);
      await tester.pumpAndSettle();
    });

    testWidgets('ketukan pada tab yang sudah aktif tidak memicu animasi transisi',
        (tester) async {
      await loadPlusJakartaSans(tester);
      int callCount = 0;

      await tester.pumpWidget(
        _buildNavBarHarness(
          initialIndex: 0,
          onTap: (_) => callCount++,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_tabSemantics('Beranda'));
      await tester.pump();

      // Panggilan tetap diteruskan (untuk re-select / scroll-to-top)
      expect(callCount, 1);
      // Tetapi tidak ada animasi transisi yang berjalan
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('aksesibilitas semantics dan tooltip untuk tab tidak aktif',
        (tester) async {
      await loadPlusJakartaSans(tester);
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _buildNavBarHarness(initialIndex: 1), // Peta aktif
      );
      await tester.pumpAndSettle();

      // Tab Peta (aktif): terpilih, tombol, label "Peta", tanpa tooltip
      final petaNode = tester.getSemantics(_tabSemantics('Peta'));
      expect(petaNode.flagsCollection.isButton, isTrue);
      expect(petaNode.flagsCollection.isSelected, ui.Tristate.isTrue);
      expect(petaNode.label, 'Peta');
      expect(petaNode.tooltip.isEmpty, isTrue);

      // Tab Beranda (tidak aktif): tidak terpilih, tombol, label "Beranda", punya tooltip
      final berandaNode = tester.getSemantics(_tabSemantics('Beranda'));
      expect(berandaNode.flagsCollection.isButton, isTrue);
      expect(berandaNode.flagsCollection.isSelected, isNot(ui.Tristate.isTrue));
      expect(berandaNode.label, 'Beranda');
      expect(berandaNode.tooltip, 'Beranda');

      // Tab Track di tengah: tombol interaktif dengan tooltip saat tidak aktif
      final trackNode = tester.getSemantics(_tabSemantics('Track'));
      expect(trackNode.flagsCollection.isButton, isTrue);
      expect(trackNode.flagsCollection.isSelected, isNot(ui.Tristate.isTrue));
      expect(trackNode.label, 'Track');
      expect(trackNode.tooltip, 'Track');

      handle.dispose();
    });

    testWidgets('mode kurangi animasi (disableAnimations) berpindah langsung tanpa sisa cincin',
        (tester) async {
      await loadPlusJakartaSans(tester);
      int? tappedIndex;

      await tester.pumpWidget(
        _buildNavBarHarness(
          initialIndex: 0,
          onTap: (index) => tappedIndex = index,
          reduceMotion: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_tabSemantics('Peta'));
      expect(tappedIndex, 1);

      // Dalam mode reduce motion, transisi singkat (150 ms)
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('efek tekan (pointer down) pada tab tidak aktif dan cancel',
        (tester) async {
      await loadPlusJakartaSans(tester);

      await tester.pumpWidget(
        _buildNavBarHarness(initialIndex: 0),
      );
      await tester.pumpAndSettle();

      // Pointer down pada tab tidak aktif (Peta)
      final gesture = await tester.startGesture(
        tester.getCenter(_tabSemantics('Peta')),
      );
      await tester.pump(const Duration(milliseconds: 70));
      expect(tester.hasRunningAnimations, isTrue);

      // Batalkan pointer (drag keluar / cancel)
      await gesture.cancel();
      await tester.pump(const Duration(milliseconds: 170));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('5 tab dengan Track di tengah merender dan memilih Track dengan benar',
        (tester) async {
      await loadPlusJakartaSans(tester);
      int currentIndex = 0;
      final fiveItems = <HiqeoNavBarItem>[
        HiqeoNavBarItem(label: 'Beranda', icon: HiqeoIcons.home, route: '/beranda'),
        HiqeoNavBarItem(label: 'Peta', icon: HiqeoIcons.map, route: '/peta'),
        HiqeoNavBarItem(label: 'Track', icon: HiqeoIcons.activity, route: '/lacak'),
        HiqeoNavBarItem(label: 'Grup', icon: HiqeoIcons.group, route: '/grup'),
        HiqeoNavBarItem(label: 'Profil', icon: HiqeoIcons.user, route: '/profil'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: hiqeoLightTheme,
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: const SizedBox.expand(),
              bottomNavigationBar: MediaQuery(
                data: const MediaQueryData(size: Size(390, 844)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: VisualEffectPolicyScope(
                    policy: const VisualEffectPolicy(
                      powerProfile: PowerProfile.normal,
                      reduceMotion: false,
                      deviceTier: DeviceTier.capable,
                    ),
                    child: HiqeoNavBar(
                      currentIndex: currentIndex,
                      items: fiveItems,
                      onTap: (index) => setState(() => currentIndex = index),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final handle = tester.ensureSemantics();
      expect(_tabSemantics('Track'), findsOneWidget);
      await tester.tap(_tabSemantics('Track'));
      await tester.pumpAndSettle();

      expect(currentIndex, 2);
      expect(
        tester.getSemantics(_tabSemantics('Track')).flagsCollection.isSelected,
        ui.Tristate.isTrue,
      );
      handle.dispose();
    });
  });
}
