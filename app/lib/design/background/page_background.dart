import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// Latar halaman: warna dasar + dua blob radial lembut sesuai rancangan
/// (sekunder di kiri atas, primer 20% di kanan bawah).
class PageBackground extends StatelessWidget {
  const PageBackground({super.key, required this.child, this.showBlobs = true});

  final Widget child;
  final bool showBlobs;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return ColoredBox(
      color: colors.background,
      child: CustomPaint(
        painter: _PageBackgroundPainter(colors, showBlobs),
        child: child,
      ),
    );
  }
}

class _PageBackgroundPainter extends CustomPainter {
  const _PageBackgroundPainter(this.colors, this.showBlobs);

  final HiqeoColors colors;
  final bool showBlobs;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    if (!showBlobs) return;
    final rect = ui.Offset.zero & size;

    canvas.drawRect(
      rect,
      ui.Paint()
        ..shader = ui.Gradient.radial(
          ui.Offset(size.width * 0.06, size.height * 0.02),
          size.width * 0.95,
          <ui.Color>[
            colors.blobTopLeft.withValues(alpha: 0.55),
            colors.blobTopLeft.withValues(alpha: 0),
          ],
        ),
    );

    canvas.drawRect(
      rect,
      ui.Paint()
        ..shader = ui.Gradient.radial(
          ui.Offset(size.width * 0.98, size.height * 0.99),
          size.width * 1.05,
          <ui.Color>[
            colors.blobBottomRight,
            colors.blobBottomRight.withValues(alpha: 0),
          ],
        ),
    );
  }

  @override
  bool shouldRepaint(_PageBackgroundPainter oldDelegate) =>
      oldDelegate.colors != colors || oldDelegate.showBlobs != showBlobs;
}
