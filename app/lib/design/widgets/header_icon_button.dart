import 'package:flutter/material.dart';

import '../glass/hiqeo_liquid_glass.dart';
import 'line_icons.dart';

/// Tombol tutup bulat 44 px untuk layar penuh berpalet terbalik (Kartu, SOS).
///
/// Materialnya Liquid Glass yang sama dengan semua tombol bulat lain, tetapi
/// palet gelap dikunci karena layar pemakainya selalu berlatar gelap, bukan
/// mengikuti pilihan terang/gelap aplikasi.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final HiqeoIconData icon;
  final String label;

  /// `null` saat layar sedang sibuk dan tombol tidak boleh dipakai.
  final VoidCallback? onTap;

  static const double size = 44;
  static const Color _foreground = Color(0xFFF6F3ED);

  @override
  Widget build(BuildContext context) {
    return HiqeoGlassCircleButton(
      semanticsLabel: label,
      size: size,
      brightness: Brightness.dark,
      onTap: onTap,
      child: HiqeoIcon(icon, size: 20, color: _foreground),
    );
  }
}
