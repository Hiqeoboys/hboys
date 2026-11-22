import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../design/glass/glass_surface.dart';
import '../../../../design/tokens.dart';
import '../../../plus/domain/plus_format.dart';
import '../../domain/sport_science_analytics.dart';

class _ChartPalette {
  const _ChartPalette._();

  static const Color uphill = Color(0xFFE89D54);
  static const Color flat = Color(0xFF7FA8D9);
  static const Color downhill = Color(0xFF56B89A);
  static const Color stopped = Color(0xFF9DA6BD);

  static const Color altBelow2k = Color(0xFF56B89A);
  static const Color altMid = Color(0xFFE89D54);
  static const Color altHigh = Color(0xFFE0705C);
}

class DonutSliceData {
  const DonutSliceData({
    required this.label,
    required this.value,
    required this.valueText,
    required this.percentText,
    required this.color,
  });

  final String label;
  final double value;
  final String valueText;
  final String percentText;
  final Color color;
}

class BarChartItemData {
  const BarChartItemData({
    required this.label,
    required this.value,
    required this.topValueLabel,
    required this.color,
  });

  final String label;
  final double value;
  final String topValueLabel;
  final Color color;
}

class SportScienceDisclaimerBanner extends StatelessWidget {
  const SportScienceDisclaimerBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey<String>('sport-science-disclaimer'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.health_and_safety_outlined,
            size: 16,
            color: colors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Perkiraan fisiologis berbasis sensor GPS ini disusun sebagai panduan latihan, bukan diagnosis medis.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11.5,
                color: colors.textSecondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsSurfaceCard extends StatelessWidget {
  const _AnalyticsSurfaceCard({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      tier: GlassTier.card,
      borderRadius: HiqeoRadius.card,
      padding: const EdgeInsets.all(HiqeoSpacing.lg),
      child: child,
    );
  }
}

/// Donut chart 120fps yang dibungkus [RepaintBoundary] dengan legenda vertikal.
class HiqeoDonutChart extends StatelessWidget {
  const HiqeoDonutChart({
    super.key,
    required this.slices,
    required this.centerValue,
    required this.centerLabel,
  });

  final List<DonutSliceData> slices;
  final String centerValue;
  final String centerLabel;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final total = slices.fold<double>(0.0, (sum, s) => sum + s.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: SizedBox(
            width: 146,
            height: 146,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _DonutPainter(
                  slices: slices,
                  trackColor: colors.hairline,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        centerValue,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        centerLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: HiqeoSpacing.md),
        for (final slice in slices)
          if (slice.value > 0 || total == 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: slice.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      slice.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    slice.percentText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 64,
                    child: Text(
                      slice.valueText,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.slices,
    required this.trackColor,
  });

  final List<DonutSliceData> slices;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 17.0;
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    if (radius <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = trackColor,
    );

    final positive = slices.where((s) => s.value > 0).toList(growable: false);
    final total = positive.fold<double>(0.0, (sum, s) => sum + s.value);
    if (total <= 0) return;

    final gapRad = positive.length > 1 ? 0.045 : 0.0;
    var startAngle = -math.pi / 2;

    for (final slice in positive) {
      final sweep = (slice.value / total) * (2 * math.pi);
      final drawSweep = math.max(0.02, sweep - gapRad);
      canvas.drawArc(
        rect,
        startAngle + gapRad / 2,
        drawSweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt
          ..color = slice.color,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.slices != slices || oldDelegate.trackColor != trackColor;
}

/// Bar chart ringan dengan garis kisi tipis dan label nilai di atas batang.
class HiqeoBarChart extends StatelessWidget {
  const HiqeoBarChart({
    super.key,
    required this.items,
    this.height = 132,
  });

  final List<BarChartItemData> items;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final maxVal = items.fold<double>(
      1.0,
      (prev, item) => math.max(prev, item.value),
    );

    return SizedBox(
      height: height,
      child: RepaintBoundary(
        child: Column(
          children: <Widget>[
            Expanded(
              child: CustomPaint(
                size: Size.infinite,
                painter: _SimpleBarGridPainter(gridColor: colors.hairline),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    for (final item in items)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: <Widget>[
                              Text(
                                item.topValueLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 10,
                                  color: colors.textSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Flexible(
                                child: FractionallySizedBox(
                                  heightFactor: item.value <= 0
                                      ? 0.05
                                      : (item.value / maxVal).clamp(0.08, 1.0),
                                  widthFactor: 0.62,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: item.value <= 0
                                          ? colors.hairline
                                          : item.color,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                for (final item in items)
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10.5,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SimpleBarGridPainter extends CustomPainter {
  const _SimpleBarGridPainter({required this.gridColor});

  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final frac in const <double>[0.25, 0.6, 0.98]) {
      final y = size.height * frac;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_SimpleBarGridPainter oldDelegate) =>
      oldDelegate.gridColor != gridColor;
}

/// Kartu A.1 (History Detail): Donut distribusi waktu medan & istirahat.
class TerrainDistributionCard extends StatelessWidget {
  const TerrainDistributionCard({
    super.key,
    required this.distribution,
  });

  final TerrainDistribution distribution;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final slices = <DonutSliceData>[
      DonutSliceData(
        label: 'Menanjak (>+3%)',
        value: distribution.uphillSeconds.toDouble(),
        valueText: formatDuration(distribution.uphillSeconds),
        percentText: '${distribution.uphillPct.round()}%',
        color: _ChartPalette.uphill,
      ),
      DonutSliceData(
        label: 'Datar (−3%..+3%)',
        value: distribution.flatSeconds.toDouble(),
        valueText: formatDuration(distribution.flatSeconds),
        percentText: '${distribution.flatPct.round()}%',
        color: _ChartPalette.flat,
      ),
      DonutSliceData(
        label: 'Menurun (<−3%)',
        value: distribution.downhillSeconds.toDouble(),
        valueText: formatDuration(distribution.downhillSeconds),
        percentText: '${distribution.downhillPct.round()}%',
        color: _ChartPalette.downhill,
      ),
      DonutSliceData(
        label: 'Berhenti / Istirahat',
        value: distribution.stoppedSeconds.toDouble(),
        valueText: formatDuration(distribution.stoppedSeconds),
        percentText: '${distribution.stoppedPct.round()}%',
        color: _ChartPalette.stopped,
      ),
    ];

    return _AnalyticsSurfaceCard(
      key: const ValueKey<String>('history-terrain-donut-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Distribusi waktu & kemiringan medan',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            distribution.usedSummaryFallback
                ? 'Diperkirakan dari ringkasan elevasi naik-turun karena titik GPS per detik belum tersimpan penuh.'
                : 'Pemecahan waktu saat menanjak curam, berjalan datar, turun jalur, serta berhenti istirahat.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: HiqeoSpacing.md),
          if (!distribution.hasData)
            Text(
              'Durasi sesi belum cukup untuk memecah distribusi waktu medan.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            )
          else
            HiqeoDonutChart(
              slices: slices,
              centerValue: formatDuration(distribution.totalSeconds),
              centerLabel: 'Total sesi',
            ),
        ],
      ),
    );
  }
}

/// Kartu A.2 (History Detail): Pace split & elevasi per km dengan garis GAP.
class KmPaceSplitCard extends StatelessWidget {
  const KmPaceSplitCard({
    super.key,
    required this.splitReport,
  });

  final KmSplitReport splitReport;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final splits = splitReport.splits;
    final avgGap = splitReport.averageGapSecondsPerKm;

    return _AnalyticsSurfaceCard(
      key: const ValueKey<String>('history-km-split-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Split pace & elevasi per kilometer',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (avgGap != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _ChartPalette.downhill.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                  ),
                  child: Text(
                    'GAP rata ${formatPace(avgGap)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Batang menunjukkan pace tiap kilometer dengan angka elevasi naik (+m). Garis putus menunjukkan Grade-Adjusted Pace (GAP), yakni ritme setara berjalan di jalan datar.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: HiqeoSpacing.md),
          if (!splitReport.hasData)
            Text(
              splitReport.pacingConsistencyNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            )
          else ...<Widget>[
            _KmSplitChartBox(splits: splits, averageGap: avgGap),
            const SizedBox(height: HiqeoSpacing.sm),
            Text(
              splitReport.pacingConsistencyNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _KmSplitChartBox extends StatelessWidget {
  const _KmSplitChartBox({
    required this.splits,
    required this.averageGap,
  });

  final List<KmSplitEntry> splits;
  final double? averageGap;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);

    var maxPace = 1.0;
    for (final s in splits) {
      maxPace = math.max(maxPace, s.paceSecondsPerKm);
    }
    if (averageGap != null) {
      maxPace = math.max(maxPace, averageGap!);
    }
    maxPace *= 1.15;

    final chartContent = SizedBox(
      height: 148,
      width: splits.length > 6 ? splits.length * 52.0 : double.infinity,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _GapReferenceLinePainter(
            averageGap: averageGap,
            maxPace: maxPace,
            lineColor: _ChartPalette.downhill,
            gridColor: colors.hairline,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (final split in splits)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          '+${split.elevationGainM.round()}m',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: _ChartPalette.uphill,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatPaceValueShort(split.paceSecondsPerKm),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9.5,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Flexible(
                          child: FractionallySizedBox(
                            heightFactor: (split.paceSecondsPerKm / maxPace)
                                .clamp(0.10, 0.92),
                            widthFactor: 0.65,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.primary,
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          split.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (splits.length > 6) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: chartContent,
      );
    }
    return chartContent;
  }

  static String formatPaceValueShort(double secondsPerKm) {
    final total = secondsPerKm.round();
    final min = total ~/ 60;
    final sec = (total % 60).toString().padLeft(2, '0');
    return '$min:$sec';
  }
}

class _GapReferenceLinePainter extends CustomPainter {
  const _GapReferenceLinePainter({
    required this.averageGap,
    required this.maxPace,
    required this.lineColor,
    required this.gridColor,
  });

  final double? averageGap;
  final double maxPace;
  final Color lineColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    const topReserve = 34.0;
    const bottomReserve = 20.0;
    final plotHeight = math.max(10.0, size.height - topReserve - bottomReserve);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final frac in const <double>[0.25, 0.6, 1.0]) {
      final y = topReserve + plotHeight * frac;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final gap = averageGap;
    if (gap == null || maxPace <= 0) return;

    final ratio = (gap / maxPace).clamp(0.05, 0.95);
    final gapY = topReserve + plotHeight * (1.0 - ratio);

    final dashPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, gapY),
        Offset(math.min(x + 6, size.width), gapY),
        dashPaint,
      );
      x += 11;
    }
  }

  @override
  bool shouldRepaint(_GapReferenceLinePainter oldDelegate) =>
      oldDelegate.averageGap != averageGap ||
      oldDelegate.maxPace != maxPace ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.gridColor != gridColor;
}

/// Kartu A.3 (History Detail): Estimasi energi (Pandolf/ACSM), hidrasi, & pemulihan.
class RecoveryHydrationCard extends StatelessWidget {
  const RecoveryHydrationCard({
    super.key,
    required this.recovery,
  });

  final RecoveryHydrationEstimate recovery;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return _AnalyticsSurfaceCard(
      key: const ValueKey<String>('history-recovery-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Pemulihan energi & hidrasi',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Dihitung memakai persamaan beban bawaan Pandolf dan ACSM${recovery.assumedPackKg > 0 ? ' (asumsi ransel ${recovery.assumedPackKg.round()} kg)' : ''}.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: HiqeoSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: _MetricTileBox(
                  label: 'Perkiraan energi',
                  value: '${groupDigits(recovery.totalKcal.round())} kkal',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTileBox(
                  label: 'Pengganti cairan',
                  value: '${groupDigits(recovery.fluidReplacementMl)} ml',
                ),
              ),
            ],
          ),
          const SizedBox(height: HiqeoSpacing.sm),
          Text(
            recovery.recoveryNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textPrimary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTileBox extends StatelessWidget {
  const _MetricTileBox({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11.5,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kartu B.1 (Advanced Analytics): Acute vs Chronic Workload Ratio (7:28 hari).
class AcwrLoadCard extends StatelessWidget {
  const AcwrLoadCard({
    super.key,
    required this.report,
  });

  final AcwrReport report;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final statusColor = switch (report.zone) {
      AcwrZone.highRisk => colors.warningText,
      AcwrZone.elevated => _ChartPalette.uphill,
      AcwrZone.optimal => _ChartPalette.downhill,
      AcwrZone.recovery => _ChartPalette.flat,
      AcwrZone.insufficientData => colors.textSecondary,
    };

    return _AnalyticsSurfaceCard(
      key: const ValueKey<String>('analytics-acwr-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Beban latihan 7 hari vs 28 hari (ACWR)',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                ),
                child: Text(
                  report.ratio == null
                      ? '—'
                      : formatDecimal(report.ratio!, digits: 2),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            report.zoneLabel,
            style: theme.textTheme.titleSmall?.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            report.explanation,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: HiqeoSpacing.md),
          HiqeoBarChart(
            items: <BarChartItemData>[
              for (var i = 0; i < report.weeklyBuckets.length; i++)
                BarChartItemData(
                  label: report.weeklyBuckets[i].label,
                  value: report.weeklyBuckets[i].loadScore,
                  topValueLabel:
                      report.weeklyBuckets[i].loadScore.toStringAsFixed(0),
                  color: i == report.weeklyBuckets.length - 1
                      ? statusColor
                      : colors.primary.withValues(alpha: 0.55),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Kartu B.2 (Advanced Analytics): Beban turun eksentrik & kecepatan turun.
class EccentricDownhillCard extends StatelessWidget {
  const EccentricDownhillCard({
    super.key,
    required this.report,
  });

  final EccentricDownhillReport report;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return _AnalyticsSurfaceCard(
      key: const ValueKey<String>('analytics-eccentric-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Beban turun jalur (eksentrik)',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                report.kneeLoadLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: report.kneeLoadLabel.startsWith('Tinggi')
                      ? colors.warningText
                      : colors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            report.guidance,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: HiqeoSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: _MetricTileBox(
                  label: 'Total elevasi turun',
                  value: '−${groupDigits(report.totalElevationLossM.round())} m',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTileBox(
                  label: 'Kecepatan turun',
                  value: report.avgDescentSpeedMPerHour == null
                      ? '—'
                      : '${report.avgDescentSpeedMPerHour!.round()} m/jam',
                ),
              ),
            ],
          ),
          if (report.bars.isNotEmpty) ...<Widget>[
            const SizedBox(height: HiqeoSpacing.md),
            HiqeoBarChart(
              height: 118,
              items: <BarChartItemData>[
                for (final bar in report.bars)
                  BarChartItemData(
                    label: bar.label,
                    value: bar.elevationLossM,
                    topValueLabel: '−${bar.elevationLossM.round()}m',
                    color: _ChartPalette.downhill,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Kartu B.3 (Advanced Analytics): Zona ketinggian aklimatisasi & tren VAM.
class AltitudeVamCard extends StatelessWidget {
  const AltitudeVamCard({
    super.key,
    required this.report,
  });

  final AltitudeVamReport report;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final slices = <DonutSliceData>[
      DonutSliceData(
        label: '<2.000 mdpl (rendah)',
        value: report.below2000Seconds.toDouble(),
        valueText: formatDuration(report.below2000Seconds),
        percentText: '${report.below2000Pct.round()}%',
        color: _ChartPalette.altBelow2k,
      ),
      DonutSliceData(
        label: '2.000–2.500 mdpl (transisi)',
        value: report.between2000And2500Seconds.toDouble(),
        valueText: formatDuration(report.between2000And2500Seconds),
        percentText: '${report.between2000And2500Pct.round()}%',
        color: _ChartPalette.altMid,
      ),
      DonutSliceData(
        label: '>2.500 mdpl (waspada AMS)',
        value: report.above2500Seconds.toDouble(),
        valueText: formatDuration(report.above2500Seconds),
        percentText: '${report.above2500Pct.round()}%',
        color: _ChartPalette.altHigh,
      ),
    ];

    return _AnalyticsSurfaceCard(
      key: const ValueKey<String>('analytics-altitude-vam-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Zona ketinggian & kecepatan naik (VAM)',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                report.steepVamMPerHour == null
                    ? '—'
                    : '${report.steepVamMPerHour!.round()} m/jam',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            report.vamNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: HiqeoSpacing.md),
          if (!report.hasAltitudeData)
            Text(
              'Data ketinggian GPS belum tersedia pada sesi terpilih untuk memetakan waktu di zona di atas 2.500 mdpl (zona kewaspadaan aklimatisasi/AMS).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            )
          else
            HiqeoDonutChart(
              slices: slices,
              centerValue: report.steepVamMPerHour == null
                  ? formatDuration(report.totalAltitudeSeconds)
                  : '${report.steepVamMPerHour!.round()}',
              centerLabel:
                  report.steepVamMPerHour == null ? 'Waktu GPS' : 'VAM m/jam',
            ),
        ],
      ),
    );
  }
}

/// Kartu B.4 (Advanced Analytics): Fatigue Drift Index berbasis GAP.
class FatigueDriftCard extends StatelessWidget {
  const FatigueDriftCard({
    super.key,
    required this.report,
  });

  final FatigueDriftReport report;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final drift = report.driftPercent;

    return _AnalyticsSurfaceCard(
      key: const ValueKey<String>('analytics-fatigue-drift-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Indeks penurunan ritme (Fatigue Drift GAP)',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (drift != null)
                Text(
                  '${drift >= 0 ? '+' : '−'}${formatDecimal(drift.abs(), digits: 1)}%',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: drift >= 12 ? colors.warningText : colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            report.guidance,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          if (report.hasData) ...<Widget>[
            const SizedBox(height: HiqeoSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: _MetricTileBox(
                    label: 'GAP paruh pertama',
                    value: formatPace(report.firstHalfGapSecPerKm!),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricTileBox(
                    label: 'GAP paruh kedua',
                    value: formatPace(report.secondHalfGapSecPerKm!),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
