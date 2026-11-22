import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geo_utils/geo_utils.dart' show LatLng;
import 'package:go_router/go_router.dart';

import '../../../design/glass/glass_surface.dart';
import '../../../design/gooey/gooey_selector.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/line_icons.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_connection.dart';
import '../../../infrastructure/database/repositories/drift_tracking_repository.dart';
import '../../map/domain/map_package.dart';
import '../../map/domain/mountain_pack.dart';
import '../../map/domain/mountain_pack_data.dart';
import '../../tracking/domain/tracking_repository.dart';
import '../../tracking/domain/tracking_session.dart';
import '../../trails/data/gpx_loader.dart';
import '../../trails/domain/track_route.dart';
import '../application/plus_navigation.dart';
import '../domain/hike_analytics.dart';
import '../domain/plus_format.dart';
import '../domain/route_estimate.dart';
import '../infrastructure/device_sharing.dart';
import '../plus_content_dependencies.dart';
import 'widgets/plus_widgets.dart';

/// D3 Estimasi & Kalkulator Pendakian Lokal.
///
/// Jika dibuka dengan data gunung/jalur nyata (mis. dari Siap Naik atau katalog
/// gunung), menghitung durasi naik/turun, logistik air/kalori, dan ETA tiap pos
/// secara real-time di perangkat memakai Naismith's Rule + Tobler dengan 0 beban DB.
class RouteEstimatePage extends StatefulWidget {
  const RouteEstimatePage({
    super.key,
    required this.route,
    this.repository,
    this.sharer,
    this.nowLocal,
    this.assetBundle,
  });

  final PlusRouteContext route;
  final TrackingRepository? repository;
  final PlusTextSharer? sharer;
  final DateTime? nowLocal;
  final AssetBundle? assetBundle;

  @override
  State<RouteEstimatePage> createState() => _RouteEstimatePageState();
}

class _RouteEstimatePageState extends State<RouteEstimatePage> {
  // Mode kalkulator interaktif (0 beban database)
  bool _calculatorMode = false;
  late double _distanceM;
  late double _elevationGainM;
  late double _basecampElevM;
  late double _summitElevM;
  String? _trailLabel;
  LatLng? _centerCoord;
  List<TrackWaypoint> _waypoints = const <TrackWaypoint>[];
  HikingPace _pace = HikingPace.normal;
  CarrierLoad _load = CarrierLoad.sedang;
  late TimeOfDay _startTime;

  // Mode legacy berbasis kecepatan pribadi
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
    final refNow = widget.nowLocal ?? DateTime(2026, 6, 1, 6, 0);
    _startTime = widget.nowLocal != null
        ? TimeOfDay(hour: refNow.hour, minute: refNow.minute)
        : const TimeOfDay(hour: 6, minute: 0);

    final matched = _matchCatalogTarget();
    final useCalculator = widget.route.hasCalculatorMetadata ||
        (widget.repository == null && matched.pack != null);

