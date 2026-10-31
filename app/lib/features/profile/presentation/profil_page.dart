import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../design/glass/glass_surface.dart';
import '../../../design/theme_mode_controller.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/line_icons.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_connection.dart';
import '../../../infrastructure/database/repositories/drift_safety_repository.dart';
import '../../../infrastructure/database/repositories/drift_tracking_repository.dart';
import '../../../infrastructure/power/power_profile_controller.dart';
import '../../../infrastructure/power/power_profile_manager.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../../auth/application/account_controller.dart';
import '../../auth/domain/auth_service.dart';
import '../../auth/presentation/account_page.dart';
import '../../safety/domain/emergency_contact.dart';
import '../../safety/domain/safety_repository.dart';
import '../../tracking/domain/tracking_repository.dart';
import '../application/profile_map_status.dart';
import '../domain/profile_summary.dart';

/// Profil tamu dan profil setelah masuk.
///
/// Angka ringkasan berasal dari sesi selesai di database perangkat. Tidak ada
/// angka contoh: selama data belum terbaca, nilainya "—".
class ProfilPage extends StatefulWidget {
  const ProfilPage({
    super.key,
    this.accountController,
    this.powerController,
    this.themeController,
    this.trackingRepository,
    this.safetyRepository,
    this.downloadedMountainCount,
  });

  /// Disuntikkan untuk uji; produksi memakai layanan perangkat.
  final AccountController? accountController;
  final PowerProfileController? powerController;
  final ThemeModeController? themeController;
  final TrackingRepository? trackingRepository;
  final SafetyRepository? safetyRepository;
  final Future<int> Function()? downloadedMountainCount;

  @override
  State<ProfilPage> createState() => _ProfilPageState();
}

class _ProfilPageState extends State<ProfilPage> {
  AppDatabase? _database;
  TrackingRepository? _tracking;
  SafetyRepository? _safety;

  late final AccountController _account;
  late final PowerProfileController _power;
  late final ThemeModeController _theme;
  late final bool _ownsAccount;
  late final bool _ownsPower;

  ProfileSummary? _summary;
  bool _summaryFailed = false;

  int? _downloadedMountains;
  bool _mapsLoading = true;

  List<EmergencyContact> _contacts = const <EmergencyContact>[];
  bool _contactsLoading = false;
  bool _contactsFailed = false;
  String? _contactsUserId;
  int _contactsGeneration = 0;

  @override
  void initState() {
    super.initState();
    _ownsAccount = widget.accountController == null;
    _account =
        widget.accountController ?? SupabaseServices.createAccountController();
    _account.initialize();
    _ownsPower = widget.powerController == null;
    _power = widget.powerController ?? PowerProfileController();
    if (_ownsPower) unawaited(_power.refresh());
    _theme = widget.themeController ?? ThemeModeController.instance;
    _account.addListener(_onAccountChanged);
    unawaited(_openLocal());
    unawaited(_loadMaps());
  }

  @override
  void dispose() {
    _account.removeListener(_onAccountChanged);
    if (_ownsAccount) _account.dispose();
    if (_ownsPower) _power.dispose();
    final database = _database;
    if (database != null) unawaited(database.close());
    super.dispose();
  }

  void _onAccountChanged() {
    _syncContacts();
    if (mounted) setState(() {});
  }

  Future<void> _openLocal() async {
    AppDatabase? database;
    try {
      if (widget.trackingRepository == null ||
          widget.safetyRepository == null) {
        database = openAppDatabase(await defaultAppDatabaseFile());
      }
    } catch (_) {
      database = null;
    }
    if (!mounted) {
      await database?.close();
      return;
    }
    _database = database;
    _tracking = widget.trackingRepository ??
        (database == null ? null : DriftTrackingRepository(database));
    _safety = widget.safetyRepository ??
        (database == null ? null : DriftSafetyRepository(database));
    if (_tracking == null) {
      setState(() => _summaryFailed = true);
    } else {
      await _loadSummary();
    }
    _syncContacts();
  }

