import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// Ikon garis khas Hiqeo: digambar sebagai path vektor pada kisi 24×24
/// dengan goresan 1,8 px dan ujung membulat.
///
/// Ikon Material tidak bisa diatur tebal goresannya, jadi seluruh ikon
/// rancangan digambar sendiri di sini.
class HiqeoIconData {
  HiqeoIconData(this._builder);

  final List<ui.Path> Function() _builder;

  late final List<ui.Path> paths = _builder();
}

class HiqeoIcon extends StatelessWidget {
  const HiqeoIcon(
    this.data, {
    super.key,
    this.size = 24,
    this.color,
    this.strokeWidth = HiqeoMetrics.iconStroke,
    this.semanticLabel,
  });

  final HiqeoIconData data;
  final double size;
  final Color? color;

  /// Dalam satuan kisi 24×24, jadi ikut terukur bersama [size].
  final double strokeWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resolved = color ??
        IconTheme.of(context).color ??
        HiqeoColors.of(context).textPrimary;
    return Semantics(
      label: semanticLabel,
      container: semanticLabel != null,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _HiqeoIconPainter(data.paths, resolved, strokeWidth),
        ),
      ),
    );
  }
}

class _HiqeoIconPainter extends CustomPainter {
  const _HiqeoIconPainter(this.paths, this.color, this.strokeWidth);

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
  bool shouldRepaint(_HiqeoIconPainter oldDelegate) =>
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
class HiqeoIcons {
  const HiqeoIcons._();

  static final HiqeoIconData home = HiqeoIconData(
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

  static final HiqeoIconData map = HiqeoIconData(
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

  static final HiqeoIconData activity = HiqeoIconData(
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

  static final HiqeoIconData group = HiqeoIconData(
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

  static final HiqeoIconData user = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..addOval(
          ui.Rect.fromCircle(center: const ui.Offset(12, 8.4), radius: 3.6),
        ),
      _dome(12, 20.8, 7.2),
    ],
  );

  static final HiqeoIconData mountain = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(2.8, 19.2)
        ..lineTo(9, 7.6)
        ..lineTo(13.1, 15.1)
        ..lineTo(15.4, 11.2)
        ..lineTo(21.2, 19.2),
      ui.Path()
        ..addOval(
          ui.Rect.fromCircle(center: const ui.Offset(17.1, 6.6), radius: 1.5),
        ),
    ],
  );

