import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/safe_url_launcher.dart';
import '../../../design/glass/glass_surface.dart';
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
/// Mengelola status Hiqeo Plus, menu eksklusif Mahasiswa & Tahunan (Analitik
/// lanjutan dan Rekap tahunan), cadangan cloud otomatis terenkripsi sesi, serta
/// ekspor GPX gratis.
class ManageSubscriptionPage extends StatefulWidget {
  const ManageSubscriptionPage({
    super.key,
    this.backupRepository,
    this.repository,
    this.exporter,
    this.onOpenExternalUrl,
  });

  final CloudBackupRepository? backupRepository;

  /// Hanya dipakai lembar ekspor GPX; layar utama tidak membuka basis data.
  final TrackingRepository? repository;
  final GpxExporter? exporter;
  final Future<bool> Function(String url)? onOpenExternalUrl;

  @override
  State<ManageSubscriptionPage> createState() => _ManageSubscriptionPageState();
}

class _ManageSubscriptionPageState extends State<ManageSubscriptionPage> {
  CloudBackupState? _backup;
  bool _backupLoading = true;
  String? _backupError;
  bool _savingAutoBackup = false;
  bool _syncingNow = false;

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

  Future<void> _setWifiOnly(bool value) async {
    final current = _backup;
    if (current == null || _savingAutoBackup) return;
    setState(() {
      _savingAutoBackup = true;
      _backup = current.copyWith(wifiOnly: value);
    });
    try {
      final saved = await _backupRepository.setWifiOnly(value);
      if (!mounted) return;
      setState(() => _backup = saved);
    } catch (_) {
      if (!mounted) return;
      setState(() => _backup = current);
      _notify('Pengaturan Wi-Fi belum bisa disimpan.');
    } finally {
      if (mounted) setState(() => _savingAutoBackup = false);
    }
  }

  Future<void> _syncNow() async {
    if (_syncingNow) return;
    setState(() => _syncingNow = true);
    try {
      final updated = await _backupRepository.syncNow(ignoreWifiOnly: true);
      if (!mounted) return;
      setState(() => _backup = updated);
      _notify('Riwayat dan statistik tersinkron dengan server.');
    } catch (_) {
      if (!mounted) return;
      _notify('Sinkronisasi gagal. Periksa koneksi internet.');
    } finally {
      if (mounted) setState(() => _syncingNow = false);
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openStoreSubscriptions() async {
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    final url = isIos
        ? 'https://apps.apple.com/account/subscriptions'
        : 'https://play.google.com/store/account/subscriptions';
    var launched = false;
    try {
      launched = widget.onOpenExternalUrl != null
          ? await widget.onOpenExternalUrl!(url)
          : await launchSafeExternalUrl(Uri.parse(url));
    } catch (_) {
      launched = false;
    }
    if (!launched && mounted) {
      try {
        await Clipboard.setData(ClipboardData(text: url));
      } catch (_) {}
      if (!mounted) return;
      await _showStoreInfo(isIos: isIos);
    }
  }

  Future<void> _showStoreInfo({required bool isIos}) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final storeName = isIos ? 'App Store' : 'Google Play';
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (sheetContext) {
        final safeBottom = MediaQuery.paddingOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            HiqeoSpacing.md,
            0,
            HiqeoSpacing.md,
            HiqeoSpacing.md + safeBottom,
          ),
          child: GlassSurface(
            tier: GlassTier.panel,
            borderRadius: 28,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
                Text('Kelola langganan', style: theme.textTheme.headlineSmall),
                const SizedBox(height: HiqeoSpacing.sm),
                Text(
                  'Langganan dikelola melalui $storeName. Tautan halaman '
                  'langganan sudah disalin jika toko aplikasi tidak terbuka '
                  'otomatis.',
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
        );
      },
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
        onBack: () => popPlusRoute(context),
      ),
      children: <Widget>[
        _StatusCard(
          access: access,
          planTitle: planTitle,
          graceDays: graceDays,
        ),
        if (access.hasFullSocialAccess) ...<Widget>[
          const SizedBox(height: HiqeoSpacing.md),
          _ExclusiveToolsCard(
            onAnalytics: () => context.push(PlusRoutes.analytics),
            onRecap: () => context.push(PlusRoutes.recap),
          ),
        ],
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
              syncing: _syncingNow,
              onAutoBackupChanged: _setAutoBackup,
              onWifiOnlyChanged: _setWifiOnly,
              onSyncNow: _syncNow,
            ),
          const SizedBox(height: HiqeoSpacing.md),
          if (_backup != null) _DeviceCard(devices: _backup!.devices),
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
        const SizedBox(height: HiqeoSpacing.xl),
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
            label: defaultTargetPlatform == TargetPlatform.iOS
                ? 'Kelola langganan di App Store'
                : 'Kelola langganan di Google Play',
            variant: HiqeoButtonVariant.secondary,
            onPressed: () => unawaited(_openStoreSubscriptions()),
          )
        else
          HiqeoButton(
            label: 'Aktifkan Plus',
            onPressed: () => context.push(PlusRoutes.paywall),
          ),
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

class _ExclusiveToolsCard extends StatelessWidget {
  const _ExclusiveToolsCard({
    required this.onAnalytics,
    required this.onRecap,
  });

