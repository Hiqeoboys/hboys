import 'package:flutter/material.dart';

import 'line_icons.dart';

/// Tombol tutup bulat 44 px untuk layar penuh berpalet terbalik (Kartu, SOS).
///
/// Mengikuti rancangan S7: isi kaca putih 8%, garis tepi krem tipis, dan ikon
/// krem bergoresan 1,8 px. Nilainya tetap karena layar pemakainya selalu
/// berlatar gelap, bukan mengikuti pilihan terang/gelap aplikasi.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final AltracqIconData icon;
  final String label;

  /// `null` saat layar sedang sibuk dan tombol tidak boleh dipakai.
  final VoidCallback? onTap;

  static const double size = 44;
  static const Color _fill = Color(0x14FFFFFF);
  static const Color _border = Color(0x66F6F3ED);
  static const Color _foreground = Color(0xFFF6F3ED);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: _fill,
          shape: const CircleBorder(side: BorderSide(color: _border)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(
              child: AltracqIcon(icon, size: 20, color: _foreground),
            ),
          ),
        ),
      ),
    );
  }
}
