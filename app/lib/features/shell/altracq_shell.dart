import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/background/page_background.dart';
import '../../design/tokens.dart';
import '../../design/widgets/altracq_nav_bar.dart';
import '../../design/widgets/line_icons.dart';

/// Kerangka lima tab (Beranda, Peta, Lacak, Grup, Profil).
///
/// Layar di luar tab — Splash, Siap Naik, SOS, Kartu Pendakian — berada di
/// rute terpisah sehingga tidak menampilkan navigasi bawah.
class AltracqShell extends StatelessWidget {
  const AltracqShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static final List<AltracqNavBarItem> navItems = <AltracqNavBarItem>[
    AltracqNavBarItem(label: 'Beranda', icon: AltracqIcons.home, route: '/beranda'),
    AltracqNavBarItem(label: 'Peta', icon: AltracqIcons.map, route: '/peta'),
    AltracqNavBarItem(label: 'Lacak', icon: AltracqIcons.activity, route: '/lacak'),
    AltracqNavBarItem(label: 'Grup', icon: AltracqIcons.group, route: '/grup'),
    AltracqNavBarItem(label: 'Profil', icon: AltracqIcons.user, route: '/profil'),
  ];

  @override
  Widget build(BuildContext context) {
    return PageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: navigationShell,
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.fromLTRB(
            AltracqMetrics.navbarInset,
            0,
            AltracqMetrics.navbarInset,
            AltracqMetrics.navbarInset,
          ),
          child: AltracqNavBar(
            currentIndex: navigationShell.currentIndex,
            items: navItems,
            onTap: (index) => navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            ),
          ),
        ),
      ),
    );
  }
}