  final VoidCallback onAnalytics;
  final VoidCallback onRecap;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return PlusCard(
      key: const ValueKey('manage-plus-exclusive-tools'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const PlusOverline('Eksklusif Mahasiswa & Tahunan'),
          const SizedBox(height: HiqeoSpacing.sm),
          _toolRow(
            key: const ValueKey('plus-row-analitik'),
            icon: HiqeoIcons.activity,
            title: 'Analitik lanjutan',
            subtitle: 'Pace kemiringan, kecepatan vertikal, dan rekor pribadi',
            colors: colors,
            theme: theme,
            onTap: onAnalytics,
          ),
          Divider(color: colors.hairline, height: HiqeoSpacing.md),
          _toolRow(
            key: const ValueKey('plus-row-rekap'),
            icon: HiqeoIcons.calendar,
            title: 'Rekap tahunan',
            subtitle: 'Kartu statistik tahunan yang bisa dibagikan',
            colors: colors,
            theme: theme,
            onTap: onRecap,
          ),
        ],
      ),
    );
  }

  Widget _toolRow({
    required Key key,
    required HiqeoIconData icon,
    required String title,
    required String subtitle,
    required HiqeoColors colors,
    required ThemeData theme,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(HiqeoRadius.floating),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.secondary,
                ),
                child: Center(
                  child: HiqeoIcon(icon, size: 19, color: colors.textPrimary),
                ),
              ),
              const SizedBox(width: HiqeoSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
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
    );
  }
}

class _CloudCard extends StatelessWidget {
  const _CloudCard({
    required this.backup,
    required this.saving,
    required this.syncing,
    required this.onAutoBackupChanged,
    required this.onWifiOnlyChanged,
    required this.onSyncNow,
  });

  final CloudBackupState backup;
  final bool saving;
  final bool syncing;
  final ValueChanged<bool> onAutoBackupChanged;
  final ValueChanged<bool> onWifiOnlyChanged;
  final VoidCallback onSyncNow;

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
                      'Riwayat & statistik otomatis dipulihkan saat masuk di perangkat baru',
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
                semanticsLabel: 'Cadangkan otomatis',
                onChanged: saving ? (_) {} : onAutoBackupChanged,
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
                      'Hanya lewat Wi-Fi',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Hemat kuota seluler saat mencadangkan sesi',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: HiqeoSpacing.sm),
              GooeySwitch(
                key: const ValueKey('manage-wifi-only-switch'),
                value: backup.wifiOnly,
                semanticsLabel: 'Hanya lewat Wi-Fi',
                onChanged: saving ? (_) {} : onWifiOnlyChanged,
              ),
            ],
          ),
          Divider(color: colors.hairline, height: HiqeoSpacing.xl),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Terakhir dicadangkan',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      lastBackup == null
                          ? 'Menunggu sinkronisasi pertama'
                          : '${formatDate(lastBackup)} · '
                              '${formatClock(lastBackup.toLocal())}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: HiqeoSpacing.sm),
              FilledButton.tonal(
                key: const ValueKey('manage-sync-now'),
                onPressed: syncing ? null : onSyncNow,
                child: Text(syncing ? 'Menyinkronkan…' : 'Sinkronkan'),
              ),
            ],
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
              'Riwayat dan statistik otomatis dipulihkan saat kamu masuk dengan akun yang sama di perangkat lain.',
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
    if (database != null) {
      DriftTrackingRepository.unregisterDatabase(database);
      unawaited(database.close());
    }
    super.dispose();
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
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: FractionallySizedBox(
        heightFactor: 0.78,
        child: GlassSurface(
          key: const ValueKey('gpx-sheet'),
          tier: GlassTier.panel,
          borderRadius: 28,
          padding: EdgeInsets.fromLTRB(
            HiqeoSpacing.lg,
            HiqeoSpacing.md,
            HiqeoSpacing.lg,
            HiqeoSpacing.lg + safeBottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
