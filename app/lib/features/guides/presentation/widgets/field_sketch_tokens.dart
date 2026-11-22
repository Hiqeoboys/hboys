import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Palet baku Technical Field Sketch (100% vektor offline).
abstract final class FieldSketchPalette {
  static const Color canvas = Color(0xFF242B40);
  static const Color contour = Color(0x16F2EFE9);
  static const Color ink = Color(0xFFF2EFE9);
  static const Color inkSoft = Color(0xB8F2EFE9);
  static const Color hatch = Color(0x4AF2EFE9);
  static const Color sage = Color(0xFF6FCF97);
  static const Color coral = Color(0xFFEB5757);
}

/// Primitif gambar vektor pada ruang koordinat virtual 400 x 240.
abstract final class FieldSketchPrimitives {
  static const double virtualWidth = 400.0;
  static const double virtualHeight = 240.0;

  static void withVirtualCanvas(
    Canvas canvas,
    Size size,
    void Function(Canvas c) draw,
  ) {
    canvas.save();
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = FieldSketchPalette.canvas,
    );
    final sx = size.width / virtualWidth;
    final sy = size.height / virtualHeight;
    final scale = math.min(sx, sy);
    final dx = (size.width - virtualWidth * scale) * 0.5;
    final dy = (size.height - virtualHeight * scale) * 0.5;
    canvas.translate(dx, dy);
    canvas.scale(scale, scale);
    draw(canvas);
    canvas.restore();
  }

  static Paint inkPaint({
    double width = 1.8,
    Color color = FieldSketchPalette.ink,
    PaintingStyle style = PaintingStyle.stroke,
  }) =>
      Paint()
        ..color = color
        ..strokeWidth = width
        ..style = style
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

  static Paint helperPaint({
    double width = 1.15,
    Color color = FieldSketchPalette.inkSoft,
  }) =>
      inkPaint(width: width, color: color);

  static void drawTopoBackground(Canvas canvas, {int seed = 1}) {
    final p = Paint()
      ..color = FieldSketchPalette.contour
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Lengkung kontur topografi tipis agar latar terasa seperti peta lapangan.
    for (var i = 0; i < 6; i++) {
      final path = Path();
      final baseY = 24.0 + i * 38.0 + ((seed % 5) * 3.0);
      path.moveTo(-20, baseY);
      for (var x = -20.0; x <= virtualWidth + 20; x += 24) {
        final wave = math.sin((x + i * 47 + seed * 29) * 0.025) * 14.0 +
            math.cos((x - i * 31) * 0.015) * 7.0;
        path.lineTo(x, baseY + wave);
      }
      canvas.drawPath(path, p);
    }

    // Ring kontur puncak tertutup di sudut kiri atas & kanan bawah.
    for (var r = 1; r <= 3; r++) {
      final rx = 68.0 + (seed % 3) * 18.0;
      final ry = 48.0;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(rx, ry),
          width: r * 42.0,
          height: r * 24.0,
        ),
        p,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(virtualWidth - 52, virtualHeight - 36),
          width: r * 36.0,
          height: r * 22.0,
        ),
        p,
      );
    }
  }

  static void drawCrossHatch(
    Canvas canvas,
    Path clipPath,
    Rect bounds, {
    double spacing = 5.5,
    bool cross = true,
    Color color = FieldSketchPalette.hatch,
    double strokeWidth = 0.85,
  }) {
    canvas.save();
    canvas.clipPath(clipPath);
    final p = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final span = bounds.height;
    for (var x = bounds.left - span; x <= bounds.right + span; x += spacing) {
      canvas.drawLine(
        Offset(x, bounds.bottom),
        Offset(x + span * 0.85, bounds.top),
        p,
      );
      if (cross) {
        canvas.drawLine(
          Offset(x, bounds.top),
          Offset(x + span * 0.85, bounds.bottom),
          p,
        );
      }
    }
    canvas.restore();
  }

  static void drawGroundSection(
    Canvas canvas,
    List<Offset> topLine, {
    double bottomY = 230.0,
    Color lineColor = FieldSketchPalette.ink,
    Color hatchColor = FieldSketchPalette.hatch,
  }) {
    if (topLine.length < 2) return;
    final minX = topLine.first.dx;
    final maxX = topLine.last.dx;
    var minY = topLine.first.dy;
    for (final pt in topLine) {
      if (pt.dy < minY) minY = pt.dy;
    }
    final sectionPath = Path()..moveTo(topLine.first.dx, topLine.first.dy);
    final surfacePath = Path()..moveTo(topLine.first.dx, topLine.first.dy);
    for (final pt in topLine.skip(1)) {
      sectionPath.lineTo(pt.dx, pt.dy);
      surfacePath.lineTo(pt.dx, pt.dy);
    }
    sectionPath
      ..lineTo(maxX, bottomY)
      ..lineTo(minX, bottomY)
      ..close();

    drawCrossHatch(
      canvas,
      sectionPath,
      Rect.fromLTRB(minX, minY, maxX, bottomY),
      spacing: 6.2,
      cross: true,
      color: hatchColor,
    );
    canvas.drawPath(surfacePath, inkPaint(width: 2.0, color: lineColor));
  }

  static void drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end, {
    double dash = 5.0,
    double gap = 4.0,
    double width = 1.2,
    Color color = FieldSketchPalette.inkSoft,
  }) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 1) return;
    final ux = dx / dist;
    final uy = dy / dist;
    final p = inkPaint(width: width, color: color);
    var cur = 0.0;
    while (cur < dist) {
      final segEnd = math.min(cur + dash, dist);
      canvas.drawLine(
        Offset(start.dx + ux * cur, start.dy + uy * cur),
        Offset(start.dx + ux * segEnd, start.dy + uy * segEnd),
        p,
      );
      cur += dash + gap;
    }
  }

  static void drawDashedRect(
    Canvas canvas,
    Rect rect, {
    double dash = 5.0,
    double gap = 4.0,
    double width = 1.2,
    Color color = FieldSketchPalette.inkSoft,
  }) {
    drawDashedLine(canvas, rect.topLeft, rect.topRight, dash: dash, gap: gap, width: width, color: color);
    drawDashedLine(canvas, rect.topRight, rect.bottomRight, dash: dash, gap: gap, width: width, color: color);
    drawDashedLine(canvas, rect.bottomRight, rect.bottomLeft, dash: dash, gap: gap, width: width, color: color);
    drawDashedLine(canvas, rect.bottomLeft, rect.topLeft, dash: dash, gap: gap, width: width, color: color);
  }

  static void drawArrow(
    Canvas canvas,
    Offset start,
    Offset end, {
    double width = 1.6,
    Color color = FieldSketchPalette.ink,
    double headSize = 7.0,
    bool doubleHead = false,
  }) {
    final p = inkPaint(width: width, color: color);
    canvas.drawLine(start, end, p);
    _drawArrowHead(canvas, start, end, p, headSize);
    if (doubleHead) {
      _drawArrowHead(canvas, end, start, p, headSize);
    }
  }

  static void _drawArrowHead(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint,
    double size,
  ) {
    final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
    final a1 = angle + math.pi * 0.8;
    final a2 = angle - math.pi * 0.8;
    canvas.drawLine(
      to,
      Offset(to.dx + math.cos(a1) * size, to.dy + math.sin(a1) * size),
      paint,
    );
    canvas.drawLine(
      to,
      Offset(to.dx + math.cos(a2) * size, to.dy + math.sin(a2) * size),
      paint,
    );
  }

  static void drawCurvedWindArrow(
    Canvas canvas,
    Offset start,
    Offset c1,
    Offset c2,
    Offset end, {
    Color color = FieldSketchPalette.inkSoft,
    double width = 1.3,
  }) {
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
    final p = inkPaint(width: width, color: color);
    canvas.drawPath(path, p);
    _drawArrowHead(canvas, c2, end, p, 6.5);
  }

  static void drawAngleArc(
    Canvas canvas,
    Offset vertex,
    double radius,
    double startAngle,
    double sweepAngle, {
    Color color = FieldSketchPalette.sage,
    double width = 1.3,
  }) {
    canvas.drawArc(
      Rect.fromCircle(center: vertex, radius: radius),
      startAngle,
      sweepAngle,
      false,
      inkPaint(width: width, color: color),
    );
  }

  static void drawLabel(
    Canvas canvas,
    String text,
    Offset pos, {
    Color color = FieldSketchPalette.ink,
    double fontSize = 10.5,
    TextAlign align = TextAlign.left,
    bool bold = true,
    bool withBacking = true,
    double maxWidth = 175.0,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'PlusJakartaSans',
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: color,
          height: 1.2,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    var dx = pos.dx;
    if (align == TextAlign.center) {
      dx -= painter.width * 0.5;
    } else if (align == TextAlign.right) {
      dx -= painter.width;
    }
    final offset = Offset(
      dx.clamp(6.0, virtualWidth - painter.width - 6.0),
      pos.dy.clamp(4.0, virtualHeight - painter.height - 4.0),
    );

    if (withBacking) {
      final bg = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          offset.dx - 4,
          offset.dy - 2,
          painter.width + 8,
          painter.height + 4,
        ),
        const Radius.circular(5),
      );
      canvas.drawRRect(
        bg,
        Paint()..color = FieldSketchPalette.canvas.withValues(alpha: 0.86),
      );
    }
    painter.paint(canvas, offset);
  }

  static void drawPillBadge(
    Canvas canvas,
    String text,
    Offset center, {
    Color borderColor = FieldSketchPalette.sage,
    Color textColor = FieldSketchPalette.sage,
    double fontSize = 9.5,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'PlusJakartaSans',
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: textColor,
          height: 1.15,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 180);

    final w = painter.width + 14;
    final h = painter.height + 8;
    final left = (center.dx - w * 0.5).clamp(6.0, virtualWidth - w - 6.0);
    final top = (center.dy - h * 0.5).clamp(6.0, virtualHeight - h - 6.0);
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, w, h),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = FieldSketchPalette.canvas.withValues(alpha: 0.92),
    );
    canvas.drawRRect(rect, inkPaint(width: 1.2, color: borderColor));
    painter.paint(canvas, Offset(left + 7, top + 4));
  }

  static void drawCheckBadge(Canvas canvas, Offset center, {double r = 9.0}) {
    canvas.drawCircle(
      center,
      r,
      Paint()..color = FieldSketchPalette.sage.withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      center,
      r,
      inkPaint(width: 1.5, color: FieldSketchPalette.sage),
    );
    final p = Path()
      ..moveTo(center.dx - r * 0.44, center.dy + 0.5)
      ..lineTo(center.dx - r * 0.1, center.dy + r * 0.36)
      ..lineTo(center.dx + r * 0.45, center.dy - r * 0.36);
    canvas.drawPath(p, inkPaint(width: 1.8, color: FieldSketchPalette.sage));
  }

  static void drawCrossBadge(Canvas canvas, Offset center, {double r = 9.0}) {
    canvas.drawCircle(
      center,
      r,
      Paint()..color = FieldSketchPalette.coral.withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      center,
      r,
      inkPaint(width: 1.5, color: FieldSketchPalette.coral),
    );
    final s = r * 0.38;
    final p = inkPaint(width: 1.8, color: FieldSketchPalette.coral);
    canvas.drawLine(
      Offset(center.dx - s, center.dy - s),
      Offset(center.dx + s, center.dy + s),
      p,
    );
    canvas.drawLine(
      Offset(center.dx + s, center.dy - s),
      Offset(center.dx - s, center.dy + s),
      p,
    );
  }

  static void drawInsetFrame(Canvas canvas, Rect rect, {String? title}) {
    canvas.drawRect(
      rect,
      Paint()..color = FieldSketchPalette.canvas.withValues(alpha: 0.94),
    );
    canvas.drawRect(rect, helperPaint(width: 1.2));
    if (title != null) {
      drawLabel(
        canvas,
        title,
        Offset(rect.left + 8, rect.top + 5),
        fontSize: 9.0,
        color: FieldSketchPalette.inkSoft,
        withBacking: false,
      );
    }
  }

  static void drawStake(
    Canvas canvas,
    Offset head,
    double angleFromHorizontalRad,
    double length, {
    Color color = FieldSketchPalette.sage,
    double width = 2.0,
  }) {
    final tip = Offset(
      head.dx + math.cos(angleFromHorizontalRad) * length,
      head.dy + math.sin(angleFromHorizontalRad) * length,
    );
    final perpX = -math.sin(angleFromHorizontalRad);
    final perpY = math.cos(angleFromHorizontalRad);
    final leftShoulder = Offset(
      head.dx + math.cos(angleFromHorizontalRad) * 4 + perpX * 2.2,
      head.dy + math.sin(angleFromHorizontalRad) * 4 + perpY * 2.2,
    );
    final rightShoulder = Offset(
      head.dx + math.cos(angleFromHorizontalRad) * 4 - perpX * 2.2,
      head.dy + math.sin(angleFromHorizontalRad) * 4 - perpY * 2.2,
    );
    final stakePath = Path()
      ..moveTo(head.dx, head.dy)
      ..lineTo(leftShoulder.dx, leftShoulder.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(rightShoulder.dx, rightShoulder.dy)
      ..close();
    canvas.drawPath(stakePath, inkPaint(width: width, color: color));
    // Kait kepala pasak
    canvas.drawCircle(
      Offset(head.dx + perpX * 2.5, head.dy + perpY * 2.5),
      2.2,
      inkPaint(width: 1.4, color: color),
    );
  }

  static void drawPersonSilhouette(
    Canvas canvas,
    Offset feetCenter, {
    double height = 46,
    Color color = FieldSketchPalette.ink,
    bool withPack = false,
  }) {
    final p = inkPaint(width: 1.7, color: color);
    final headR = height * 0.11;
    final headCenter = Offset(feetCenter.dx, feetCenter.dy - height + headR);
    canvas.drawCircle(headCenter, headR, p);

    final neck = Offset(feetCenter.dx, headCenter.dy + headR);
    final hip = Offset(feetCenter.dx, feetCenter.dy - height * 0.40);
    canvas.drawLine(neck, hip, p);

    // Lengan
    final shoulder = Offset(feetCenter.dx, neck.dy + height * 0.08);
    canvas.drawLine(
      shoulder,
      Offset(feetCenter.dx - height * 0.16, hip.dy - height * 0.04),
      p,
    );
    canvas.drawLine(
      shoulder,
      Offset(feetCenter.dx + height * 0.16, hip.dy - height * 0.04),
      p,
    );

    // Kaki
    canvas.drawLine(
      hip,
      Offset(feetCenter.dx - height * 0.13, feetCenter.dy),
      p,
    );
    canvas.drawLine(
      hip,
      Offset(feetCenter.dx + height * 0.13, feetCenter.dy),
      p,
    );

    if (withPack) {
      final packRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          feetCenter.dx - height * 0.22,
          shoulder.dy - 2,
          height * 0.15,
          height * 0.34,
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(packRect, p);
    }
  }

  static void drawPineTree(
    Canvas canvas,
    Offset baseCenter, {
    double height = 58,
    Color color = FieldSketchPalette.inkSoft,
  }) {
    final p = inkPaint(width: 1.5, color: color);
    canvas.drawLine(
      baseCenter,
      Offset(baseCenter.dx, baseCenter.dy - height * 0.25),
      p,
    );
    final tiers = 3;
    for (var i = 0; i < tiers; i++) {
      final bottomY = baseCenter.dy - height * (0.22 + i * 0.22);
      final topY = bottomY - height * 0.30;
      final halfW = height * (0.28 - i * 0.06);
      final path = Path()
        ..moveTo(baseCenter.dx, topY)
        ..lineTo(baseCenter.dx - halfW, bottomY)
        ..lineTo(baseCenter.dx + halfW, bottomY)
        ..close();
      canvas.drawPath(path, p);
    }
  }
}

