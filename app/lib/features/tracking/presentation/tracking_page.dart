import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../infrastructure/power/power_profile_manager.dart';
import '../../onboarding/permission_onboarding_page.dart';
import '../../onboarding/permission_service.dart';
import '../application/tracking_controller.dart';
import '../application/tracking_status.dart';
import '../domain/tracking_session.dart';

/// Layar rekam. Memakai [TrackingController] tunggal agar rekaman iOS tetap
/// berjalan ketika pengguna berpindah halaman.
class TrackingPage extends StatefulWidget {
  const TrackingPage({super.key});

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage>
    with WidgetsBindingObserver {
  TrackingController get _controller => TrackingController.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Controller bisa sudah diinisialisasi saat bootstrap; muat ulang izin
    // agar status tidak basi ketika halaman dibuka setelah izin diberikan.
    unawaited(_controller.refreshPermissionsAndResume());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.refreshPermissionsAndResume());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _openOnboarding() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PermissionOnboardingPage(),
      ),
    );
    if (!mounted) return;
    await _controller.refreshPermissionsAndResume();
  }

  Future<void> _start() async {
    final started = await _controller.start();
    if (!mounted) return;
    if (!started && !(_controller.permission?.readyForBackground ?? false)) {
      await _openOnboarding();
    }
  }

  Future<void> _stop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hentikan rekaman?'),
        content: const Text(
          'Sesi akan ditandai selesai. Titik yang sudah tersimpan tetap ada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hentikan'),
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
      animation: _controller,
      builder: (context, _) {
        final phase = _controller.phase;
        final status = _controller.status;
        final permission = _controller.permission;
        final permissionReady = permission?.readyForBackground ?? false;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Rekam Perjalanan'),
            actions: [
              IconButton(
                tooltip: 'Izin & baterai',
                onPressed: () => unawaited(_openOnboarding()),
                icon: const Icon(Icons.shield_outlined),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              if (phase == TrackingPhase.initializing)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(),
                ),
              if (_controller.error != null) ...[
                _MessageCard(
                  icon: Icons.error_outline,
                  title: 'Rekaman tidak dapat disiapkan',
                  body: _controller.error!,
                  isError: true,
                ),
                const SizedBox(height: 12),
              ],
              if (_controller.notice != null) ...[
                _MessageCard(
                  icon: Icons.info_outline,
                  title: 'Catatan',
                  body: _controller.notice!,
                ),
                const SizedBox(height: 12),
              ],
              if (permission != null && !permissionReady) ...[
                _MessageCard(
                  icon: Icons.lock_outline,
                  title: 'Izin latar belakang belum lengkap',
                  body: _permissionSummary(permission),
                  actionLabel: 'Buka panduan izin',
                  onAction: () => unawaited(_openOnboarding()),
                  isError: true,
                ),
                const SizedBox(height: 12),
              ],
              if (_controller.recoveryPending &&
                  phase == TrackingPhase.idle &&
                  permissionReady) ...[
                _MessageCard(
                  icon: Icons.restore,
                  title: 'Sesi aktif ditemukan',
                  body: 'Sesi terakhir belum selesai. Mulai rekam untuk '
                      'melanjutkan sesi tersebut tanpa membuat sesi baru.',
                  actionLabel: 'Lanjutkan sesi',
                  onAction: () => unawaited(_start()),
                ),
                const SizedBox(height: 12),
              ],
              _StatusCard(phase: phase, status: status),
              const SizedBox(height: 12),
              _Controls(
                phase: phase,
                permissionReady: permissionReady,
                onStart: () => unawaited(_start()),
                onStop: () => unawaited(_stop()),
                onOpenPermissions: () => unawaited(_openOnboarding()),
              ),
              const SizedBox(height: 16),
              const _BackgroundInfoCard(),
            ],
          ),
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.phase, required this.status});

  final TrackingPhase phase;
  final TrackingStatus? status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final recording =
        phase == TrackingPhase.recording || phase == TrackingPhase.preparing;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  recording ? Icons.fiber_manual_record : Icons.route_outlined,
                  color: recording ? scheme.error : scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _phaseLabel(phase),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (status != null &&
                    status!.sessionStatus == TrackingSessionStatus.active &&
                    recording)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(status!.isMoving ? 'Bergerak' : 'Berhenti'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _formatElapsed(status?.elapsedSeconds ?? 0),
              style: Theme.of(context).textTheme.displaySmall,
            ),
            Text(
              'Durasi sesi (jam:menit:detik)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: 'Jarak',
                    value: _formatDistance(status?.distanceM ?? 0),
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Waktu bergerak',
                    value: _formatDuration(status?.movingSeconds ?? 0),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: 'Elevasi naik',
                    value: '${(status?.elevationGainM ?? 0).round()} m',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Laju',
                    value: _formatPace(status?.paceSecPerKm),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: 'Titik GPS',
                    value: '${status?.pointCount ?? 0}',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Baterai',
                    value: status?.batteryPercent == null
                        ? '—'
                        : '${status!.batteryPercent}%',
                  ),
                ),
              ],
            ),
            if (status != null) ...[
              const SizedBox(height: 12),
              Text(
                _profileLabel(status!.profile),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.phase,
    required this.permissionReady,
    required this.onStart,
    required this.onStop,
    required this.onOpenPermissions,
  });

  final TrackingPhase phase;
  final bool permissionReady;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onOpenPermissions;

  @override
  Widget build(BuildContext context) {
    final recording =
        phase == TrackingPhase.recording || phase == TrackingPhase.preparing;
    if (phase == TrackingPhase.uninitialized ||
        phase == TrackingPhase.initializing) {
      return FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.hourglass_empty),
        label: const Text('Menyiapkan...'),
      );
    }
    if (recording) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
          foregroundColor: Theme.of(context).colorScheme.onError,
        ),
        onPressed: phase == TrackingPhase.stopping ? null : onStop,
        icon: const Icon(Icons.stop_circle_outlined),
        label: Text(
          phase == TrackingPhase.stopping
              ? 'Menghentikan...'
              : 'Hentikan rekaman',
        ),
      );
    }
    if (phase == TrackingPhase.error) {
      return const SizedBox.shrink();
    }
    if (!permissionReady) {
      return FilledButton.tonalIcon(
        onPressed: onOpenPermissions,
        icon: const Icon(Icons.lock_open),
        label: const Text('Lengkapi izin untuk merekam'),
      );
    }
    return FilledButton.icon(
      onPressed:
          phase == TrackingPhase.initializing || phase == TrackingPhase.stopping
              ? null
              : onStart,
      icon: const Icon(Icons.play_arrow),
      label: Text(
        phase == TrackingPhase.finished ? 'Rekam sesi baru' : 'Mulai merekam',
      ),
    );
  }
}

