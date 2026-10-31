import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../design/tokens.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/line_icons.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_connection.dart';
import '../../../infrastructure/database/repositories/drift_tracking_repository.dart';
import '../domain/plus_format.dart';
import '../../tracking/domain/tracking_repository.dart';
import '../../tracking/domain/tracking_session.dart';
import '../application/plus_navigation.dart';
import '../domain/hike_analytics.dart';
import '../domain/route_estimate.dart';
import '../infrastructure/device_sharing.dart';
import '../plus_content_dependencies.dart';
import 'widgets/plus_widgets.dart';

/// D3 Estimasi dan Itinerary.
///
/// Semua angka dihitung di perangkat dari median kecepatan jelajah pribadi.
/// Bila rute belum punya jalur atau belum ada sesi selesai, layar menyatakan
/// kekurangan itu dan tidak memakai asumsi kecepatan pendaki lain.
class RouteEstimatePage extends StatefulWidget {
  const RouteEstimatePage({
    super.key,
    required this.route,
    this.repository,
    this.sharer,
    this.nowLocal,
  });

  final PlusRouteContext route;
  final TrackingRepository? repository;
  final PlusTextSharer? sharer;
  final DateTime? nowLocal;

  @override
  State<RouteEstimatePage> createState() => _RouteEstimatePageState();
}

class _RouteEstimatePageState extends State<RouteEstimatePage> {
  AppDatabase? _database;
  bool _loading = true;
  String? _error;
  double? _paceKmh;
  RouteEstimate? _estimate;

