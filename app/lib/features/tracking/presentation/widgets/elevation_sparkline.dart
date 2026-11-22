import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../design/tokens.dart';
import '../../domain/elevation_profile.dart';

/// Widget grafik profil ketinggian kurva kubik monoton Fritsch-Carlson
/// (tanpa overshoot) yang dipakai bersama oleh halaman Track dan halaman Peta.
class MonotoneElevationSparkline extends StatelessWidget {
  const MonotoneElevationSparkline({
    super.key,
    required this.samples,
    this.lineColor,
    this.emptyLabel = 'Belum ada data ketinggian',
    this.semanticsPrefix = 'Profil ketinggian',
  });

  final List<double> samples;
  final Color? lineColor;
  final String emptyLabel;
  final String semanticsPrefix;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasProfile = samples.length >= 2;
    final effectiveLineColor =
        lineColor ?? (isDark ? const Color(0xFFF5F2EA) : colors.primary);

    return RepaintBoundary(
      child: hasProfile
          ? Semantics(
              label: '$semanticsPrefix dari ${samples.length} sampel',
              container: true,
              child: ExcludeSemantics(
                child: CustomPaint(
                  painter: MonotoneElevationPainter(
                    samples: samples,
                    lineColor: effectiveLineColor,
                  ),
                ),
              ),
            )
          : Stack(
              fit: StackFit.expand,
              children: <Widget>[
                CustomPaint(
                  painter: MonotoneElevationPainter(
                    samples: samples,
                    lineColor: effectiveLineColor,
                  ),
                ),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: Text(
                      emptyLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Painter kurva ketinggian halus dengan interpolasi kubik monoton
/// Fritsch-Carlson (tanpa overshoot), gradien vertikal krem (#F5F2EA alpha
/// 0,38 ke 0), rentang Y minimum 20 m, dan titik penanda di ujung kanan.
class MonotoneElevationPainter extends CustomPainter {
  const MonotoneElevationPainter({
    required this.samples,
    required this.lineColor,
  });

  final List<double> samples;
  final Color lineColor;

  static const Color _cream = Color(0xFFF5F2EA);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Saat titik < 3, tampilkan garis datar tipis.
    if (samples.length < 3) {
      final y = size.height * 0.65;
      canvas.drawLine(
        Offset(12, y),
        Offset(size.width - 12, y),
        Paint()
          ..color = lineColor.withValues(alpha: 0.35)
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round,
      );
      return;
    }

    final minSample = samples.reduce(math.min);
    final maxSample = samples.reduce(math.max);
    final rawRange = maxSample - minSample;
    // Rentang Y minimum 20 m agar noise kecil di tanah datar tidak tampak
    // seperti gunung.
    final range = math.max(rawRange, 20.0);
    final extraPad = (range - rawRange) / 2.0;
    final yBase = minSample - extraPad;

    const topInset = 8.0;
    const bottomInset = 6.0;
    const rightDotPad = 8.0;
    final usableWidth = math.max(1.0, size.width - rightDotPad);
    final usableHeight = math.max(1.0, size.height - topInset - bottomInset);

    final n = samples.length;
    final h = usableWidth / (n - 1);
    final ys = <double>[
      for (var i = 0; i < n; i++)
        topInset + usableHeight - ((samples[i] - yBase) / range) * usableHeight,
    ];
    final tangents = monotoneTangents(ys, h);

    final linePath = Path()..moveTo(0, ys.first);
    for (var i = 0; i < n - 1; i++) {
      final x0 = i * h;
      final x1 = (i + 1) * h;
      final y0 = ys[i];
      final y1 = ys[i + 1];
      final c1x = x0 + h / 3.0;
      final c1y = y0 + tangents[i] * h / 3.0;
      final c2x = x1 - h / 3.0;
      final c2y = y1 - tangents[i + 1] * h / 3.0;
      linePath.cubicTo(c1x, c1y, c2x, c2y, x1, y1);
    }

    final fillPath = Path.from(linePath)
      ..lineTo(usableWidth, size.height)
      ..lineTo(0, size.height)
      ..close();

    final minY = ys.reduce(math.min);
    final gradientRect = Rect.fromLTRB(0, minY, size.width, size.height);
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            _cream.withValues(alpha: 0.38),
            _cream.withValues(alpha: 0.0),
          ],
        ).createShader(gradientRect),
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = lineColor,
    );

    // Titik penanda kecil di ujung kanan (posisi saat ini).
    final endOffset = Offset(usableWidth, ys.last);
    canvas.drawCircle(
      endOffset,
      3.5,
      Paint()..color = lineColor,
    );
  }

  @override
  bool shouldRepaint(MonotoneElevationPainter oldDelegate) =>
      oldDelegate.samples != samples || oldDelegate.lineColor != lineColor;
}

