import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../design/gooey/gooey_selector.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/line_icons.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_connection.dart';
import '../../../infrastructure/database/repositories/drift_tracking_repository.dart';
import '../../tracking/domain/track_point.dart';
import '../../tracking/domain/tracking_repository.dart';
import '../../tracking/domain/tracking_session.dart';
import '../domain/hike_analytics.dart';
import '../domain/plus_format.dart';
import 'widgets/plus_widgets.dart';

/// D4 Analitik Lanjutan.
///
/// Semua angka berasal dari sesi selesai dan titik GPS di perangkat. Tidak ada
/// kategori kecepatan: yang ditampilkan pace, kemiringan, kecepatan vertikal,
/// rekor jarak/elevasi, dan indikasi kelelahan.
class AdvancedAnalyticsPage extends StatefulWidget {
  const AdvancedAnalyticsPage({
    super.key,
    this.repository,
    this.nowLocal,
  });

  final TrackingRepository? repository;
  final DateTime? nowLocal;

  @override
  State<AdvancedAnalyticsPage> createState() => _AdvancedAnalyticsPageState();
}

class _AdvancedAnalyticsPageState extends State<AdvancedAnalyticsPage> {
  AppDatabase? _database;
  bool _loading = true;
  String? _error;
  List<HikeSample> _samples = const <HikeSample>[];
  PlusAnalyticsRange _range = PlusAnalyticsRange.recent;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    final database = _database;
    if (database != null) unawaited(database.close());
    super.dispose();
  }

  Future<TrackingRepository?> _openRepository() async {
    final injected = widget.repository;
    if (injected != null) return injected;
    try {
      final file = await defaultAppDatabaseFile();
      final database = openAppDatabase(file);
      if (!mounted) {
        await database.close();
        return null;
      }
      _database = database;
      return DriftTrackingRepository(database);
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repository = await _openRepository();
    if (!mounted) return;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = 'Data pendakian lokal belum dapat dibuka.';
      });
      return;
    }
    try {
      final sessions = await repository.watchSessions().first;
      final completed = sessions
          .where((session) => session.status == TrackingSessionStatus.completed)
          .toList()
        ..sort((a, b) => b.startedAtUtc.compareTo(a.startedAtUtc));
      final samples = <HikeSample>[];
      for (final session in completed) {
        List<TrackPoint> points = const <TrackPoint>[];
        try {
          points = await repository.points(session.id);
        } catch (_) {
          points = const <TrackPoint>[];
        }
        samples.add(HikeSample(session: session, points: points));
      }
      if (!mounted) return;
      setState(() {
        _samples = samples;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Riwayat pendakian belum dapat dibaca.';
      });
    }
  }

  List<HikeSample> _filtered(PlusAnalyticsRange range) {
    switch (range) {
      case PlusAnalyticsRange.recent:
        return _samples.take(5).toList();
      case PlusAnalyticsRange.year:
        final year = (widget.nowLocal ?? DateTime.now()).year;
        return _samples
            .where(
                (sample) => sample.session.startedAtUtc.toLocal().year == year)
            .toList();
      case PlusAnalyticsRange.all:
        return _samples;
    }
  }

  Future<void> _showCompareInfo() {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(HiqeoSpacing.md),
          child: PlusCard(
            radius: HiqeoRadius.hero,
            padding: const EdgeInsets.all(HiqeoSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Bandingkan segmen jalur',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: HiqeoSpacing.sm),
                Text(
                  'Perbandingan per segmen membutuhkan katalog jalur '
                  'terverifikasi per gunung. Katalog itu belum terisi di build '
                  'ini, jadi Hiqeo tidak menampilkan perbandingan yang '
                  'dikarang.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: HiqeoSpacing.md),
                HiqeoButton(
                  label: 'Mengerti',
                  variant: HiqeoButtonVariant.secondary,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = HiqeoColors.of(context);
    return PlusScrollPage(
      topBar: PlusTopBar(
        title: 'Analitik lanjutan',
        subtitle: 'Dari sesi selesai di HP ini',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      children: <Widget>[
        _RangeTabs(
          selected: _range,
          onChanged: (range) => setState(() => _range = range),
        ),
        const SizedBox(height: HiqeoSpacing.xs),
        Text(
          _range.description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: HiqeoSpacing.lg),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: HiqeoSpacing.xxl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          PlusEmptyState(
            icon: HiqeoIcons.warning,
            title: 'Analitik belum bisa dibuka',
            message: _error!,
            action: HiqeoButton(
              label: 'Coba lagi',
              variant: HiqeoButtonVariant.secondary,
              onPressed: _load,
            ),
          )
        else
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: KeyedSubtree(
              key: ValueKey<PlusAnalyticsRange>(_range),
              child: _rangeContent(
                HikeAnalytics.build(_filtered(_range)),
                theme,
                colors,
              ),
            ),
          ),
        const SizedBox(height: HiqeoSpacing.md),
        PlusNotice(
          icon: HiqeoIcons.activity,
          text: 'Tidak ada kategori kecepatan di Hiqeo. Analitik dipakai untuk '
              'mengenali pola dan kelelahan, bukan memeringkat pendaki.',
        ),
      ],
    );
  }

  Widget _rangeContent(
    HikeAnalytics analytics,
    ThemeData theme,
    HiqeoColors colors,
  ) {
    if (analytics.isEmpty) {
      return PlusEmptyState(
        icon: HiqeoIcons.activity,
        title: 'Belum ada pendakian',
        message: 'Analitik terisi setelah ada sesi yang selesai dan tersimpan '
            'di HP ini.',
        action: HiqeoButton(
          label: 'Mulai pendakian',
          variant: HiqeoButtonVariant.secondary,
          onPressed: () => context.go('/lacak'),
        ),
      );
    }

    final fatigue = analytics.fatigue;
    final slowdown = fatigue.slowdownPercent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PlusCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${analytics.sampleCount} pendakian',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: HiqeoSpacing.md),
              Row(
                children: <Widget>[
                  Expanded(
                    child: PlusStatTile(
                      stat: PlusStat(
                        value: formatKm(analytics.distanceM),
                        label: 'Jarak',
                      ),
                      valueSize: 18,
                    ),
                  ),
                  Expanded(
                    child: PlusStatTile(
                      stat: PlusStat(
                        value: formatMeters(analytics.elevationGainM),
                        label: 'Elevasi naik',
                      ),
                      valueSize: 18,
                    ),
                  ),
                  Expanded(
                    child: PlusStatTile(
                      stat: PlusStat(
                        value: formatDuration(analytics.movingSeconds),
                        label: 'Waktu gerak',
                      ),
                      valueSize: 18,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: HiqeoSpacing.md),
        PlusCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Pace per kemiringan', style: theme.textTheme.titleMedium),
              const SizedBox(height: HiqeoSpacing.xs),
              Text(
                'Dihitung dari segmen yang punya altitude; jeda di atas 60 '
                'detik tidak dihitung sebagai berjalan.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: HiqeoSpacing.md),
              for (final pace in analytics.slopePaces)
                Padding(
                  padding: const EdgeInsets.only(bottom: HiqeoSpacing.sm),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              pace.kind.label,
                              style: theme.textTheme.titleSmall,
                            ),
                            Text(
                              pace.kind.gradeHint,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        pace.secondsPerKm == null
                            ? 'Belum cukup data'
                            : formatPace(pace.secondsPerKm!),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: pace.secondsPerKm == null
                              ? colors.textSecondary
                              : colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: HiqeoSpacing.md),
        PlusCard(
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Kecepatan vertikal',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Total elevasi naik dibagi waktu bergerak',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: HiqeoSpacing.md),
              Text(
                analytics.verticalSpeedMPerHour == null
                    ? '—'
                    : '${analytics.verticalSpeedMPerHour!.round()} m/jam',
                style: theme.textTheme.headlineSmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: HiqeoSpacing.md),
        PlusCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Rekor pribadi', style: theme.textTheme.titleMedium),
              const SizedBox(height: HiqeoSpacing.xs),
              Text(
                'Tanpa rekor kecepatan; keselamatan di atas persaingan.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: HiqeoSpacing.md),
              for (final record in analytics.records)
                Padding(
                  padding: const EdgeInsets.only(bottom: HiqeoSpacing.sm),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              record.label,
                              style: theme.textTheme.titleSmall,
                            ),
                            Text(
                              formatDate(record.occurredAtUtc),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        record.value,
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: HiqeoSpacing.md),
        PlusCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Analisis kelelahan', style: theme.textTheme.titleMedium),
              const SizedBox(height: HiqeoSpacing.xs),
              if (!fatigue.hasData)
                Text(
                  'Butuh sesi minimal 1 km dengan titik GPS cukup untuk '
                  'membandingkan paruh pertama dan kedua. Data sekarang belum '
                  'memenuhi syarat itu.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                )
              else ...<Widget>[
                Text(
                  slowdown != null && slowdown > 5
                      ? 'Pace paruh kedua ${formatDecimal(slowdown)}% lebih '
                          'lambat. Pertimbangkan istirahat lebih awal.'
                      : (slowdown != null && slowdown < -5
                          ? 'Pace paruh kedua ${formatDecimal(slowdown.abs())}% '
                              'lebih cepat.'
                          : 'Pace paruh kedua relatif stabil.'),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: HiqeoSpacing.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: PlusStatTile(
                        stat: PlusStat(
                          value: formatPace(fatigue.firstHalfSecondsPerKm!),
                          label: 'Paruh pertama',
                        ),
                        valueSize: 18,
                      ),
                    ),
                    Expanded(
                      child: PlusStatTile(
                        stat: PlusStat(
                          value: formatPace(fatigue.secondHalfSecondsPerKm!),
                          label: 'Paruh kedua',
                        ),
                        valueSize: 18,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: HiqeoSpacing.md),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(HiqeoRadius.card),
            onTap: _showCompareInfo,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: HiqeoSpacing.lg,
                vertical: HiqeoSpacing.md,
              ),
              child: Row(
                children: <Widget>[
                  HiqeoIcon(
                    HiqeoIcons.map,
                    size: 18,
                    color: colors.primary,
                  ),
                  const SizedBox(width: HiqeoSpacing.sm),
                  Expanded(
                    child: Text(
                      'Bandingkan segmen jalur',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  HiqeoIcon(
                    HiqeoIcons.chevronRight,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RangeTabs extends StatelessWidget {
  const _RangeTabs({required this.selected, required this.onChanged});

  final PlusAnalyticsRange selected;
  final ValueChanged<PlusAnalyticsRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return GooeySelector<PlusAnalyticsRange>(
      key: const ValueKey('analytics-range-tabs'),
      axis: Axis.horizontal,
      items: <GooeySelectorItem<PlusAnalyticsRange>>[
        for (final range in PlusAnalyticsRange.values)
          GooeySelectorItem<PlusAnalyticsRange>(
            value: range,
            semanticsLabel: range.label,
            builder: (context, state) => Text(
              range.label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Color.lerp(
                      colors.textSecondary,
                      colors.onPrimary,
                      state.coverage,
                    ),
                  ),
            ),
          ),
      ],
      selected: selected,
      gap: 6,
      itemPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      onChanged: onChanged,
    );
  }
}
