import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../design/widgets/hiqeo_back_button.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/utils/safe_url_launcher.dart';
import '../../../design/background/app_background.dart';
import '../../../design/glass/hiqeo_liquid_glass.dart';
import '../../../design/gooey/gooey_switch.dart';
import '../../../design/layout.dart';
import '../../../design/theme_mode_controller.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../auth/application/account_controller.dart';
import '../../debug/glass_diagnostics_page.dart';
import '../../onboarding/permission_service.dart';
import '../../plus/application/plus_controller.dart';
import '../../plus/application/plus_scope.dart';
import '../../plus/domain/plus_format.dart';
import '../application/body_metrics_store.dart';
import '../application/storage_settings_service.dart';
import 'profil_page.dart';

/// Ringkasan ukuran cache peta offline dan data sementara.
class CacheUsageSummary {
  const CacheUsageSummary({
    required this.mapCacheBytes,
    required this.tempCacheBytes,
  });

  final int mapCacheBytes;
  final int tempCacheBytes;

  String get mapLabel => _formatMegabytes(mapCacheBytes);
  String get tempLabel => _formatMegabytes(tempCacheBytes);

  static String _formatMegabytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    if (mb < 0.1) return '< 0,1 MB';
    if (mb >= 10 || (mb - mb.round()).abs() < 0.05) {
      return '${mb.round()} MB';
    }
    return '${mb.toStringAsFixed(1).replaceAll('.', ',')} MB';
  }
}

