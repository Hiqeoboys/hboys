import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../design/gooey/gooey_switch.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/line_icons.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_connection.dart';
import '../../../infrastructure/database/repositories/drift_tracking_repository.dart';
import '../../tracking/domain/tracking_repository.dart';
import '../../tracking/domain/tracking_session.dart';
import '../application/plus_navigation.dart';
import '../application/plus_scope.dart';
import '../domain/cloud_backup.dart';
import '../domain/gpx_export.dart';
import '../domain/plus_entitlement.dart';
import '../domain/plus_format.dart';
import '../domain/plus_remote_config.dart';
import '../plus_content_dependencies.dart';
import 'widgets/plus_widgets.dart';

/// D6 Kelola Langganan.
///
/// Cadangan cloud belum punya server pada tahap ini, jadi layar tidak pernah
/// menampilkan waktu cadangan karangan: statusnya dinyatakan belum tersambung
/// dan saklar hanya menyimpan pilihan di HP. Ekspor GPX tetap gratis dan
/// tersedia meskipun Plus tidak aktif.
class ManageSubscriptionPage extends StatefulWidget {
  const ManageSubscriptionPage({
    super.key,
    this.backupRepository,
    this.repository,
    this.exporter,
  });

  final CloudBackupRepository? backupRepository;

  /// Hanya dipakai lembar ekspor GPX; layar utama tidak membuka basis data.
  final TrackingRepository? repository;
  final GpxExporter? exporter;

  @override
  State<ManageSubscriptionPage> createState() => _ManageSubscriptionPageState();
}

class _ManageSubscriptionPageState extends State<ManageSubscriptionPage> {
  CloudBackupState? _backup;
  bool _backupLoading = true;
  String? _backupError;
  bool _savingAutoBackup = false;

  CloudBackupRepository get _backupRepository =>
      widget.backupRepository ?? PlusContentDependencies.cloudBackup();

