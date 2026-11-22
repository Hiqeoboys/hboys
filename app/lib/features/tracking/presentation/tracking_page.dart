import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../design/glass/glass_surface.dart';
import '../../../design/layout.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../infrastructure/location/location_source.dart';
import '../../../infrastructure/location/pedometer_step_counter.dart';
import '../../../infrastructure/power/power_profile_controller.dart';
import '../../../infrastructure/power/power_profile_manager.dart';
import '../../onboarding/permission_onboarding_page.dart';
import '../../onboarding/permission_service.dart';
import '../../profile/application/body_metrics_store.dart';
import '../../trails/data/gpx_loader.dart';
import '../application/tracking_controller.dart';
import '../application/tracking_status.dart';
import '../domain/tracking_diagnostics.dart';
import '../domain/tracking_session.dart';
import 'tracking_view_data.dart';
import 'widgets/debug_simulation_panel.dart';
import 'widgets/elevation_sparkline.dart';
import 'widgets/live_route_polyline_view.dart';

/// Menampilkan modal Liquid Glass pilihan aktivitas ("Hiking" atau "Jogging")
/// ketika pengguna menekan tombol "Mulai tracking".
Future<String?> showTrackingModeChoiceModal(BuildContext context) {
  final colors = HiqeoColors.of(context);
  final theme = Theme.of(context);
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    isScrollControlled: true,
    builder: (sheetContext) {
      final bottomPad = math.max(
        MediaQuery.paddingOf(sheetContext).bottom,
        MediaQuery.viewPaddingOf(sheetContext).bottom,
      );
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad + 16),
        child: GlassSurface(
          tier: GlassTier.panel,
          borderRadius: 28,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textSecondary.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Pilih aktivitas',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: HiqeoTypography.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tentukan mode tracking yang ingin direkam.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              _ModeOptionTile(
                key: const ValueKey<String>('tracking-mode-hiking'),
                icon: Icons.terrain_rounded,
                title: 'Hiking',
                subtitle: 'Pilih gunung & jalur di halaman Peta terlebih dulu',
                onTap: () => Navigator.of(sheetContext)
                    .pop(TrackingSession.activityHiking),
              ),
              const SizedBox(height: 10),
              _ModeOptionTile(
                key: const ValueKey<String>('tracking-mode-jogging'),
                icon: Icons.directions_run_rounded,
                title: 'Jogging',
                subtitle: 'Langsung mulai rekam statistik & rute GPS di sini',
                onTap: () => Navigator.of(sheetContext)
                    .pop(TrackingSession.activityJogging),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Layar rekam bergaya Bento (Opsi B). Data diambil dari [TrackingController]
/// tunggal agar rekaman latar Android dan iOS tetap berjalan saat berpindah
/// layar.
class TrackingPage extends StatefulWidget {
  const TrackingPage({
    super.key,
    this.powerController,
    this.bodyMetricsStore,
    this.stepCounter,
  });

  /// Disuntikkan untuk uji; produksi membaca baterai perangkat.
  final PowerProfileController? powerController;
  final BodyMetricsStore? bodyMetricsStore;
  final PedometerStepCounter? stepCounter;

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage>
    with WidgetsBindingObserver {
  TrackingController get _controller => TrackingController.instance;

  late final PowerProfileController _power;
  late final bool _ownsPower;
  late final BodyMetricsStore _bodyMetrics;
  late final PedometerStepCounter _steps;
  late final bool _ownsSteps;

  List<double> _elevation = const <double>[];
  List<Offset> _routePoints = const <Offset>[];
  int _loadedPointCount = -1;
  DateTime? _lastPointsLoad;
  Timer? _uiTimer;
  int _extraMovingSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsPower = widget.powerController == null;
    _power = widget.powerController ?? PowerProfileController();
    if (_ownsPower) unawaited(_power.refresh());
    _bodyMetrics = widget.bodyMetricsStore ?? BodyMetricsStore.instance;
    unawaited(_bodyMetrics.load());
    _ownsSteps = widget.stepCounter == null;
    _steps = widget.stepCounter ?? PedometerStepCounter();
    _controller.addListener(_onTrackingChanged);
    _onTrackingChanged(force: true);
    unawaited(_controller.refreshPermissionsAndResume());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_power.refresh());
      unawaited(_controller.refreshPermissionsAndResume());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onTrackingChanged);
    _uiTimer?.cancel();
    _uiTimer = null;
    if (_ownsSteps) _steps.dispose();
    if (_ownsPower) _power.dispose();
    super.dispose();
  }

  void _onTrackingChanged({bool force = false}) {
    _extraMovingSeconds = 0;
    _syncUiTimer();
    final status = _controller.status;
    final permission = _controller.permission;
    final phase = _controller.phase;
    final sessionId =
        (_controller.isRecording || phase == TrackingPhase.finished)
            ? status?.sessionId
            : null;
    _steps.syncSession(
      sessionId: sessionId,
      activityPermissionGranted: permission?.activityRecognitionGranted ?? true,
      isPaused: _controller.isPaused,
      isFinished: phase == TrackingPhase.finished,
      isGpsMoving: status?.isMoving ?? false,
    );
    final count = status?.pointCount ?? 0;
    if (sessionId == null || count == 0) {
      if (_loadedPointCount != 0 ||
          _elevation.isNotEmpty ||
          _routePoints.isNotEmpty) {
        _loadedPointCount = count;
        if (mounted) {
          setState(() {
            _elevation = const <double>[];
            _routePoints = const <Offset>[];
          });
        }
      }
      return;
    }
    if (count == _loadedPointCount) return;
    final refreshInterval = _controller.isJoggingSession
        ? const Duration(seconds: 2)
        : const Duration(seconds: 5);
    if (!force) {
      final last = _lastPointsLoad;
      if (last != null && DateTime.now().difference(last) < refreshInterval) {
        return;
      }
    }
    unawaited(_loadPoints(count));
  }

  void _syncUiTimer() {
    final recording = _controller.isRecording && !_controller.isPaused;
    if (recording && _uiTimer == null) {
      _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final status = _controller.status;
        final stale = isFixStale(
          status?.lastValidFixAtUtc,
          DateTime.now().toUtc(),
        );
        if (status?.isMoving == true && !_controller.isPaused && !stale) {
          _extraMovingSeconds++;
        }
        setState(() {});
      });
    } else if (!recording && _uiTimer != null) {
      _uiTimer?.cancel();
      _uiTimer = null;
    }
  }

  Future<void> _loadPoints(int count) async {
    _lastPointsLoad = DateTime.now();
    _loadedPointCount = count;
    final points = await _controller.currentTrackPoints();
    if (!mounted) return;
    setState(() {
      _elevation = elevationSeries(points);
      _routePoints = normalizeTrackRoutePoints(points);
    });
  }

  Future<void> _openOnboarding() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PermissionOnboardingPage(),
      ),
    );
    if (!mounted) return;
    await _controller.refreshPermissionsAndResume();
    await _power.refresh();
  }

  Future<void> _requestStepPermission() async {
    final granted =
        await const PermissionService().requestActivityRecognition();
    if (!mounted) return;
    await _controller.refreshPermissionsAndResume();
    _steps.syncSession(
      sessionId: _controller.status?.sessionId,
      activityPermissionGranted: granted,
      isPaused: _controller.isPaused,
    );
  }

  Future<void> _startActivity(String activityType) async {
    final started = await _controller.start(activityType: activityType);
    if (!mounted) return;
    if (!started && !(_controller.permission?.readyForBackground ?? false)) {
      await _openOnboarding();
    }
  }

  Future<void> _start() async {
    final choice = await showTrackingModeChoiceModal(context);
    if (!mounted || choice == null) return;
    if (choice == TrackingSession.activityHiking) {
      GoRouter.maybeOf(context)?.go('/peta');
      return;
    }
    await _startActivity(TrackingSession.activityJogging);
  }

  Future<void> _finish() async {
    final isJogging = _controller.isJoggingSession;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isJogging ? 'Selesaikan jogging?' : 'Belum sampai puncak'),
        content: Text(
          isJogging
              ? 'Yakin ingin menghentikan sesi jogging sekarang? Statistik dan rute GPS akan disimpan ke Riwayat Jogging.'
              : 'Pendakian belum mencapai titik puncak. Yakin ingin menghentikan tracking sekarang? Sesi akan disimpan dengan status belum sampai puncak.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(isJogging ? 'Selesai' : 'Hentikan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _controller.stop(reachedSummit: false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        _controller,
        _power,
        _bodyMetrics,
        _steps,
      ]),
      builder: (context, _) {
        final status = _controller.status;
        final permission = _controller.permission;
        final permissionReady = permission?.readyForBackground ?? false;

        TrackingStatus? liveStatus = status;
        final nowUtc = DateTime.now().toUtc();
        if (status != null &&
            (_controller.phase == TrackingPhase.recording ||
                _controller.phase == TrackingPhase.paused)) {
          final elapsed = nowUtc.difference(status.startedAtUtc).inSeconds;
          final moving = status.movingSeconds + _extraMovingSeconds;
          liveStatus = status.copyWith(
            elapsedSeconds: elapsed > 0 ? elapsed : status.elapsedSeconds,
            movingSeconds: moving,
            stepCount: _steps.sensorSteps ?? status.stepCount,
          );
        }

        final hasValidFix = liveStatus != null &&
            (liveStatus.hasValidFix || liveStatus.pointCount > 0);
        final caloriesKcal = hasValidFix
            ? liveStatus.kcalPerKg * _bodyMetrics.effectiveWeightKg
            : null;

        final stepState = _steps.state;
        final sensorSteps = liveStatus?.stepCount ?? _steps.sensorSteps;
        final stepsEstimated =
            sensorSteps == null && hasValidFix && liveStatus.distanceM > 0;
        final effectiveSteps = sensorSteps ??
            (stepsEstimated
                ? estimateStepsFromDistance(
                    distanceM: liveStatus.distanceM,
                    heightCm: _bodyMetrics.effectiveHeightCm,
                  )
                : null);

        return TrackingView(
          phase: _controller.phase,
          status: liveStatus,
          permission: permission,
          permissionReady: permissionReady || _controller.simulationEnabled,
          permissionSummary:
              permission == null ? null : permissionSummaryText(permission),
          recoveryPending: _controller.recoveryPending,
          profile: status?.profile ?? _power.profile,
          isPowerSaveMode: _power.isOsPowerSaveMode,
          activityType: _controller.activeActivityType,
          elevation: _elevation,
          routePoints: _routePoints,
          caloriesKcal: caloriesKcal,
          weightKg: _bodyMetrics.effectiveWeightKg,
          isWeightEstimated: !_bodyMetrics.hasCustomWeight,
          stepCount: effectiveSteps,
          stepsEstimated: stepsEstimated,
          stepPermissionNeeded: stepState == StepSourceState.permissionNeeded,
          nowUtc: nowUtc,
          error: _controller.error,
          notice: _controller.notice,
          simulationEnabled: _controller.simulationEnabled,
          simulationRouteAsset: _controller.simulationRouteAsset,
          simulatedLocationSource: _controller.simulatedLocationSource,
          onRetryInitialize: () =>
              unawaited(_controller.refreshPermissionsAndResume()),
          onToggleSimulation: (enabled) =>
              unawaited(_controller.setSimulationEnabled(enabled)),
          onSelectSimulationRoute: (asset) =>
              unawaited(_controller.setSimulationRouteAsset(asset)),
          onStart: () => unawaited(_start()),
          onResumeRecovery: () =>
              unawaited(_startActivity(_controller.activeActivityType)),
          onPause: () => unawaited(_controller.pause()),
          onResume: () => unawaited(_controller.resume()),
          onFinish: () => unawaited(_finish()),
          onOpenPermissions: () => unawaited(_openOnboarding()),
          onRequestStepPermission: () => unawaited(_requestStepPermission()),
          onEditBodyMetrics: () =>
              unawaited(showBodyMetricsDialog(context, store: _bodyMetrics)),
        );
      },
    );
  }
}