  PlusTextSharer get _sharer =>
      widget.sharer ?? PlusContentDependencies.textSharer;

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
    if (!widget.route.hasPath) {
      setState(() => _loading = false);
      return;
    }
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
          .toList();
      final pace = personalPaceKmh(completed);
      final estimate = RouteEstimate.build(
        routeName: widget.route.name,
        points: widget.route.points,
        nowLocal: widget.nowLocal ?? DateTime.now(),
        paceKmh: pace,
      );
      if (!mounted) return;
      setState(() {
        _paceKmh = pace;
        _estimate = estimate;
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

  Future<void> _share() async {
    final estimate = _estimate;
    if (estimate == null) return;
    final ok = await _sharer.share(
      estimate.summaryText,
      subject: 'Estimasi ${estimate.routeName}',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Ringkasan siap dibagikan ke grup.'
                : 'Lembar berbagi tidak tersedia di perangkat ini.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return PlusScrollPage(
      topBar: PlusTopBar(
        title: 'Estimasi & itinerary',
        subtitle: widget.route.name,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      bottomBar: _estimate == null
          ? null
          : HiqeoButton(
              label: 'Bagikan ke grup',
              leading: HiqeoIcon(
                HiqeoIcons.share,
                size: 18,
                color: colors.onPrimary,
              ),
              onPressed: _share,
            ),
      children: <Widget>[
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: HiqeoSpacing.xxl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (!widget.route.hasPath)
          PlusEmptyState(
            icon: HiqeoIcons.trail,
            title: 'Rute belum punya jalur',
            message: 'Rute ${widget.route.name} belum punya titik jalur yang '
                'terunduh. Pilih dan unduh rutenya di Peta agar estimasi bisa '
                'dihitung.',
            action: HiqeoButton(
              label: 'Buka Peta',
              variant: HiqeoButtonVariant.secondary,
              onPressed: () => context.go('/peta'),
            ),
          )
        else if (_error != null)
          PlusEmptyState(
            icon: HiqeoIcons.warning,
            title: 'Estimasi belum bisa dibuat',
            message: _error!,
            action: HiqeoButton(
              label: 'Coba lagi',
              variant: HiqeoButtonVariant.secondary,
              onPressed: _load,
            ),
          )
        else if (_estimate == null)
          PlusEmptyState(
            icon: HiqeoIcons.clock,
            title: 'Belum ada kecepatan pribadi',
            message: _paceKmh == null
                ? 'Selesaikan minimal satu pendakian agar Hiqeo tahu kecepatan '
                    'jelajahmu. Estimasi tidak memakai kecepatan pendaki lain.'
                : 'Rute ini terlalu pendek untuk diestimasi.',
            action: _paceKmh == null
                ? HiqeoButton(
                    label: 'Mulai pendakian',
                    variant: HiqeoButtonVariant.secondary,
                    onPressed: () => context.go('/lacak'),
                  )
                : null,
          )
        else
          ..._estimateContent(theme, colors, _estimate!),
      ],
    );
  }

  List<Widget> _estimateContent(
    ThemeData theme,
    HiqeoColors colors,
    RouteEstimate estimate,
  ) {
    final fits = estimate.fitsBeforeSunset;
    return <Widget>[
      PlusCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const PlusOverline('Perkiraan tiba di puncak'),
            const SizedBox(height: HiqeoSpacing.xs),
            Text(
              formatClock(estimate.arrivalLocal),
              style: theme.textTheme.displayMedium,
            ),
            const SizedBox(height: HiqeoSpacing.xs),
            Text(
              '${formatKm(estimate.distanceM)} · mulai '
              '${formatClock(estimate.startLocal)} · kecepatan pribadi '
              '${formatDecimal(estimate.paceKmh)} km/jam',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: HiqeoSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: PlusStatTile(
                    stat: PlusStat(
                      value: estimate.turnAroundLocal == null
                          ? '—'
                          : formatClock(estimate.turnAroundLocal!),
                      label: 'Batas putar balik',
                    ),
                  ),
                ),
                Expanded(
                  child: PlusStatTile(
                    stat: PlusStat(
                      value: estimate.sunsetLocal == null
                          ? '—'
                          : formatClock(estimate.sunsetLocal!),
                      label: 'Matahari terbenam',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      if (fits == false) ...<Widget>[
        const SizedBox(height: HiqeoSpacing.md),
        PlusCard(
          child: PlusNotice(
            icon: HiqeoIcons.warning,
            warning: true,
            text: 'Dengan kecepatan ini, perjalanan tidak muat sebelum gelap. '
                'Mulai lebih pagi atau pilih target yang lebih dekat.',
          ),
        ),
      ],
      const SizedBox(height: HiqeoSpacing.lg),
      const PlusOverline('Garis waktu'),
      const SizedBox(height: HiqeoSpacing.sm),
      PlusCard(
        child: Column(
          children: <Widget>[
            for (var index = 0; index < estimate.timeline.length; index++)
              _TimelineRow(
                point: estimate.timeline[index],
                last: index == estimate.timeline.length - 1,
              ),
          ],
        ),
      ),
      const SizedBox(height: HiqeoSpacing.lg),
      const PlusOverline('Itinerary'),
      const SizedBox(height: HiqeoSpacing.sm),
      PlusCard(
        child: Column(
          children: <Widget>[
            _ItineraryRow(
              label: 'Naik ke puncak',
              detail: 'Termasuk istirahat ${estimate.breaks.inMinutes} menit',
              duration: estimate.ascent + estimate.breaks,
            ),
            Divider(color: colors.hairline, height: HiqeoSpacing.lg),
            _ItineraryRow(
              label: 'Istirahat di puncak',
              detail: 'Makan, foto, dan periksa cuaca',
              duration: estimate.summitRest,
            ),
            Divider(color: colors.hairline, height: HiqeoSpacing.lg),
            _ItineraryRow(
              label: 'Turun ke titik awal',
              detail: 'Tanpa istirahat panjang',
              duration: estimate.descent,
            ),
          ],
        ),
      ),
      const SizedBox(height: HiqeoSpacing.lg),
      const PlusOverline('Perlengkapan'),
      const SizedBox(height: HiqeoSpacing.sm),
      PlusCard(
        child: Column(
          children: <Widget>[
            for (final item in estimate.gear)
              Padding(
                padding: const EdgeInsets.only(bottom: HiqeoSpacing.sm),
                child: Row(
                  children: <Widget>[
                    HiqeoIcon(
                      HiqeoIcons.check,
                      size: 16,
                      color: colors.primary,
                    ),
                    const SizedBox(width: HiqeoSpacing.sm),
                    Expanded(
                      child: Text(item, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: HiqeoSpacing.md),
      PlusNotice(
        icon: HiqeoIcons.clock,
        text: 'Estimasi dihitung di HP ini dari kecepatan pribadi dan jarak '
            'rute. Bukan jadwal resmi; cuaca dan kondisi jalur dapat mengubah '
            'waktu.',
      ),
    ];
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.point, required this.last});

  final ItineraryPoint point;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final tint = point.warning ? colors.warningText : colors.primary;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: 50,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                formatClock(point.timeLocal),
                style: theme.textTheme.titleSmall?.copyWith(color: tint),
              ),
            ),
          ),
          SizedBox(
            width: 20,
            child: Column(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tint,
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(width: 1.5, color: colors.hairline),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : HiqeoSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(point.label, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 1),
                  Text(
                    point.detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItineraryRow extends StatelessWidget {
  const _ItineraryRow({
    required this.label,
    required this.detail,
    required this.duration,
  });

  final String label;
  final String detail;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: theme.textTheme.titleSmall),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: HiqeoSpacing.sm),
        Text(
          formatDuration(duration.inSeconds),
          style: theme.textTheme.titleMedium,
        ),
      ],
    );
  }
}