/// Menggambar sketsa pasak 45 derajat (reused di panduan pemula dan detail tenda).
void drawTentStake45Diagram(ui.Canvas canvas) {
  FieldSketchPrimitives.drawTopoBackground(canvas, seed: 4);

  // Tanah miring dengan arsiran cross-hatching
  FieldSketchPrimitives.drawGroundSection(
    canvas,
    const <Offset>[
      Offset(20, 210),
      Offset(115, 170),
      Offset(220, 150),
      Offset(380, 146),
    ],
    bottomY: 234,
  );

  // Garis arah angin di bagian atas
  FieldSketchPrimitives.drawCurvedWindArrow(
    canvas,
    const Offset(42, 42),
    const Offset(115, 30),
    const Offset(185, 50),
    const Offset(258, 38),
  );
  FieldSketchPrimitives.drawCurvedWindArrow(
    canvas,
    const Offset(66, 56),
    const Offset(130, 46),
    const Offset(192, 62),
    const Offset(248, 52),
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Arah angin',
    const Offset(152, 20),
    align: TextAlign.center,
    color: FieldSketchPalette.ink,
  );

  // Sisi kanan tenda yang sedang ditambat
  final tentShell = Path()
    ..moveTo(222, 150)
    ..quadraticBezierTo(265, 62, 355, 30)
    ..lineTo(385, 34)
    ..lineTo(385, 146)
    ..close();
  FieldSketchPrimitives.drawCrossHatch(
    canvas,
    Path()
      ..moveTo(286, 118)
      ..lineTo(342, 72)
      ..lineTo(372, 102)
      ..close(),
    const Rect.fromLTRB(280, 68, 376, 122),
    spacing: 5.0,
    color: FieldSketchPalette.hatch,
  );
  canvas.drawPath(tentShell, FieldSketchPrimitives.inkPaint(width: 2.0));

  // Pasak 45 derajat menjauh dari tenda (aksen sage)
  const stakeHead = Offset(88, 152);
  FieldSketchPrimitives.drawStake(
    canvas,
    stakeHead,
    math.pi * 0.25,
    56,
    color: FieldSketchPalette.sage,
    width: 2.3,
  );
  // Garis bantu horizontal & sumbu pasak
  FieldSketchPrimitives.drawDashedLine(
    canvas,
    const Offset(52, 180),
    const Offset(192, 180),
    color: FieldSketchPalette.inkSoft,
  );
  FieldSketchPrimitives.drawDashedLine(
    canvas,
    const Offset(70, 174),
    const Offset(112, 126),
    color: FieldSketchPalette.inkSoft,
  );
  FieldSketchPrimitives.drawAngleArc(
    canvas,
    const Offset(84, 180),
    20,
    -math.pi * 0.25,
    math.pi * 0.25,
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Pasak 45°',
    const Offset(46, 118),
    color: FieldSketchPalette.sage,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    '45°',
    const Offset(60, 166),
    color: FieldSketchPalette.sage,
    fontSize: 9.5,
  );

  // Tali guyline dari titik kait tenda ke kepala pasak (sage)
  const tentAnchor = Offset(306, 56);
  canvas.drawLine(
    stakeHead,
    tentAnchor,
    FieldSketchPrimitives.inkPaint(width: 2.0, color: FieldSketchPalette.sage),
  );
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(146, 122),
    const Offset(214, 91),
    width: 1.3,
    color: FieldSketchPalette.sage,
    doubleHead: true,
    headSize: 5.5,
  );
  FieldSketchPrimitives.drawLabel(
    canvas,
    'Tali guyline',
    const Offset(172, 74),
    align: TextAlign.center,
    color: FieldSketchPalette.sage,
  );

  // Inset kanan bawah: perbandingan 45° Kuat ✓ vs 90° Mudah Cabut ✗
  const insetRect = Rect.fromLTWH(262, 152, 128, 78);
  FieldSketchPrimitives.drawInsetFrame(canvas, insetRect);
  FieldSketchPrimitives.drawStake(
    canvas,
    const Offset(308, 166),
    math.pi * 0.72,
    38,
    color: FieldSketchPalette.sage,
    width: 1.8,
  );
  FieldSketchPrimitives.drawCheckBadge(canvas, const Offset(276, 166), r: 7);
  FieldSketchPrimitives.drawLabel(
    canvas,
    '45° Kuat',
    const Offset(272, 206),
    fontSize: 8.8,
    color: FieldSketchPalette.sage,
    withBacking: false,
  );

  FieldSketchPrimitives.drawStake(
    canvas,
    const Offset(358, 164),
    math.pi * 0.5,
    40,
    color: FieldSketchPalette.coral,
    width: 1.8,
  );
  FieldSketchPrimitives.drawArrow(
    canvas,
    const Offset(356, 170),
    const Offset(336, 170),
    color: FieldSketchPalette.coral,
    width: 1.3,
    headSize: 5,
  );
  FieldSketchPrimitives.drawCrossBadge(canvas, const Offset(376, 166), r: 7);
  FieldSketchPrimitives.drawLabel(
    canvas,
    '90° Cabut',
    const Offset(338, 206),
    fontSize: 8.8,
    color: FieldSketchPalette.coral,
    withBacking: false,
  );
}
