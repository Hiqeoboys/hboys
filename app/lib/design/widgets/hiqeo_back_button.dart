import 'package:flutter/material.dart';

import '../glass/hiqeo_liquid_glass.dart';
import '../tokens.dart';
import 'line_icons.dart';

/// Tombol kembali bulat 44 px (Liquid Glass + ikon `<`) yang dipakai semua
/// layar; materialnya dari [HiqeoGlassTokens], warna ikon mengikuti tema.
class HiqeoBackButton extends StatelessWidget {
  const HiqeoBackButton({
    super.key,
    this.onTap,
    this.inAppBar = false,
    this.overMap = false,
    this.brightness,
    this.blurSigma,
  });

  /// Bawaan: `Navigator.maybePop`.
  final VoidCallback? onTap;

  /// Beri jarak kiri 16 px; pasangkan dengan `leadingWidth: appBarWidth`.
  final bool inAppBar;

  /// Dipakai di atas peta Mapbox (tanpa blur, fill rapat).
  final bool overMap;

  /// Penimpaan palet terang/gelap opsional (mis. di atas kanvas media gelap).
  final Brightness? brightness;

  /// Radius blur opsional untuk efisiensi GPU pada header menggulir.
  final double? blurSigma;

  static const double size = 44;
  static const double appBarWidth = size + HiqeoSpacing.lg + HiqeoSpacing.sm;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final iconColor = brightness == Brightness.dark
        ? HiqeoColors.dark.textPrimary
        : (brightness == Brightness.light
            ? HiqeoColors.light.textPrimary
            : colors.textPrimary);
    final button = HiqeoGlassCircleButton(
      semanticsLabel: 'Kembali',
      size: size,
      overMap: overMap,
      brightness: brightness,
      blurSigma: blurSigma,
      onTap: onTap ?? () => Navigator.of(context).maybePop(),
      child: HiqeoIcon(
        HiqeoIcons.chevronLeft,
        size: 20,
        color: iconColor,
      ),
    );
    if (!inAppBar) return button;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: HiqeoSpacing.lg),
        child: button,
      ),
    );
  }
}