  GpxExporter get _exporter =>
      widget.exporter ?? PlusContentDependencies.gpxExporter;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBackup());
  }

  Future<void> _loadBackup() async {
    setState(() {
      _backupLoading = true;
      _backupError = null;
    });
    try {
      final state = await _backupRepository.load();
      if (!mounted) return;
      setState(() {
        _backup = state;
        _backupLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _backupLoading = false;
        _backupError = 'Pengaturan cadangan belum dapat dibaca.';
      });
    }
  }

  Future<void> _setAutoBackup(bool value) async {
    final current = _backup;
    if (current == null || _savingAutoBackup) return;
    setState(() {
      _savingAutoBackup = true;
      _backup = current.copyWith(autoBackup: value);
    });
    try {
      final saved = await _backupRepository.setAutoBackup(value);
      if (!mounted) return;
      setState(() => _backup = saved);
    } catch (_) {
      if (!mounted) return;
      setState(() => _backup = current);
      _notify('Pilihan cadangan belum bisa disimpan.');
    } finally {
      if (mounted) setState(() => _savingAutoBackup = false);
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyRecoveryCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    _notify('Kode pemulihan disalin.');
  }

  Future<void> _showRecoveryCode(CloudBackupState backup) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
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
                Text('Kode pemulihan', style: theme.textTheme.headlineSmall),
                const SizedBox(height: HiqeoSpacing.sm),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: HiqeoSpacing.lg,
                    vertical: HiqeoSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: colors.secondary.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(HiqeoRadius.floating),
                    border: Border.all(color: colors.hairline),
                  ),
                  child: Text(
                    backup.recoveryCode,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: HiqeoSpacing.md),
                Text(
                  'Simpan kode ini untuk memulihkan data di perangkat baru. '
                  'Kode baru bisa dipakai setelah server cadangan tersambung; '
                  'pada build ini tidak ada data yang dikirim ke server.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: HiqeoSpacing.lg),
                HiqeoButton(
                  key: const ValueKey('manage-copy-recovery'),
                  label: 'Salin kode',
                  onPressed: () async {
                    Navigator.of(sheetContext).pop();
                    await _copyRecoveryCode(backup.recoveryCode);
                  },
                ),
                const SizedBox(height: HiqeoSpacing.sm),
                HiqeoButton(
                  label: 'Tutup',
                  variant: HiqeoButtonVariant.secondary,
                  onPressed: () => Navigator.of(sheetContext).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showStoreInfo() {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
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
                Text('Kelola langganan', style: theme.textTheme.headlineSmall),
                const SizedBox(height: HiqeoSpacing.sm),
                Text(
                  'Langganan dibeli dan dikelola lewat App Store atau Google '
                  'Play. Build ini belum tersambung ke toko, jadi Hiqeo belum '
                  'bisa membuka halaman pengelolaan langganan di perangkat '
                  'ini.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: HiqeoSpacing.md),
                Text(
                  'Membatalkan langganan tidak menghapus riwayat, data, peta '
                  'unduhan, atau ekspor GPX.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: HiqeoSpacing.lg),
                HiqeoButton(
                  label: 'Mengerti',
                  variant: HiqeoButtonVariant.secondary,
                  onPressed: () => Navigator.of(sheetContext).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showGpxSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _GpxSheet(
        repository: widget.repository,
        exporter: _exporter,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plus = PlusScope.maybeOf(context);
    final access = plus?.access ?? PlusAccess.free;
    final hasPlus = access.hasPlus;
    final graceDays =
        plus?.config?.effectiveGraceDays ?? PlusRemoteConfig.fallbackGraceDays;
    final planTitle = plus?.currentPlan?.title ?? 'Plus';

    return PlusScrollPage(
      topBar: PlusTopBar(
        lockup: true,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          HiqeoButton(
            key: const ValueKey('manage-export-gpx'),
            label: 'Ekspor data (GPX) · gratis',
            variant: HiqeoButtonVariant.secondary,
            onPressed: _showGpxSheet,
          ),
          const SizedBox(height: HiqeoSpacing.sm),
          if (hasPlus || access.planId != null)
            HiqeoButton(
              key: const ValueKey('manage-store'),
              label: 'Kelola langganan di app store',
              variant: HiqeoButtonVariant.secondary,
              onPressed: _showStoreInfo,
            )
          else
            HiqeoButton(
              label: 'Aktifkan Plus',
              onPressed: () => context.push(PlusRoutes.paywall),
            ),
        ],
      ),
      children: <Widget>[
        _StatusCard(
          access: access,
          planTitle: planTitle,
          graceDays: graceDays,
        ),
        if (hasPlus) ...<Widget>[
          const SizedBox(height: HiqeoSpacing.md),
          if (_backupLoading)
            const _BackupLoadingCard()
          else if (_backupError != null)
            _BackupErrorCard(message: _backupError!, onRetry: _loadBackup)
          else if (_backup != null)
            _CloudCard(
              backup: _backup!,
              saving: _savingAutoBackup,
              onAutoBackupChanged: _setAutoBackup,
              onRecoveryCode: () => _showRecoveryCode(_backup!),
            ),
          const SizedBox(height: HiqeoSpacing.md),
          if (_backup != null) _DeviceCard(devices: _backup!.devices),
          const SizedBox(height: HiqeoSpacing.md),
          PlusNotice(
            icon: HiqeoIcons.lock,
            text: 'Server cadangan cloud belum ada di build ini. Saklar dan '
                'kode disimpan di HP; tidak ada data yang dikirim ke server.',
          ),
        ] else if (access.state == PlusAccessState.expired) ...<Widget>[
          const SizedBox(height: HiqeoSpacing.md),
          PlusNotice(
            icon: HiqeoIcons.warning,
            text: 'Cadangan cloud berhenti bersama Plus. Riwayat, data, peta '
                'unduhan, dan ekspor GPX tetap bisa dipakai.',
          ),
        ],
        const SizedBox(height: HiqeoSpacing.md),
        const _OwnershipCard(),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.access,
    required this.planTitle,
    required this.graceDays,
  });

  static const HiqeoColors _dark = HiqeoColors.dark;

  final PlusAccess access;
  final String planTitle;
  final int graceDays;

  String get _title => switch (access.state) {
        PlusAccessState.active || PlusAccessState.grace => 'Plus aktif',
        PlusAccessState.expired => 'Masa aktif berakhir',
        PlusAccessState.free => 'Plus belum aktif',
      };

  String get _subtitle {
    if (access.lifetime) return '$planTitle · berlaku selamanya';
    final expiresAt = access.expiresAtUtc;
    switch (access.state) {
      case PlusAccessState.active:
        return expiresAt == null
            ? '$planTitle · aktif'
            : '$planTitle · berakhir ${formatDate(expiresAt)}';
      case PlusAccessState.grace:
        final graceEnds = access.graceEndsAtUtc;
        return graceEnds == null
            ? '$planTitle · masa tenggang'
            : '$planTitle · tenggang sampai ${formatDate(graceEnds)}';
      case PlusAccessState.expired:
        return expiresAt == null
            ? '$planTitle · berakhir'
            : '$planTitle · berakhir ${formatDate(expiresAt)}';
      case PlusAccessState.free:
        return 'Fitur inti tetap gratis';
    }
  }

  String get _body {
    switch (access.state) {
      case PlusAccessState.active:
        return 'Status tersimpan di HP dengan masa tenggang $graceDays hari, '
            'agar fitur tidak terkunci di tengah pendakian.';
      case PlusAccessState.grace:
        return 'Tanggal berlaku sudah lewat. Fitur Plus tetap terbuka sampai '
            'masa tenggang $graceDays hari habis; data tidak dihapus.';
      case PlusAccessState.expired:
        return 'Masa tenggang sudah habis. Riwayat, data, peta unduhan, dan '
            'ekspor tetap bisa dipakai; hanya fitur Plus yang berhenti.';
      case PlusAccessState.free:
        return 'Plus menambah cuaca rute, estimasi, analitik, dan rekap '
            'tahunan. Fitur inti serta peta offline tetap gratis.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(HiqeoSpacing.xl),
      decoration: BoxDecoration(
        color: _dark.background,
        borderRadius: BorderRadius.circular(HiqeoRadius.hero),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Text(
                  _title,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontSize: 28,
                    height: 1.05,
                    color: _dark.primary,
                  ),
                ),
              ),
              const SizedBox(width: HiqeoSpacing.sm),
              _StatusPill(access: access),
            ],
          ),
          const SizedBox(height: HiqeoSpacing.xs),
          Text(
            _subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _dark.textSecondary,
            ),
          ),
          const SizedBox(height: HiqeoSpacing.md),
          Text(
            _body,
            style: theme.textTheme.bodySmall?.copyWith(
              height: 1.45,
              color: _dark.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.access});

  static const HiqeoColors _dark = HiqeoColors.dark;

  final PlusAccess access;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, icon) = switch (access.state) {
      PlusAccessState.active => ('Aktif tanpa sinyal', HiqeoIcons.check),
      PlusAccessState.grace => ('Masa tenggang', HiqeoIcons.clock),
      PlusAccessState.expired => ('Berakhir', HiqeoIcons.warning),
      PlusAccessState.free => ('Gratis', HiqeoIcons.mountain),
    };
    return Semantics(
      label: 'Status: $label',
      child: Container(
        key: const ValueKey('manage-status-pill'),
        padding: const EdgeInsets.symmetric(
          horizontal: HiqeoSpacing.md,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: _dark.primary.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(HiqeoRadius.pill),
          border: Border.all(color: _dark.primary.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            HiqeoIcon(icon, size: 14, color: _dark.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 11,
                letterSpacing: 0.3,
                color: _dark.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloudCard extends StatelessWidget {
  const _CloudCard({
    required this.backup,
    required this.saving,
    required this.onAutoBackupChanged,
    required this.onRecoveryCode,
  });

  final CloudBackupState backup;
  final bool saving;
  final ValueChanged<bool> onAutoBackupChanged;
  final VoidCallback onRecoveryCode;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final lastBackup = backup.lastBackupAtUtc;
    return PlusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              HiqeoIcon(
                HiqeoIcons.cloud,
                size: 20,
                color: colors.primary,
              ),
              const SizedBox(width: HiqeoSpacing.sm),
              Text('Cadangan cloud', style: theme.textTheme.titleMedium),
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
                      'Cadangkan otomatis',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Hanya lewat Wi-Fi',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: HiqeoSpacing.sm),
              GooeySwitch(
                key: const ValueKey('manage-backup-switch'),
                value: backup.autoBackup,
                semanticsLabel: 'Cadangkan otomatis, hanya lewat Wi-Fi',
                onChanged: saving ? (_) {} : onAutoBackupChanged,
              ),
            ],
          ),
          Divider(color: colors.hairline, height: HiqeoSpacing.xl),
          Text(
            'Terakhir dicadangkan',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 1),
          Text(
            lastBackup == null
                ? 'Belum ada · server cadangan belum tersambung'
                : '${formatDate(lastBackup)} · '
                    '${formatClock(lastBackup.toLocal())}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: HiqeoSpacing.md),
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('manage-recovery-code'),
              borderRadius: BorderRadius.circular(HiqeoRadius.floating),
              onTap: onRecoveryCode,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Kode pemulihan',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'Simpan untuk memulihkan di perangkat baru',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
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
      ),
    );
  }
}

class _BackupLoadingCard extends StatelessWidget {
  const _BackupLoadingCard();

  @override
  Widget build(BuildContext context) {
    return const PlusCard(
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: HiqeoSpacing.md),
          Expanded(child: Text('Membaca pengaturan cadangan…')),
        ],
      ),
    );
  }
}

class _BackupErrorCard extends StatelessWidget {
  const _BackupErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return PlusEmptyState(
      icon: HiqeoIcons.warning,
      title: 'Cadangan belum bisa dibuka',
      message: message,
      action: HiqeoButton(
        label: 'Coba lagi',
        variant: HiqeoButtonVariant.secondary,
        onPressed: onRetry,
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.devices});

  final List<BackupDevice> devices;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return PlusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const PlusOverline('Perangkat'),
          const SizedBox(height: HiqeoSpacing.md),
          for (var index = 0; index < devices.length; index++) ...<Widget>[
            if (index > 0)
              Divider(color: colors.hairline, height: HiqeoSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        devices[index].name,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        devices[index].current
                            ? 'Perangkat ini'
                            : 'Terakhir aktif '
                                '${formatDate(devices[index].lastActiveUtc)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (devices[index].current)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: HiqeoSpacing.md,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: colors.secondary.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        HiqeoIcon(
                          HiqeoIcons.check,
                          size: 13,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Aktif',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 11,
                            color: colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          if (devices.length <= 1) ...<Widget>[
            const SizedBox(height: HiqeoSpacing.md),
            Text(
              'Perangkat lain muncul di sini setelah cadangan cloud '
              'tersambung.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OwnershipCard extends StatelessWidget {
  const _OwnershipCard();

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return PlusCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: HiqeoIcon(
              HiqeoIcons.check,
              size: 16,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: HiqeoSpacing.sm),
          Expanded(
            child: Text(
              'Jika berhenti berlangganan, riwayat, data, dan peta unduhan '
              'tetap bisa diakses dan diekspor. Hanya fitur Plus yang '
              'berhenti.',
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.45,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GpxSheet extends StatefulWidget {
  const _GpxSheet({required this.repository, required this.exporter});

  final TrackingRepository? repository;
  final GpxExporter exporter;

  @override
  State<_GpxSheet> createState() => _GpxSheetState();
}

class _GpxSheetState extends State<_GpxSheet> {
  AppDatabase? _database;
  bool _loading = true;
  String? _error;
  List<TrackingSession> _sessions = const <TrackingSession>[];
  String? _exportingId;

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
      if (!mounted) return;
      setState(() {
        _sessions = completed;
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

  Future<void> _export(TrackingSession session) async {
    final repository = await _openRepository();
    if (!mounted) return;
    if (repository == null) {
      _notify('Data pendakian lokal belum dapat dibuka.');
      return;
    }
    setState(() => _exportingId = session.id);
    try {
      final points = await repository.points(session.id);
      final contents = GpxDocument.build(session: session, points: points);
      final ok = await widget.exporter.share(
        fileName: 'hiqeo-gpx-${isoDateForFile(session.startedAtUtc)}.gpx',
        contents: contents,
        subject: 'GPX pendakian Hiqeo',
      );
      if (!mounted) return;
      _notify(
        ok
            ? 'Berkas GPX siap dibagikan.'
            : 'Lembar berbagi tidak tersedia di perangkat ini.',
      );
    } catch (_) {
      if (!mounted) return;
      _notify('GPX belum bisa dibuat. Coba lagi.');
    } finally {
      if (mounted) setState(() => _exportingId = null);
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: FractionallySizedBox(
        heightFactor: 0.78,
        child: Container(
          key: const ValueKey('gpx-sheet'),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(HiqeoRadius.hero),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                HiqeoSpacing.lg,
                HiqeoSpacing.md,
                HiqeoSpacing.lg,
                HiqeoSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.hairline,
                        borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                      ),
                    ),
                  ),
                  const SizedBox(height: HiqeoSpacing.md),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const PlusOverline('Ekspor GPX · gratis'),
                            const SizedBox(height: 2),
                            Text(
                              'Ekspor data pendakian',
                              style: theme.textTheme.headlineSmall,
                            ),
                          ],
                        ),
                      ),
                      PlusCircleButton(
                        icon: HiqeoIcons.close,
                        label: 'Tutup',
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: HiqeoSpacing.sm),
                  Text(
                    'Berkas GPX berisi titik GPS sesi dan bisa dibuka di '
                    'aplikasi peta lain. Ekspor tetap tersedia tanpa Plus.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: HiqeoSpacing.md),
                  Expanded(child: _list(theme, colors)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(ThemeData theme, HiqeoColors colors) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return PlusEmptyState(
        icon: HiqeoIcons.warning,
        title: 'Ekspor belum bisa dibuka',
        message: _error!,
        action: HiqeoButton(
          label: 'Coba lagi',
          variant: HiqeoButtonVariant.secondary,
          onPressed: _load,
        ),
      );
    }
    if (_sessions.isEmpty) {
      return PlusEmptyState(
        icon: HiqeoIcons.download,
        title: 'Belum ada sesi selesai',
        message: 'GPX dibuat dari pendakian yang sudah selesai dan tersimpan '
            'di HP ini.',
      );
    }
    return ListView.separated(
      itemCount: _sessions.length,
      separatorBuilder: (context, index) =>
          Divider(color: colors.hairline, height: 1),
      itemBuilder: (context, index) {
        final session = _sessions[index];
        final exporting = _exportingId == session.id;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey<String>('gpx-session-${session.id}'),
            onTap: exporting ? null : () => _export(session),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: HiqeoSpacing.md),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          formatDayDate(session.startedAtUtc),
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${formatKm(session.distanceM)} · '
                          '${formatDuration(session.movingSeconds)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: HiqeoSpacing.sm),
                  exporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : HiqeoIcon(
                          HiqeoIcons.download,
                          size: 20,
                          color: colors.primary,
                        ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
