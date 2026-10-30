import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../motion/visual_effect_policy.dart';
import '../tokens.dart';

/// Matriks warna saturasi 170% untuk kaca, mengikuti rancangan.
const List<double> _kSaturate170 = <double>[
  1.5509, -0.5005, -0.0504, 0, 0,
  -0.1491, 1.1995, -0.0504, 0, 0,
  -0.1491, -0.5005, 1.6496, 0, 0,
  0, 0, 0, 1, 0,
];

/// Permukaan liquid glass: isi semi-transparan, blur latar 18, saturasi 170%,
/// garis tepi 1 px, kilau 1 px di sisi atas, dan bayangan lembut.
///
/// Saat [VisualEffectPolicy.glassBlur] mati (profil daya Hemat/Kritis atau
/// perangkat lemah), blur dan saturasi dilewati dan isi dibuat lebih pekat
/// supaya keterbacaan tetap terjaga.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    this.borderRadius = AltracqRadius.card,
    this.padding,
    this.child,
  });

  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = AltracqColors.of(context);
    final blur = VisualEffectPolicyScope.of(context).glassBlur;
    final radius = BorderRadius.circular(borderRadius);

    Widget backdrop = Container(
      decoration: BoxDecoration(
        color: blur ? colors.glassFill : colors.glassFillFallback,
        borderRadius: radius,
        border: Border.all(
          color: colors.glassBorder,
          width: AltracqGlass.borderWidth,
        ),
      ),
    );

    if (blur) {
      // Saturasi dibungkus di luar blur sehingga hanya mengenai latar dan isi
      // kaca; konten di lapisan atas tetap tajam dan tidak ikut tersaring.
      backdrop = ColorFiltered(
        colorFilter: const ColorFilter.matrix(_kSaturate170),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: AltracqGlass.blurSigma,
            sigmaY: AltracqGlass.blurSigma,
          ),
          child: backdrop,
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: <BoxShadow>[AltracqGlass.shadow(colors)],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          // Konten dibiarkan tidak diposisikan supaya ukurannya yang menentukan
          // besar permukaan; lapisan kaca mengikutinya.
          fit: StackFit.passthrough,
          children: <Widget>[
            Positioned.fill(child: backdrop),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: AltracqGlass.highlightWidth,
              child: IgnorePointer(child: ColoredBox(color: colors.glassHighlight)),
            ),
            Padding(
              padding: padding ?? EdgeInsets.zero,
              child: child ?? const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
