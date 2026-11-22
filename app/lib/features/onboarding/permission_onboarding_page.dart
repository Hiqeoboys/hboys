import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../design/app_theme.dart';
import '../../design/background/app_background.dart';
import '../../design/background/page_background.dart';
import '../../design/glass/hiqeo_liquid_glass.dart';
import '../../design/layout.dart';
import '../../design/tokens.dart';
import '../../design/widgets/hiqeo_back_button.dart';
import '../../design/widgets/hiqeo_button.dart';
import 'android_brand_guides.dart';
import 'permission_service.dart';

/// Panduan izin dan baterai. Semua hasil izin diverifikasi ulang lewat
/// [PermissionService.check], bukan diasumsikan dari dialog sistem.
class PermissionOnboardingPage extends StatefulWidget {
  const PermissionOnboardingPage({
    super.key,
    this.service = const PermissionService(),
    this.supportedPlatform,
  });

  final PermissionService service;

  /// Dipakai tes agar halaman dapat diuji tanpa plugin platform.
  final bool? supportedPlatform;

  @override
  State<PermissionOnboardingPage> createState() =>
      _PermissionOnboardingPageState();
}

class _PermissionOnboardingPageState extends State<PermissionOnboardingPage>
    with WidgetsBindingObserver {
  late final bool _supported;
  PermissionReport? _report;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _supported = widget.supportedPlatform ??
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    WidgetsBinding.instance.addObserver(this);
    if (_supported) unawaited(_refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _supported && !_busy) {
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final report = await widget.service.check();
      if (!mounted) return;
      setState(() => _report = report);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('PermissionOnboardingPage._refresh failed: $error');
      }
      if (!mounted) return;
      setState(() => _message = 'Status izin belum bisa dibaca dari perangkat.');
    }
  }

  Future<void> _run(Future<PermissionReport> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final report = await action();
      if (!mounted) return;
      setState(() => _report = report);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('PermissionOnboardingPage._run failed: $error');
      }
      if (!mounted) return;
      setState(
        () => _message =
            'Permintaan izin belum dapat diproses. Buka setelan perangkat.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runBatteryRequest() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final opened = await widget.service.requestIgnoreBatteryOptimization();
      final report = await widget.service.check();
      if (!mounted) return;
      setState(() {
        _report = report;
        if (!opened) {
          _message = 'Dialog pengecualian baterai tidak terbuka. Gunakan '
              'tombol setelan baterai dan ikuti panduan merek.';
        }
      });
    } catch (error) {
      if (kDebugMode) {
        debugPrint('PermissionOnboardingPage._runBatteryRequest failed: $error');
      }
      if (!mounted) return;
      setState(
        () => _message =
            'Permintaan optimasi baterai tidak tersedia. Buka setelan baterai manual.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Future<bool> Function() action) async {
    try {
      final opened = await action();
      if (!mounted) return;
      if (!opened) {
        setState(() => _message =
            'Setelan tidak dapat dibuka otomatis. Buka setelan perangkat '
                'secara manual.');
      }
      await _refresh();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('PermissionOnboardingPage._open failed: $error');
      }
      if (!mounted) return;
      setState(
        () => _message = 'Setelan perangkat tidak dapat dibuka otomatis.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTokens = Theme.of(context).extension<HiqeoColors>() != null;
    if (!hasTokens) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Theme(
        data: isDark ? hiqeoDarkTheme : hiqeoLightTheme,
        child: Builder(builder: _buildScaffold),
      );
    }
    return _buildScaffold(context);
  }

  Widget _buildScaffold(BuildContext context) {
    final report = _report;
    final colors = HiqeoColors.of(context);
    final isAndroid =
        _supported && defaultTargetPlatform == TargetPlatform.android;
    final isIos = _supported && defaultTargetPlatform == TargetPlatform.iOS;

    return PageBackground(
      page: AppBackgroundPage.profil,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: const HiqeoBackButton(inAppBar: true),
          leadingWidth: HiqeoBackButton.appBarWidth,
          title: const Text('Izin & baterai'),
        ),
        body: SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              AppLayout.bottomInset(context),
            ),
            children: [
              if (!_supported)
                const _Banner(
                  icon: Icons.info_outline,
                  title: 'Panduan hanya tersedia di Android dan iOS',
                  body: 'Perangkat ini tidak mendukung layanan lokasi latar '
                      'belakang yang dipakai aplikasi.',
                )
              else ...[
                if (_busy) const LinearProgressIndicator(),
                if (_message != null) ...[
                  const SizedBox(height: 8),
                  _Banner(
                    icon: Icons.warning_amber_outlined,
                    title: 'Perhatian',
                    body: _message!,
                    isWarning: true,
                  ),
                ],
                const SizedBox(height: 12),
                if (report == null)
                  const _Banner(
                    icon: Icons.hourglass_empty,
                    title: 'Memeriksa izin…',
                    body: 'Sedang memeriksa status izin lokasi dan baterai di HP ini.',
                  )
                else ...[
                  _ReadyBanner(ready: report.readyForBackground),
                  const SizedBox(height: 12),
                  _Checklist(report: report, android: isAndroid),
                  const SizedBox(height: 16),
                  _PermissionActions(
                    report: report,
                    busy: _busy,
                    android: isAndroid,
                    onCore: () => _run(widget.service.requestCore),
                    onBackground: () =>
                        _run(widget.service.requestBackgroundLocation),
                    onOpenSettings: () => _open(widget.service.openSettings),
                    onOpenLocationSettings: () =>
                        _open(widget.service.openLocationSettings),
                    onBatteryRequest: _runBatteryRequest,
                    onOpenBatterySettings: () =>
                        _open(widget.service.openBatteryOptimizationSettings),
                  ),
                ],
                if (isIos) ...[
                  const SizedBox(height: 16),
                  const _Banner(
                    icon: Icons.phone_iphone,
                    title: 'Catatan iOS',
                    body: 'Pilih "Always" dan aktifkan "Precise Location" agar '
                        'pelacakan tetap akurat saat layar mati. iOS dapat '
                        'meminta konfirmasi ulang setelah aplikasi memakai '
                        'lokasi di latar belakang.',
                  ),
                ],
                if (isAndroid) ...[
                  const SizedBox(height: 24),
                  const _BrandGuideDisclaimer(),
                  const SizedBox(height: 8),
                  for (final guide in androidBrandGuides)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: HiqeoGlassCard(
                        borderRadius: 22,
                        padding: EdgeInsets.zero,
                        child: Theme(
                          data: Theme.of(context)
                              .copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            leading: Icon(
                              Icons.smartphone_outlined,
                              color: colors.primary,
                            ),
                            title: Text(
                              guide.brand,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            childrenPadding:
                                const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            children: [
                              for (var i = 0; i < guide.steps.length; i++)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${i + 1}. ',
                                        style: TextStyle(
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          guide.steps[i],
                                          style: TextStyle(
                                            color: colors.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadyBanner extends StatelessWidget {
  const _ReadyBanner({required this.ready});

  final bool ready;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final accent = ready ? colors.successText : colors.warningText;
    return HiqeoGlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      borderColor: (ready ? colors.success : colors.warning)
          .withValues(alpha: 0.42),
      child: Row(
        children: [
          Icon(
            ready ? Icons.check_circle_outline : Icons.error_outline,
            color: accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ready
                  ? 'Izin siap. Rekaman dapat berjalan saat layar mati.'
                  : 'Izin belum lengkap untuk rekaman latar belakang. '
                      'Lengkapi daftar di bawah.',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Checklist extends StatelessWidget {
  const _Checklist({required this.report, required this.android});

  final PermissionReport report;
  final bool android;

  @override
  Widget build(BuildContext context) {
    return HiqeoGlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          _CheckItem(
            ok: report.locationServiceEnabled,
            title: 'Layanan lokasi perangkat aktif',
          ),
          _CheckItem(
            ok: report.locationWhileInUse,
            title: 'Izin lokasi saat digunakan',
          ),
          _CheckItem(
            ok: report.locationAlways,
            title: 'Izin lokasi selalu',
            hint: 'Wajib agar rekaman berlanjut di latar belakang.',
          ),
          _CheckItem(
            ok: report.preciseLocation,
            title: 'Lokasi presisi',
            hint: 'Aktifkan "Gunakan lokasi presisi" di setelan izin.',
          ),
          if (android)
            _CheckItem(
              ok: report.notificationGranted,
              title: 'Izin notifikasi',
              hint: 'Notifikasi layanan latar harus terlihat.',
            ),
          if (android)
            _CheckItem(
              ok: report.ignoringBatteryOptimizations,
              title: 'Dikecualikan dari optimasi baterai',
              hint: 'Disarankan agar pelacakan tetap aktif saat layar mati.',
            ),
        ],
      ),
    );
  }
}

class _CheckItem extends StatelessWidget {
  const _CheckItem({required this.ok, required this.title, this.hint});

  final bool ok;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return ListTile(
      dense: true,
      leading: Icon(
        ok ? Icons.check_circle : Icons.radio_button_unchecked,
        color: ok ? colors.successText : colors.warningText,
      ),
      title: Text(title, style: TextStyle(color: colors.textPrimary)),
      subtitle: hint == null
          ? null
          : Text(hint!, style: TextStyle(color: colors.textSecondary)),
      trailing: Text(
        ok ? 'Siap' : 'Belum',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: ok ? colors.successText : colors.textSecondary,
        ),
      ),
    );
  }
}

class _PermissionActions extends StatelessWidget {
  const _PermissionActions({
    required this.report,
    required this.busy,
    required this.android,
    required this.onCore,
    required this.onBackground,
    required this.onOpenSettings,
    required this.onOpenLocationSettings,
    required this.onBatteryRequest,
    required this.onOpenBatterySettings,
  });

  final PermissionReport report;
  final bool busy;
  final bool android;
  final Future<void> Function() onCore;
  final Future<void> Function() onBackground;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onOpenLocationSettings;
  final Future<void> Function() onBatteryRequest;
  final Future<void> Function() onOpenBatterySettings;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return HiqeoGlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Langkah izin',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Izin dasar diminta lebih dulu. Izin "Selalu" diminta terpisah; '
            'pada Android terbaru sistem dapat mengarahkan ke halaman setelan.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          HiqeoButton(
            label: report.locationWhileInUse
                ? 'Periksa ulang izin dasar'
                : 'Aktifkan izin dasar',
            leading: Icon(
              Icons.my_location,
              size: 18,
              color: colors.onPrimary,
            ),
            onPressed: busy ? null : () => unawaited(onCore()),
          ),
          if (!report.locationAlways) ...[
            const SizedBox(height: 8),
            HiqeoButton(
              label: 'Izinkan lokasi "Selalu"',
              leading: Icon(Icons.public, size: 18, color: colors.onPrimary),
              onPressed: busy ? null : () => unawaited(onBackground()),
            ),
          ],
          if (!report.locationServiceEnabled) ...[
            const SizedBox(height: 8),
            HiqeoButton(
              label: 'Aktifkan layanan lokasi',
              variant: HiqeoButtonVariant.secondary,
              leading: Icon(
                Icons.location_off_outlined,
                size: 18,
                color: colors.textPrimary,
              ),
              onPressed: busy ? null : () => unawaited(onOpenLocationSettings()),
            ),
          ],
          if (!report.preciseLocation) ...[
            const SizedBox(height: 8),
            HiqeoButton(
              label: 'Buka setelan lokasi presisi',
              variant: HiqeoButtonVariant.secondary,
              leading: Icon(
                Icons.gps_fixed,
                size: 18,
                color: colors.textPrimary,
              ),
              onPressed: busy ? null : () => unawaited(onOpenSettings()),
            ),
          ],
          const SizedBox(height: 8),
          HiqeoButton(
            label: 'Buka setelan aplikasi',
            variant: HiqeoButtonVariant.secondary,
            leading: Icon(
              Icons.settings_outlined,
              size: 18,
              color: colors.textPrimary,
            ),
            onPressed: busy ? null : () => unawaited(onOpenSettings()),
          ),
          if (android) ...[
            Divider(height: 32, color: colors.hairline),
            Text(
              'Baterai (Android)',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pengecualian optimasi baterai membantu pelacakan tetap aktif '
              'saat layar mati. Jika dialog tidak muncul, buka setelan baterai '
              'lewat tombol di bawah sesuai merek perangkat.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            if (!report.ignoringBatteryOptimizations) ...[
              HiqeoButton(
                label: 'Minta pengecualian optimasi baterai',
                variant: HiqeoButtonVariant.secondary,
                leading: Icon(
                  Icons.battery_charging_full,
                  size: 18,
                  color: colors.textPrimary,
                ),
                onPressed: busy ? null : () => unawaited(onBatteryRequest()),
              ),
              const SizedBox(height: 8),
            ],
            HiqeoButton(
              label: 'Buka setelan baterai',
              variant: HiqeoButtonVariant.secondary,
              leading: Icon(
                Icons.battery_saver_outlined,
                size: 18,
                color: colors.textPrimary,
              ),
              onPressed:
                  busy ? null : () => unawaited(onOpenBatterySettings()),
            ),
          ],
        ],
      ),
    );
  }
}

class _BrandGuideDisclaimer extends StatelessWidget {
  const _BrandGuideDisclaimer();

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return HiqeoGlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book_outlined, color: colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Panduan baterai per merek Android',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Nama menu bisa sedikit berbeda tergantung versi Android di '
            'perangkatmu. Ikuti langkah yang paling sesuai dengan pengaturan '
            'baterai di HP-mu.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.title,
    required this.body,
    this.isWarning = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return HiqeoGlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      borderColor: isWarning ? colors.warning.withValues(alpha: 0.4) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: isWarning ? colors.warningText : colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: isWarning ? colors.warningText : colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