/// Tampilan murni Opsi B (Bento), dipisahkan agar dapat diuji tanpa layanan GPS.
class TrackingView extends StatefulWidget {
  const TrackingView({
    super.key,
    required this.phase,
    required this.profile,
    this.isPowerSaveMode = false,
    this.activityType = TrackingSession.activityHiking,
    this.status,
    this.permission,
    this.permissionReady = false,
    this.permissionSummary,
    this.recoveryPending = false,
    this.elevation = const <double>[],
    this.routePoints = const <Offset>[],
    this.caloriesKcal,
    this.weightKg = 65,
    this.isWeightEstimated = true,
    this.stepCount,
    this.stepsEstimated = false,
    this.stepPermissionNeeded = false,
    this.nowUtc,
    this.error,
    this.notice,
    this.simulationEnabled = false,
    this.simulationRouteAsset = GpxLoader.defaultGpxAssetPath,
    this.simulatedLocationSource,
    this.onToggleSimulation,
    this.onSelectSimulationRoute,
    this.onStart,
    this.onResumeRecovery,
    this.onPause,
    this.onResume,
    this.onFinish,
    this.onOpenPermissions,
    this.onRetryInitialize,
    this.onRequestStepPermission,
    this.onEditBodyMetrics,
  });

  final TrackingPhase phase;
  final TrackingStatus? status;
  final PermissionReport? permission;
  final bool permissionReady;
  final String? permissionSummary;
  final bool recoveryPending;
  final PowerProfile profile;