/// Halaman Pengaturan yang diakses dari Profil.
///
/// Berisi: Izin & baterai, Tema, Kebijakan privasi, Hapus cache, serta
/// Batalkan langganan (bila Plus aktif). Keluar, ganti akun, dan hapus akun
/// berada di halaman Akun agar tidak duplikat.
///
/// TIDAK ada sakelar efek kaca di Pengaturan. Pada build debug (atau
/// `--dart-define=ENABLE_GLASS_DIAGNOSTICS=true`), tekan lama label versi
/// aplikasi di bagian bawah untuk membuka layar diagnostik "Uji kaca".
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.accountController,
    this.themeController,
    this.permissionLoader,
    this.onOpenSystemSettings,
    this.onRequestBatteryException,
    this.cacheLoader,
    this.onClearCache,
    this.onClearAllLocalData,
    this.onOpenExternalUrl,
  });

  final AccountController? accountController;
  final ThemeModeController? themeController;
  final Future<PermissionReport> Function()? permissionLoader;
  final Future<bool> Function()? onOpenSystemSettings;
  final Future<bool> Function()? onRequestBatteryException;
  final Future<CacheUsageSummary> Function()? cacheLoader;
  final Future<void> Function()? onClearCache;
  final Future<void> Function()? onClearAllLocalData;
  final Future<bool> Function(String url)? onOpenExternalUrl;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final ThemeModeController _theme;
  late final Listenable _settingsListenable;
  final BodyMetricsStore _bodyMetrics = BodyMetricsStore.instance;

  PermissionReport? _permissions;
  bool _permissionsLoading = true;

  CacheUsageSummary _cache = const CacheUsageSummary(
    mapCacheBytes: 0,
    tempCacheBytes: 0,
  );
  bool _cacheLoading = true;
  bool _clearingCache = false;
  bool _wifiOnlyDownload = true;

  @override
  void initState() {
    super.initState();
    _theme = widget.themeController ?? ThemeModeController.instance;
    _settingsListenable = Listenable.merge(<Listenable>[_theme, _bodyMetrics]);
    unawaited(_bodyMetrics.load());
    unawaited(_loadPermissions());
    unawaited(_loadCacheUsage());
    unawaited(_loadWifiOnlySetting());
  }

  Future<void> _loadWifiOnlySetting() async {
    final val = await StorageSettingsService.instance.loadSettings();
    if (!mounted) return;
    setState(() => _wifiOnlyDownload = val);
  }

  Future<void> _loadPermissions() async {
    setState(() => _permissionsLoading = true);
    try {
      final loader = widget.permissionLoader;
      final report = loader != null
          ? await loader()
          : await const PermissionService().check();
      if (!mounted) return;
      setState(() {
        _permissions = report;
        _permissionsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _permissions = const PermissionReport(
          notificationGranted: false,
          locationWhileInUse: false,
          locationAlways: false,
          locationServiceEnabled: false,
          preciseLocation: false,
          ignoringBatteryOptimizations: false,
          activityRecognitionGranted: false,
        );
        _permissionsLoading = false;
      });
    }
  }

  Future<void> _loadCacheUsage() async {
    setState(() => _cacheLoading = true);
    try {
      final loader = widget.cacheLoader;
      final summary =
          loader != null ? await loader() : await _computeDeviceCache();
      if (!mounted) return;
      setState(() {
        _cache = summary;
        _cacheLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cacheLoading = false);
    }
  }

  Future<CacheUsageSummary> _computeDeviceCache() async {
    var tempBytes = 0;
    var mapBytes = 0;
    try {
      final tempDir = await getTemporaryDirectory();
      tempBytes = await _directorySizeBytes(tempDir);
    } catch (_) {
      tempBytes = 0;
    }
    try {
      final supportDir = await getApplicationSupportDirectory();
      final mapDir = Directory('${supportDir.path}/offline_maps');
      if (await mapDir.exists()) {
        mapBytes = await _directorySizeBytes(mapDir);
      }
    } catch (_) {
      mapBytes = 0;
    }
    return CacheUsageSummary(
      mapCacheBytes: mapBytes,
      tempCacheBytes: tempBytes,
    );
  }

  Future<int> _directorySizeBytes(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity
        in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }

  Future<void> _handleOpenSystemSettings() async {
    final opener = widget.onOpenSystemSettings;
    if (opener != null) {
      await opener();
    } else {
      await const PermissionService().openSettings();
    }
    if (mounted) await _loadPermissions();
  }

  Future<void> _handleRequestBatteryException() async {
    final requester = widget.onRequestBatteryException;
    if (requester != null) {
      await requester();
    } else {
      await const PermissionService().requestIgnoreBatteryOptimization();
    }
    if (mounted) await _loadPermissions();
  }

  Future<void> _openExternalUrl(String url) async {
    final customOpener = widget.onOpenExternalUrl;
    var launched = false;
    if (customOpener != null) {
      launched = await customOpener(url);
    } else {
      try {
        final uri = Uri.tryParse(url);
        launched = uri != null ? await launchSafeExternalUrl(uri) : false;
      } catch (_) {
        launched = false;
      }
    }
    if (!mounted) return;
    if (!launched) {
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      _showNotice('Tidak bisa membuka browser, tautan disalin');
    }
  }

  void _showNotice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmClearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bersihkan cache?'),
        content: const Text(
          'Tindakan ini hanya menghapus data peta sementara dan berkas '
          'cache. Riwayat pendakian yang tersimpan di HP ini tidak akan '
          'dihapus.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            key: const ValueKey<String>('settings-confirm-clear-cache'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Bersihkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearingCache = true);
    try {
      final clearer = widget.onClearCache;
      if (clearer != null) {
        await clearer();
      } else {
        await _clearDeviceCacheFiles();
      }
      if (!mounted) return;
      setState(() {
        _cache = const CacheUsageSummary(
          mapCacheBytes: 0,
          tempCacheBytes: 0,
        );
        _clearingCache = false;
      });
      _showNotice('Cache peta dan data sementara berhasil dibersihkan.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _clearingCache = false);
      _showNotice('Gagal membersihkan sebagian cache perangkat.');
    }
  }

  Future<void> _clearDeviceCacheFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list(followLinks: false)) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
    try {
      final supportDir = await getApplicationSupportDirectory();
      final mapDir = Directory('${supportDir.path}/offline_maps');
      if (await mapDir.exists()) {
        await mapDir.delete(recursive: true);
      }
    } catch (_) {}
  }

  void _openGlassDiagnostics() {
    if (!kEnableGlassDiagnostics) return;
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.push(kGlassDiagnosticsRoute);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const GlassDiagnosticsPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final plus = PlusScope.maybeOf(context);
    final hasPlus = plus?.hasPlus ?? false;

    return AppBackground(
      page: AppBackgroundPage.pengaturan,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: const HiqeoBackButton(inAppBar: true),
          leadingWidth: HiqeoBackButton.appBarWidth,
          title: Text(
            'Pengaturan',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: ListenableBuilder(
            listenable: _settingsListenable,
            builder: (context, _) {
              return RepaintBoundary(
                key: const ValueKey<String>('settings-scroll-boundary'),
                child: ListView(
                  clipBehavior: Clip.hardEdge,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    AppLayout.bottomInset(context),
                  ),
                  children: <Widget>[
                    // 1. Izin & baterai
                    _buildPermissionsAndBatterySection(theme, colors),
                    const SizedBox(height: 12),

                    // 2. Tema
                    _buildThemeSection(theme, colors),
                    const SizedBox(height: 12),

                    // 3. Kebijakan privasi
                    _buildPrivacyPolicySection(theme, colors),
                    const SizedBox(height: 12),

                    // 4. Hapus cache
                    _buildClearCacheSection(theme, colors),

                    // 5. Batalkan langganan (hanya tampil jika Plus aktif)
                    if (hasPlus && plus != null) ...<Widget>[
                      const SizedBox(height: 12),
                      _buildCancelSubscriptionSection(theme, colors, plus),
                    ],

                    const SizedBox(height: 24),
                    Center(
                      child: GestureDetector(
                        key: const ValueKey<String>('settings-app-version'),
                        onLongPress: kEnableGlassDiagnostics
                            ? _openGlassDiagnostics
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Text(
                            'Hiqeo v1.0.0',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionsAndBatterySection(
    ThemeData theme,
    HiqeoColors colors,
  ) {
    final report = _permissions;
    final String locationLabel;
    if (_permissionsLoading || report == null) {
      locationLabel = 'Memeriksa…';
    } else if (report.locationAlways) {
      locationLabel = 'Selalu';
    } else if (report.locationWhileInUse) {
      locationLabel = 'Saat digunakan';
    } else {
      locationLabel = 'Belum diizinkan';
    }

    final notificationLabel = _permissionsLoading || report == null
        ? 'Memeriksa…'
        : (report.notificationGranted ? 'Aktif' : 'Belum diizinkan');
    final activityLabel = _permissionsLoading || report == null
        ? 'Memeriksa…'
        : (report.activityRecognitionGranted ? 'Aktif' : 'Belum diizinkan');
    final batteryLabel = _permissionsLoading || report == null
        ? 'Memeriksa…'
        : (report.ignoringBatteryOptimizations
            ? 'Tidak dibatasi'
            : 'Dibatasi sistem');

    final anyPermissionMissing = report == null ||
        !report.locationAlways ||
        !report.notificationGranted ||
        !report.activityRecognitionGranted;

    return _SectionCard(
      key: const ValueKey<String>('settings-section-permissions'),
      title: 'Izin & baterai',
      subtitle: 'Status akses latar belakang dan sensor pendakian',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _StatusRow(label: 'Lokasi', value: locationLabel),
          const SizedBox(height: 8),
          _StatusRow(label: 'Notifikasi', value: notificationLabel),
          const SizedBox(height: 8),
          _StatusRow(label: 'Sensor aktivitas fisik', value: activityLabel),
          if (anyPermissionMissing) ...<Widget>[
            const SizedBox(height: 12),
            HiqeoButton(
              key: const ValueKey<String>('settings-open-system-permissions'),
              label: 'Buka pengaturan sistem',
              variant: HiqeoButtonVariant.secondary,
              onPressed: _handleOpenSystemSettings,
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          _StatusRow(label: 'Optimasi baterai', value: batteryLabel),
          const SizedBox(height: 4),
          Text(
            report?.ignoringBatteryOptimizations == true
                ? 'Aplikasi diizinkan berjalan di latar belakang tanpa dibatasi sistem.'
                : 'Sistem dapat menghentikan pelacakan saat layar mati jika optimasi baterai aktif.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          HiqeoButton(
            key: const ValueKey<String>(
              'settings-request-battery-optimization',
            ),
            label: 'Minta pengecualian optimasi baterai',
            variant: HiqeoButtonVariant.secondary,
            onPressed: _handleRequestBatteryException,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          _StatusRow(
            label: 'Data fisik (kalori & langkah)',
            value:
                '${_bodyMetrics.effectiveWeightKg.round()} kg · ${_bodyMetrics.effectiveHeightCm.round()} cm',
          ),
          const SizedBox(height: 8),
          HiqeoButton(
            key: const ValueKey<String>('settings-edit-body-metrics'),
            label: 'Ubah berat & tinggi badan',
            variant: HiqeoButtonVariant.secondary,
            onPressed: () => unawaited(
              showBodyMetricsDialog(context, store: _bodyMetrics),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSection(ThemeData theme, HiqeoColors colors) {
    return _SectionCard(
      key: const ValueKey<String>('settings-section-theme'),
      title: 'Tema',
      subtitle: 'Diterapkan langsung tanpa memulai ulang aplikasi',
      child: RadioGroup<ThemeMode>(
        groupValue: _theme.mode,
        onChanged: (selected) {
          if (selected != null) {
            unawaited(_theme.setMode(selected));
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final mode in const <ThemeMode>[
              ThemeMode.system,
              ThemeMode.light,
              ThemeMode.dark,
            ])
              RadioListTile<ThemeMode>(
                key: ValueKey<String>('settings-theme-${mode.name}'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  themeModeLabel(mode),
                  style: theme.textTheme.bodyLarge,
                ),
                value: mode,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyPolicySection(ThemeData theme, HiqeoColors colors) {
    return _SectionCard(
      key: const ValueKey<String>('settings-section-privacy'),
      title: 'Kebijakan privasi',
      subtitle:
          'Pesan grup dan berbagi lokasi bersifat sukarela serta terenkripsi ujung ke ujung',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Jejak pendakian disimpan di HP ini. Berbagi lokasi terakhir ke '
            'grup bersifat sukarela (baku nonaktif), hanya berjalan saat '
            'tracking aktif, dan dienkripsi dengan kunci grup sebelum diunggah.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          HiqeoButton(
            key: const ValueKey<String>('settings-open-privacy-policy'),
            label: 'Buka kebijakan privasi',
            variant: HiqeoButtonVariant.secondary,
            onPressed: () => unawaited(_openExternalUrl(kPrivacyPolicyUrl)),
          ),
        ],
      ),
    );
  }

  Widget _buildClearCacheSection(ThemeData theme, HiqeoColors colors) {
    final usageText = _cacheLoading
        ? 'Menghitung ukuran cache…'
        : 'Cache peta: ${_cache.mapLabel}, Data sementara: ${_cache.tempLabel}';

    return _SectionCard(
      key: const ValueKey<String>('settings-section-cache'),
      title: 'Hapus cache',
      subtitle: usageText,
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
                      'Unduh hanya lewat Wi-Fi',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Hemat kuota data seluler saat mengunduh paket peta offline',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              GooeySwitch(
                key: const ValueKey<String>('settings-wifi-only-switch'),
                value: _wifiOnlyDownload,
                semanticsLabel: 'Unduh hanya lewat Wi-Fi',
                onChanged: (val) async {
                  setState(() => _wifiOnlyDownload = val);
                  await StorageSettingsService.instance.setWifiOnlyDownload(val);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: colors.hairline, height: 1),
          const SizedBox(height: 12),
          Text(
            'Membersihkan cache hanya menghapus data peta sementara dan berkas '
            'cache, tanpa menghapus riwayat pendakian di HP ini.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          HiqeoButton(
            key: const ValueKey<String>('settings-clear-cache-button'),
            label: _clearingCache ? 'Membersihkan…' : 'Bersihkan cache',
            variant: HiqeoButtonVariant.secondary,
            onPressed: _clearingCache ? null : _confirmClearCache,
          ),
        ],
      ),
    );
  }

  Widget _buildCancelSubscriptionSection(
    ThemeData theme,
    HiqeoColors colors,
    PlusController plus,
  ) {
    final access = plus.access;
    final planTitle = plus.currentPlan?.title ?? 'Hiqeo Plus';
    final String renewalText;
    if (access.lifetime) {
      renewalText = 'Berlaku selamanya (tanpa perpanjangan berulang)';
    } else if (access.expiresAtUtc != null) {
      renewalText = formatDate(access.expiresAtUtc!);
    } else {
      renewalText = 'Aktif';
    }

    final storeUrl = Platform.isIOS
        ? 'https://apps.apple.com/account/subscriptions'
        : 'https://play.google.com/store/account/subscriptions';

    return _SectionCard(
      key: const ValueKey<String>('settings-section-subscription'),
      title: 'Batalkan langganan',
      subtitle: '$planTitle · Status langganan aktif',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _StatusRow(label: 'Status langganan', value: 'Aktif ($planTitle)'),
          const SizedBox(height: 8),
          _StatusRow(label: 'Perpanjangan berikutnya', value: renewalText),
          const SizedBox(height: 12),
          HiqeoButton(
            key: const ValueKey<String>('settings-manage-store-subscription'),
            label: 'Kelola langganan di Google Play / App Store',
            variant: HiqeoButtonVariant.secondary,
            onPressed: () => unawaited(_openExternalUrl(storeUrl)),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return HiqeoGlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
