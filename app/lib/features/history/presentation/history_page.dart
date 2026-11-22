import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../design/background/app_background.dart';
import '../../../design/background/page_background.dart';
import '../../../design/gooey/gooey_selector.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/hiqeo_back_button.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/hiqeo_state_view.dart';
import '../../../infrastructure/auth/active_account_scope.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_connection.dart';
import '../../../infrastructure/database/repositories/drift_tracking_repository.dart';
import '../../../infrastructure/location/pedometer_step_counter.dart';
import '../../analytics/domain/sport_science_analytics.dart';
import '../../analytics/presentation/widgets/sport_science_charts.dart';
import '../../kartu/domain/kartu_data.dart';
import '../../profile/application/body_metrics_store.dart';
import '../../profile/domain/profile_summary.dart';
import '../../tracking/domain/calorie_estimator.dart';
import '../../tracking/domain/motion_estimators.dart';
import '../../tracking/domain/track_point.dart';
import '../../tracking/domain/tracking_repository.dart';
import '../../tracking/domain/tracking_session.dart';
import '../../tracking/presentation/tracking_view_data.dart';
import '../../tracking/presentation/widgets/live_route_polyline_view.dart';

/// Tab jenis aktivitas pada halaman Riwayat.
enum _HistoryTab {
  hiking('Pendakian'),
  jogging('Jogging');

  const _HistoryTab(this.label);
  final String label;
}