  /// Status nyata `PowerManager.isPowerSaveMode` OS Android.
  final bool isPowerSaveMode;

  /// `'hiking'` atau `'jogging'`.
  final String activityType;
  final List<double> elevation;
  final List<Offset> routePoints;
  final double? caloriesKcal;
  final double weightKg;
  final bool isWeightEstimated;
  final int? stepCount;
  final bool stepsEstimated;
  final bool stepPermissionNeeded;
  final DateTime? nowUtc;
  final String? error;
  final String? notice;
  final bool simulationEnabled;
  final String simulationRouteAsset;
  final SimulatedLocationSource? simulatedLocationSource;
  final ValueChanged<bool>? onToggleSimulation;
  final ValueChanged<String>? onSelectSimulationRoute;
  final VoidCallback? onStart;
  final VoidCallback? onResumeRecovery;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onFinish;
  final VoidCallback? onOpenPermissions;
  final VoidCallback? onRetryInitialize;
  final VoidCallback? onRequestStepPermission;
  final VoidCallback? onEditBodyMetrics;

  @override
  State<TrackingView> createState() => _TrackingViewState();
}

class _TrackingViewState extends State<TrackingView> {
  bool _debugExpanded = false;
  bool _simExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final status = widget.status;
    final phase = widget.phase;
    final profile = widget.profile;

