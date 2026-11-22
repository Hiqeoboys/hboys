import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geo_utils/geo_utils.dart';

import '../../../../design/tokens.dart';
import '../../../kartu/domain/kartu_data.dart';
import '../../domain/track_point.dart';

/// Mengubah titik GPS sesi tracking menjadi koordinat polyline 0..1 agar siap
/// digambar langsung di kanvas tanpa proyeksi peta eksternal.
List<Offset> normalizeTrackRoutePoints(List<TrackPoint> points) {
  if (points.length < 2) return const <Offset>[];
  final positions = <LatLng>[for (final p in points) p.position];
  final midLat =
      positions.map((p) => p.lat).reduce((a, b) => a + b) / positions.length;
  final cosLat = math.cos(midLat * math.pi / 180).abs();
  final xs = <double>[for (final p in positions) p.lon * cosLat];
  final ys = <double>[for (final p in positions) p.lat];
  final minX = xs.reduce(math.min);
  final maxX = xs.reduce(math.max);
  final minY = ys.reduce(math.min);
  final maxY = ys.reduce(math.max);
  final spanX = maxX - minX;
  final spanY = maxY - minY;
  if (spanX <= 0 && spanY <= 0) return const <Offset>[];
  final scale = math.max(spanX, spanY);
  final padX = (scale - spanX) / 2;
  final padY = (scale - spanY) / 2;
  return List<Offset>.generate(positions.length, (i) {
    final nx = (xs[i] - minX + padX) / scale;
    final ny = 1 - (ys[i] - minY + padY) / scale;
    return Offset(nx, ny);
  }, growable: false);
}

/// Tampilan rute polyline GPS (dipakai di kartu hero Tracking mode Jogging dan
/// pratinjau kartu Riwayat Jogging).
class LiveRoutePolylineView extends StatelessWidget {
  const LiveRoutePolylineView({
    super.key,
    required this.routePoints,
    this.isLive = true,
    this.compact = false,
    this.lineColor,
  });

  final List<Offset> routePoints;
  final bool isLive;
  final bool compact;
  final Color? lineColor;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final accent = lineColor ?? colors.primary;

    if (routePoints.length < 2) {
      if (compact) {
        return Center(
          child: Icon(
            Icons.route_rounded,
            size: 24,
            color: colors.textSecondary.withValues(alpha: 0.55),
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.route_rounded,
                size: 26,
                color: colors.textSecondary.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 6),
              Text(
                'Rute GPS akan tampil saat kamu bergerak',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: CustomPaint(
        painter: _LiveRoutePolylinePainter(
          routePoints: routePoints,
          lineColor: accent,
          startColor: colors.successText,
          haloColor: accent.withValues(alpha: 0.24),
          guideColor: colors.hairline.withValues(alpha: 0.45),
          surfaceColor: colors.surface,
          isLive: isLive,
          compact: compact,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _LiveRoutePolylinePainter extends CustomPainter {
  const _LiveRoutePolylinePainter({
    required this.routePoints,
    required this.lineColor,
    required this.startColor,
    required this.haloColor,
    required this.guideColor,
    required this.surfaceColor,
    required this.isLive,
    required this.compact,
  });

  final List<Offset> routePoints;
  final Color lineColor;
  final Color startColor;
  final Color haloColor;
  final Color guideColor;
  final Color surfaceColor;
  final bool isLive;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    if (routePoints.length < 2 || size.isEmpty) return;

    if (!compact) {
      final guidePaint = Paint()
        ..color = guideColor
        ..strokeWidth = 0.8;
      canvas.drawLine(
        Offset(0, size.height * 0.35),
        Offset(size.width, size.height * 0.35),
        guidePaint,
      );
      canvas.drawLine(
        Offset(0, size.height * 0.7),
        Offset(size.width, size.height * 0.7),
        guidePaint,
      );
    }

    final pad = compact ? 9.0 : 18.0;
    final fitted = KartuData.fitRoute(routePoints, size, padding: pad);
    if (fitted.length < 2) return;

    final path = Path()..moveTo(fitted.first.dx, fitted.first.dy);
    for (var i = 1; i < fitted.length; i++) {
      path.lineTo(fitted[i].dx, fitted[i].dy);
    }

    final strokeWidth = compact ? 2.4 : 3.2;

    canvas.drawPath(
      path,
      Paint()
        ..color = haloColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + (compact ? 2.5 : 4.0)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final startRadius = compact ? 3.2 : 4.2;
    canvas.drawCircle(
      fitted.first,
      startRadius + 1.4,
      Paint()..color = surfaceColor,
    );
    canvas.drawCircle(
      fitted.first,
      startRadius,
      Paint()..color = startColor,
    );

    final end = fitted.last;
    final endRadius = compact ? 3.4 : 4.8;
    if (isLive) {
      canvas.drawCircle(end, endRadius * 2.1, Paint()..color = haloColor);
    }
    canvas.drawCircle(
      end,
      endRadius + 1.5,
      Paint()..color = surfaceColor,
    );
    canvas.drawCircle(end, endRadius, Paint()..color = lineColor);
  }

  @override
  bool shouldRepaint(covariant _LiveRoutePolylinePainter oldDelegate) =>
      oldDelegate.routePoints != routePoints ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.isLive != isLive ||
      oldDelegate.compact != compact;
}
