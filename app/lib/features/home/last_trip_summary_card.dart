import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../design/glass/glass_surface.dart';
import '../../design/motion/visual_effect_policy.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../kartu/domain/kartu_data.dart';

/// Durasi gambar-turut intro 700 ms; hitung-naik selesai pada 600 ms di dalamnya.
const Duration _kIntroDuration = Duration(milliseconds: 700);
const double _kCountFraction = 600 / 700;

/// Durasi satu siklus animasi loop lembut garis elevasi & rute GPS:
/// ~2,8 detik gerak garis + 2,0 detik jeda diam di ujung (100%) + 0,2 detik pudar.
const Duration _kLoopDuration = Duration(milliseconds: 5000);

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
    this.isActive = true,
  });

  /// Ringkasan sesi selesai terbaru; null bila belum ada atau gagal dibaca.
  final KartuData? data;

  /// Nama gunung dari grup sesi itu; null bila tidak diketahui.
  final String? mountain;

  /// Dipanggil tombol "Lihat kartu".
  final VoidCallback? onViewKartu;

  /// Alasan jujur bila riwayat ada tetapi tidak dapat dibaca dari HP.
  final String? unavailableReason;

  /// Menghentikan animasi loop saat tab Beranda tidak sedang aktif.
  final bool isActive;

  /// Mengembalikan `(sweep, tipAlpha)` dari progres siklus loop [t] (0..1):
  /// 0..0.56 (~2,8s) menggambar dari awal ke ujung, 0.56..0.96 (2,0s) jeda diam
  /// di ujung kanan, lalu 0.96..1.0 (~0,2s) memudar sebelum mengulang.
  @visibleForTesting
  static (double sweep, double tipAlpha) loopSweepFor(double t) {
    const drawPhaseEnd = 0.56;
    const pausePhaseEnd = 0.96;
    if (t < drawPhaseEnd) {
      return (
        Curves.easeInOutCubic.transform((t / drawPhaseEnd).clamp(0.0, 1.0)),
        1.0,
      );
    }
    if (t < pausePhaseEnd) {
      return (1.0, 1.0);
    }
    final fadeOut = ((1.0 - t) / (1.0 - pausePhaseEnd)).clamp(0.0, 1.0);
    return (1.0, fadeOut);
  }

  /// Menghitung koordinat titik ujung garis serta sub-daftar titik polyline
  /// sampai fraksi panjang [progress] (`0..1`) secara konsisten di semua device.
  @visibleForTesting
  static (List<Offset> segmentPoints, Offset tip) samplePolylineAt(
    List<Offset> points,
    double progress,
  ) {
    if (points.isEmpty) return (const <Offset>[], Offset.zero);
    if (points.length == 1 || progress <= 0) {
      return (<Offset>[points.first], points.first);
    }
    final clamped = progress.clamp(0.0, 1.0);
    if (clamped >= 1.0) {
      return (points, points.last);
    }

    var totalLength = 0.0;
    final segLengths = <double>[];
    for (var i = 1; i < points.length; i++) {
      final len = (points[i] - points[i - 1]).distance;
      segLengths.add(len);
      totalLength += len;
    }
    if (totalLength <= 0.0001) {
      return (points, points.last);
    }

    final target = totalLength * clamped;
    var acc = 0.0;
    final out = <Offset>[points.first];
    for (var i = 0; i < segLengths.length; i++) {
      final segLen = segLengths[i];
      final p0 = points[i];
      final p1 = points[i + 1];
      if (acc + segLen >= target) {
        final localT = segLen <= 0.0001
            ? 1.0
            : ((target - acc) / segLen).clamp(0.0, 1.0);
        final tip = Offset.lerp(p0, p1, localT) ?? p1;
        out.add(tip);
        return (out, tip);
      }
      out.add(p1);
      acc += segLen;
    }
    return (points, points.last);
  }

  @override
  State<LastTripSummaryCard> createState() => _LastTripSummaryCardState();
}