    final recording =
        phase == TrackingPhase.recording || phase == TrackingPhase.preparing;
    final paused = phase == TrackingPhase.paused;
    final finishing = phase == TrackingPhase.stopping;
    final loading = phase == TrackingPhase.uninitialized ||
        phase == TrackingPhase.initializing;
    final finished = phase == TrackingPhase.finished;
    final showPermission = !widget.permissionReady &&
        widget.permissionSummary != null &&
        !recording &&
        !paused;

    final hasValidFix =
        status != null && (status.hasValidFix || status.pointCount > 0);
    final searchingGps = (recording || paused) && !hasValidFix;

    final now = widget.nowUtc ?? DateTime.now().toUtc();
    final fixStale = status?.lastValidFixAtUtc != null &&
        isFixStale(status!.lastValidFixAtUtc, now);

    final distance = hasValidFix ? formatDistanceValue(status.distanceM) : '—';
    final pace = (hasValidFix && status.isMoving && !fixStale)
        ? formatPaceValue(status.paceSecPerKm)
        : '—';
    final gain =
        hasValidFix ? formatElevationValue(status.elevationGainM) : '—';
    final vertical = (hasValidFix && !fixStale)
        ? formatVerticalSpeedValue(status.verticalSpeedMph)
        : '—';

    final effectiveStepCount = widget.stepCount ?? status?.stepCount;
    final stepsText = formatStepCount(
      effectiveStepCount,
      estimated: widget.stepsEstimated,
    );

    final effectiveCalories = widget.caloriesKcal ??
        (status != null && status.kcalPerKg > 0
            ? status.kcalPerKg * widget.weightKg
            : null);
    final caloriesText = formatCaloriesValue(effectiveCalories);

    final timer = formatTimer(status?.movingSeconds ?? 0);

    // Hanya tampil bila OS Android benar-benar mengaktifkan Power Save Mode
    // (`PowerManager.isPowerSaveMode == true`). Tidak pernah dipicu oleh
    // `isIgnoringBatteryOptimizations`, level baterai, atau akurasi GPS.
    final showPowerAccuracyWarning = widget.isPowerSaveMode;
    final isJogging = (status?.activityType ?? widget.activityType) ==
        TrackingSession.activityJogging;