class _BackgroundInfoCard extends StatelessWidget {
  const _BackgroundInfoCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.phonelink_lock_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Rekaman di latar belakang',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Android memakai layanan latar dengan notifikasi tetap. iOS '
              'memakai background location. Keduanya memerlukan izin lokasi '
              '"Selalu", lokasi presisi, dan pengaturan baterai yang tepat.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Di Android, interval GPS ditargetkan mengikuti profil daya: '
              'normal 5 detik, hemat 15 detik, kritis 60 detik. iOS menentukan '
              'interval dari sistem; aplikasi hanya mengatur akurasi. Perilaku '
              'ini belum diuji di perangkat nyata; lihat '
              'docs/field_tests/tracking_gps.md.',
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background =
        isError ? scheme.errorContainer : scheme.surfaceContainerHighest;
    final foreground =
        isError ? scheme.onErrorContainer : scheme.onSurfaceVariant;
    return Card(
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: foreground),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(body, style: TextStyle(color: foreground)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 8),
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
      ),
    );
  }
}

String _permissionSummary(PermissionReport permission) {
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

String _phaseLabel(TrackingPhase phase) => switch (phase) {
      TrackingPhase.uninitialized => 'Menyiapkan...',
      TrackingPhase.initializing => 'Menyiapkan...',
      TrackingPhase.idle => 'Siap merekam',
      TrackingPhase.preparing => 'Menyiapkan GPS...',
      TrackingPhase.recording => 'Merekam',
      TrackingPhase.stopping => 'Menghentikan...',
      TrackingPhase.finished => 'Sesi selesai',
      TrackingPhase.error => 'Rekaman tidak tersedia',
    };

String _profileLabel(PowerProfile profile) => switch (profile) {
      PowerProfile.normal => 'Profil normal · target GPS 5 detik',
      PowerProfile.saver => 'Profil hemat · target GPS 15 detik',
      PowerProfile.critical => 'Profil kritis · target GPS 60 detik',
    };

String _formatElapsed(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final secs = safe % 60;
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${secs.toString().padLeft(2, '0')}';
}

String _formatDuration(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  if (hours > 0) return '$hours j ${minutes.toString().padLeft(2, '0')} m';
  return '$minutes m';
}

String _formatDistance(double meters) {
  if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(2)} km';
  return '${meters.round()} m';
}

String _formatPace(double? secondsPerKm) {
  if (secondsPerKm == null ||
      !secondsPerKm.isFinite ||
      secondsPerKm <= 0 ||
      secondsPerKm > 36000) {
    return '—';
  }
  final seconds = secondsPerKm.round();
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')} /km';
}
