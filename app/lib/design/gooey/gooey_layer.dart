import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../motion/visual_effect_policy.dart';
import '../tokens.dart';

/// Ambang alfa metaball: alfa' = alfa * 20 - 9 pada skala 0–1, yaitu
/// alfa * 20 - 2295 pada matriks 0–255 milik Flutter. Tepi kabur hasil blur
/// yang alfanya di bawah 0,45 dipangkas habis, di atasnya dipadatkan, sehingga
/// dua bentuk yang berdekatan tampak menyatu seperti cairan.
const List<double> _kAlphaThreshold = <double>[
  1, 0, 0, 0, 0,
  0, 1, 0, 0, 0,
  0, 0, 1, 0, 0,
  0, 0, 0, AltracqGooey.alphaScale, AltracqGooey.alphaShift,
];

/// Pembungkus gooey tunggal untuk seluruh aplikasi.
///
/// [shapes] adalah lapisan bentuk cair (blob indikator navbar dan morph kartu
/// "Semua fitur" di Beranda); [child] adalah konten tajam (teks, ikon) yang
/// ditumpuk di atasnya tanpa ikut dikaburkan. Saat [VisualEffectPolicy.gooey]
/// mati, bentuk ditampilkan apa adanya tanpa blur sehingga fungsi tidak pernah
/// bergantung pada efek.
class GooeyLayer extends StatelessWidget {
  const GooeyLayer({
    super.key,
    required this.shapes,
    this.child,
  });

  final Widget shapes;
  final Widget? child;

  static bool enabledOf(BuildContext context) =>
      VisualEffectPolicyScope.of(context).gooey;

  @override
  Widget build(BuildContext context) {
    Widget layer = shapes;
    if (enabledOf(context)) {
      layer = ColorFiltered(
        colorFilter: const ColorFilter.matrix(_kAlphaThreshold),
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: AltracqGooey.blurSigma,
            sigmaY: AltracqGooey.blurSigma,
          ),
          child: shapes,
        ),
      );
    }
    if (child == null) return layer;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        layer,
        Positioned.fill(child: child!),
      ],
    );
  }
}
