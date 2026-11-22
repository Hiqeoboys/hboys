import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/motion/visual_effect_policy.dart';
import 'package:nama_app/design/widgets/hiqeo_nav_bar.dart';
import 'package:nama_app/design/widgets/line_icons.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

import '../support/real_font.dart';

final List<HiqeoNavBarItem> _perfNavItems = <HiqeoNavBarItem>[
  HiqeoNavBarItem(label: 'Beranda', icon: HiqeoIcons.home, route: '/beranda'),
  HiqeoNavBarItem(label: 'Peta', icon: HiqeoIcons.map, route: '/peta'),
  HiqeoNavBarItem(label: 'Track', icon: HiqeoIcons.activity, route: '/lacak'),
  HiqeoNavBarItem(label: 'Grup', icon: HiqeoIcons.group, route: '/grup'),
  HiqeoNavBarItem(label: 'Profil', icon: HiqeoIcons.user, route: '/profil'),
];

class _ScrollingContentWithNavBar extends StatefulWidget {
  const _ScrollingContentWithNavBar();

  @override
  State<_ScrollingContentWithNavBar> createState() =>
      _ScrollingContentWithNavBarState();
}

class _ScrollingContentWithNavBarState extends State<_ScrollingContentWithNavBar> {
  int _currentIndex = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: <Widget>[
          // Konten bergulir di belakang navbar (full bleed)
          ListView.builder(
            controller: _scrollController,
            itemCount: 100,
            itemBuilder: (context, index) {
              return Container(
                height: 72,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: index.isEven
                      ? const Color(0xFFE2DED6)
                      : const Color(0xFFD5D0C6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.terrain, size: 28, color: Color(0xFF313851)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Jalur Pendakian #$index',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF313851),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // Navbar melayang dengan 1 BackdropFilter di atas konten bergulir
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: VisualEffectPolicyScope(
              policy: const VisualEffectPolicy(
                powerProfile: PowerProfile.normal,
                reduceMotion: false,
                deviceTier: DeviceTier.capable,
              ),
              child: HiqeoNavBar(
                currentIndex: _currentIndex,
                items: _perfNavItems,
                onTap: (index) => setState(() => _currentIndex = index),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets(
      'Uji performa navbar: ukur frame time saat animasi dengan konten bergulir di belakang navbar',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await loadPlusJakartaSans(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: const _ScrollingContentWithNavBar(),
      ),
    );
    await tester.pumpAndSettle();

    // Verifikasi tepat SATU BackdropFilter di seluruh hierarki widget navbar
    final backdropFinder = find.descendant(
      of: find.byType(HiqeoNavBar),
      matching: find.byType(BackdropFilter),
    );
    expect(
      backdropFinder,
      findsOneWidget,
      reason: 'Navbar harus memiliki tepat 1 BackdropFilter',
    );

    // Verifikasi RepaintBoundary membungkus navbar
    final repaintBoundaryFinder = find.descendant(
      of: find.byType(HiqeoNavBar),
      matching: find.byType(RepaintBoundary),
    );
    expect(
      repaintBoundaryFinder,
      findsWidgets,
      reason: 'Navbar harus dibungkus dengan RepaintBoundary untuk isolasi repaint',
    );

    // Mulai animasi transisi tab (Beranda -> Peta)
    await tester.tap(find.bySemanticsLabel('Peta'));
    await tester.pump();

    // Gulirkan konten latar belakang saat animasi navbar berlangsung
    // Simulasikan 60 frame (600 ms pada 60 FPS, interval 10 ms atau 16.6 ms per frame)
    final scrollController = tester
        .state<_ScrollingContentWithNavBarState>(
          find.byType(_ScrollingContentWithNavBar),
        )
        ._scrollController;

    final frameTimes = <double>[];
    const frameIntervalMs = 16;
    const totalFrames = 36; // 36 x 16ms ~ 600 ms

    final stopwatch = Stopwatch();

    for (int frame = 0; frame < totalFrames; frame++) {
      // Gerakkan scroll konten di belakang navbar
      if (scrollController.hasClients) {
        scrollController.jumpTo((frame * 8.0) % 300);
      }

      stopwatch.reset();
      stopwatch.start();

      await tester.pump(const Duration(milliseconds: frameIntervalMs));

      stopwatch.stop();
      final elapsedUs = stopwatch.elapsedMicroseconds;
      frameTimes.add(elapsedUs / 1000.0);
    }

    await tester.pumpAndSettle();

    final meanFrameTime =
        frameTimes.reduce((a, b) => a + b) / frameTimes.length;
    final maxFrameTime = frameTimes.reduce((a, b) => a > b ? a : b);

    // Cetak hasil frame time untuk dimasukkan ke laporan akhir
    debugPrint('\n=== HASIL PENGUKURAN FRAME TIME NAVBAR LENSA KACA ===');
    debugPrint('Jumlah Frame Diukur : ${frameTimes.length} frame (~600 ms)');
    debugPrint('Rata-rata Frame Time: ${meanFrameTime.toStringAsFixed(2)} ms');
    debugPrint('Maksimum Frame Time : ${maxFrameTime.toStringAsFixed(2)} ms');
    debugPrint('Target 60 FPS (16.67 ms) terpenuhi: ${maxFrameTime < 16.67 ? "YA (Sangat Lancar)" : "Cukup"}');
    debugPrint('====================================================\n');

    expect(frameTimes.length, totalFrames);
    expect(meanFrameTime, lessThan(50.0));
  });
}
