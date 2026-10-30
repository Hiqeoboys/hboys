import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../design/glass/glass_surface.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';
import '../../../design/widgets/altracq_button.dart';
import '../../../infrastructure/power/power_profile_controller.dart';
import '../../../infrastructure/power/power_profile_manager.dart';
import '../../onboarding/permission_onboarding_page.dart';
import '../../onboarding/permission_service.dart';
import '../application/tracking_controller.dart';
import '../application/tracking_status.dart';
import 'tracking_view_data.dart';

/// Layar rekam bergaya rancangan. Data diambil dari [TrackingController]
/// tunggal agar rekaman latar Android dan iOS tetap berjalan saat berpindah
/// layar.
class TrackingPage extends StatefulWidget {
  const TrackingPage({super.key, this.powerController});

  /// Disuntikkan untuk uji; produksi membaca baterai perangkat.
  final PowerProfileController? powerController;

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage>
    with WidgetsBindingObserver {
  TrackingController get _controller => TrackingController.instance;

  late final PowerProfileController _power;
  late final bool _ownsPower;

  List<double> _elevation = const <double>[];
  int _loadedPointCount = -1;
  DateTime? _lastPointsLoad;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsPower = widget.powerController == null;
    _power = widget.powerController ?? PowerProfileController();
    if (_ownsPower) unawaited(_power.refresh());
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
    if (_ownsPower) _power.dispose();
    super.dispose();
  }

  void _onTrackingChanged({bool force = false}) {
    final status = _controller.status;
    final count = status?.pointCount ?? 0;
    if (count == _loadedPointCount) return;
    if (!force) {
      final last = _lastPointsLoad;
      if (last != null &&
          DateTime.now().difference(last) < const Duration(seconds: 5)) {
        return;
      }
    }
    unawaited(_loadPoints(count));
  }

  Future<void> _loadPoints(int count) async {
    _lastPointsLoad = DateTime.now();
    _loadedPointCount = count;
    final points = await _controller.currentTrackPoints();
    if (!mounted) return;
    setState(() => _elevation = elevationSeries(points));
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

  Future<void> _start() async {
    final started = await _controller.start();
    if (!mounted) return;
    if (!started && !(_controller.permission?.readyForBackground ?? false)) {
      await _openOnboarding();
    }
  }

  Future<void> _finish() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Akhiri pendakian?'),
        content: const Text(
          'Sesi akan ditandai selesai. Titik yang sudah tersimpan tetap ada.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Selesai'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _controller.stop();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_controller, _power]),
      builder: (context, _) {
        final status = _controller.status;
        final permission = _controller.permission;
        final permissionReady = permission?.readyForBackground ?? false;
        return TrackingView(
          phase: _controller.phase,
          status: status,
          permissionReady: permissionReady,
          permissionSummary:
              permission == null ? null : permissionSummaryText(permission),
          recoveryPending: _controller.recoveryPending,
          powerPercent: status?.batteryPercent ?? _power.levelPercent,
          profile: status?.profile ?? _power.profile,
          elevation: _elevation,
          error: _controller.error,
          notice: _controller.notice,
          onStart: () => unawaited(_start()),
          onPause: () => unawaited(_controller.pause()),
          onResume: () => unawaited(_controller.resume()),
          onFinish: () => unawaited(_finish()),
          onOpenPermissions: () => unawaited(_openOnboarding()),
        );
      },
    );
  }
}

/// Tampilan murni, dipisahkan agar dapat diuji tanpa layanan GPS.
class TrackingView extends StatelessWidget {
  const TrackingView({
    super.key,
    required this.phase,
    required this.profile,
    this.status,
    this.permissionReady = false,
    this.permissionSummary,
    this.recoveryPending = false,
    this.powerPercent,
    this.elevation = const <double>[],
    this.error,
    this.notice,
    this.onStart,
    this.onPause,
    this.onResume,
    this.onFinish,
    this.onOpenPermissions,
  });

  final TrackingPhase phase;
  final TrackingStatus? status;
  final bool permissionReady;
  final String? permissionSummary;
  final bool recoveryPending;
  final int? powerPercent;
  final PowerProfile profile;
  final List<double> elevation;
  final String? error;
  final String? notice;
  final VoidCallback? onStart;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onFinish;
  final VoidCallback? onOpenPermissions;

