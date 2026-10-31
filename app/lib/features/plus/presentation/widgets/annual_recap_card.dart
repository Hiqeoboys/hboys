import 'package:flutter/material.dart';

import '../../../../core/brand/app_brand.dart';
import '../../../../design/tokens.dart';
import '../../../../design/typography.dart';
import '../../../../design/widgets/line_icons.dart';
import '../../domain/annual_recap.dart';
import '../../domain/plus_format.dart';

/// Kartu Rekap Tahunan yang selalu memakai palet gelap, di tema terang
/// maupun malam, karena kartu ini juga dibagikan sebagai PNG.
class AnnualRecapCard extends StatelessWidget {
  const AnnualRecapCard({
    super.key,
    required this.recap,
    required this.hideLocations,
    required this.peakBadgesEnabled,
  });

  final AnnualRecap recap;
  final bool hideLocations;
  final bool peakBadgesEnabled;

  static const HiqeoColors _dark = HiqeoColors.dark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: _dark.background,
      padding: const EdgeInsets.fromLTRB(
        HiqeoSpacing.lg,
        HiqeoSpacing.sm,
        HiqeoSpacing.lg,
        HiqeoSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${AppBrand.lockup} · REKAP TAHUNAN',
            style: HiqeoTypography.overline(_dark.textSecondary).copyWith(
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'Rekap ${recap.year}',
              maxLines: 1,
              style: theme.textTheme.displayLarge?.copyWith(
                fontSize: 46,
                height: 1.02,
                letterSpacing: -1.4,
                color: _dark.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: HiqeoSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _BigStat(
                  value: '${recap.sessionCount}',
                  label: 'Pendakian',
                ),
              ),
              Expanded(
                child: _BigStat(
                  value: formatKm(recap.distanceM),
                  label: 'Jarak',
                ),
              ),
              Expanded(
                child: _BigStat(
                  value: formatMeters(recap.elevationGainM),
                  label: 'Tanjakan',
                ),
              ),
            ],
          ),
          const SizedBox(height: HiqeoSpacing.lg),
          _ComparisonPanel(recap: recap),
          const SizedBox(height: HiqeoSpacing.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _HighlightPanel(
                    label: 'GUNUNG TERTINGGI',
                    value: recap.highestAltitudeM == null
                        ? 'Belum tercatat'
                        : formatMeters(recap.highestAltitudeM!),
                    detail: recap.highestAltitudeAtUtc == null
                        ? 'Altitude belum terekam'
                        : 'Titik GPS tertinggi · '
                            '${formatDayMonth(recap.highestAltitudeAtUtc!)}',
                  ),
                ),
                const SizedBox(width: HiqeoSpacing.sm),
                Expanded(
                  child: _HighlightPanel(
                    label: 'PENDAKIAN TERBERAT',
                    value: recap.hardestAtUtc == null
                        ? 'Belum ada'
                        : formatDayMonth(recap.hardestAtUtc!),
                    detail: recap.hardestAtUtc == null
                        ? 'Belum ada sesi selesai'
                        : '${formatKm(recap.hardestDistanceM)} · '
                            '${formatMeters(recap.hardestElevationGainM)} naik',
                  ),
                ),
              ],
            ),
          ),
          if (recap.route != null) ...<Widget>[
            const SizedBox(height: HiqeoSpacing.md),
            _RoutePanel(recap: recap, hideLocations: hideLocations),
          ],
          if (peakBadgesEnabled) ...<Widget>[
            const SizedBox(height: HiqeoSpacing.md),
            const _PeakBadgesPanel(),
          ],
          const SizedBox(height: HiqeoSpacing.lg),
          Row(
            children: <Widget>[
              HiqeoIcon(
                HiqeoIcons.mountain,
                size: 14,
                color: _dark.textSecondary,
              ),
              const SizedBox(width: HiqeoSpacing.xs),
              Text(
                '${AppBrand.lockup} · ${recap.year}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _dark.textSecondary,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BigStat extends StatelessWidget {
  const _BigStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: theme.textTheme.displaySmall?.copyWith(
              fontSize: 30,
              height: 1.05,
              letterSpacing: -0.8,
              color: AnnualRecapCard._dark.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AnnualRecapCard._dark.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _ComparisonPanel extends StatelessWidget {
  const _ComparisonPanel({required this.recap});

  final AnnualRecap recap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentDistance = recap.distanceM;
    final previousDistance = recap.previousDistanceM;
    final distanceMax =
        currentDistance > previousDistance ? currentDistance : previousDistance;
    return _RecapPanel(
      padding: const EdgeInsets.all(HiqeoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'DIBANDINGKAN ${recap.previousYear}',
                  style: HiqeoTypography.overline(
                    AnnualRecapCard._dark.textSecondary,
                  ).copyWith(fontSize: 10, letterSpacing: 1.4),
                ),
              ),
              Text(
                's.d. ${formatDayMonth(recap.comparisonEndLocal)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: AnnualRecapCard._dark.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: HiqeoSpacing.sm),
          _ComparisonRow(
            year: recap.previousYear,
            value: '${recap.previousSessionCount}',
            fraction: AnnualRecap.barFraction(
              recap.previousSessionCount.toDouble(),
              recap.sessionCount.toDouble(),
            ),
          ),
          const SizedBox(height: 6),
          _ComparisonRow(
            year: recap.year,
            value: _sessionValue(recap),
            fraction: AnnualRecap.barFraction(
              recap.sessionCount.toDouble(),
              recap.previousSessionCount.toDouble(),
            ),
            active: true,
          ),
          const SizedBox(height: HiqeoSpacing.sm),
          _ComparisonRow(
            year: recap.previousYear,
            value: previousDistance <= 0 ? '—' : formatKm(previousDistance),
            fraction: AnnualRecap.barFraction(previousDistance, distanceMax),
          ),
          const SizedBox(height: 6),
          _ComparisonRow(
            year: recap.year,
            value: formatKm(currentDistance),
            fraction: AnnualRecap.barFraction(currentDistance, distanceMax),
            active: true,
          ),
          if (recap.previousSessionCount == 0 &&
              recap.previousDistanceM <= 0) ...<Widget>[
            const SizedBox(height: HiqeoSpacing.sm),
            Text(
              'Belum ada sesi ${recap.previousYear} di HP ini.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10,
                color: AnnualRecapCard._dark.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _sessionValue(AnnualRecap recap) {
    final delta = recap.sessionDelta;
    if (delta == 0) return '${recap.sessionCount}';
    final sign = delta > 0 ? '+' : '−';
    return '${recap.sessionCount} ($sign${delta.abs()})';
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({
    required this.year,
    required this.value,
    required this.fraction,
    this.active = false,
  });

  final int year;
  final String value;
  final double fraction;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AnnualRecapCard._dark;
    return Row(
      children: <Widget>[
        SizedBox(
          width: 34,
          child: Text(
            '$year',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
              fontSize: 11,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(HiqeoRadius.pill),
            child: SizedBox(
              height: 7,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ColoredBox(
                    color: colors.primary.withValues(alpha: 0.14),
                  ),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: fraction,
                    child: ColoredBox(
                      color: active
                          ? colors.primary
                          : colors.primary.withValues(alpha: 0.38),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: HiqeoSpacing.sm),
        SizedBox(
          width: 66,
          child: Text(
            value,
            maxLines: 1,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _HighlightPanel extends StatelessWidget {
  const _HighlightPanel({
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AnnualRecapCard._dark;
    return _RecapPanel(
      padding: const EdgeInsets.all(HiqeoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: HiqeoTypography.overline(colors.textSecondary).copyWith(
              fontSize: 9,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: HiqeoSpacing.sm),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.textPrimary,
              fontSize: 17,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 10.5,
              height: 1.3,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutePanel extends StatelessWidget {
  const _RoutePanel({required this.recap, required this.hideLocations});

  final AnnualRecap recap;
  final bool hideLocations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AnnualRecapCard._dark;
    final route = recap.route!;
    return _RecapPanel(
      padding: const EdgeInsets.fromLTRB(
        HiqeoSpacing.md,
        HiqeoSpacing.sm,
        HiqeoSpacing.md,
        HiqeoSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'RUTE TAHUN INI',
                  style:
                      HiqeoTypography.overline(colors.textSecondary).copyWith(
                    fontSize: 9,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              Text(
                'Sesi terberat',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 92,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const padding = 10.0;
                final start = _routePoint(
                  route.first,
                  constraints.biggest,
                  padding,
                );
                final end = _routePoint(
                  route.last,
                  constraints.biggest,
                  padding,
                );
                return Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _RecapRoutePainter(
                          route: route,
                          color: colors.primary,
                        ),
                      ),
                    ),
                    if (!hideLocations)
                      Positioned(
                        key: const ValueKey<String>('recap-start-marker'),
                        left: start.dx - 4,
                        top: start.dy - 4,
                        child: _marker(filled: true),
                      ),
                    if (!hideLocations)
                      Positioned(
                        key: const ValueKey<String>('recap-end-marker'),
                        left: end.dx - 4,
                        top: end.dy - 4,
                        child: _marker(filled: false),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Offset _routePoint(Offset normalized, Size size, double padding) {
    final width = size.width - padding * 2;
    final height = size.height - padding * 2;
    return Offset(
      padding + normalized.dx * width,
      padding + normalized.dy * height,
    );
  }

  Widget _marker({required bool filled}) {
    final colors = AnnualRecapCard._dark;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? colors.primary : colors.background,
        border: Border.all(color: colors.primary, width: 1.5),
      ),
    );
  }
}

class _RecapRoutePainter extends CustomPainter {
  const _RecapRoutePainter({required this.route, required this.color});

  final List<Offset> route;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (route.length < 2) return;
    const padding = 10.0;
    final width = size.width - padding * 2;
    final height = size.height - padding * 2;
    final path = Path();
    for (var index = 0; index < route.length; index++) {
      final point = Offset(
        padding + route[index].dx * width,
        padding + route[index].dy * height,
      );
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.78)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_RecapRoutePainter oldDelegate) =>
      oldDelegate.route != route || oldDelegate.color != color;
}

class _PeakBadgesPanel extends StatelessWidget {
  const _PeakBadgesPanel();

  static const int _slotCount = 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AnnualRecapCard._dark;
    return _RecapPanel(
      padding: const EdgeInsets.all(HiqeoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'LENCANA PUNCAK',
            style: HiqeoTypography.overline(colors.textSecondary).copyWith(
              fontSize: 10,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: HiqeoSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              for (var index = 0; index < _slotCount; index++)
                Semantics(
                  label: 'Lencana puncak ${index + 1}, terkunci',
                  child: SizedBox(
                    width: 42,
                    height: 42,
                    child: CustomPaint(
                      painter: const _DashedCirclePainter(),
                      child: Center(
                        child: HiqeoIcon(
                          HiqeoIcons.lock,
                          size: 16,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: HiqeoSpacing.sm),
          Text(
            'Katalog puncak terverifikasi belum tersedia di build ini, jadi '
            'lencana belum bisa diberikan.',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 10.5,
              height: 1.3,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AnnualRecapCard._dark.primary.withValues(alpha: 0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final circle = Path()
      ..addOval(Rect.fromCircle(
        center: size.center(Offset.zero),
        radius: size.shortestSide / 2 - 1,
      ));
    for (final metric in circle.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + 3.2;
        canvas.drawPath(
          metric.extractPath(
            distance,
            next > metric.length ? metric.length : next,
          ),
          paint,
        );
        distance = next + 3.2;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter oldDelegate) => false;
}

class _RecapPanel extends StatelessWidget {
  const _RecapPanel({
    required this.child,
    this.padding = const EdgeInsets.all(HiqeoSpacing.md),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = AnnualRecapCard._dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(HiqeoRadius.floating),
        border: Border.all(color: colors.glassBorder),
      ),
      child: child,
    );
  }
}
