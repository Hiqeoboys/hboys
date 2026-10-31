import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/brand/app_brand.dart';
import '../../../design/widgets/line_icons.dart';
import '../domain/kartu_data.dart';

enum KartuStyle { profil, tengah, peta }

/// Latar kartu selalu biru gelap seperti rancangan, terlepas dari tema
/// aplikasi. Foto pengguna, bila ada, digelapkan agar teks tetap terbaca.
class KartuCard extends StatelessWidget {
  const KartuCard({
    super.key,
    required this.data,
    required this.style,
    required this.hideEndpoints,
    this.photoBytes,
  });

  final KartuData data;
  final KartuStyle style;
  final bool hideEndpoints;
  final Uint8List? photoBytes;

  static const Color _ink = Color(0xFFF6F3ED);
  static const Color _gradientTop = Color(0xFF3F4765);
  static const Color _gradientMiddle = Color(0xFF5C6684);
  static const Color _gradientBottom = Color(0xFF8B94AE);

  /// Latar kartu dan layar dibuat sama agar kartu menyatu dengan tepi layar.
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[_gradientTop, _gradientMiddle, _gradientBottom],
    stops: <double>[0, 0.55, 1],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      key: ValueKey<String>('kartu-card-${style.name}'),
      decoration: const BoxDecoration(gradient: backgroundGradient),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (photoBytes != null)
            Image.memory(
              photoBytes!,
              key: const ValueKey<String>('kartu-photo'),
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          if (photoBytes != null)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0xCC313851), Color(0x66313851)],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
            child: switch (style) {
              KartuStyle.profil => _profilLayout(theme),
              KartuStyle.tengah => _tengahLayout(theme),
              KartuStyle.peta => _petaLayout(theme),
            },
          ),
        ],
      ),
    );
  }

  Widget _profilLayout(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: _metrics(theme, centered: false)),
              const SizedBox(
                width: 104,
                height: 92,
                child: CustomPaint(painter: _SquigglePainter()),
              ),
            ],
          ),
          const Spacer(flex: 3),
          _profile(theme),
          const Spacer(flex: 2),
          _branding(theme, centered: false),
        ],
      );

  Widget _tengahLayout(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 4),
          _metrics(theme, centered: true),
          const Spacer(flex: 2),
          _profile(theme),
          const Spacer(flex: 2),
          _branding(theme, centered: true),
        ],
      );

  Widget _petaLayout(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _metrics(theme, centered: false),
          const Spacer(flex: 2),
          _route(theme),
          const Spacer(flex: 2),
          _branding(theme, centered: false),
        ],
      );

  Widget _metrics(ThemeData theme, {required bool centered}) {
    final cross =
        centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = centered ? TextAlign.center : TextAlign.left;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: cross,
      children: <Widget>[
        _metric(theme, 'JARAK', data.distanceLabel, textAlign),
        const SizedBox(height: 10),
        _metric(theme, 'TANJAKAN', data.gainLabel, textAlign),
        const SizedBox(height: 10),
        _metric(theme, 'WAKTU', data.timeLabel, textAlign),
      ],
    );
  }

  Widget _metric(
    ThemeData theme,
    String label,
    String value,
    TextAlign textAlign,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: textAlign == TextAlign.center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          textAlign: textAlign,
          style: theme.textTheme.labelSmall?.copyWith(
            color: _ink.withValues(alpha: 0.72),
            fontWeight: FontWeight.w500,
            letterSpacing: 2.4,
            fontSize: 10,
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment:
              textAlign == TextAlign.center ? Alignment.center : Alignment.centerLeft,
          child: Text(
            value,
            textAlign: textAlign,
            maxLines: 1,
            style: theme.textTheme.displayMedium?.copyWith(
              color: _ink,
              fontWeight: FontWeight.w800,
              fontSize: 38,
              height: 1.05,
              letterSpacing: -1.2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _profile(ThemeData theme) {
    final profile = data.profile;
    if (profile == null || profile.length < 2) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'Profil elevasi belum tersedia',
            style: theme.textTheme.bodySmall?.copyWith(
              color: _ink.withValues(alpha: 0.7),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 152,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final geometry = _ProfileGeometry.from(
            profile,
            Size(constraints.maxWidth, constraints.maxHeight),
          );
          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                child: CustomPaint(
                  key: const ValueKey<String>('kartu-profile'),
                  painter: _ProfilePainter(geometry),
                ),
              ),
              Positioned(
                left:
                    (geometry.peak.dx - 30).clamp(0, constraints.maxWidth - 60),
                top: 0,
                width: 60,
                child: Text(
                  'PUNCAK',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    fontSize: 9,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                bottom: 0,
                child: _axisLabel(theme, '0 km'),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: _axisLabel(theme, data.rightAxisLabel),
              ),
              if (!hideEndpoints)
                Positioned(
                  left: geometry.start.dx - 4,
                  top: geometry.start.dy - 4,
                  child: _marker(
                    const ValueKey<String>('kartu-start-marker'),
                    size: 8,
                  ),
                ),
              if (!hideEndpoints)
                Positioned(
                  left: geometry.end.dx - 4,
                  top: geometry.end.dy - 4,
                  child: _marker(
                    const ValueKey<String>('kartu-end-marker'),
                    size: 8,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _axisLabel(ThemeData theme, String text) => Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: _ink.withValues(alpha: 0.72),
          fontSize: 11,
        ),
      );

  Widget _marker(Key key, {required double size}) => Container(
        key: key,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: _ink.withValues(alpha: 0.9),
          shape: BoxShape.circle,
        ),
      );

  Widget _route(ThemeData theme) {
    final route = data.route;
    if (route == null || route.length < 2) {
      return SizedBox(
        height: 190,
        child: Center(
          child: Text(
            'Rute belum tersedia',
            style: theme.textTheme.bodySmall?.copyWith(
              color: _ink.withValues(alpha: 0.7),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 200,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final points = KartuData.fitRoute(
            route,
            Size(constraints.maxWidth, constraints.maxHeight),
          );
          final start = points.first;
          final end = points.last;
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: CustomPaint(
                  key: const ValueKey<String>('kartu-route'),
                  painter: _RoutePainter(points),
                ),
              ),
              if (!hideEndpoints)
                Positioned(
                  left: start.dx - 6,
                  top: start.dy - 6,
                  child: _routeMarker(
                    const ValueKey<String>('kartu-start-marker'),
                  ),
                ),
              if (!hideEndpoints)
                Positioned(
                  left: end.dx - 6,
                  top: end.dy - 6,
                  child: _routeMarker(
                    const ValueKey<String>('kartu-end-marker'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _routeMarker(Key key) => Container(
        key: key,
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: _ink,
          shape: BoxShape.circle,
          border: Border.all(color: _gradientTop, width: 2.5),
        ),
      );

  Widget _branding(ThemeData theme, {required bool centered}) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        HiqeoIcon(HiqeoIcons.mountain, size: 18, color: _ink),
        const SizedBox(width: 8),
        Text(
          '${AppBrand.lockup} · ${data.dateLabel}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: _ink.withValues(alpha: 0.92),
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
            fontSize: 10,
          ),
        ),
      ],
    );
    return centered ? Center(child: row) : row;
  }
}

class _ProfileGeometry {
  const _ProfileGeometry({
    required this.points,
    required this.peak,
    required this.start,
    required this.end,
    required this.baseY,
  });

  final List<Offset> points;
  final Offset peak;
  final Offset start;
  final Offset end;
  final double baseY;

  static _ProfileGeometry from(List<KartuProfilePoint> profile, Size size) {
    const topPadding = 20.0;
    const bottomPadding = 22.0;
    final usableHeight = size.height - topPadding - bottomPadding;
    var minAlt = profile.first.altitudeM;
    var maxAlt = profile.first.altitudeM;
    for (final point in profile) {
      if (point.altitudeM < minAlt) minAlt = point.altitudeM;
      if (point.altitudeM > maxAlt) maxAlt = point.altitudeM;
    }
    final span = math.max(1.0, maxAlt - minAlt);
    Offset position(KartuProfilePoint point) => Offset(
          point.fraction.clamp(0.0, 1.0) * size.width,
          topPadding + (1 - (point.altitudeM - minAlt) / span) * usableHeight,
        );
    var peakPoint = profile.first;
    for (final point in profile) {
      if (point.altitudeM > peakPoint.altitudeM) peakPoint = point;
    }
    return _ProfileGeometry(
      points: <Offset>[for (final point in profile) position(point)],
      peak: position(peakPoint),
      start: position(profile.first),
      end: position(profile.last),
      baseY: size.height - bottomPadding,
    );
  }
}

class _ProfilePainter extends CustomPainter {
  const _ProfilePainter(this.geometry);

  final _ProfileGeometry geometry;

  @override
  void paint(Canvas canvas, Size size) {
    final points = geometry.points;
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final fill = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 20),
          Offset(0, size.height),
          <Color>[
            const Color(0xFFFFFFFF).withValues(alpha: 0.22),
            const Color(0xFFFFFFFF).withValues(alpha: 0.02),
          ],
        ),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFF6F3ED),
    );
    canvas.drawLine(
      Offset(geometry.start.dx, geometry.baseY),
      Offset(geometry.end.dx, geometry.baseY),
      Paint()
        ..color = const Color(0xFFF6F3ED).withValues(alpha: 0.25)
        ..strokeWidth = 1,
    );
    final dashed = Paint()
      ..color = const Color(0xFFF6F3ED).withValues(alpha: 0.7)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    var y = geometry.peak.dy + 12;
    while (y < geometry.baseY) {
      canvas.drawLine(
        Offset(geometry.peak.dx, y),
        Offset(geometry.peak.dx, math.min(y + 4, geometry.baseY)),
        dashed,
      );
      y += 8;
    }
    canvas.drawCircle(
      geometry.peak,
      7,
      Paint()..color = const Color(0xFFF6F3ED),
    );
    canvas.drawCircle(
      geometry.peak,
      12,
      Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  @override
  bool shouldRepaint(_ProfilePainter oldDelegate) =>
      oldDelegate.geometry != geometry;
}

class _RoutePainter extends CustomPainter {
  const _RoutePainter(this.points);

  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFF6F3ED).withValues(alpha: 0.10)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      final y = size.height * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFF6F3ED),
    );
  }

  @override
  bool shouldRepaint(_RoutePainter oldDelegate) => oldDelegate.points != points;
}

class _SquigglePainter extends CustomPainter {
  const _SquigglePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFF6F3ED).withValues(alpha: 0.9);
    final path = Path()
      ..moveTo(size.width * 0.12, size.height * 0.78)
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.92,
        size.width * 0.36,
        size.height * 0.42,
        size.width * 0.5,
        size.height * 0.42,
      )
      ..cubicTo(
        size.width * 0.64,
        size.height * 0.42,
        size.width * 0.6,
        size.height * 0.1,
        size.width * 0.78,
        size.height * 0.1,
      )
      ..cubicTo(
        size.width * 0.9,
        size.height * 0.1,
        size.width * 0.92,
        size.height * 0.32,
        size.width * 0.98,
        size.height * 0.3,
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SquigglePainter oldDelegate) => false;
}