    if (useCalculator) {
      _calculatorMode = true;
      _loading = false;
      _seedCalculatorMetrics(matched.pack, matched.trail);
      if (matched.gpxAssetPath != null) {
        unawaited(_hydrateWaypointsFromGpx(matched.gpxAssetPath!));
      }
    } else {
      _distanceM = 0;
      _elevationGainM = 0;
      _basecampElevM = 0;
      _summitElevM = 0;
      unawaited(_loadLegacy());
    }
  }

  ({MountainPack? pack, MapTrail? trail, String? gpxAssetPath})
      _matchCatalogTarget() {
    final packs = MountainPackData.createDefaultPacks();
    final needleId = widget.route.mountainId?.trim().toLowerCase();
    final lowerName = widget.route.name.trim().toLowerCase();

    MountainPack? pack;
    for (final candidate in packs) {
      if (needleId != null && candidate.id.toLowerCase() == needleId) {
        pack = candidate;
        break;
      }
      if (lowerName.contains(candidate.name.toLowerCase()) ||
          candidate.name.toLowerCase().contains(lowerName) ||
          lowerName.contains(candidate.id.toLowerCase())) {
        pack = candidate;
        break;
      }
    }

    MapTrail? trail;
    if (pack != null && pack.package.trails.isNotEmpty) {
      final tId = widget.route.trailId?.trim().toLowerCase();
      final tName = widget.route.trailName?.trim().toLowerCase();
      for (final t in pack.package.trails) {
        if ((tId != null && t.id.toLowerCase() == tId) ||
            (tName != null && t.name.toLowerCase() == tName) ||
            lowerName.contains(t.name.toLowerCase())) {
          trail = t;
          break;
        }
      }
      trail ??= pack.package.trails.first;
    }

    final gpxAssetPath =
        widget.route.gpxAssetPath ?? trail?.gpxAssetPath ?? pack?.gpxAssetPath;
    return (pack: pack, trail: trail, gpxAssetPath: gpxAssetPath);
  }

  void _seedCalculatorMetrics(MountainPack? pack, MapTrail? trail) {
    _trailLabel = widget.route.trailName ?? trail?.name;
    final pts = widget.route.points.isNotEmpty
        ? widget.route.points
        : (trail?.points ?? const <LatLng>[]);
    final ptsDistance = pts.length >= 2 ? routeDistanceM(pts) : 0.0;
    _distanceM = widget.route.distanceM ??
        trail?.distanceM ??
        (ptsDistance >= 100 ? ptsDistance : 6000.0);

    _summitElevM = widget.route.summitElevationM ??
        trail?.maxElevationM ??
        (pack?.elevationM.toDouble() ?? 2800.0);
    _elevationGainM = widget.route.elevationGainM ??
        trail?.elevationGainM ??
        (_summitElevM * 0.45).clamp(400.0, 2200.0);
    _basecampElevM = widget.route.basecampElevationM ??
        (_summitElevM - _elevationGainM).clamp(300.0, 3500.0);
    _centerCoord = widget.route.summitCoord ??
        (pts.isNotEmpty
            ? routeCenter(pts)
            : pack?.package.offline.bounds.center);
  }

  Future<void> _hydrateWaypointsFromGpx(String assetPath) async {
    try {
      final loaded = await GpxLoader.loadAsset(
        assetPath,
        bundle: widget.assetBundle,
      );
      if (!mounted) return;
      setState(() {
        if (loaded.totalDistanceM >= 100) {
          _distanceM = loaded.totalDistanceM;
        }
        if (loaded.totalElevationGainM >= 50) {
          _elevationGainM = loaded.totalElevationGainM;
        }
        if (loaded.points.isNotEmpty && loaded.points.first.ele != null) {
          _basecampElevM = loaded.points.first.ele!;
        } else if (loaded.minElevationM != null) {
          _basecampElevM = loaded.minElevationM!;
        }
        if (loaded.summitPoint?.ele != null) {
          _summitElevM = loaded.summitPoint!.ele!;
        } else if (loaded.maxElevationM != null) {
          _summitElevM = loaded.maxElevationM!;
        }
        if (loaded.points.isNotEmpty) {
          _centerCoord ??= routeCenter(loaded.positions);
        }
        if (loaded.waypoints.isNotEmpty) {
          _waypoints = loaded.waypoints;
        }
      });
    } catch (_) {
      // Asset GPX opsional jika tidak dibundel di test runner.
    }
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

  Future<void> _loadLegacy() async {
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

  HikingPlanEstimate _buildPlanEstimate() {
    final baseDay = widget.nowLocal ?? DateTime.now();
    final startLocal = DateTime(
      baseDay.year,
      baseDay.month,
      baseDay.day,
      _startTime.hour,
      _startTime.minute,
    );
    return HikingPlanEstimate.calculate(
      routeName: widget.route.name,
      trailName: _trailLabel,
      distanceM: _distanceM,
      elevationGainM: _elevationGainM,
      basecampElevationM: _basecampElevM,
      summitElevationM: _summitElevM,
      startLocal: startLocal,
      pace: _pace,
      load: _load,
      centerCoord: _centerCoord,
      waypoints: _waypoints,
    );
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null && mounted) {
      setState(() => _startTime = picked);
    }
  }

  Future<void> _shareSummary(String text, String routeName) async {
    final ok = await _sharer.share(text, subject: 'Estimasi $routeName');
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

    if (_calculatorMode) {
      final plan = _buildPlanEstimate();
      return PlusScrollPage(
        topBar: PlusTopBar(
          title: 'Estimasi & itinerary',
          subtitle: widget.route.name,
          onBack: () => Navigator.of(context).maybePop(),
        ),
        bottomBar: HiqeoButton(
          label: 'Bagikan ke grup',
          leading: HiqeoIcon(
            HiqeoIcons.share,
            size: 18,
            color: colors.onPrimary,
          ),
          onPressed: () =>
              unawaited(_shareSummary(plan.summaryText, plan.routeName)),
        ),
        children: _calculatorContent(theme, colors, plan),
      );
    }

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
              onPressed: () => unawaited(
                _shareSummary(_estimate!.summaryText, _estimate!.routeName),
              ),
            ),
      children: <Widget>[
        if (_loading)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              PlusCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      height: 12,
                      width: 120,
                      decoration: BoxDecoration(
                        color: colors.hairline.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 28,
                      width: 170,
                      decoration: BoxDecoration(
                        color: colors.hairline.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 12,
                      width: 220,
                      decoration: BoxDecoration(
                        color: colors.hairline.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: HiqeoSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Menghitung estimasi pendakian…',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
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
              onPressed: _loadLegacy,
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
          ..._legacyEstimateContent(theme, colors, _estimate!),
      ],
    );
  }

  List<Widget> _calculatorContent(
    ThemeData theme,
    HiqeoColors colors,
    HikingPlanEstimate plan,
  ) {
    return <Widget>[
      // 1. Ringkasan Jalur + Kontrol Interaktif (0 beban DB)
      PlusCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const PlusOverline('Pengaturan rencana pendakian'),
            const SizedBox(height: HiqeoSpacing.xs),
            Text(
              '${formatKm(plan.distanceM)} naik · '
              '+${groupDigits(plan.elevationGainM.round())} m · '
              'Puncak ${groupDigits(plan.summitElevationM.round())} mdpl',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: HiqeoSpacing.md),
            Text('Kecepatan tim', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, constraints) {
                const double outer = 4;
                const double gap = 4;
                final count = HikingPace.values.length;
                final width =
                    (constraints.maxWidth - outer * 2 - gap * (count - 1)) /
                        count;
                return GlassSurface(
                  tier: GlassTier.card,
                  borderRadius: HiqeoRadius.pill,
                  child: GooeySelector<HikingPace>(
                    axis: Axis.horizontal,
                    padding: const EdgeInsets.all(outer),
                    gap: gap,
                    itemPadding: EdgeInsets.zero,
                    borderRadius: HiqeoRadius.pill,
                    items: <GooeySelectorItem<HikingPace>>[
                      for (final pace in HikingPace.values)
                        GooeySelectorItem<HikingPace>(
                          value: pace,
                          semanticsLabel: pace.label,
                          builder: (context, state) => SizedBox(
                            key: ValueKey<String>('estimate-pace-${pace.name}'),
                            width: width,
                            height: 40,
                            child: Center(
                              child: Text(
                                pace.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
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
                        ),
                    ],
                    selected: _pace,
                    onChanged: (pace) {
                      HapticFeedback.selectionClick();
                      setState(() => _pace = pace);
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: HiqeoSpacing.md),
            Text('Beban carrier', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 2,
              children: <Widget>[
                for (final load in CarrierLoad.values)
                  _SelectChip(
                    key: ValueKey<String>('estimate-load-${load.name}'),
                    label: load.label,
                    selected: _load == load,
                    onTap: () => setState(() => _load = load),
                  ),
              ],
            ),
            const SizedBox(height: HiqeoSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Rencana jam mulai',
                        style: theme.textTheme.labelMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Ketuk tombol jam untuk menyesuaikan waktu',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11.5,
                          color: colors.brightness == Brightness.dark
                              ? Colors.white.withValues(alpha: 0.60)
                              : colors.textSecondary.withValues(alpha: 0.78),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: const ValueKey<String>('estimate-start-time-picker'),
                    borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      unawaited(_pickStartTime());
                    },
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      child: Center(
                        widthFactor: 1.0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.14),
                            borderRadius:
                                BorderRadius.circular(HiqeoRadius.pill),
                            border: Border.all(color: colors.primary),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.schedule_rounded,
                                size: 15,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                formatClock(plan.startLocal),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: HiqeoSpacing.md),

      // 2. Durasi Naik, Turun, Total PP, & Kebutuhan Logistik
      PlusCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const PlusOverline('Estimasi waktu & logistik'),
            const SizedBox(height: HiqeoSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: _EstimateStatBox(
                    key: const ValueKey<String>('estimate-ascent-value'),
                    label: 'Estimasi naik',
                    value: formatDuration(plan.ascentTotal.inSeconds),
                    detail: 'Tiba ${formatClock(plan.summitArrivalLocal)}',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _EstimateStatBox(
                    key: const ValueKey<String>('estimate-descent-value'),
                    label: 'Estimasi turun',
                    value: formatDuration(plan.descent.inSeconds),
                    detail: 'Tanpa istirahat panjang',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: _EstimateStatBox(
                    key: const ValueKey<String>('estimate-total-value'),
                    label: 'Total pulang-pergi',
                    value: formatDuration(plan.totalRoundTrip.inSeconds),
                    detail: 'Tiba BC ${formatClock(plan.returnBasecampLocal)}',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _EstimateStatBox(
                    label: 'Istirahat puncak',
                    value: formatDuration(plan.summitRest.inSeconds),
                    detail: plan.sunsetLocal == null
                        ? 'Termasuk istirahat'
                        : 'Terbenam ${formatClock(plan.sunsetLocal!)}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: HiqeoSpacing.md),
            Divider(color: colors.hairline, height: 1),
            const SizedBox(height: HiqeoSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: _EstimateStatBox(
                    key: const ValueKey<String>('estimate-water-value'),
                    label: 'Kebutuhan air minum',
                    value: '${formatDecimal(plan.waterLiters)} liter',
                    detail: 'Rekomendasi per orang',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _EstimateStatBox(
                    key: const ValueKey<String>('estimate-calories-value'),
                    label: 'Kebutuhan kalori',
                    value: '${groupDigits(plan.caloriesKcal)} kkal',
                    detail: 'Sesuai beban & elevasi',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),

      if (plan.fitsBeforeSunset == false) ...<Widget>[
        const SizedBox(height: HiqeoSpacing.md),
        PlusCard(
          child: PlusNotice(
            icon: HiqeoIcons.warning,
            warning: true,
            text:
                'Dengan jam mulai ${formatClock(plan.startLocal)}, perkiraan turun ke basecamp '
                '(${formatClock(plan.returnBasecampLocal)}) melewati matahari terbenam '
                '(${formatClock(plan.sunsetLocal!)}). Siapkan headlamp atau mulai lebih awal.',
          ),
        ),
      ],

      const SizedBox(height: HiqeoSpacing.lg),
      const PlusOverline('Estimasi waktu per pos'),
      const SizedBox(height: HiqeoSpacing.sm),
      PlusCard(
        key: const ValueKey<String>('estimate-post-timeline'),
        child: Column(
          children: <Widget>[
            for (var i = 0; i < plan.postEtas.length; i++)
              _PostEtaRow(
                item: plan.postEtas[i],
                last: i == plan.postEtas.length - 1,
              ),
          ],
        ),
      ),

      const SizedBox(height: HiqeoSpacing.lg),
      const PlusOverline('Perlengkapan disarankan'),
      const SizedBox(height: HiqeoSpacing.sm),
      PlusCard(
        child: Column(
          children: <Widget>[
            for (final item in plan.gear)
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
        text: 'Perkiraan dihitung langsung di HP berdasarkan jarak dan tanjakan '
            'jalur. Cuaca serta kondisi fisik dapat memengaruhi waktu tempuh.',
      ),
    ];
  }

  List<Widget> _legacyEstimateContent(
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

class _SelectChip extends StatelessWidget {
  const _SelectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(HiqeoRadius.pill),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Center(
            widthFactor: 1.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: ShapeDecoration(
                color: selected
                    ? colors.primary
                    : colors.surface.withValues(alpha: 0.72),
                shape: StadiumBorder(
                  side: BorderSide(
                    color: selected ? colors.primary : colors.hairline,
                  ),
                ),
              ),
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected ? colors.onPrimary : colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EstimateStatBox extends StatelessWidget {
  const _EstimateStatBox({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
              fontSize: 11,
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
          const SizedBox(height: 2),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PostEtaRow extends StatelessWidget {
  const _PostEtaRow({required this.item, required this.last});

  final PostEtaItem item;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final tint = item.isSummit
        ? colors.warningText
        : (item.isReturn ? colors.textSecondary : colors.primary);
    final details = <String>[
      if (item.elevationM != null)
        '${groupDigits(item.elevationM!.round())} mdpl',
      if (!item.isReturn && item.distanceFromStartM > 0)
        formatKm(item.distanceFromStartM),
      if (item.isReturn) 'Selesai pulang-pergi',
    ];

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: 52,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                formatClock(item.etaLocal),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: tint,
                  fontWeight: FontWeight.w700,
                ),
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
                  Text(item.name, style: theme.textTheme.titleSmall),
                  if (details.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 1),
                    Text(
                      details.join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
              const SizedBox(height: 1),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Text(
          formatDuration(duration.inSeconds),
          style: theme.textTheme.titleMedium,
        ),
      ],
    );
  }
}