/// Halaman Riwayat (Pendakian & Riwayat Jogging, 100% bekerja offline dari SQLite lokal).
class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    this.repository,
  });

  final TrackingRepository? repository;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  AppDatabase? _database;
  TrackingRepository? _repo;
  StreamSubscription<List<TrackingSession>>? _sub;
  List<TrackingSession> _sessions = const <TrackingSession>[];
  final Map<String, List<Offset>> _joggingRoutes = <String, List<Offset>>{};
  final Set<String> _loadingRoutes = <String>{};
  _HistoryTab _selectedTab = _HistoryTab.hiking;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    ActiveAccountScope.activeUserId.addListener(_onAccountChanged);
    unawaited(_open());
  }

  @override
  void dispose() {
    ActiveAccountScope.activeUserId.removeListener(_onAccountChanged);
    unawaited(_sub?.cancel());
    final db = _database;
    if (db != null) {
      DriftTrackingRepository.unregisterDatabase(db);
      unawaited(db.close());
    }
    super.dispose();
  }

  void _onAccountChanged() {
    if (!mounted) return;
    setState(() {
      _sessions = const <TrackingSession>[];
      _joggingRoutes.clear();
      _loadingRoutes.clear();
    });
    unawaited(_open());
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _sub?.cancel();
    _sub = null;
    try {
      TrackingRepository? repo = widget.repository ?? _repo;
      if (repo == null) {
        final file = await defaultAppDatabaseFile();
        final db = openAppDatabase(file);
        if (!mounted) {
          await db.close();
          return;
        }
        _database = db;
        repo = DriftTrackingRepository(db);
      }
      _repo = repo;
      _sub = repo.watchSessions().listen(
        (list) {
          final completed = list
              .where(isMeaningfulCompletedSession)
              .toList()
            ..sort((a, b) => b.startedAtUtc.compareTo(a.startedAtUtc));
          if (!mounted) return;
          setState(() {
            _sessions = completed;
            _loading = false;
            _error = null;
          });
          unawaited(_prefetchJoggingRoutes(completed));
        },
        onError: (Object e) {
          if (kDebugMode) {
            debugPrint('HistoryPage watchSessions error: $e');
          }
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = 'Riwayat pendakian di perangkat ini belum bisa dimuat.';
          });
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('HistoryPage._open failed: $e');
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Riwayat di HP ini belum dapat dibuka. Coba muat ulang.';
      });
    }
  }

  Future<void> _prefetchJoggingRoutes(List<TrackingSession> sessions) async {
    final repo = _repo;
    if (repo == null) return;
    for (final s in sessions) {
      if (!s.isJogging) continue;
      if (_joggingRoutes.containsKey(s.id) || _loadingRoutes.contains(s.id)) {
        continue;
      }
      _loadingRoutes.add(s.id);
      try {
        final pts = await repo.points(s.id);
        final route = KartuData.fromSession(s, pts)?.route;
        if (route != null && route.length >= 2 && mounted) {
          setState(() => _joggingRoutes[s.id] = route);
        }
      } catch (_) {
      } finally {
        _loadingRoutes.remove(s.id);
      }
    }
  }

  String _formatDate(DateTime utc) {
    const months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    final local = utc.toLocal();
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  String _formatTime(DateTime utc) {
    final local = utc.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final h = safe ~/ 3600;
    final m = (safe % 3600) ~/ 60;
    if (h > 0) return '${h}j ${m}m';
    return '$m mnt';
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final isJoggingTab = _selectedTab == _HistoryTab.jogging;
    final visibleSessions = _sessions
        .where((s) => isJoggingTab ? s.isJogging : !s.isJogging)
        .toList(growable: false);

    return PageBackground(
      page: AppBackgroundPage.profil,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: const HiqeoBackButton(inAppBar: true),
          leadingWidth: HiqeoBackButton.appBarWidth,
          title: const Text('Riwayat'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: HiqeoStateView(
                        icon: Icons.error_outline_rounded,
                        title: 'Riwayat belum bisa dibuka',
                        message: _error!,
                        isError: true,
                        actionLabel: 'Coba lagi',
                        onAction: () => unawaited(_open()),
                      ),
                    ),
                  )
                : Column(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: colors.hairline),
                          ),
                          child: GooeySelector<_HistoryTab>(
                            key: const ValueKey<String>('history-tab-selector'),
                            axis: Axis.horizontal,
                            expandItems: true,
                            gap: 4,
                            borderRadius: 16,
                            indicatorColor: colors.primary,
                            itemPadding: const EdgeInsets.symmetric(
                              vertical: 11,
                              horizontal: 8,
                            ),
                            selected: _selectedTab,
                            onChanged: (tab) {
                              if (_selectedTab == tab) return;
                              setState(() => _selectedTab = tab);
                            },
                            items: <GooeySelectorItem<_HistoryTab>>[
                              for (final tab in _HistoryTab.values)
                                GooeySelectorItem<_HistoryTab>(
                                  value: tab,
                                  semanticsLabel: tab.label,
                                  builder: (context, state) => Center(
                                    key: ValueKey<String>(
                                      'history-tab-${tab.name}',
                                    ),
                                    child: Text(
                                      tab.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Color.lerp(
                                          colors.textSecondary,
                                          colors.onPrimary,
                                          state.coverage,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: visibleSessions.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(28),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Icon(
                                        isJoggingTab
                                            ? Icons.directions_run_rounded
                                            : Icons.terrain_outlined,
                                        size: 48,
                                        color: colors.textSecondary,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        isJoggingTab
                                            ? 'Belum ada riwayat jogging'
                                            : 'Belum ada riwayat pendakian',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        isJoggingTab
                                            ? 'Mulai mode Jogging dari tab Lacak untuk merekam statistik dan rute lari kamu.'
                                            : 'Semua sesi tracking yang selesai tersimpan 100% offline di HP ini.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.separated(
                                padding: EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  24 + MediaQuery.paddingOf(context).bottom,
                                ),
                                itemCount: visibleSessions.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final session = visibleSessions[index];
                                  return isJoggingTab
                                      ? _buildJoggingItem(
                                          context,
                                          session,
                                          colors,
                                        )
                                      : _buildHikingItem(
                                          context,
                                          session,
                                          colors,
                                        );
                                },
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildHikingItem(
    BuildContext context,
    TrackingSession session,
    HiqeoColors colors,
  ) {
    final title = session.mountainName?.trim().isNotEmpty == true
        ? session.mountainName!
        : 'Pendakian ${_formatDate(session.startedAtUtc)}';
    final trailSubtitle = session.trailName?.trim().isNotEmpty == true
        ? '${session.trailName} · ${_formatDate(session.startedAtUtc)}'
        : _formatDate(session.startedAtUtc);
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('history-item-${session.id}'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => HistoryDetailPage(
              session: session,
              repository: _repo,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SummitBadge(
                    reachedSummit: session.reachedSummit,
                    colors: colors,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                trailSubtitle,
                style: TextStyle(
                  fontSize: 12.5,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _MiniMetric(
                      label: 'Jarak',
                      value: '${(session.distanceM / 1000).toStringAsFixed(2)} km',
                      colors: colors,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniMetric(
                      label: 'Tanjakan',
                      value:
                          '+${formatElevationValue(canonicalSessionElevationGain(session))} m',
                      colors: colors,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniMetric(
                      label: 'Waktu',
                      value: _formatDuration(session.movingSeconds),
                      colors: colors,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJoggingItem(
    BuildContext context,
    TrackingSession session,
    HiqeoColors colors,
  ) {
    final avgPaceSec = PaceEstimator.computeAveragePaceSecPerKm(
      distanceM: session.distanceM,
      movingSeconds: session.movingSeconds,
    );
    final route = _joggingRoutes[session.id] ?? const <Offset>[];
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('history-item-${session.id}'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => HistoryDetailPage(
              session: session,
              repository: _repo,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Jogging ${_formatDate(session.startedAtUtc)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatDate(session.startedAtUtc)} · ${_formatTime(session.startedAtUtc)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 14,
                      runSpacing: 6,
                      children: <Widget>[
                        _MiniMetric(
                          label: 'Jarak',
                          value:
                              '${(session.distanceM / 1000).toStringAsFixed(2)} km',
                          colors: colors,
                        ),
                        _MiniMetric(
                          label: 'Pace',
                          value: avgPaceSec == null
                              ? '—'
                              : '${formatPaceValue(avgPaceSec)} /km',
                          colors: colors,
                        ),
                        _MiniMetric(
                          label: 'Waktu',
                          value: _formatDuration(session.movingSeconds),
                          colors: colors,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                key: ValueKey('history-jogging-route-preview-${session.id}'),
                width: 76,
                height: 76,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colors.secondary,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.hairline),
                ),
                child: LiveRoutePolylineView(
                  routePoints: route,
                  isLive: false,
                  compact: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HistoryDetailPage extends StatefulWidget {
  const HistoryDetailPage({
    super.key,
    required this.session,
    this.repository,
  });

  final TrackingSession session;
  final TrackingRepository? repository;

  @override
  State<HistoryDetailPage> createState() => _HistoryDetailPageState();
}

class _HistoryDetailPageState extends State<HistoryDetailPage> {
  List<TrackPoint> _points = const <TrackPoint>[];
  late SessionSportScienceReport _sportReport;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _sportReport = SessionSportScienceReport.fromSession(
      session: widget.session,
      points: _points,
      weightKg: BodyMetricsStore.instance.effectiveWeightKg,
    );
    unawaited(_loadPoints());
  }

  Future<void> _loadPoints() async {
    try {
      final repo = widget.repository;
      if (repo != null) {
        final pts = await repo.points(widget.session.id);
        if (mounted) {
          setState(() {
            _points = pts;
            _sportReport = SessionSportScienceReport.fromSession(
              session: widget.session,
              points: pts,
              weightKg: BodyMetricsStore.instance.effectiveWeightKg,
            );
            _loading = false;
          });
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _formatDuration(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final h = safe ~/ 3600;
    final m = (safe % 3600) ~/ 60;
    final s = safe % 60;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final s = widget.session;
    final isJogging = s.isJogging;
    final kartu = KartuData.fromSession(s, _points);
    final avgPaceSec = PaceEstimator.computeAveragePaceSecPerKm(
      distanceM: s.distanceM,
      movingSeconds: s.movingSeconds,
    );
    final body = BodyMetricsStore.instance;
    final estSteps = estimateStepsFromDistance(
      distanceM: s.distanceM,
      heightCm: body.heightCm ?? 170.0,
    );
    final estKcal = estimateKcal(
      weightKg: body.weightKg ?? 65.0,
      movingTime: Duration(seconds: s.movingSeconds),
    );
    double? maxEle;
    for (final pt in _points) {
      final a = pt.altitudeM;
      if (a == null) continue;
      if (maxEle == null || a > maxEle) maxEle = a;
    }

    final dateText = kartu?.dateText ?? '';
    return PageBackground(
      page: AppBackgroundPage.profil,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: const HiqeoBackButton(inAppBar: true),
          leadingWidth: HiqeoBackButton.appBarWidth,
          title: Text(
            isJogging ? 'Detail jogging' : (s.mountainName ?? 'Detail pendakian'),
          ),
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          isJogging
                              ? (dateText.isNotEmpty
                                  ? 'Jogging $dateText'
                                  : 'Catatan Jogging')
                              : (s.mountainName ?? 'Catatan Pendakian'),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                        if (!isJogging &&
                            s.trailName != null &&
                            s.trailName!.isNotEmpty)
                          Text(
                            s.trailName!,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: colors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!isJogging)
                    _SummitBadge(reachedSummit: s.reachedSummit, colors: colors),
                ],
              ),
              const SizedBox(height: 16),
              if (isJogging &&
                  !_loading &&
                  kartu?.route != null &&
                  kartu!.route!.length >= 2) ...<Widget>[
                Container(
                  key: const ValueKey<String>('history-jogging-route'),
                  height: 180,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colors.hairline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Rute jogging',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: LiveRoutePolylineView(
                          routePoints: kartu.route!,
                          isLive: false,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.1,
                children: <Widget>[
                  _DetailStatBox(
                    label: 'Jarak tempuh',
                    value: '${(s.distanceM / 1000).toStringAsFixed(2)} km',
                    colors: colors,
                  ),
                  _DetailStatBox(
                    label: 'Waktu bergerak',
                    value: _formatDuration(s.movingSeconds),
                    colors: colors,
                  ),
                  _DetailStatBox(
                    label: 'Tanjakan',
                    value:
                        '+${formatElevationValue(canonicalSessionElevationGain(s))} m',
                    colors: colors,
                  ),
                  _DetailStatBox(
                    label: 'Turunan',
                    value: '-${formatElevationValue(s.elevationLossM)} m',
                    colors: colors,
                  ),
                  _DetailStatBox(
                    label: 'Elevasi maks',
                    value: maxEle != null ? '${maxEle.round()} mdpl' : '—',
                    colors: colors,
                  ),
                  _DetailStatBox(
                    label: 'Pace rata-rata',
                    value: '${formatPaceValue(avgPaceSec)} /km',
                    colors: colors,
                  ),
                  _DetailStatBox(
                    label: 'Perkiraan langkah',
                    value: '$estSteps',
                    colors: colors,
                  ),
                  _DetailStatBox(
                    label: 'Perkiraan kalori',
                    value: '${estKcal.round()} kkal',
                    colors: colors,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!_loading &&
                  kartu?.profile != null &&
                  kartu!.profile!.length >= 2)
                Container(
                  height: 150,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colors.hairline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Profil elevasi',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _SimpleProfilePainter(
                            points: kartu.profile!,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              TerrainDistributionCard(distribution: _sportReport.terrain),
              const SizedBox(height: 12),
              KmPaceSplitCard(splitReport: _sportReport.kmSplits),
              const SizedBox(height: 12),
              RecoveryHydrationCard(recovery: _sportReport.recovery),
              const SizedBox(height: 10),
              const SportScienceDisclaimerBanner(),
              const SizedBox(height: 18),
              HiqeoButton(
                label: isJogging ? 'Lihat kartu' : 'Lihat kartu pendakian',
                onPressed: () => context.push(
                  '/kartu?sesi=${Uri.encodeQueryComponent(s.id)}',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummitBadge extends StatelessWidget {
  const _SummitBadge({
    required this.reachedSummit,
    required this.colors,
  });

  final bool reachedSummit;
  final HiqeoColors colors;

  @override
  Widget build(BuildContext context) {
    final bg = reachedSummit
        ? colors.success.withValues(alpha: 0.16)
        : colors.hairline;
    final fg = reachedSummit ? colors.successText : colors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(HiqeoRadius.pill),
      ),
      child: Text(
        reachedSummit ? 'Sampai puncak' : 'Belum sampai puncak',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.label,
    required this.value,
    required this.colors,
  });

  final String label;
  final String value;
  final HiqeoColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: colors.textSecondary),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailStatBox extends StatelessWidget {
  const _DetailStatBox({
    required this.label,
    required this.value,
    required this.colors,
  });

  final String label;
  final String value;
  final HiqeoColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SimpleProfilePainter extends CustomPainter {
  const _SimpleProfilePainter({required this.points, required this.color});

  final List<KartuProfilePoint> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    var minAlt = points.first.altitudeM;
    var maxAlt = points.first.altitudeM;
    for (final p in points) {
      if (p.altitudeM < minAlt) minAlt = p.altitudeM;
      if (p.altitudeM > maxAlt) maxAlt = p.altitudeM;
    }
    final span = (maxAlt - minAlt).abs() < 1 ? 1.0 : (maxAlt - minAlt);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = points[i].fraction.clamp(0.0, 1.0) * size.width;
      final y =
          size.height - ((points[i].altitudeM - minAlt) / span) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SimpleProfilePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}