    return SafeArea(
      bottom: false,
      child: Stack(
        children: <Widget>[
          LayoutBuilder(
            builder: (context, constraints) {
              final compactHeight = constraints.maxHeight < 520;
              final content = Padding(
                padding: EdgeInsets.fromLTRB(
                  HiqeoSpacing.md,
                  10,
                  HiqeoSpacing.md,
                  AppLayout.bottomInset(context),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (searchingGps ||
                        showPowerAccuracyWarning ||
                        ((recording || paused) && isJogging)) ...<Widget>[
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: <Widget>[
                          if ((recording || paused) && isJogging)
                            _StatusBannerPill(
                              text: 'Mode Jogging',
                              icon: Icons.directions_run_rounded,
                              color: colors.textPrimary,
                            ),
                          if (searchingGps)
                            _StatusBannerPill(
                              text: 'Mencari sinyal GPS',
                              icon: Icons.gps_not_fixed,
                              color: colors.warningText,
                            ),
                          if (showPowerAccuracyWarning)
                            _StatusBannerPill(
                              text:
                                  'Mode hemat baterai aktif, akurasi GPS bisa menurun',
                              icon: Icons.battery_saver,
                              color: colors.textSecondary,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (widget.error != null &&
                        !recording &&
                        !paused &&
                        !loading) ...<Widget>[
                      _NoticeCard(
                        title: 'Rekaman tidak tersedia',
                        body: widget.error!,
                        isError: true,
                        actionLabel: !widget.permissionReady
                            ? (widget.onOpenPermissions != null
                                ? 'Buka panduan izin'
                                : null)
                            : (widget.onRetryInitialize != null
                                ? 'Muat ulang'
                                : null),
                        onAction: !widget.permissionReady
                            ? widget.onOpenPermissions
                            : widget.onRetryInitialize,
                      ),
                      const SizedBox(height: 8),
                    ] else if (widget.notice != null) ...<Widget>[
                      _NoticeCard(title: 'Catatan', body: widget.notice!),
                      const SizedBox(height: 8),
                    ] else if (showPermission) ...<Widget>[
                      _NoticeCard(
                        title: 'Izin belum lengkap',
                        body: widget.permissionSummary!,
                        actionLabel: widget.onOpenPermissions == null
                            ? null
                            : 'Buka panduan izin',
                        onAction: widget.onOpenPermissions,
                      ),
                      const SizedBox(height: 8),
                    ] else if (widget.recoveryPending &&
                        !recording &&
                        !paused) ...<Widget>[
                      _NoticeCard(
                        title: 'Sesi aktif ditemukan',
                        body:
                            'Sesi terakhir belum selesai. Lanjutkan tanpa membuat sesi baru.',
                        actionLabel: widget.permissionReady
                            ? 'Lanjutkan sesi'
                            : 'Buka izin',
                        onAction: widget.permissionReady
                            ? (widget.onResumeRecovery ?? widget.onStart)
                            : widget.onOpenPermissions,
                      ),
                      const SizedBox(height: 8),
                    ],

                    // 2. Label "Waktu bergerak" + timer kompak
                    Semantics(
                      label: 'Waktu bergerak $timer',
                      container: true,
                      child: ExcludeSemantics(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Text(
                                  'Waktu bergerak',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                ),
                                if (paused || finishing) ...<Widget>[
                                  const SizedBox(width: 8),
                                  Text(
                                    finishing
                                        ? '· Menyelesaikan sesi…'
                                        : '· Dijeda',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: HiqeoTypography.bold,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              timer,
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: HiqeoTypography.extraBold,
                                height: 1.05,
                                letterSpacing: -1.0,
                                color: colors.textPrimary,
                                fontFeatures: const <ui.FontFeature>[
                                  ui.FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 3. Kartu hero untuk "Jarak" + grafik profil ketinggian atau rute GPS Jogging
                    if (compactHeight)
                      SizedBox(
                        height: 180,
                        child: _HeroDistanceElevationCard(
                          distance: distance,
                          samples: widget.elevation,
                          isJogging: isJogging,
                          routePoints: widget.routePoints,
                        ),
                      )
                    else
                      Expanded(
                        child: _HeroDistanceElevationCard(
                          distance: distance,
                          samples: widget.elevation,
                          isJogging: isJogging,
                          routePoints: widget.routePoints,
                        ),
                      ),
                    const SizedBox(height: 8),

                    // 4. Satu baris 3 kartu kecil: Pace, Tanjakan, Kec. vertikal
                    SizedBox(
                      height: 68,
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: _MetricCard(
                              label: 'Pace',
                              value: pace,
                              unit: pace == '—' ? null : '/km',
                              compact: true,
                              semanticsValue: pace == '—'
                                  ? null
                                  : '$pace menit per kilometer',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _MetricCard(
                              label: 'Tanjakan',
                              value: gain,
                              unit: gain == '—' ? null : 'm',
                              compact: true,
                              semanticsValue:
                                  gain == '—' ? null : '$gain meter',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _MetricCard(
                              label: 'Kec. vertikal',
                              value: vertical,
                              unit: vertical == '—' ? null : 'm/jam',
                              compact: true,
                              semanticsValue: vertical == '—'
                                  ? null
                                  : '$vertical meter per jam',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 5. Satu baris 2 kartu: Langkah dan Kalori
                    SizedBox(
                      height: 68,
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: _MetricCard(
                              label: 'Langkah',
                              value: stepsText,
                              badge: widget.stepPermissionNeeded
                                  ? 'Izinkan'
                                  : (widget.stepsEstimated ? 'jarak' : null),
                              onBadgeTap: widget.stepPermissionNeeded
                                  ? widget.onRequestStepPermission
                                  : null,
                              semanticsValue: effectiveStepCount == null
                                  ? 'Sensor tidak tersedia'
                                  : '$stepsText langkah',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _MetricCard(
                              label: 'Kalori',
                              value: caloriesText,
                              unit: caloriesText == '—' ? null : 'kkal',
                              badge:
                                  widget.isWeightEstimated ? 'perkiraan' : null,
                              onBadgeTap: widget.onEditBodyMetrics,
                              semanticsValue: caloriesText == '—'
                                  ? null
                                  : '$caloriesText kilokalori',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),

                    // Catatan kaki ringkas + pintasan isi berat badan
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            _footerText(
                              paused: paused,
                              finishing: finishing,
                              stepsEstimated: widget.stepsEstimated,
                              hasStepCount: effectiveStepCount != null,
                              weightKg: widget.weightKg,
                              isWeightEstimated: widget.isWeightEstimated,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              height: 1.2,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                        if (widget.onEditBodyMetrics != null &&
                            widget.isWeightEstimated)
                          Semantics(
                            button: true,
                            label: 'Isi berat badan',
                            child: GestureDetector(
                              key: const ValueKey('track-edit-weight-shortcut'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                unawaited(HapticFeedback.selectionClick());
                                widget.onEditBodyMetrics!();
                              },
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minWidth: 44,
                                  minHeight: 44,
                                ),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  widthFactor: 1.0,
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Text(
                                      'Isi berat badan',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        fontSize: 11,
                                        fontWeight: HiqeoTypography.bold,
                                        color: colors.textPrimary,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),

                    // 6. Baris tombol Jeda dan Selesai menempel di atas navbar
                    _controls(
                      phase: phase,
                      recording: recording,
                      paused: paused,
                      finishing: finishing,
                      finished: finished,
                      permissionReady: widget.permissionReady,
                    ),
                  ],
                ),
              );
              if (compactHeight) {
                return SingleChildScrollView(child: content);
              }
              return content;
            },
          ),

          // Tombol lipat/buka panel debug (hanya kDebugMode, melayang)
          if (kDebugMode)
            Positioned(
              top: 8,
              left: HiqeoSpacing.md,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  GestureDetector(
                    key: const ValueKey('track-debug-toggle'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() {
                      _debugExpanded = !_debugExpanded;
                      if (_debugExpanded) _simExpanded = false;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.secondary.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                        border: Border.all(color: colors.hairline),
                      ),
                      child: Text(
                        _debugExpanded ? 'Tutup' : 'Diag GPS',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.textSecondary,
                          fontSize: 9,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    key: const ValueKey('track-sim-toggle'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() {
                      _simExpanded = !_simExpanded;
                      if (_simExpanded) _debugExpanded = false;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: widget.simulationEnabled
                            ? colors.primary.withValues(alpha: 0.18)
                            : colors.secondary.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                        border: Border.all(
                          color: widget.simulationEnabled
                              ? colors.primary
                              : colors.hairline,
                        ),
                      ),
                      child: Text(
                        _simExpanded
                            ? 'Tutup simulasi'
                            : (widget.simulationEnabled
                                ? 'Simulasi ${widget.simulatedLocationSource?.speedMultiplier ?? 1}x · ${(widget.simulatedLocationSource?.progressPercent ?? 0).round()}%'
                                : 'Simulasi GPX'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: widget.simulationEnabled
                              ? colors.textPrimary
                              : colors.textSecondary,
                          fontSize: 9,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Overlay diagnosa GPS (hanya kDebugMode, bisa dilipat)
          if (kDebugMode && _debugExpanded)
            Positioned(
              top: 34,
              left: HiqeoSpacing.md,
              right: HiqeoSpacing.md,
              child: _DebugDiagnosticsOverlay(
                diagnostics: status?.diagnostics,
                permission: widget.permission,
                profile: profile,
                isPowerSaveMode: widget.isPowerSaveMode,
                nowUtc: now,
                onClose: () => setState(() => _debugExpanded = false),
              ),
            ),

          // Panel debug simulasi lokasi (hanya kDebugMode, bisa dilipat)
          if (kDebugMode && _simExpanded)
            Positioned(
              top: 34,
              left: HiqeoSpacing.md,
              right: HiqeoSpacing.md,
              child: DebugSimulationPanel(
                onClose: () => setState(() => _simExpanded = false),
              ),
            ),
        ],
      ),
    );
  }

  String _footerText({
    required bool paused,
    required bool finishing,
    required bool stepsEstimated,
    required bool hasStepCount,
    required double weightKg,
    required bool isWeightEstimated,
  }) {
    if (paused || finishing) {
      return 'Waktu bergerak berhenti selama rekaman dijeda';
    }
    if (stepsEstimated) {
      return 'Langkah diperkirakan dari jarak';
    }
    if (!hasStepCount) {
      return 'Sensor langkah tidak tersedia';
    }
    return isWeightEstimated
        ? 'Perkiraan kalori berdasarkan berat ${weightKg.round()} kg'
        : 'Kalori dihitung berdasarkan berat ${weightKg.round()} kg';
  }

  Widget _controls({
    required TrackingPhase phase,
    required bool recording,
    required bool paused,
    required bool finishing,
    required bool finished,
    required bool permissionReady,
  }) {
    if (recording || paused) {
      final leftAction = paused ? widget.onResume : widget.onPause;
      final rightAction = widget.onFinish;
      return HiqeoButtonPair(
        leftLabel: paused ? 'Lanjut' : 'Jeda',
        rightLabel: finishing ? 'Menyelesaikan…' : 'Selesai',
        onLeftTap: (finishing || leftAction == null)
            ? null
            : () {
                unawaited(HapticFeedback.selectionClick());
                leftAction();
              },
        onRightTap: (finishing || rightAction == null)
            ? null
            : () {
                unawaited(HapticFeedback.lightImpact());
                rightAction();
              },
        leftSemanticLabel: paused ? 'Lanjutkan rekaman' : 'Jeda rekaman',
        rightSemanticLabel: 'Selesai dan akhiri sesi',
      );
    }
    if (finishing) {
      return const HiqeoButton(label: 'Menyelesaikan…');
    }
    if (phase == TrackingPhase.error) {
      return const SizedBox.shrink();
    }
    if (phase == TrackingPhase.initializing ||
        phase == TrackingPhase.uninitialized) {
      return const HiqeoButton(label: 'Menyiapkan…');
    }
    if (!permissionReady) {
      return HiqeoButton(
        label: 'Lengkapi izin',
        onPressed: widget.onOpenPermissions,
      );
    }
    final onStart = widget.onStart;
    return HiqeoButton(
      key: const ValueKey<String>('tracking-start-button'),
      label: finished ? 'Mulai tracking baru' : 'Mulai tracking',
      onPressed: onStart == null
          ? null
          : () {
              unawaited(HapticFeedback.lightImpact());
              onStart();
            },
    );
  }
}

class _ModeOptionTile extends StatelessWidget {
  const _ModeOptionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: isDark
          ? Colors.white.withValues(alpha: 0.08)
          : colors.primary.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.hairline),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.primary.withValues(alpha: 0.14),
                ),
                child: Icon(icon, color: colors.textPrimary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: HiqeoTypography.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBannerPill extends StatelessWidget {
  const _StatusBannerPill({
    required this.text,
    required this.icon,
    required this.color,
  });

  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.secondary,
        borderRadius: BorderRadius.circular(HiqeoRadius.pill),
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: color,
                fontWeight: HiqeoTypography.medium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kartu Hero Bento (Opsi B): Jarak (34 px + km) menyatu dengan profil
/// ketinggian halus yang menempati ~62% bagian bawah kartu.
class _HeroDistanceElevationCard extends StatelessWidget {
  const _HeroDistanceElevationCard({
    required this.distance,
    required this.samples,
    this.isJogging = false,
    this.routePoints = const <Offset>[],
  });

  final String distance;
  final List<double> samples;
  final bool isJogging;
  final List<Offset> routePoints;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);

    return Semantics(
      container: true,
      label: distance == '—'
          ? 'Jarak: belum tersedia'
          : 'Jarak: $distance kilometer',
      child: GlassSurface(
        tier: GlassTier.card,
        borderRadius: HiqeoRadius.card,
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(HiqeoRadius.card),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final chartHeight = math.max(
                36.0,
                constraints.maxHeight * (isJogging ? 0.66 : 0.62),
              );
              return Stack(
                children: <Widget>[
                  // Mode Jogging: tampilkan rute polyline GPS realtime; Mode Hiking: profil elevasi
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: chartHeight,
                    child: isJogging
                        ? LiveRoutePolylineView(
                            key: const ValueKey<String>(
                              'tracking-jogging-live-route',
                            ),
                            routePoints: routePoints,
                            isLive: true,
                          )
                        : MonotoneElevationSparkline(samples: samples),
                  ),

                  if (isJogging)
                    Positioned(
                      top: 12,
                      right: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colors.secondary,
                          borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                          border: Border.all(color: colors.hairline),
                        ),
                        child: Text(
                          'Rute GPS',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.textSecondary,
                            fontSize: 10,
                            fontWeight: HiqeoTypography.medium,
                          ),
                        ),
                      ),
                    ),

                  // Label "Jarak" dan angka 34 px di bagian atas kartu
                  ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            'Jarak',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text.rich(
                            TextSpan(
                              text: distance,
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: HiqeoTypography.extraBold,
                                height: 1.05,
                                letterSpacing: -0.8,
                                color: colors.textPrimary,
                                fontFeatures: const <ui.FontFeature>[
                                  ui.FontFeature.tabularFigures(),
                                ],
                              ),
                              children: <InlineSpan>[
                                if (distance != '—')
                                  TextSpan(
                                    text: ' km',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colors.textSecondary,
                                      fontWeight: HiqeoTypography.medium,
                                    ),
                                  ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    this.unit,
    this.badge,
    this.onBadgeTap,
    this.compact = false,
    this.semanticsValue,
  });

  final String label;
  final String value;
  final String? unit;
  final String? badge;
  final VoidCallback? onBadgeTap;
  final bool compact;
  final String? semanticsValue;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final valueStyle =
        (compact ? theme.textTheme.titleLarge : theme.textTheme.headlineSmall)
            ?.copyWith(
      color: colors.textPrimary,
      fontWeight: HiqeoTypography.extraBold,
      height: 1.05,
      fontFeatures: const <ui.FontFeature>[ui.FontFeature.tabularFigures()],
    );
    final unitStyle = theme.textTheme.bodySmall?.copyWith(
      color: colors.textSecondary,
      fontWeight: HiqeoTypography.medium,
      fontSize: compact ? 11 : 12,
    );
    final card = GlassSurface(
      tier: GlassTier.card,
      borderRadius: HiqeoRadius.card,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: 9,
      ),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      fontSize: compact ? 11 : 12,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: colors.secondary,
                      borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                    ),
                    child: Text(
                      badge!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  text: value,
                  style: valueStyle,
                  children: <InlineSpan>[
                    if (unit != null)
                      TextSpan(text: ' $unit', style: unitStyle),
                  ],
                ),
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      container: true,
      button: onBadgeTap != null,
      label: semanticsValue == null
          ? '$label: belum tersedia'
          : '$label: $semanticsValue',
      child: onBadgeTap == null
          ? card
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                unawaited(HapticFeedback.selectionClick());
                onBadgeTap!();
              },
              child: card,
            ),
    );
  }
}

class _DebugDiagnosticsOverlay extends StatelessWidget {
  const _DebugDiagnosticsOverlay({
    required this.diagnostics,
    required this.permission,
    required this.profile,
    required this.isPowerSaveMode,
    required this.nowUtc,
    required this.onClose,
  });

  final TrackingDiagnostics? diagnostics;
  final PermissionReport? permission;
  final PowerProfile profile;
  final bool isPowerSaveMode;
  final DateTime nowUtc;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final d = diagnostics ?? TrackingDiagnostics();
    final p = permission;
    final ageSec = d.lastFixAgeSeconds(nowUtc);

    String fmt(double? v, [int digits = 1]) =>
        v == null ? '—' : v.toStringAsFixed(digits);

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 290),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(HiqeoRadius.card),
          border: Border.all(color: colors.hairline),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: DefaultTextStyle(
            style: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
              fontSize: 11,
              color: colors.textPrimary,
              height: 1.35,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Diagnosa pipeline lokasi (kDebugMode)',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    GestureDetector(
                      onTap: onClose,
                      child: const Icon(Icons.close, size: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Fix diterima: ${d.received} | Lolos: ${d.accepted} | Ditolak: ${d.rejected}',
                ),
                Text(
                  'Alasan tolak -> akurasi: ${d.rejectedAccuracy}, '
                  'loncatan: ${d.rejectedJump}, '
                  'jitter: ${d.rejectedJitter}, '
                  'timestamp duplikat: ${d.rejectedDuplicateTime}',
                ),
                const Divider(height: 10),
                Text(
                  'Provider: ${d.provider} | Umur fix: ${ageSec?.toStringAsFixed(1) ?? "—"} dtk | '
                  'Mock: ${d.lastIsMocked ? "ya" : "tidak"}',
                ),
                Text(
                  'Lat/Lon: ${fmt(d.lastLat, 6)}, ${fmt(d.lastLon, 6)}',
                ),
                Text(
                  'Akurasi: ${fmt(d.lastAccuracyM)} m (rata2 ${fmt(d.avgAccuracyM)} m) | '
                  'Speed: ${fmt(d.lastSpeedMps, 2)} m/s (±${fmt(d.lastSpeedAccuracyMps, 2)})',
                ),
                Text(
                  'Altitud: ${fmt(d.lastAltitudeM)} m (±${fmt(d.lastAltitudeAccuracyM)} m)',
                ),
                const Divider(height: 10),
                Text(
                  'Izin -> fine: ${_yn(p?.preciseLocation)}, '
                  'coarse: ${_yn(p?.locationWhileInUse)}, '
                  'background: ${_yn(p?.locationAlways)}, '
                  'activity: ${_yn(p?.activityRecognitionGranted)}, '
                  'notifikasi: ${_yn(p?.notificationGranted)}, '
                  'ignore battery opt: ${_yn(p?.ignoringBatteryOptimizations)}, '
                  'mode hemat baterai OS: ${isPowerSaveMode ? "aktif" : "mati"} (${profileLabel(profile)})',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _yn(bool? v) => v == null ? '?' : (v ? 'ya' : 'tidak');
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.isError = false,
  });

  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return GlassSurface(
      tier: GlassTier.card,
      borderRadius: HiqeoRadius.card,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: HiqeoTypography.bold,
                    color: isError ? colors.warningText : colors.textPrimary,
                  ),
                ),
              ),
              if (actionLabel != null && onAction != null)
                GestureDetector(
                  onTap: onAction,
                  child: Text(
                    actionLabel!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: HiqeoTypography.bold,
                      color: colors.textPrimary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

String permissionSummaryText(PermissionReport permission) {
  final missing = <String>[
    if (!permission.locationServiceEnabled) 'layanan lokasi',
    if (!permission.locationWhileInUse) 'izin lokasi',
    if (!permission.locationAlways) 'izin "Selalu"',
    if (!permission.preciseLocation) 'lokasi presisi',
  ];
  final parts = missing.isEmpty
      ? <String>[]
      : <String>['Belum aktif: ${missing.join(', ')}.'];
  if (defaultTargetPlatform == TargetPlatform.android &&
      !permission.notificationGranted) {
    parts.add('Izin notifikasi diperlukan untuk layanan latar Android.');
  }
  return parts.isEmpty
      ? 'Periksa status izin di halaman panduan.'
      : parts.join(' ');
}
