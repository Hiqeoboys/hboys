import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// Ikon garis khas Altracq: digambar sebagai path vektor pada kisi 24×24
/// dengan goresan 1,8 px dan ujung membulat.
///
/// Ikon Material tidak bisa diatur tebal goresannya, jadi seluruh ikon
/// rancangan digambar sendiri di sini.
class AltracqIconData {
  AltracqIconData(this._builder);

  final List<ui.Path> Function() _builder;

  late final List<ui.Path> paths = _builder();
}

class AltracqIcon extends StatelessWidget {
  const AltracqIcon(
    this.data, {
    super.key,
    this.size = 24,
    this.color,
    this.strokeWidth = AltracqMetrics.iconStroke,
    this.semanticLabel,
  });

  final AltracqIconData data;
  final double size;
  final Color? color;

  /// Dalam satuan kisi 24×24, jadi ikut terukur bersama [size].
  final double strokeWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resolved =
        color ?? IconTheme.of(context).color ?? AltracqColors.of(context).textPrimary;
    return Semantics(
      label: semanticLabel,
      container: semanticLabel != null,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _AltracqIconPainter(data.paths, resolved, strokeWidth),
        ),
      ),
    );
  }
}

class _AltracqIconPainter extends CustomPainter {
  const _AltracqIconPainter(this.paths, this.color, this.strokeWidth);

  final List<ui.Path> paths;
  final ui.Color color;
  final double strokeWidth;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final scale = size.width / 24;
    final paint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round
      ..color = color;
    canvas
      ..save()
      ..scale(scale, scale);
    for (final path in paths) {
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AltracqIconPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.paths != paths;
}

ui.Path _dome(double centerX, double baseY, double radius) => ui.Path()
  ..addArc(
    ui.Rect.fromCircle(center: ui.Offset(centerX, baseY), radius: radius),
    math.pi,
    math.pi,
  );

/// Kumpulan ikon. Ditambah sesuai layar yang dikerjakan.
class AltracqIcons {
  const AltracqIcons._();

  static final AltracqIconData home = AltracqIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(3.2, 10.8)
        ..lineTo(12, 3.8)
        ..lineTo(20.8, 10.8),
      ui.Path()
        ..moveTo(5.8, 9.4)
        ..lineTo(5.8, 20.2)
        ..lineTo(18.2, 20.2)
        ..lineTo(18.2, 9.4),
    ],
  );

  static final AltracqIconData map = AltracqIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(9, 4.4)
        ..lineTo(3.6, 6.6)
        ..lineTo(3.6, 19.6)
        ..lineTo(9, 17.4)
        ..lineTo(15, 19.6)
        ..lineTo(20.4, 17.4)
        ..lineTo(20.4, 4.4)
        ..lineTo(15, 6.6)
        ..close(),
      ui.Path()
        ..moveTo(9, 4.4)
        ..lineTo(9, 17.4),
      ui.Path()
        ..moveTo(15, 6.6)
        ..lineTo(15, 19.6),
    ],
  );

  static final AltracqIconData activity = AltracqIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(2.8, 12.6)
        ..lineTo(7.2, 12.6)
        ..lineTo(9.8, 6.2)
        ..lineTo(14.2, 17.8)
        ..lineTo(16.6, 12.6)
        ..lineTo(21.2, 12.6),
    ],
  );

  static final AltracqIconData group = AltracqIconData(
    () => <ui.Path>[
      ui.Path()
        ..addOval(
          ui.Rect.fromCircle(center: const ui.Offset(8.6, 8.6), radius: 3),
        ),
      _dome(8.6, 19.8, 5.2),
      ui.Path()
        ..addOval(
          ui.Rect.fromCircle(center: const ui.Offset(16.9, 9.4), radius: 2.4),
        ),
      _dome(17.8, 19.8, 3.6),
    ],
  );

  static final AltracqIconData user = AltracqIconData(
    () => <ui.Path>[
      ui.Path()
        ..addOval(
          ui.Rect.fromCircle(center: const ui.Offset(12, 8.4), radius: 3.6),
        ),
      _dome(12, 20.8, 7.2),
    ],
  );
}
