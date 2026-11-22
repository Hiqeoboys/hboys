import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../design/glass/glass_surface.dart';
import '../../../design/gooey/gooey_selector.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/line_icons.dart';
import '../../../infrastructure/auth/active_account_scope.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_connection.dart';
import '../../../infrastructure/database/repositories/drift_tracking_repository.dart';
import '../../analytics/domain/sport_science_analytics.dart';
import '../../analytics/presentation/widgets/sport_science_charts.dart';
import '../../profile/domain/profile_summary.dart';
import '../../tracking/domain/track_point.dart';
import '../../tracking/domain/tracking_repository.dart';
import '../../trails/data/gpx_loader.dart';
import '../../trails/domain/track_route.dart';
import '../domain/hike_analytics.dart';
import '../domain/plus_format.dart';
import '../domain/trail_segment_comparison.dart';
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
  final Map<String, List<TrackWaypoint>> _waypointCache =
      <String, List<TrackWaypoint>>{};

  @override
  void initState() {
    super.initState();
    ActiveAccountScope.activeUserId.addListener(_onAccountChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    ActiveAccountScope.activeUserId.removeListener(_onAccountChanged);
    final database = _database;
    if (database != null) {
      DriftTrackingRepository.unregisterDatabase(database);
      unawaited(database.close());
    }
    super.dispose();
  }

  void _onAccountChanged() {
    if (!mounted) return;
    setState(() {
      _samples = const <HikeSample>[];
      _loading = true;
      _error = null;
    });
    unawaited(_load());
  }

  Future<TrackingRepository?> _openRepository() async {
    final injected = widget.repository;
    if (injected != null) return injected;
    final existing = _database;
    if (existing != null) return DriftTrackingRepository(existing);
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
          .where((s) => isMeaningfulCompletedSession(s) && !s.isJogging)
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

  Future<void> _showSegmentComparisonSheet() async {
    final baseGroups = TrailSegmentComparisonBuilder.buildGroups(_samples);
    for (final g in baseGroups) {
      final path = g.gpxAssetPath;
      if (path == null || path.isEmpty) continue;
      if (_waypointCache.containsKey(g.routeKey)) continue;
      try {
        final route = await GpxLoader.loadAsset(path);
        _waypointCache[g.routeKey] = route.waypoints;
      } catch (_) {
        _waypointCache[g.routeKey] = const <TrackWaypoint>[];
      }
    }
    if (!mounted) return;
    final groups = TrailSegmentComparisonBuilder.buildGroups(
      _samples,
      waypointsByRouteKey: _waypointCache,
    );
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final safeBottom = MediaQuery.paddingOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            HiqeoSpacing.md,
            HiqeoSpacing.lg,
            HiqeoSpacing.md,
            HiqeoSpacing.md + safeBottom,
          ),
          child: _SegmentComparisonSheet(groups: groups),
        );
      },
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
                _filtered(_range),
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
        const SizedBox(height: HiqeoSpacing.sm),
        const SportScienceDisclaimerBanner(),
      ],
    );
  }

  Widget _rangeContent(
    List<HikeSample> rangeSamples,
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
    final sportScience = CrossSessionSportScienceReport.build(
      allSamples: _samples,
      rangeSamples: rangeSamples,
      nowLocal: widget.nowLocal,
    );
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
        AcwrLoadCard(report: sportScience.acwr),
        const SizedBox(height: HiqeoSpacing.md),
        EccentricDownhillCard(report: sportScience.eccentricDownhill),
        const SizedBox(height: HiqeoSpacing.md),
        AltitudeVamCard(report: sportScience.altitudeVam),
        const SizedBox(height: HiqeoSpacing.md),
        FatigueDriftCard(report: sportScience.fatigueDrift),
        const SizedBox(height: HiqeoSpacing.md),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(HiqeoRadius.card),
            onTap: _showSegmentComparisonSheet,
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

class _SegmentComparisonSheet extends StatefulWidget {
  const _SegmentComparisonSheet({required this.groups});

  final List<TrailComparisonGroup> groups;

  @override
  State<_SegmentComparisonSheet> createState() =>
      _SegmentComparisonSheetState();
}

class _SegmentComparisonSheetState extends State<_SegmentComparisonSheet> {
  int _selectedGroupIndex = 0;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final groups = widget.groups;
    final active = groups.isNotEmpty
        ? groups[_selectedGroupIndex.clamp(0, groups.length - 1)]
        : null;

    return GlassSurface(
      key: const ValueKey<String>('segment-comparison-sheet'),
      tier: GlassTier.panel,
      borderRadius: 28,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textSecondary.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Bandingkan segmen jalur',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              if (active == null) ...<Widget>[
                Text(
                  'Selesaikan minimal satu sesi agar segmen rute dan tanjakannya dapat dibandingkan.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ] else ...<Widget>[
                Text(
                  active.usedWaypoints
                      ? 'Segmen dihitung otomatis berdasarkan titik pos GPX jalur ${active.routeTitle}.'
                      : 'Segmen dibagi otomatis menjadi 4 tahap sepanjang ${active.routeTitle}.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                if (groups.length > 1) ...<Widget>[
                  const SizedBox(height: HiqeoSpacing.sm),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        for (var i = 0; i < groups.length; i++) ...<Widget>[
                          if (i > 0) const SizedBox(width: 8),
                          ChoiceChip(
                            label: Text(groups[i].routeTitle),
                            selected: i == _selectedGroupIndex,
                            onSelected: (_) =>
                                setState(() => _selectedGroupIndex = i),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: HiqeoSpacing.md),
                _ComparisonSummaryBanner(group: active),
                const SizedBox(height: HiqeoSpacing.md),
                for (final row in active.segments)
                  _SegmentMetricCard(
                    row: row,
                    isHardest: !active.hasMultiSessionComparison &&
                        active.hardestSegmentIndex == row.index,
                    isMostStable: !active.hasMultiSessionComparison &&
                        active.mostStableSegmentIndex == row.index,
                  ),
              ],
              const SizedBox(height: HiqeoSpacing.sm),
              HiqeoButton(
                label: 'Tutup',
                variant: HiqeoButtonVariant.secondary,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComparisonSummaryBanner extends StatelessWidget {
  const _ComparisonSummaryBanner({required this.group});

  final TrailComparisonGroup group;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);

    String summary;
    if (group.hasMultiSessionComparison) {
      final totalDelta = group.totalDeltaSeconds ?? 0;
      final latestDate = formatDate(group.latestSession.startedAtUtc);
      final prevDate = formatDate(group.previousSession!.startedAtUtc);
      if (totalDelta.abs() < 60) {
        summary =
            'Sesi $latestDate nyaris menyamai catatan $prevDate di jalur yang sama.';
      } else {
        final mins = (totalDelta.abs() / 60).round();
        final direction = totalDelta < 0 ? 'lebih cepat' : 'lebih lambat';
        summary =
            'Total segmen pada $latestDate tercatat $mins mnt $direction dibanding $prevDate.';
      }
    } else {
      final hardest = group.hardestSegment?.label;
      final stable = group.mostStableSegment?.label;
      summary = (hardest != null && stable != null)
          ? 'Baru ada 1 sesi di jalur ini. Segmen terberat ada di $hardest, sementara ritme paling stabil di $stable.'
          : 'Baru ada 1 sesi di jalur ini. Lakukan pendakian kedua pada gunung yang sama untuk membandingkan waktu antar-sesi.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
      ),
      child: Text(
        summary,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }
}

class _SegmentMetricCard extends StatelessWidget {
  const _SegmentMetricCard({
    required this.row,
    required this.isHardest,
    required this.isMostStable,
  });

  final SegmentDeltaRow row;
  final bool isHardest;
  final bool isMostStable;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final m = row.latest;
    final delta = row.deltaSeconds;

    String? badgeText;
    Color badgeColor = colors.primary;
    if (delta != null) {
      final mins = (delta.abs() / 60).round();
      if (mins == 0) {
        badgeText = 'Sama';
        badgeColor = colors.textSecondary;
      } else if (delta < 0) {
        badgeText = 'Lebih cepat $mins mnt';
        badgeColor = colors.successText;
      } else {
        badgeText = 'Lebih lambat $mins mnt';
        badgeColor = colors.warningText;
      }
    } else if (isHardest) {
      badgeText = 'Segmen terberat';
      badgeColor = colors.warningText;
    } else if (isMostStable) {
      badgeText = 'Paling stabil';
      badgeColor = colors.successText;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  row.label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (badgeText != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                  ),
                  child: Text(
                    badgeText,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10.5,
                      color: badgeColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: <Widget>[
              _tinyChip(context, 'Jarak', formatKm(m.distanceM)),
              _tinyChip(
                context,
                'Naik',
                '+${m.elevationGainM.round()} m',
              ),
              _tinyChip(
                context,
                'Gradien',
                '${m.avgGradePercent >= 0 ? '+' : '−'}${formatDecimal(m.avgGradePercent.abs())}%',
              ),
              _tinyChip(context, 'Durasi', formatDuration(m.durationSeconds)),
              _tinyChip(
                context,
                'Pace',
                m.paceSecondsPerKm == null
                    ? '—'
                    : formatPace(m.paceSecondsPerKm!),
              ),
              _tinyChip(
                context,
                'VAM',
                m.vamMPerHour == null ? '—' : '${m.vamMPerHour!.round()} m/jam',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tinyChip(BuildContext context, String label, String value) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 10.5,
            color: colors.textSecondary,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }
}
