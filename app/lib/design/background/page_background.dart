import 'package:flutter/material.dart';

import 'app_background.dart';

/// Adapter kompatibilitas ke belakang untuk [AppBackground].
///
/// Pengujian dan widget lama yang merujuk [PageBackground] tetap berjalan
/// dengan spesifikasi latar aura baru.
class PageBackground extends StatelessWidget {
  const PageBackground({
    super.key,
    required this.child,
    this.showBlobs = true,
    this.page = AppBackgroundPage.beranda,
  });

  final Widget child;
  final bool showBlobs;
  final AppBackgroundPage page;

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      showAura: showBlobs,
      page: page,
      child: child,
    );
  }
}
