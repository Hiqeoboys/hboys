import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/background/page_background.dart';
import '../../design/motion/visual_effect_policy.dart';
import '../../design/system_ui.dart';
import '../../design/tokens.dart';
import '../../design/widgets/altracq_nav_bar.dart';
import '../../design/widgets/line_icons.dart';
import '../../infrastructure/power/power_profile_controller.dart';

/// Kerangka lima tab (Beranda, Peta, Lacak, Grup, Profil).
///
/// Layar di luar tab — Splash, Siap Naik, SOS, Kartu Pendakian — berada di
/// rute terpisah sehingga tidak menampilkan navigasi bawah.
class AltracqShell extends StatefulWidget {
  const AltracqShell({
    super.key,
    required this.navigationShell,
    this.powerController,
  });

  final StatefulNavigationShell navigationShell;

  /// Disuntikkan untuk uji; produksi membaca baterai perangkat.
  final PowerProfileController? powerController;

  static final List<AltracqNavBarItem> navItems = <AltracqNavBarItem>[
    AltracqNavBarItem(label: 'Beranda', icon: AltracqIcons.home, route: '/beranda'),
    AltracqNavBarItem(label: 'Peta', icon: AltracqIcons.map, route: '/peta'),
    AltracqNavBarItem(label: 'Lacak', icon: AltracqIcons.activity, route: '/lacak'),
    AltracqNavBarItem(label: 'Grup', icon: AltracqIcons.group, route: '/grup'),
    AltracqNavBarItem(label: 'Profil', icon: AltracqIcons.user, route: '/profil'),
  ];

  /// Indeks cabang Peta. Peta digambar penuh di bawah navbar (edge-to-edge),
  /// sehingga hanya tab ini yang mematikan blob latar dan memakai kaca
  /// bertint di atas peta.
  static const int mapBranchIndex = 1;

  @override
  State<AltracqShell> createState() => _AltracqShellState();
}

class _AltracqShellState extends State<AltracqShell> {
  static final DeviceTier _deviceTier = VisualEffectPolicy.probeDeviceTier();

  late final PowerProfileController _power =
      widget.powerController ?? PowerProfileController();

  @override
  void initState() {
    super.initState();
    if (widget.powerController == null) {
      unawaited(_power.refresh());
    }
  }

  @override
  void dispose() {
    if (widget.powerController == null) {
      _power.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.navigationShell.currentIndex;
    final systemInset = MediaQuery.paddingOf(context).bottom;
    return ListenableBuilder(
      listenable: _power,
      builder: (context, child) => VisualEffectPolicyScope(
        policy: VisualEffectPolicy(
          powerProfile: _power.profile,
          reduceMotion: MediaQuery.disableAnimationsOf(context),
          deviceTier: _deviceTier,
        ),
        child: child!,
      ),
      child: AltracqSystemInset(
        bottom: systemInset,
        child: PageBackground(
          // Peta digambar penuh tanpa blob latar; tab lain tetap memakai blob.
          showBlobs: index != AltracqShell.mapBranchIndex,
          child: Scaffold(
            // Hanya Peta yang memanjang sampai tepi bawah layar. Tab lain
            // menata navbar di luar isi supaya kartu/tombol terang tidak
            // tampak menembus kaca dan menyatu dengan blob.
            extendBody: index == AltracqShell.mapBranchIndex,
            backgroundColor: Colors.transparent,
            body: _TabFade(
              index: index,
              child: widget.navigationShell,
            ),
            bottomNavigationBar: Padding(
              padding: EdgeInsets.fromLTRB(
                AltracqMetrics.navbarInset,
                0,
                AltracqMetrics.navbarInset,
                AltracqMetrics.navbarInset + systemInset,
              ),
              child: AltracqNavBar(
                currentIndex: index,
                items: AltracqShell.navItems,
                overMap: index == AltracqShell.mapBranchIndex,
                onTap: (target) {
                  // Tab yang sudah aktif tidak memicu animasi apa pun.
                  if (target == index) return;
                  widget.navigationShell.goBranch(target);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Memudarkan isi tab baru selama 180 ms. Tab lama hilang seketika; pemilik
/// proyek memilih fade-in isi baru, bukan silang dua cabang.
class _TabFade extends StatefulWidget {
  const _TabFade({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_TabFade> createState() => _TabFadeState();
}

class _TabFadeState extends State<_TabFade>
    with SingleTickerProviderStateMixin {
  static const Duration _duration = Duration(milliseconds: 180);

  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: _duration,
    value: 1,
  );
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = VisualEffectPolicyScope.of(context).reduceMotion;
  }

  @override
  void didUpdateWidget(_TabFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    if (_reduceMotion) {
      _fade.value = 1;
      return;
    }
    _fade.forward(from: 0);
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        key: const ValueKey<String>('tab-fade'),
        opacity: _fade,
        child: widget.child,
      );
}
