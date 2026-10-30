import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
      if (!mounted) return;
      setState(() => _message = 'Gagal membaca status izin: $error');
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
      if (!mounted) return;
      setState(() => _message = 'Permintaan izin gagal: $error');
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
      if (!mounted) return;
      setState(() => _message = 'Gagal meminta pengecualian baterai: $error');
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
      if (!mounted) return;
      setState(() => _message = 'Gagal membuka setelan: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final isAndroid =
        _supported && defaultTargetPlatform == TargetPlatform.android;
    final isIos = _supported && defaultTargetPlatform == TargetPlatform.iOS;

    return Scaffold(
      appBar: AppBar(title: const Text('Izin & Baterai')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
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
              ),
            ],
            const SizedBox(height: 12),
            if (report == null)
              const _Banner(
                icon: Icons.hourglass_empty,
                title: 'Memeriksa izin...',
                body: 'Status izin dibaca dari sistem, bukan dari dialog.',
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
                body: 'Pilih "Always" dan aktifkan "Precise Location". iOS '
                    'dapat menampilkan konfirmasi tambahan setelah aplikasi '
                    'memakai lokasi di latar belakang. Perilaku ini perlu '
                    'diuji di perangkat.',
              ),
            ],
            if (isAndroid) ...[
              const SizedBox(height: 24),
              const _BrandGuideDisclaimer(),
              const SizedBox(height: 8),
              for (final guide in androidBrandGuides)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    leading: const Icon(Icons.smartphone_outlined),
                    title: Text(guide.brand),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      for (var i = 0; i < guide.steps.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${i + 1}. '),
                              Expanded(child: Text(guide.steps[i])),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ReadyBanner extends StatelessWidget {
  const _ReadyBanner({required this.ready});

  final bool ready;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ready ? scheme.secondaryContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            ready ? Icons.check_circle_outline : Icons.error_outline,
            color:
                ready ? scheme.onSecondaryContainer : scheme.onErrorContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ready
                  ? 'Izin siap. Rekaman dapat berjalan saat layar mati.'
                  : 'Izin belum lengkap untuk rekaman latar belakang. '
                      'Lengkapi daftar di bawah.',
              style: TextStyle(
                color: ready
                    ? scheme.onSecondaryContainer
                    : scheme.onErrorContainer,
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
    return Card(
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
              hint: 'Disarankan; sangat penting pada ROM dengan pembunuh '
                  'aplikasi latar.',
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
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: Icon(
        ok ? Icons.check_circle : Icons.radio_button_unchecked,
        color: ok ? scheme.primary : scheme.error,
      ),
      title: Text(title),
      subtitle: hint == null ? null : Text(hint!),
      trailing: Text(ok ? 'Siap' : 'Belum'),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Langkah izin',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Izin dasar diminta lebih dulu. Izin "Selalu" diminta terpisah; '
              'pada Android 11+ sistem dapat mengarahkan ke halaman setelan.',
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: busy ? null : () => unawaited(onCore()),
              icon: const Icon(Icons.my_location),
              label: Text(
                report.locationWhileInUse
                    ? 'Periksa ulang izin dasar'
                    : 'Aktifkan izin dasar',
              ),
            ),
            if (!report.locationAlways) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: busy ? null : () => unawaited(onBackground()),
                icon: const Icon(Icons.public),
                label: const Text('Izinkan lokasi "Selalu"'),
              ),
            ],
            if (!report.locationServiceEnabled) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed:
                    busy ? null : () => unawaited(onOpenLocationSettings()),
                icon: const Icon(Icons.location_off_outlined),
                label: const Text('Aktifkan layanan lokasi'),
              ),
            ],
            if (!report.preciseLocation) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: busy ? null : () => unawaited(onOpenSettings()),
                icon: const Icon(Icons.gps_fixed),
                label: const Text('Buka setelan lokasi presisi'),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: busy ? null : () => unawaited(onOpenSettings()),
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Buka setelan aplikasi'),
            ),
            if (android) ...[
              const Divider(height: 32),
              Text(
                'Baterai (Android)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Pengecualian optimasi baterai membantu layanan latar tetap '
                'hidup. Beberapa merek menonaktifkan dialog ini; gunakan '
                'tombol setelan baterai dan panduan merek di bawah.',
              ),
              const SizedBox(height: 12),
              if (!report.ignoringBatteryOptimizations)
                FilledButton.tonalIcon(
                  onPressed: busy ? null : () => unawaited(onBatteryRequest()),
                  icon: const Icon(Icons.battery_charging_full),
                  label: const Text('Minta pengecualian optimasi baterai'),
                ),
              if (!report.ignoringBatteryOptimizations)
                const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed:
                    busy ? null : () => unawaited(onOpenBatterySettings()),
                icon: const Icon(Icons.battery_saver_outlined),
                label: const Text('Buka setelan baterai'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BrandGuideDisclaimer extends StatelessWidget {
  const _BrandGuideDisclaimer();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book_outlined, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Panduan baterai per merek Android',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Nama menu berubah antar versi OS dan ROM. Panduan ini adalah '
            'titik awal dan BELUM DIUJI di perangkat nyata; verifikasi tiap '
            'langkah sebelum disampaikan ke pengguna.',
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
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
