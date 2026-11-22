import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/brand/app_brand.dart';
import '../../../design/widgets/line_icons.dart';
import '../domain/kartu_data.dart';

enum KartuStyle { profil, tengah, peta }

/// Latar kartu selalu biru gelap seperti rancangan, terlepas dari tema
/// aplikasi. Saat pengguna menyisipkan foto, scrim gradasi tipis menjaga angka
/// statistik, grafik elevasi, dan footer tetap terbaca jelas.
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

  static const List<Shadow> _textShadows = <Shadow>[
    Shadow(
      color: Color(0x55000000),
      offset: Offset(0, 1),
      blurRadius: 4,
    ),
  ];

  static const List<Shadow> _photoTextShadows = <Shadow>[
    Shadow(
      color: Color(0x8A000000),
      offset: Offset(0, 1.5),
      blurRadius: 6,
    ),
    Shadow(
      color: Color(0x42000000),
      offset: Offset(0, 0.5),
      blurRadius: 2,
    ),
  ];

  List<Shadow> get _activeTextShadows =>
      photoBytes != null ? _photoTextShadows : _textShadows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      key: ValueKey<String>('kartu-card-${style.name}'),
      decoration: const BoxDecoration(gradient: backgroundGradient),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (photoBytes != null) ...<Widget>[
            Image.memory(
              photoBytes!,
              key: const ValueKey<String>('kartu-photo'),
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: ValueKey<String>('kartu-photo-scrim'),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Color(0x6E181E30),
                        Color(0x33181E30),
                        Color(0x52181E30),
                        Color(0x70181E30),
                      ],
                      stops: <double>[0.0, 0.34, 0.68, 1.0],
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.92,
                        colors: <Color>[
                          Colors.transparent,
                          Color(0x47101522),
                        ],
                        stops: <double>[0.52, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
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
          _metrics(theme, centered: false),
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
        const SizedBox(height: 8),
        _metric(theme, 'TANJAKAN', data.gainLabel, textAlign),
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
            color: _ink.withValues(alpha: 0.88),
            fontWeight: FontWeight.w600,
            letterSpacing: 2.0,
            fontSize: 9.5,
            shadows: _activeTextShadows,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: textAlign == TextAlign.center
              ? Alignment.center
              : Alignment.centerLeft,
          child: Text(
            value,
            textAlign: textAlign,
            maxLines: 1,
            style: theme.textTheme.displayMedium?.copyWith(
              color: _ink,
              fontWeight: FontWeight.w800,
              fontSize: 26,
              height: 1.08,
              letterSpacing: -0.6,
              shadows: _activeTextShadows,
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
    final hasPhoto = photoBytes != null;
    return SizedBox(
      height: 152,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final geometry = _ProfileGeometry.from(
            profile,
            Size(constraints.maxWidth, constraints.maxHeight),
          );
          final peakLabelWidth = math.min(104.0, constraints.maxWidth);
          final peakLeft = (geometry.peak.dx - peakLabelWidth / 2)
              .clamp(0.0, math.max(0.0, constraints.maxWidth - peakLabelWidth))
              .toDouble();
          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                child: CustomPaint(
                  key: const ValueKey<String>('kartu-profile'),
                  painter: _ProfilePainter(geometry, hasPhoto: hasPhoto),
                ),
              ),
              Positioned(
                left: peakLeft,
                top: 0,
                width: peakLabelWidth,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Text(
                    data.isJogging ? 'TERTINGGI' : 'PUNCAK',
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.8,
                      fontSize: 9,
                      shadows: _activeTextShadows,
                    ),
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
          color: _ink.withValues(alpha: 0.78),
          fontSize: 11,
          shadows: _activeTextShadows,
        ),
      );

  Widget _marker(Key key, {required double size}) => Container(
        key: key,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: _ink.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          boxShadow: photoBytes != null
              ? const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
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
    final hasPhoto = photoBytes != null;
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
                  painter: _RoutePainter(points, hasPhoto: hasPhoto),
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
    final row = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: centered ? Alignment.center : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (data.isJogging)
            Icon(
              Icons.directions_run_rounded,
              size: 18,
              color: _ink,
              shadows: _activeTextShadows,
            )
          else
            HiqeoIcon(HiqeoIcons.mountain, size: 18, color: _ink),
          const SizedBox(width: 8),
          Text(
            data.isJogging
                ? '${AppBrand.lockup} · JOGGING · ${data.dateLabel}'
                : '${AppBrand.lockup} · ${data.dateLabel}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: _ink.withValues(alpha: 0.92),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              fontSize: 10,
              shadows: _activeTextShadows,
            ),
          ),
        ],
      ),
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
  const _ProfilePainter(this.geometry, {this.hasPhoto = false});

  final _ProfileGeometry geometry;
  final bool hasPhoto;

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
            const Color(0xFFFFFFFF).withValues(alpha: hasPhoto ? 0.28 : 0.22),
            const Color(0xFFFFFFFF).withValues(alpha: 0.03),
          ],
        ),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = hasPhoto ? 4.8 : 3.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Color(hasPhoto ? 0x66000000 : 0x2E000000)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          hasPhoto ? 3.0 : 1.5,
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
        ..color = const Color(0xFFF6F3ED).withValues(alpha: 0.28)
        ..strokeWidth = 1,
    );
    final dashed = Paint()
      ..color = const Color(0xFFF6F3ED).withValues(alpha: 0.72)
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
    if (hasPhoto) {
      canvas.drawCircle(
        geometry.peak,
        9.5,
        Paint()
          ..color = const Color(0x66000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
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
      oldDelegate.geometry != geometry || oldDelegate.hasPhoto != hasPhoto;
}

class _RoutePainter extends CustomPainter {
  const _RoutePainter(this.points, {this.hasPhoto = false});

  final List<Offset> points;
  final bool hasPhoto;

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
        ..strokeWidth = hasPhoto ? 5.2 : 4.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Color(hasPhoto ? 0x66000000 : 0x2E000000)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          hasPhoto ? 3.0 : 1.5,
        ),
    );
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
  bool shouldRepaint(_RoutePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.hasPhoto != hasPhoto;
}