class _LastTripSummaryCardState extends State<LastTripSummaryCard>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _intro;
  late final AnimationController _loop;
  bool _played = false;
  bool _reduceMotion = false;
  bool _tickerEnabled = true;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _intro = AnimationController(vsync: this, duration: _kIntroDuration)
      ..addStatusListener(_onIntroStatus);
    _loop = AnimationController(vsync: this, duration: _kLoopDuration);
    if (widget.data != null) _play();
  }

  void _onIntroStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _syncLoopState();
      if (mounted) setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_lifecycleState == state) return;
    _lifecycleState = state;
    _syncLoopState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = VisualEffectPolicyScope.of(context).reduceMotion;
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    if (_reduceMotion) _intro.value = 1;
    _syncLoopState();
  }

  @override
  void didUpdateWidget(LastTripSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data == null && widget.data != null) _play();
    if (widget.data == null) {
      _loop.stop();
    } else if (oldWidget.isActive != widget.isActive ||
        oldWidget.data?.isJogging != widget.data?.isJogging) {
      _syncLoopState();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _intro.removeStatusListener(_onIntroStatus);
    _loop.dispose();
    _intro.dispose();
    super.dispose();
  }

  bool get _shouldAnimateLoop =>
      widget.data != null &&
      widget.isActive &&
      !_reduceMotion &&
      _tickerEnabled &&
      _lifecycleState == AppLifecycleState.resumed &&
      _intro.isCompleted;

  void _syncLoopState() {
    if (!mounted) return;
    if (_shouldAnimateLoop) {
      if (!_loop.isAnimating) {
        unawaited(_loop.repeat());
      }
    } else if (_loop.isAnimating) {
      _loop.stop();
    }
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
    final fitted = hasRoute
        ? KartuData.fitRoute(
            route,
            const Size.square(_kTraceSize),
            padding: 2,
          )
        : const <Offset>[];
    return Semantics(
      container: hasRoute,
      label: hasRoute ? 'Jejak rute pendakian' : null,
      child: RepaintBoundary(
        child: SizedBox(
          width: _kTraceSize,
          height: _kTraceSize,
          child: AnimatedBuilder(
            animation: _loop,
            builder: (context, _) {
              final animateRouteLoop = hasRoute && _shouldAnimateLoop;
              final (sweep, tipAlpha) = animateRouteLoop
                  ? LastTripSummaryCard.loopSweepFor(_loop.value)
                  : (1.0, 0.0);
              return CustomPaint(
                key: const ValueKey<String>('ringkasan-rute'),
                painter: _MiniRoutePainter(
                  points: fitted,
                  progress: _draw,
                  color: colors.textPrimary,
                  showTracer: animateRouteLoop,
                  loopProgress: sweep,
                  tipAlpha: tipAlpha,
                ),
              );
            },
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
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _loop,
                    builder: (context, _) {
                      final animateElevationLoop = _shouldAnimateLoop;
                      final (sweep, tipAlpha) = animateElevationLoop
                          ? LastTripSummaryCard.loopSweepFor(_loop.value)
                          : (1.0, 0.0);
                      return CustomPaint(
                        key: const ValueKey<String>('ringkasan-elevasi'),
                        painter: _SparklinePainter(
                          geometry: geometry,
                          progress: _draw,
                          color: colors.textPrimary,
                          showTracer: animateElevationLoop,
                          loopProgress: sweep,
                          tipAlpha: tipAlpha,
                        ),
                      );
                    },
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

Path _polylinePath(List<Offset> pts) {
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (final p in pts.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  return path;
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.geometry,
    required this.progress,
    required this.color,
    this.showTracer = false,
    this.loopProgress = 1.0,
    this.tipAlpha = 0.0,
  });

  final _SparkGeometry geometry;
  final double progress;
  final Color color;
  final bool showTracer;
  final double loopProgress;
  final double tipAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    final points = geometry.points;
    if (points.length < 2 || progress <= 0) return;
    final fullPath = _polylinePath(points);

    if (showTracer) {
      // Latar jejak elevasi halus utuh sepanjang profil.
      canvas.drawPath(
        fullPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = HiqeoMetrics.iconStroke * 0.85
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color.withValues(alpha: 0.22),
      );
      final activeT = loopProgress.clamp(0.0, 1.0);
      if (activeT > 0.005) {
        final (segPts, tip) = LastTripSummaryCard.samplePolylineAt(
          points,
          activeT,
        );
        final drawn = _polylinePath(segPts);
        final fill = Path.from(drawn)
          ..lineTo(tip.dx, size.height)
          ..lineTo(points.first.dx, size.height)
          ..close();
        canvas.drawPath(
          fill,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset.zero,
              Offset(0, size.height),
              <Color>[
                color.withValues(alpha: 0.20),
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
        if (tipAlpha > 0.01) {
          canvas.drawCircle(
            tip,
            7.5,
            Paint()..color = color.withValues(alpha: 0.14 * tipAlpha),
          );
          canvas.drawCircle(
            tip,
            4.5,
            Paint()..color = color.withValues(alpha: 0.30 * tipAlpha),
          );
          canvas.drawCircle(
            tip,
            2.6,
            Paint()..color = color.withValues(alpha: tipAlpha),
          );
        }
        if (tip.dx >= geometry.peak.dx - 0.5) {
          canvas.drawCircle(geometry.peak, 3.0, Paint()..color = color);
        }
      }
      return;
    }

    final (segPts, tip) = LastTripSummaryCard.samplePolylineAt(
      points,
      progress,
    );
    final drawn = _polylinePath(segPts);
    final fill = Path.from(drawn)
      ..lineTo(tip.dx, size.height)
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
    if (tip.dx >= geometry.peak.dx - 0.5) {
      canvas.drawCircle(geometry.peak, 3.2, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.geometry != geometry ||
      oldDelegate.showTracer != showTracer ||
      oldDelegate.loopProgress != loopProgress ||
      oldDelegate.tipAlpha != tipAlpha;
}

class _MiniRoutePainter extends CustomPainter {
  const _MiniRoutePainter({
    required this.points,
    required this.progress,
    required this.color,
    this.showTracer = false,
    this.loopProgress = 1.0,
    this.tipAlpha = 0.0,
  });

  final List<Offset> points;
  final double progress;
  final Color color;
  final bool showTracer;
  final double loopProgress;
  final double tipAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || progress <= 0) return;
    final fullPath = _polylinePath(points);
    if (showTracer) {
      canvas.drawPath(
        fullPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color.withValues(alpha: 0.26),
      );
      final activeT = loopProgress.clamp(0.0, 1.0);
      if (activeT > 0.005) {
        final (segPts, tip) = LastTripSummaryCard.samplePolylineAt(
          points,
          activeT,
        );
        canvas.drawPath(
          _polylinePath(segPts),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = color.withValues(alpha: 0.92),
        );
        if (tipAlpha > 0.01) {
          canvas.drawCircle(
            tip,
            5.8,
            Paint()..color = color.withValues(alpha: 0.24 * tipAlpha),
          );
          canvas.drawCircle(
            tip,
            2.6,
            Paint()..color = color.withValues(alpha: tipAlpha),
          );
        }
      }
      return;
    }
    final (segPts, _) = LastTripSummaryCard.samplePolylineAt(points, progress);
    canvas.drawPath(
      _polylinePath(segPts),
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
      oldDelegate.points != points ||
      oldDelegate.showTracer != showTracer ||
      oldDelegate.loopProgress != loopProgress ||
      oldDelegate.tipAlpha != tipAlpha;
}