  static final HiqeoIconData trail = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(4.4, 19.6)
        ..cubicTo(9.2, 18.2, 6.2, 13.6, 10.4, 11)
        ..cubicTo(14.2, 8.6, 13.4, 6.4, 17.6, 5.6),
      ui.Path()
        ..addOval(
          ui.Rect.fromCircle(center: const ui.Offset(18.2, 5.4), radius: 2.4),
        ),
    ],
  );

  static final HiqeoIconData compass = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..addOval(
          ui.Rect.fromCircle(center: const ui.Offset(12, 12), radius: 8.2),
        ),
      ui.Path()
        ..moveTo(15.4, 8.6)
        ..lineTo(13.2, 13.2)
        ..lineTo(8.6, 15.4)
        ..lineTo(10.8, 10.8)
        ..close(),
    ],
  );

  static final HiqeoIconData pin = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(12, 20.6)
        ..cubicTo(9.4, 17.2, 5.8, 13.8, 5.8, 10.2)
        ..cubicTo(5.8, 6.8, 8.6, 4, 12, 4)
        ..cubicTo(15.4, 4, 18.2, 6.8, 18.2, 10.2)
        ..cubicTo(18.2, 13.8, 14.6, 17.2, 12, 20.6)
        ..close(),
      ui.Path()
        ..addOval(
          ui.Rect.fromCircle(center: const ui.Offset(12, 10.2), radius: 2.2),
        ),
    ],
  );

  static final HiqeoIconData image = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..addRRect(
          ui.RRect.fromRectAndRadius(
            const ui.Rect.fromLTRB(3.4, 5, 20.6, 19),
            const ui.Radius.circular(3),
          ),
        ),
      ui.Path()
        ..moveTo(5.8, 16.2)
        ..lineTo(10, 11.6)
        ..lineTo(13.4, 15)
        ..lineTo(15.8, 12.6)
        ..lineTo(18.2, 15),
      ui.Path()
        ..addOval(
          ui.Rect.fromCircle(center: const ui.Offset(16.4, 8.6), radius: 1.2),
        ),
    ],
  );

  static final HiqeoIconData warning = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(12, 3.8)
        ..lineTo(21.4, 19.6)
        ..lineTo(2.6, 19.6)
        ..close(),
      ui.Path()
        ..moveTo(12, 9.2)
        ..lineTo(12, 13.6),
      ui.Path()
        ..moveTo(12, 16.4)
        ..lineTo(12, 16.7),
    ],
  );

  static final HiqeoIconData check = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(5, 12.6)
        ..lineTo(9.6, 17)
        ..lineTo(19, 7),
    ],
  );

  static final HiqeoIconData locate = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(12, 3.6)
        ..lineTo(20, 20.4)
        ..lineTo(12, 16.2)
        ..lineTo(4, 20.4)
        ..close(),
    ],
  );

  static final HiqeoIconData mic = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..addRRect(
          ui.RRect.fromRectAndRadius(
            const ui.Rect.fromLTWH(9, 3, 6, 11),
            const ui.Radius.circular(3),
          ),
        )
        ..moveTo(5.5, 11)
        ..cubicTo(5.5, 14.5, 8.4, 17.2, 12, 17.2)
        ..cubicTo(15.6, 17.2, 18.5, 14.5, 18.5, 11)
        ..moveTo(12, 17.2)
        ..lineTo(12, 21)
        ..moveTo(8.5, 21)
        ..lineTo(15.5, 21),
    ],
  );

  static final HiqeoIconData close = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(6.4, 6.4)
        ..lineTo(17.6, 17.6),
      ui.Path()
        ..moveTo(17.6, 6.4)
        ..lineTo(6.4, 17.6),
    ],
  );

  static final HiqeoIconData phone = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(7.2, 3.5)
        ..cubicTo(7.9, 3.5, 8.6, 4.0, 8.9, 4.8)
        ..lineTo(9.9, 7.6)
        ..cubicTo(10.1, 8.3, 9.9, 9.0, 9.4, 9.5)
        ..lineTo(8.3, 10.6)
        ..cubicTo(9.2, 12.6, 11.4, 14.8, 13.4, 15.7)
        ..lineTo(14.5, 14.6)
        ..cubicTo(15.0, 14.1, 15.7, 13.9, 16.4, 14.1)
        ..lineTo(19.2, 15.1)
        ..cubicTo(20.0, 15.4, 20.5, 16.1, 20.5, 16.8)
        ..lineTo(20.5, 19.0)
        ..cubicTo(20.5, 20.0, 19.7, 20.8, 18.7, 20.7)
        ..cubicTo(10.1, 20.1, 3.9, 13.9, 3.3, 5.3)
        ..cubicTo(3.2, 4.3, 4.0, 3.5, 5.0, 3.5)
        ..close(),
    ],
  );

  static final HiqeoIconData send = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(20, 4)
        ..lineTo(4, 11)
        ..lineTo(10.5, 13.5)
        ..lineTo(20, 4)
        ..lineTo(12.5, 20)
        ..lineTo(10.5, 13.5),
    ],
  );

  static final HiqeoIconData battery = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..addRRect(
          ui.RRect.fromRectAndRadius(
            const ui.Rect.fromLTRB(2.8, 7.6, 18.4, 16.4),
            const ui.Radius.circular(3),
          ),
        ),
      ui.Path()
        ..moveTo(20.4, 10.2)
        ..lineTo(20.4, 13.8),
    ],
  );

  static final HiqeoIconData lock = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..addRRect(
          ui.RRect.fromRectAndRadius(
            const ui.Rect.fromLTRB(4.8, 10.4, 19.2, 20.6),
            const ui.Radius.circular(2.6),
          ),
        ),
      ui.Path()
        ..moveTo(8.2, 10.4)
        ..lineTo(8.2, 8)
        ..cubicTo(8.2, 5.8, 9.9, 4.2, 12, 4.2)
        ..cubicTo(14.1, 4.2, 15.8, 5.8, 15.8, 8)
        ..lineTo(15.8, 10.4),
      ui.Path()
        ..moveTo(12, 14)
        ..lineTo(12, 17),
    ],
  );

  static final HiqeoIconData grid = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..addRRect(
          ui.RRect.fromRectAndRadius(
            const ui.Rect.fromLTRB(3.6, 3.6, 10.4, 10.4),
            const ui.Radius.circular(2.2),
          ),
        )
        ..addRRect(
          ui.RRect.fromRectAndRadius(
            const ui.Rect.fromLTRB(13.6, 3.6, 20.4, 10.4),
            const ui.Radius.circular(2.2),
          ),
        )
        ..addRRect(
          ui.RRect.fromRectAndRadius(
            const ui.Rect.fromLTRB(3.6, 13.6, 10.4, 20.4),
            const ui.Radius.circular(2.2),
          ),
        )
        ..addRRect(
          ui.RRect.fromRectAndRadius(
            const ui.Rect.fromLTRB(13.6, 13.6, 20.4, 20.4),
            const ui.Radius.circular(2.2),
          ),
        ),
    ],
  );

  static final HiqeoIconData chevronRight = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(9.4, 5.8)
        ..lineTo(15.6, 12)
        ..lineTo(9.4, 18.2),
    ],
  );

  static final HiqeoIconData sun = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..addOval(
          ui.Rect.fromCircle(center: const ui.Offset(12, 12), radius: 4.2),
        ),
      ui.Path()
        ..moveTo(12, 2.8)
        ..lineTo(12, 4.8),
      ui.Path()
        ..moveTo(12, 19.2)
        ..lineTo(12, 21.2),
      ui.Path()
        ..moveTo(2.8, 12)
        ..lineTo(4.8, 12),
      ui.Path()
        ..moveTo(19.2, 12)
        ..lineTo(21.2, 12),
      ui.Path()
        ..moveTo(5.5, 5.5)
        ..lineTo(6.9, 6.9),
      ui.Path()
        ..moveTo(17.1, 17.1)
        ..lineTo(18.5, 18.5),
      ui.Path()
        ..moveTo(18.5, 5.5)
        ..lineTo(17.1, 6.9),
      ui.Path()
        ..moveTo(6.9, 17.1)
        ..lineTo(5.5, 18.5),
    ],
  );

  static final HiqeoIconData chevronLeft = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(14.6, 5.8)
        ..lineTo(8.4, 12)
        ..lineTo(14.6, 18.2),
    ],
  );

  static final HiqeoIconData chevronDown = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(5.8, 9.4)
        ..lineTo(12, 15.6)
        ..lineTo(18.2, 9.4),
    ],
  );

  static final HiqeoIconData cloud = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(7.4, 18.6)
        ..cubicTo(4.2, 18.6, 2.6, 16.6, 2.6, 14.4)
        ..cubicTo(2.6, 12.1, 4.4, 10.4, 6.5, 10.2)
        ..cubicTo(7.1, 7.4, 9.5, 5.4, 12.4, 5.4)
        ..cubicTo(15.7, 5.4, 18.3, 7.9, 18.5, 11)
        ..cubicTo(20.3, 11.4, 21.4, 12.8, 21.4, 14.6)
        ..cubicTo(21.4, 16.8, 19.7, 18.6, 17.4, 18.6)
        ..close(),
    ],
  );

  static final HiqeoIconData calendar = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..addRRect(
          ui.RRect.fromRectAndRadius(
            const ui.Rect.fromLTRB(3.4, 5.4, 20.6, 20.4),
            const ui.Radius.circular(3),
          ),
        ),
      ui.Path()
        ..moveTo(3.4, 10)
        ..lineTo(20.6, 10),
      ui.Path()
        ..moveTo(8, 3.4)
        ..lineTo(8, 7),
      ui.Path()
        ..moveTo(16, 3.4)
        ..lineTo(16, 7),
    ],
  );

  static final HiqeoIconData download = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(12, 3.6)
        ..lineTo(12, 15.2),
      ui.Path()
        ..moveTo(7.4, 10.8)
        ..lineTo(12, 15.4)
        ..lineTo(16.6, 10.8),
      ui.Path()
        ..moveTo(4.2, 18.6)
        ..lineTo(4.2, 20.4)
        ..lineTo(19.8, 20.4)
        ..lineTo(19.8, 18.6),
    ],
  );

  static final HiqeoIconData share = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(12, 15.4)
        ..lineTo(12, 4.2),
      ui.Path()
        ..moveTo(7.6, 8.6)
        ..lineTo(12, 4.2)
        ..lineTo(16.4, 8.6),
      ui.Path()
        ..moveTo(5.4, 13.4)
        ..lineTo(5.4, 20)
        ..lineTo(18.6, 20)
        ..lineTo(18.6, 13.4),
    ],
  );

  static final HiqeoIconData trophy = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(8, 3.8)
        ..lineTo(16, 3.8)
        ..lineTo(16, 9.4)
        ..cubicTo(16, 12.4, 14.2, 14.4, 12, 14.4)
        ..cubicTo(9.8, 14.4, 8, 12.4, 8, 9.4)
        ..close(),
      ui.Path()
        ..moveTo(8, 5.4)
        ..cubicTo(5.4, 5.4, 3.6, 6.6, 3.6, 8.4)
        ..cubicTo(3.6, 10.4, 5.4, 11.6, 8, 11.6),
      ui.Path()
        ..moveTo(16, 5.4)
        ..cubicTo(18.6, 5.4, 20.4, 6.6, 20.4, 8.4)
        ..cubicTo(20.4, 10.4, 18.6, 11.6, 16, 11.6),
      ui.Path()
        ..moveTo(12, 14.4)
        ..lineTo(12, 18.2),
      ui.Path()
        ..moveTo(8, 20.2)
        ..lineTo(16, 20.2),
    ],
  );

  static final HiqeoIconData more = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..addOval(
          ui.Rect.fromCircle(center: const ui.Offset(5.6, 12), radius: 0.9),
        ),
      ui.Path()
        ..addOval(
          ui.Rect.fromCircle(center: const ui.Offset(12, 12), radius: 0.9),
        ),
      ui.Path()
        ..addOval(
          ui.Rect.fromCircle(center: const ui.Offset(18.4, 12), radius: 0.9),
        ),
    ],
  );

  static final HiqeoIconData clock = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..addOval(
          ui.Rect.fromCircle(center: const ui.Offset(12, 12), radius: 8.4),
        ),
      ui.Path()
        ..moveTo(12, 7.2)
        ..lineTo(12, 12.2)
        ..lineTo(15.4, 14.2),
    ],
  );

  static final HiqeoIconData devices = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..addRRect(
          ui.RRect.fromRectAndRadius(
            const ui.Rect.fromLTRB(2.8, 5.2, 13.2, 14.6),
            const ui.Radius.circular(2),
          ),
        ),
      ui.Path()
        ..addRRect(
          ui.RRect.fromRectAndRadius(
            const ui.Rect.fromLTRB(15.2, 9.2, 21.2, 20.2),
            const ui.Radius.circular(2.4),
          ),
        ),
      ui.Path()
        ..moveTo(17.6, 17.8)
        ..lineTo(18.8, 17.8),
    ],
  );

  static final HiqeoIconData plus = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(12, 5.2)
        ..lineTo(12, 18.8),
      ui.Path()
        ..moveTo(5.2, 12)
        ..lineTo(18.8, 12),
    ],
  );

  static final HiqeoIconData moreVertical = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..addOval(
          ui.Rect.fromCircle(center: const ui.Offset(12, 5.6), radius: 0.9),
        ),
      ui.Path()
        ..addOval(
          ui.Rect.fromCircle(center: const ui.Offset(12, 12), radius: 0.9),
        ),
      ui.Path()
        ..addOval(
          ui.Rect.fromCircle(center: const ui.Offset(12, 18.4), radius: 0.9),
        ),
    ],
  );

  static final HiqeoIconData userPlus = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..addOval(
          ui.Rect.fromCircle(center: const ui.Offset(9.2, 8.2), radius: 3.2),
        ),
      _dome(9.2, 19.6, 5.4),
      ui.Path()
        ..moveTo(18.6, 8.8)
        ..lineTo(18.6, 13.6),
      ui.Path()
        ..moveTo(16.2, 11.2)
        ..lineTo(21.0, 11.2),
    ],
  );

  static final HiqeoIconData trash = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(4.4, 6.8)
        ..lineTo(19.6, 6.8),
      ui.Path()
        ..moveTo(9.2, 6.8)
        ..lineTo(9.2, 4.4)
        ..lineTo(14.8, 4.4)
        ..lineTo(14.8, 6.8),
      ui.Path()
        ..moveTo(6.2, 6.8)
        ..lineTo(7.0, 19.8)
        ..lineTo(17.0, 19.8)
        ..lineTo(17.8, 6.8),
      ui.Path()
        ..moveTo(10.2, 10.4)
        ..lineTo(10.4, 16.2),
      ui.Path()
        ..moveTo(13.8, 10.4)
        ..lineTo(13.6, 16.2),
    ],
  );

  static final HiqeoIconData play = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(8.0, 5.6)
        ..lineTo(18.2, 12.0)
        ..lineTo(8.0, 18.4)
        ..close(),
    ],
  );

  static final HiqeoIconData pause = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(8.4, 5.6)
        ..lineTo(8.4, 18.4),
      ui.Path()
        ..moveTo(15.6, 5.6)
        ..lineTo(15.6, 18.4),
    ],
  );

  static final HiqeoIconData crosshair = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..addOval(
          ui.Rect.fromCircle(center: const ui.Offset(12, 12), radius: 6.8),
        ),
      ui.Path()
        ..addOval(
          ui.Rect.fromCircle(center: const ui.Offset(12, 12), radius: 1.8),
        ),
      ui.Path()
        ..moveTo(12, 2.6)
        ..lineTo(12, 5.2),
      ui.Path()
        ..moveTo(12, 18.8)
        ..lineTo(12, 21.4),
      ui.Path()
        ..moveTo(2.6, 12)
        ..lineTo(5.2, 12),
      ui.Path()
        ..moveTo(18.8, 12)
        ..lineTo(21.4, 12),
    ],
  );

  static final HiqeoIconData chevronUp = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(5.8, 14.6)
        ..lineTo(12, 8.4)
        ..lineTo(18.2, 14.6),
    ],
  );

  static final HiqeoIconData firstAid = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..addRRect(
          ui.RRect.fromRectAndRadius(
            const ui.Rect.fromLTRB(3.4, 6.4, 20.6, 19.8),
            const ui.Radius.circular(3.0),
          ),
        ),
      ui.Path()
        ..moveTo(8.8, 6.4)
        ..lineTo(8.8, 4.4)
        ..lineTo(15.2, 4.4)
        ..lineTo(15.2, 6.4),
      ui.Path()
        ..moveTo(12, 9.8)
        ..lineTo(12, 16.4),
      ui.Path()
        ..moveTo(8.7, 13.1)
        ..lineTo(15.3, 13.1),
    ],
  );

  static final HiqeoIconData bell = HiqeoIconData(
    () => <ui.Path>[
      ui.Path()
        ..moveTo(6.2, 10.6)
        ..cubicTo(6.2, 6.9, 8.7, 4.4, 12, 4.4)
        ..cubicTo(15.3, 4.4, 17.8, 6.9, 17.8, 10.6)
        ..lineTo(18.6, 15.6)
        ..cubicTo(18.8, 16.4, 19.3, 17.0, 20.0, 17.4)
        ..lineTo(4.0, 17.4)
        ..cubicTo(4.7, 17.0, 5.2, 16.4, 5.4, 15.6)
        ..close(),
      ui.Path()
        ..moveTo(10.0, 19.2)
        ..cubicTo(10.5, 20.1, 11.2, 20.6, 12, 20.6)
        ..cubicTo(12.8, 20.6, 13.5, 20.1, 14.0, 19.2),
    ],
  );
}
