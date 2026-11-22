import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../design/glass/glass_surface.dart';
import '../../design/motion/visual_effect_policy.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../kartu/domain/kartu_data.dart';

/// Durasi gambar-turut 700 ms; hitung-naik selesai pada 600 ms di dalamnya.
const Duration _kIntroDuration = Duration(milliseconds: 700);
const double _kCountFraction = 600 / 700;

/// 44 px membuat tinggi kartu 207 px, masih di dalam sasaran 190-210 px.
const double _kTraceSize = 44;
const double _kSparkHeight = 38;

/// Kartu "Ringkasan perjalanan terakhir" di Beranda.
///
/// Semua angka berasal dari sesi selesai yang benar-benar tersimpan di HP, jadi
/// tanpa riwayat kartu menyatakan keadaan kosong apa adanya. Titik awal dan
/// akhir rute tidak pernah digambar di sini: sakelar privasinya hanya ada di
/// layar Kartu, dan Beranda tidak menyimpan pilihan itu, jadi sisi aman yang
/// dipakai.
class LastTripSummaryCard extends StatefulWidget {
  const LastTripSummaryCard({
    super.key,
    required this.data,
    this.mountain,
    this.onViewKartu,
    this.unavailableReason,
  });

  /// Ringkasan sesi selesai terbaru; null bila belum ada atau gagal dibaca.
  final KartuData? data;

  /// Nama gunung dari grup sesi itu; null bila tidak diketahui.
  final String? mountain;

  /// Dipanggil tombol "Lihat kartu".
  final VoidCallback? onViewKartu;

  /// Alasan jujur bila riwayat ada tetapi tidak dapat dibaca dari HP.
  final String? unavailableReason;

  @override
  State<LastTripSummaryCard> createState() => _LastTripSummaryCardState();
}

