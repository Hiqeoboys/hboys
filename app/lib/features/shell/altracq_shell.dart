import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/background/page_background.dart';
import '../../design/motion/visual_effect_policy.dart';
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
      child: PageBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: widget.navigationShell,
          bottomNavigationBar: Padding(
            padding: const EdgeInsets.fromLTRB(
              AltracqMetrics.navbarInset,
              0,
              AltracqMetrics.navbarInset,
              AltracqMetrics.navbarInset,
            ),
            child: AltracqNavBar(
              currentIndex: widget.navigationShell.currentIndex,
              items: AltracqShell.navItems,
              onTap: (index) => widget.navigationShell.goBranch(
                index,
                initialLocation:
                    index == widget.navigationShell.currentIndex,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