  @override
  Widget build(BuildContext context) {
    final colors = AltracqColors.of(context);
    final theme = Theme.of(context);
    final status = this.status;
    final hasSession = status != null && status.pointCount > 0;
    final recording = phase == TrackingPhase.recording ||
        phase == TrackingPhase.preparing;
    final paused = phase == TrackingPhase.paused;
    final finishing = phase == TrackingPhase.stopping;
    final loading = phase == TrackingPhase.uninitialized ||
        phase == TrackingPhase.initializing;
    final finished = phase == TrackingPhase.finished;
    final showPermission =
        !permissionReady && permissionSummary != null && !recording && !paused;

    final distance = hasSession ? formatDistanceValue(status.distanceM) : '—';
    final pace = formatPaceValue(status?.paceSecPerKm);
    final gain = hasSession ? formatElevationValue(status.elevationGainM) : '—';
    final vertical = hasSession
        ? formatVerticalSpeedValue(status.verticalSpeedMph)
        : '—';
    final timer = formatTimer(status?.movingSeconds ?? 0);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AltracqSpacing.lg,
          AltracqSpacing.xl,
          AltracqSpacing.lg,
          AltracqSpacing.xl,
        ),
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: colors.secondary,
                  borderRadius: BorderRadius.circular(AltracqRadius.pill),
                ),
                child: Text(
                  'Tersimpan di HP',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: AltracqTypography.medium,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AltracqSpacing.sm),
              Expanded(
                child: Text(
                  batteryStatusLabel(powerPercent, profile),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(top: AltracqSpacing.sm),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (error != null) ...<Widget>[
            const SizedBox(height: AltracqSpacing.md),
            _NoticeCard(
              title: 'Rekaman tidak tersedia',
              body: error!,
              isError: true,
              actionLabel:
                  !permissionReady && onOpenPermissions != null
                      ? 'Buka panduan izin'
                      : null,
              onAction: onOpenPermissions,
            ),
          ] else if (notice != null) ...<Widget>[
            const SizedBox(height: AltracqSpacing.md),
            _NoticeCard(title: 'Catatan', body: notice!),
          ],
          if (showPermission) ...<Widget>[
            const SizedBox(height: AltracqSpacing.md),
            _NoticeCard(
              title: 'Izin belum lengkap',
              body: permissionSummary!,
              actionLabel: onOpenPermissions == null
                  ? null
                  : 'Buka panduan izin',
              onAction: onOpenPermissions,
            ),
          ],
          if (recoveryPending && !recording && !paused) ...<Widget>[
            const SizedBox(height: AltracqSpacing.md),
            _NoticeCard(
              title: 'Sesi aktif ditemukan',
              body: 'Sesi terakhir belum selesai. Lanjutkan tanpa membuat '
                  'sesi baru.',
              actionLabel: permissionReady ? 'Lanjutkan sesi' : 'Buka izin',
              onAction: permissionReady ? onStart : onOpenPermissions,
            ),
          ],
          const SizedBox(height: AltracqSpacing.xl),
          Semantics(
            label: 'Waktu bergerak $timer',
            container: true,
            child: ExcludeSemantics(
              child: Column(
                children: <Widget>[
                  Text(
                    'Waktu bergerak',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AltracqSpacing.xs),
                  Text(
                    timer,
                    style: TextStyle(
                      fontSize: 56,
                      fontWeight: AltracqTypography.extraBold,
                      height: 1.05,
                      letterSpacing: -1.5,
                      color: colors.textPrimary,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  if (paused || finishing) ...<Widget>[
                    const SizedBox(height: AltracqSpacing.xs),
                    Text(
                      finishing ? 'Menyelesaikan sesi…' : 'Dijeda',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: AltracqTypography.medium,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: AltracqSpacing.md,
            mainAxisSpacing: AltracqSpacing.md,
            mainAxisExtent: 86,
            children: <Widget>[
              _MetricCard(
                label: 'Jarak',
                value: distance,
                unit: distance == '—' ? null : 'km',
                semanticsValue: distance == '—' ? null : '$distance kilometer',
              ),
              _MetricCard(
                label: 'Pace',
                value: pace,
                unit: pace == '—' ? null : '/km',
                semanticsValue:
                    pace == '—' ? null : '$pace menit per kilometer',
              ),
              _MetricCard(
                label: 'Tanjakan',
                value: gain,
                unit: gain == '—' ? null : 'm',
                semanticsValue: gain == '—' ? null : '$gain meter',
              ),
              _MetricCard(
                label: 'Kec. vertikal',
                value: vertical,
                unit: vertical == '—' ? null : 'm/jam',
                semanticsValue:
                    vertical == '—' ? null : '$vertical meter per jam',
              ),
              _MetricCard(
                label: 'Langkah',
                value: formatStepCount(null),
              ),
              _MetricCard(
                label: 'Kalori (estimasi)',
                value: formatCaloriesValue(null),
              ),
            ],
          ),
          const SizedBox(height: AltracqSpacing.md),
          _ElevationCard(samples: elevation),
          const SizedBox(height: AltracqSpacing.lg),
          _controls(
            phase: phase,
            recording: recording,
            paused: paused,
            finishing: finishing,
            finished: finished,
            permissionReady: permissionReady,
          ),
          const SizedBox(height: AltracqSpacing.sm),
          Text(
            paused || finishing
                ? 'Waktu bergerak berhenti selama rekaman dijeda.'
                : 'Langkah dan kalori belum dihitung karena sensor langkah '
                    'dan berat badan belum tersedia.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
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
      return AltracqButtonPair(
        leftLabel: paused ? 'Lanjut' : 'Jeda',
        rightLabel: finishing ? 'Menyelesaikan…' : 'Selesai',
        onLeftTap: finishing ? null : (paused ? onResume : onPause),
        onRightTap: finishing ? null : onFinish,
        leftSemanticLabel: paused ? 'Lanjutkan rekaman' : 'Jeda rekaman',
        rightSemanticLabel: 'Selesai dan akhiri sesi',
      );
    }
    if (finishing) {
      return const AltracqButton(label: 'Menyelesaikan…');
    }
    if (phase == TrackingPhase.error) {
      return const SizedBox.shrink();
    }
    if (phase == TrackingPhase.initializing ||
        phase == TrackingPhase.uninitialized) {
      return const AltracqButton(label: 'Menyiapkan…');
    }
    if (!permissionReady) {
      return AltracqButton(
        label: 'Lengkapi izin',
        onPressed: onOpenPermissions,
      );
    }
    return AltracqButton(
      label: finished ? 'Mulai pendakian baru' : 'Mulai pendakian',
      onPressed: onStart,
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    this.unit,
    this.semanticsValue,
  });

  final String label;
  final String value;
  final String? unit;
  final String? semanticsValue;

  @override
  Widget build(BuildContext context) {
    final colors = AltracqColors.of(context);
    final theme = Theme.of(context);
    final valueStyle = theme.textTheme.headlineMedium?.copyWith(
      color: colors.textPrimary,
      fontWeight: AltracqTypography.extraBold,
    );
    final unitStyle = theme.textTheme.bodySmall?.copyWith(
      color: colors.textSecondary,
      fontWeight: AltracqTypography.medium,
    );
    return Semantics(
      container: true,
      label: semanticsValue == null
          ? '$label: belum tersedia'
          : '$label: $semanticsValue',
      child: GlassSurface(
        borderRadius: AltracqRadius.card,
        padding: const EdgeInsets.all(14),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const Spacer(),
              Text.rich(
                TextSpan(
                  text: value,
                  style: valueStyle,
                  children: <InlineSpan>[
                    if (unit != null)
                      TextSpan(text: ' $unit', style: unitStyle),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ElevationCard extends StatelessWidget {
  const _ElevationCard({required this.samples});

  final List<double> samples;

  @override
  Widget build(BuildContext context) {
    final colors = AltracqColors.of(context);
    final theme = Theme.of(context);
    final hasProfile = samples.length >= 2;
    return GlassSurface(
      borderRadius: AltracqRadius.card,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Profil ketinggian',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AltracqSpacing.sm),
          SizedBox(
            height: 104,
            width: double.infinity,
            child: hasProfile
                ? Semantics(
                    label: 'Profil ketinggian dari ${samples.length} sampel',
                    container: true,
                    child: ExcludeSemantics(
                      child: CustomPaint(
                        painter: _ElevationPainter(
                          samples: samples,
                          line: colors.primary,
                          fill: colors.secondary.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      'Belum ada data ketinggian',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ElevationPainter extends CustomPainter {
  const _ElevationPainter({
    required this.samples,
    required this.line,
    required this.fill,
  });

  final List<double> samples;
  final Color line;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;
    final min = samples.reduce(math.min);
    final max = samples.reduce(math.max);
    final range = math.max(max - min, 1.0);
    const inset = 4.0;
    final height = size.height - inset * 2;
    final points = <Offset>[
      for (var i = 0; i < samples.length; i++)
        Offset(
          i / (samples.length - 1) * size.width,
          inset + height - (samples[i] - min) / range * height,
        ),
    ];
    final fillPath = Path()..moveTo(points.first.dx, size.height);
    for (final point in points) {
      fillPath.lineTo(point.dx, point.dy);
    }
    fillPath
      ..lineTo(points.last.dx, size.height)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = fill);
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      linePath.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = line,
    );
  }

  @override
  bool shouldRepaint(_ElevationPainter oldDelegate) =>
      oldDelegate.samples != samples ||
      oldDelegate.line != line ||
      oldDelegate.fill != fill;
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
    final colors = AltracqColors.of(context);
    final theme = Theme.of(context);
    return GlassSurface(
      borderRadius: AltracqRadius.card,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: AltracqTypography.bold,
              color: isError ? colors.warningText : colors.textPrimary,
            ),
          ),
          const SizedBox(height: AltracqSpacing.xs),
          Text(
            body,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          if (actionLabel != null && onAction != null) ...<Widget>[
            const SizedBox(height: AltracqSpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ),
          ],
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