class _LastTripSummaryCardState extends State<LastTripSummaryCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;
  bool _played = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(vsync: this, duration: _kIntroDuration);
    if (widget.data != null) _play();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = VisualEffectPolicyScope.of(context).reduceMotion;
    if (_reduceMotion) _intro.value = 1;
  }

  @override
  void didUpdateWidget(LastTripSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data == null && widget.data != null) _play();
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  /// Animasi masuk hanya sekali, saat data pertama kali tersedia.
  void _play() {
    if (_played) return;
    _played = true;
    if (_reduceMotion) {
      _intro.value = 1;
      return;
    }
    unawaited(_intro.forward(from: 0));
  }

  double get _count => _reduceMotion
      ? 1
      : Curves.easeOut.transform((_intro.value / _kCountFraction).clamp(0.0, 1.0));

  double get _draw =>
      _reduceMotion ? 1 : Curves.easeOut.transform(_intro.value);

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return AnimatedBuilder(
      animation: _intro,
      builder: (context, _) => data == null ? _empty(context) : _filled(context, data),
    );
  }

  Widget _empty(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final reason = widget.unavailableReason;
    return GlassSurface(
      key: const ValueKey<String>('ringkasan-perjalanan'),
      tier: GlassTier.card,
      borderRadius: 24,
      padding: const EdgeInsets.all(HiqeoSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'PENDAKIAN TERAKHIR',
            style: HiqeoTypography.overline(colors.textSecondary),
          ),
          const SizedBox(height: HiqeoSpacing.xs),
          Text(
            reason == null
                ? 'Belum ada riwayat pendakian'
                : 'Riwayat belum dapat dibaca',
            style: theme.textTheme.titleMedium
                ?.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: HiqeoSpacing.xs),
          Text(
            reason ?? 'Ringkasan pendakian terakhirmu akan muncul di sini.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _filled(BuildContext context, KartuData data) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final scaled = data.scaledBy(_count);
    final mountain = widget.mountain;
    return GlassSurface(
      key: const ValueKey<String>('ringkasan-perjalanan'),
      tier: GlassTier.card,
      borderRadius: 24,
      padding: const EdgeInsets.all(HiqeoSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      data.isJogging ? 'JOGGING TERAKHIR' : 'PENDAKIAN TERAKHIR',
                      style: HiqeoTypography.overline(colors.textSecondary),
                    ),
                    const SizedBox(height: HiqeoSpacing.xs),
                    Text(
                      data.isJogging
                          ? 'Jogging ${data.dateText}'
                          : (mountain ?? 'Pendakian ${data.dateText}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${data.dateText} · ${data.timeLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: HiqeoSpacing.md),
              _KartuLink(onTap: widget.onViewKartu),
            ],
          ),
          const SizedBox(height: HiqeoSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: _metric(theme, colors, 'JARAK', scaled.distanceLabel),
              ),
              Expanded(
                child: _metric(
                  theme,
                  colors,
                  'TANJAKAN',
                  scaled.gainLabel,
                ),
              ),
              Expanded(
                child: _metric(theme, colors, 'WAKTU', scaled.timeLabel),
              ),
              const SizedBox(width: HiqeoSpacing.md),
              _trace(colors, data),
            ],
          ),
          const SizedBox(height: HiqeoSpacing.md),
          _sparkline(theme, colors, data),
        ],
      ),
    );
  }

  Widget _metric(
    ThemeData theme,
    HiqeoColors colors,
    String label,
    String value,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.textSecondary,
            fontWeight: HiqeoTypography.bold,
            fontSize: 9,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: theme.textTheme.titleLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: HiqeoTypography.extraBold,
              fontSize: 20,
              height: 1.1,
              letterSpacing: -0.8,
            ),
          ),
        ),
      ],
    );
  }

  Widget _trace(HiqeoColors colors, KartuData data) {
    final route = data.route;
    final hasRoute = route != null && route.length >= 2;
    return Semantics(
      container: hasRoute,
      label: hasRoute ? 'Jejak rute pendakian' : null,
      child: SizedBox(
        width: _kTraceSize,
        height: _kTraceSize,
        child: CustomPaint(
          key: const ValueKey<String>('ringkasan-rute'),
          painter: _MiniRoutePainter(
            points: hasRoute
                ? KartuData.fitRoute(
                    route,
                    const Size.square(_kTraceSize),
                    padding: 2,
                  )
                : const <Offset>[],
            progress: _draw,
            color: colors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _sparkline(ThemeData theme, HiqeoColors colors, KartuData data) {
    final profile = data.profile;
    if (profile == null || profile.length < 2) {
      return SizedBox(
        height: _kSparkHeight,
        child: Center(
          child: Text(
            'Profil elevasi belum tersedia',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colors.textSecondary),
          ),
        ),
      );
    }
    return SizedBox(
      height: _kSparkHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final geometry = _SparkGeometry.from(profile, size);
          final span = math.max(0.08, 1 - geometry.peakFraction);
          final peakOpacity = ((_draw - geometry.peakFraction) / span)
              .clamp(0.0, 1.0);
          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                child: CustomPaint(
                  key: const ValueKey<String>('ringkasan-elevasi'),
                  painter: _SparklinePainter(
                    geometry: geometry,
                    progress: _draw,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (!data.isJogging)
                Positioned(
                  left: (geometry.peak.dx - 28)
                      .clamp(0.0, math.max(0.0, size.width - 56)),
                  top: 0,
                  width: 56,
                  child: Opacity(
                    opacity: peakOpacity,
                    child: Text(
                      'PUNCAK',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: HiqeoTypography.bold,
                        fontSize: 9,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Tombol kaca kecil menuju layar Kartu untuk sesi yang diringkas.
class _KartuLink extends StatelessWidget {
  const _KartuLink({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: 'Lihat kartu',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // Target sentuh tetap 44 px meski pil yang terlihat lebih kecil.
        child: SizedBox(
          height: HiqeoMetrics.minTouchTarget,
          child: Center(
            child: ExcludeSemantics(
              child: LightweightGlassSurface(
                key: const ValueKey<String>('ringkasan-lihat-kartu'),
                borderRadius: HiqeoRadius.pill,
                padding: const EdgeInsets.symmetric(
                  horizontal: HiqeoSpacing.lg,
                ),
                child: SizedBox(
                  height: 36,
                  child: Center(
                    child: Text(
                      'Lihat kartu',
                      maxLines: 1,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: HiqeoTypography.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Geometri sparkline: x menurut jarak tempuh 0..1, y menurut ketinggian.
class _SparkGeometry {
  const _SparkGeometry({
    required this.points,
    required this.peak,
    required this.peakFraction,
  });

  final List<Offset> points;
  final Offset peak;
  final double peakFraction;

  static _SparkGeometry from(List<KartuProfilePoint> profile, Size size) {
    const topPadding = 13.0;
    const bottomPadding = 3.0;
    final usable = math.max(1.0, size.height - topPadding - bottomPadding);
    var minAlt = profile.first.altitudeM;
    var maxAlt = profile.first.altitudeM;
    for (final point in profile) {
      if (point.altitudeM < minAlt) minAlt = point.altitudeM;
      if (point.altitudeM > maxAlt) maxAlt = point.altitudeM;
    }
    final span = math.max(1.0, maxAlt - minAlt);
    Offset at(KartuProfilePoint point) => Offset(
          point.fraction.clamp(0.0, 1.0) * size.width,
          topPadding + (1 - (point.altitudeM - minAlt) / span) * usable,
        );
    var peakPoint = profile.first;
    for (final point in profile) {
      if (point.altitudeM > peakPoint.altitudeM) peakPoint = point;
    }
    return _SparkGeometry(
      points: <Offset>[for (final point in profile) at(point)],
      peak: at(peakPoint),
      peakFraction: peakPoint.fraction.clamp(0.0, 1.0),
    );
  }
}

/// Menggambar sebagian kurva sesuai [progress] supaya tampak tumbuh dari kiri.
Path _partialPath(Path path, double progress) {
  final metric = path.computeMetrics().first;
  return metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0));
}

Offset _endOf(Path path, double progress, Offset fallback) {
  final metric = path.computeMetrics().first;
  final tangent = metric.getTangentForOffset(
    metric.length * progress.clamp(0.0, 1.0),
  );
  return tangent?.position ?? fallback;
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.geometry,
    required this.progress,
    required this.color,
  });

  final _SparkGeometry geometry;
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final points = geometry.points;
    if (points.length < 2 || progress <= 0) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final drawn = _partialPath(path, progress);
    final end = _endOf(path, progress, points.last);
    final fill = Path.from(drawn)
      ..lineTo(end.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          <Color>[
            color.withValues(alpha: 0.18),
            color.withValues(alpha: 0.0),
          ],
        ),
    );
    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = HiqeoMetrics.iconStroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    if (end.dx >= geometry.peak.dx - 0.5) {
      canvas.drawCircle(geometry.peak, 3.2, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.geometry != geometry;
}

class _MiniRoutePainter extends CustomPainter {
  const _MiniRoutePainter({
    required this.points,
    required this.progress,
    required this.color,
  });

  final List<Offset> points;
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || progress <= 0) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      _partialPath(path, progress),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_MiniRoutePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.points != points;
}