  Future<void> _loadSummary() async {
    final repository = _tracking;
    if (repository == null) return;
    try {
      final sessions = await repository.watchSessions().first;
      if (!mounted) return;
      setState(() {
        _summary = ProfileSummary.fromSessions(sessions);
        _summaryFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _summaryFailed = true);
    }
  }

  Future<void> _loadMaps() async {
    final counter =
        widget.downloadedMountainCount ?? defaultDownloadedMountainCount;
    final count = await counter();
    if (!mounted) return;
    setState(() {
      _downloadedMountains = count;
      _mapsLoading = false;
    });
  }

  void _syncContacts() {
    final userId = _account.user?.id;
    if (userId == _contactsUserId &&
        !(_contactsFailed && _safety != null)) {
      return;
    }
    _contactsUserId = userId;
    final generation = ++_contactsGeneration;
    if (userId == null) {
      setState(() {
        _contacts = const <EmergencyContact>[];
        _contactsLoading = false;
        _contactsFailed = false;
      });
      return;
    }
    final repository = _safety;
    if (repository == null) {
      setState(() {
        _contacts = const <EmergencyContact>[];
        _contactsLoading = false;
        _contactsFailed = true;
      });
      return;
    }
    setState(() {
      _contactsLoading = true;
      _contactsFailed = false;
    });
    unawaited(() async {
      try {
        final contacts = await repository.contactsOf(userId);
        if (!mounted || generation != _contactsGeneration) return;
        setState(() {
          _contacts = contacts;
          _contactsLoading = false;
          _contactsFailed = false;
        });
      } catch (_) {
        if (!mounted || generation != _contactsGeneration) return;
        setState(() {
          _contacts = const <EmergencyContact>[];
          _contactsLoading = false;
          _contactsFailed = true;
        });
      }
    }());
  }

  void _signIn(AuthProviderKind provider) {
    if (!_account.isConfigured || _account.isBusy) return;
    unawaited(_account.signIn(provider));
  }

  void _openAccount() {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => AccountPage(controller: _account),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      bottom: false,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          _account,
          _power,
          _theme,
        ]),
        builder: (context, _) {
          final signedIn = _account.user != null;
          return LayoutBuilder(
            builder: (context, constraints) {
              final minHeight = (constraints.maxHeight - 56 - bottomInset)
                  .clamp(0.0, double.infinity);
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  HiqeoSpacing.lg,
                  HiqeoSpacing.xl,
                  HiqeoSpacing.lg,
                  HiqeoSpacing.xxl + bottomInset,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minHeight),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: signedIn
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            'Profil',
                            style: Theme.of(context).textTheme.displaySmall,
                          ),
                          const SizedBox(height: HiqeoSpacing.xl),
                          if (signedIn) ..._signedIn() else ..._guestTop(),
                        ],
                      ),
                      if (!signedIn) _guestBottom(),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  List<Widget> _guestTop() {
    return <Widget>[
      const _ProfileAvatar(),
      const SizedBox(height: HiqeoSpacing.lg),
      Center(
        child: Text(
          'Pendaki tamu',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      const SizedBox(height: HiqeoSpacing.xs),
      Center(
        child: Text(
          'Data pendakian tersimpan di HP ini',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: HiqeoColors.of(context).textSecondary,
              ),
        ),
      ),
      const SizedBox(height: HiqeoSpacing.xl),
      _StatsCard(
        summary: _summary,
        failed: _summaryFailed,
      ),
      const SizedBox(height: HiqeoSpacing.lg),
      const _GuestBenefitsCard(),
    ];
  }

  Widget _guestBottom() {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final enabled = _account.isConfigured && !_account.isBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!_account.isConfigured)
          Padding(
            padding: const EdgeInsets.only(bottom: HiqeoSpacing.md),
            child: Text(
              'Login Google/Apple belum aktif di build ini.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        if (_account.error != null)
          _Message(text: _account.error!, isError: true)
        else if (_account.notice != null)
          _Message(text: _account.notice!),
        if (_account.isBusy)
          Padding(
            padding: const EdgeInsets.only(bottom: HiqeoSpacing.md),
            child: Text(
              'Membuka browser login…',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        const SizedBox(height: HiqeoSpacing.lg),
        _AuthButtons(
          enabled: enabled,
          onGoogle: () => _signIn(AuthProviderKind.google),
          onApple: () => _signIn(AuthProviderKind.apple),
        ),
        const SizedBox(height: HiqeoSpacing.md),
        Text(
          'Isi pesanmu tidak dibaca server. Lokasi hanya tersimpan di HP ini.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }

  List<Widget> _signedIn() {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final user = _account.user!;
    final profile = _account.profile;
    final name = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : (profile?.username ?? 'Pendaki');
    final handle = profile == null
        ? 'Username belum dibuat'
        : '@${profile.username}';
    return <Widget>[
      _ProfileAvatar(initial: _initialOf(name)),
      const SizedBox(height: HiqeoSpacing.lg),
      Center(
        child: Text(name, style: theme.textTheme.headlineSmall),
      ),
      const SizedBox(height: HiqeoSpacing.xs),
      Center(
        child: Text(
          handle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ),
      if (user.provider != null) ...<Widget>[
        const SizedBox(height: HiqeoSpacing.md),
        Center(
          child: _ProviderPill(provider: user.provider!),
        ),
      ],
      if (profile == null) ...<Widget>[
        const SizedBox(height: HiqeoSpacing.xs),
        Center(
          child: TextButton(
            key: const ValueKey('profil-complete-account'),
            onPressed: _openAccount,
            child: const Text('Lengkapi akun'),
          ),
        ),
      ],
      if (_account.deviceKeyMismatch) ...<Widget>[
        const SizedBox(height: HiqeoSpacing.sm),
        Text(
          'Kunci perangkat berbeda dari direktori. Buka akun untuk '
          'mendaftarkan ulang kunci.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: colors.warningText),
        ),
        Center(
          child: TextButton(
            onPressed: _openAccount,
            child: const Text('Buka akun'),
          ),
        ),
      ],
      const SizedBox(height: HiqeoSpacing.xl),
      _StatsCard(summary: _summary, failed: _summaryFailed),
      const SizedBox(height: HiqeoSpacing.lg),
      _ProfilRow(
        key: const ValueKey('profil-row-kontak'),
        icon: HiqeoIcons.phone,
        title: 'Kontak darurat',
        subtitle: _contactsSubtitle(),
        onTap: () => unawaited(_showContactsSheet()),
      ),
      const SizedBox(height: HiqeoSpacing.sm),
      _ProfilRow(
        key: const ValueKey('profil-row-peta'),
        icon: HiqeoIcons.map,
        title: 'Peta terunduh',
        subtitle: _mapsLoading
            ? 'Memuat…'
            : downloadedMountainLabel(_downloadedMountains),
        onTap: () => unawaited(_showMapsSheet()),
      ),
      const SizedBox(height: HiqeoSpacing.sm),
      _ProfilRow(
        key: const ValueKey('profil-row-daya'),
        icon: HiqeoIcons.battery,
        title: 'Profil daya',
        subtitle: _powerProfileLabel(_power.profile),
        onTap: () => unawaited(_showPowerSheet()),
      ),
      const SizedBox(height: HiqeoSpacing.sm),
      _ProfilRow(
        key: const ValueKey('profil-row-privasi'),
        icon: HiqeoIcons.lock,
        title: 'Privasi lokasi',
        subtitle: 'Belum ada berbagi lokasi',
        onTap: () => unawaited(_showPrivacySheet()),
      ),
      const SizedBox(height: HiqeoSpacing.sm),
      _ProfilRow(
        key: const ValueKey('profil-row-tampilan'),
        icon: HiqeoIcons.sun,
        title: 'Tampilan',
        subtitle: themeModeLabel(_theme.mode),
        onTap: () => unawaited(_showThemeSheet()),
      ),
      const SizedBox(height: HiqeoSpacing.xl),
      if (_account.error != null)
        _Message(text: _account.error!, isError: true)
      else if (_account.notice != null)
        _Message(text: _account.notice!),
      _SignOutButton(
        enabled: !_account.isBusy,
        onTap: () => unawaited(_account.signOut()),
      ),
      const SizedBox(height: HiqeoSpacing.xs),
      Center(
        child: TextButton(
          key: const ValueKey('profil-delete-account'),
          onPressed: _showDeleteAccount,
          child: Text(
            'Hapus akun',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ),
    ];
  }

  String _contactsSubtitle() {
    if (_contactsLoading) return 'Memuat…';
    if (_contactsFailed) return 'Kontak belum dapat dibaca';
    if (_contacts.isEmpty) return 'Belum ada kontak darurat';
    final contact = _contacts.first;
    return '${contact.name} · ${_contactStatusLabel(contact.consentStatus)}';
  }

  Future<void> _showContactsSheet() {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return _showSheet(
      title: 'Kontak darurat',
      subtitle: 'Hanya tersimpan di HP ini',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_contactsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: HiqeoSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_contactsFailed)
            Text(
              'Kontak darurat belum dapat dibaca dari HP ini.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            )
          else if (_contacts.isEmpty)
            Text(
              'Belum ada kontak darurat tersimpan di HP ini.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            )
          else
            for (final contact in _contacts)
              Padding(
                padding: const EdgeInsets.only(bottom: HiqeoSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(contact.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      '${_contactChannelLabel(contact.channel)} · '
                      '${contact.phoneE164}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    Text(
                      _contactStatusLabel(contact.consentStatus),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: HiqeoSpacing.sm),
          Text(
            'Penerusan SOS ke kontak darurat belum tersedia di build ini.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMapsSheet() {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return _showSheet(
      title: 'Peta terunduh',
      subtitle: downloadedMountainLabel(_downloadedMountains),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Status dibaca dari region peta yang benar-benar tersimpan di '
            'perangkat ini, bukan dari ingatan sesi aplikasi.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: HiqeoSpacing.lg),
          Text(
            'Unduhan peta offline memakai Mapbox dan memerlukan jaringan saat '
            'mengunduh. Setelah tersimpan, peta bisa dibuka tanpa sinyal.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: HiqeoSpacing.lg),
          _SheetAction(
            label: 'Buka Peta',
            onTap: () {
              Navigator.of(context).pop();
              context.go('/peta');
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showPowerSheet() {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return _showSheet(
      title: 'Profil daya',
      subtitle: _powerProfileLabel(_power.profile),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            _power.levelPercent == null
                ? 'Baterai belum terbaca.'
                : 'Baterai ${_power.levelPercent}%'
                    '${_power.isCharging ? ' · sedang diisi' : ''}.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: HiqeoSpacing.lg),
          for (final profile in PowerProfile.values)
            Padding(
              padding: const EdgeInsets.only(bottom: HiqeoSpacing.md),
              child: Text(
                '${_powerProfileLabel(profile)}: GPS tiap '
                '${PowerProfileConfig.of(profile).gpsInterval.inSeconds} detik, '
                '${PowerProfileConfig.of(profile).allowImages ? 'gambar aktif' : 'gambar nonaktif'}.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: profile == _power.profile
                      ? colors.textPrimary
                      : colors.textSecondary,
                ),
              ),
            ),
          Text(
            'Profil berubah otomatis mengikuti level baterai dan status '
            'pengisian.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPrivacySheet() {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return _showSheet(
      title: 'Privasi lokasi',
      subtitle: 'Belum ada berbagi lokasi',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Lokasi dan jejak pendakian hanya disimpan di HP ini. Belum ada '
            'transport yang mengirim lokasi ke anggota grup atau server.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: HiqeoSpacing.md),
          Text(
            'Saat membuat Kartu Pendakian, titik awal dan akhir bisa '
            'disembunyikan sebelum kartu disimpan atau dibagikan.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: HiqeoSpacing.md),
          Text(
            'Kontrol berbagi lokasi untuk anggota grup belum tersedia di '
            'build ini.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showThemeSheet() {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: GlassSurface(
          borderRadius: HiqeoRadius.hero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.textSecondary.withValues(alpha: 0.4),
                      borderRadius:
                          BorderRadius.circular(HiqeoRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Tampilan', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 2),
                Text(
                  'Berlaku langsung tanpa memulai ulang aplikasi.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                for (final mode in const <ThemeMode>[
                  ThemeMode.system,
                  ThemeMode.light,
                  ThemeMode.dark,
                ])
                  _ThemeOption(
                    key: ValueKey<String>('profil-theme-${mode.name}'),
                    label: themeModeLabel(mode),
                    selected: _theme.mode == mode,
                    onTap: () async {
                      await _theme.setMode(mode);
                      if (sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSheet({
    required String title,
    String? subtitle,
    required Widget body,
  }) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
          ),
          child: GlassSurface(
            borderRadius: HiqeoRadius.hero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textSecondary.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: theme.textTheme.headlineSmall),
                      if (subtitle != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    child: body,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteAccount() {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Hapus akun'),
          content: const Text(
            'Penghapusan akun belum tersedia di build ini. Tidak ada akun '
            'atau data yang dihapus.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Tutup'),
            ),
          ],
        ),
      ),
    );
  }
}

String themeModeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.light => 'Terang',
      ThemeMode.dark => 'Gelap',
      ThemeMode.system => 'Ikuti sistem',
    };

String _powerProfileLabel(PowerProfile profile) => switch (profile) {
      PowerProfile.normal => 'Normal',
      PowerProfile.saver => 'Hemat',
      PowerProfile.critical => 'Kritis',
    };

String _contactStatusLabel(EmergencyContactConsentStatus status) =>
    switch (status) {
      EmergencyContactConsentStatus.granted => 'aktif',
      EmergencyContactConsentStatus.pending => 'menunggu persetujuan',
      EmergencyContactConsentStatus.revoked => 'persetujuan dicabut',
    };

String _contactChannelLabel(EmergencyContactChannel channel) =>
    switch (channel) {
      EmergencyContactChannel.sms => 'SMS',
      EmergencyContactChannel.whatsapp => 'WhatsApp',
    };

String _initialOf(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  final rune = trimmed.runes.first;
  return String.fromCharCode(rune).toUpperCase();
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({this.initial});

  final String? initial;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final signedIn = initial != null;
    return Center(
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: signedIn ? colors.primary : colors.surface,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: colors.glassShadow,
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Center(
          child: signedIn
              ? Text(
                  initial!,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        color: colors.onPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                )
              : HiqeoIcon(
                  HiqeoIcons.user,
                  size: 38,
                  color: colors.textPrimary,
                ),
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.summary, required this.failed});

  final ProfileSummary? summary;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final summary = this.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        GlassSurface(
          borderRadius: HiqeoRadius.card,
          padding: const EdgeInsets.symmetric(
            horizontal: HiqeoSpacing.sm,
            vertical: 20,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: _Stat(
                  key: const ValueKey('profil-stat-pendakian'),
                  value: summary?.hikeCountLabel ?? '—',
                  label: 'Pendakian',
                ),
              ),
              Expanded(
                child: _Stat(
                  key: const ValueKey('profil-stat-jarak'),
                  value: summary?.distanceLabel ?? '—',
                  label: 'Jarak',
                ),
              ),
              Expanded(
                child: _Stat(
                  key: const ValueKey('profil-stat-tanjakan'),
                  value: summary?.elevationGainLabel ?? '—',
                  label: 'Tanjakan',
                ),
              ),
            ],
          ),
        ),
        if (failed)
          Padding(
            padding: const EdgeInsets.only(top: HiqeoSpacing.sm),
            child: Text(
              'Data pendakian lokal belum dapat dibuka.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _GuestBenefitsCard extends StatelessWidget {
  const _GuestBenefitsCard();

  static const List<String> _benefits = <String>[
    'Grup dan undangan anggota',
    'SOS diteruskan ke kontak darurat',
    'Cadangan jejak pendakian',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return GlassSurface(
      borderRadius: HiqeoRadius.card,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Masuk untuk membuka', style: theme.textTheme.titleMedium),
          const SizedBox(height: HiqeoSpacing.md),
          for (final benefit in _benefits)
            Padding(
              padding: const EdgeInsets.only(bottom: HiqeoSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: HiqeoIcon(
                      HiqeoIcons.check,
                      size: 18,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: HiqeoSpacing.md),
                  Expanded(
                    child: Text(
                      benefit,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: HiqeoSpacing.xs),
          Text(
            'Penerusan SOS dan cadangan jejak belum tersedia di build ini.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthButtons extends StatelessWidget {
  const _AuthButtons({
    required this.enabled,
    required this.onGoogle,
    required this.onApple,
  });

  /// Celah dua tombol penyedia masuk.
  static const double _gap = 14;

  final bool enabled;
  final VoidCallback onGoogle;
  final VoidCallback onApple;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return Column(
      children: <Widget>[
        HiqeoButton(
          key: const ValueKey('profil-login-google'),
          label: 'Lanjutkan dengan Google',
          variant: HiqeoButtonVariant.secondary,
          leading: Image.asset(
            'assets/brand/google_g.png',
            width: 20,
            height: 20,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
          ),
          onPressed: enabled ? onGoogle : null,
        ),
        const SizedBox(height: _gap),
        HiqeoButton(
          key: const ValueKey('profil-login-apple'),
          label: 'Lanjutkan dengan Apple',
          leading: Image.asset(
            'assets/brand/apple_logo.png',
            height: 20,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            color: colors.onPrimary,
            colorBlendMode: BlendMode.srcIn,
            excludeFromSemantics: true,
          ),
          onPressed: enabled ? onApple : null,
        ),
      ],
    );
  }
}

class _ProviderPill extends StatelessWidget {
  const _ProviderPill({required this.provider});

  final AuthProviderKind provider;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final label = provider == AuthProviderKind.google
        ? 'Terhubung dengan Google'
        : 'Terhubung dengan Apple';
    return Semantics(
      label: label,
      child: GlassSurface(
        borderRadius: HiqeoRadius.pill,
        padding: const EdgeInsets.symmetric(
          horizontal: HiqeoSpacing.lg,
          vertical: 8,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (provider == AuthProviderKind.google)
                Image.asset(
                  'assets/brand/google_g.png',
                  width: 16,
                  height: 16,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                )
              else
                Image.asset(
                  'assets/brand/apple_logo.png',
                  height: 16,
                  fit: BoxFit.contain,
                  color: colors.textPrimary,
                  colorBlendMode: BlendMode.srcIn,
                  excludeFromSemantics: true,
                ),
              const SizedBox(width: HiqeoSpacing.sm),
              ExcludeSemantics(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfilRow extends StatelessWidget {
  const _ProfilRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final HiqeoIconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: GlassSurface(
        borderRadius: HiqeoRadius.card,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(HiqeoRadius.card),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: HiqeoSpacing.lg,
                vertical: 14,
              ),
              child: Row(
                children: <Widget>[
                  HiqeoIcon(
                    icon,
                    size: 24,
                    color: colors.textPrimary,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(title, style: theme.textTheme.titleMedium),
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
                  const SizedBox(width: HiqeoSpacing.sm),
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
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Keluar',
      child: Opacity(
        opacity: enabled ? 1 : 0.6,
        child: GlassSurface(
          borderRadius: HiqeoRadius.pill,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: const ValueKey('profil-sign-out'),
              borderRadius: BorderRadius.circular(HiqeoRadius.pill),
              onTap: enabled ? onTap : null,
              child: SizedBox(
                height: 56,
                child: Center(
                  child: Text(
                    'Keluar',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colors.textPrimary,
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
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
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(HiqeoRadius.card),
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (selected)
                HiqeoIcon(
                  HiqeoIcons.check,
                  size: 20,
                  color: colors.textPrimary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return SizedBox(
      height: 52,
      child: Material(
        color: colors.secondary,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: HiqeoSpacing.md),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: isError ? colors.warningText : colors.textSecondary,
        ),
      ),
    );
  }
}
