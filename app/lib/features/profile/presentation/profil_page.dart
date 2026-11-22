import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/supabase_config.dart';
import '../../../design/glass/hiqeo_liquid_glass.dart';
import '../../../design/layout.dart';
import '../../../design/theme_mode_controller.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/line_icons.dart';
import '../../../design/widgets/persistent_media_image.dart';
import '../../../infrastructure/auth/active_account_scope.dart';
import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_connection.dart';
import '../../../infrastructure/database/repositories/drift_tracking_repository.dart';
import '../../../infrastructure/power/power_profile_controller.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../../auth/application/account_controller.dart';
import '../../auth/domain/auth_service.dart';
import '../../auth/presentation/account_page.dart';
import '../../history/presentation/history_page.dart';
import '../../plus/application/plus_navigation.dart';
import '../../plus/application/plus_scope.dart';
import '../../social/presentation/friends_page.dart';
import '../../tracking/domain/tracking_repository.dart';
import '../domain/profile_summary.dart';
import 'settings_page.dart';

/// Profil tamu dan profil setelah masuk.
///
/// Susunan profil masuk (tanpa duplikasi dengan Pengaturan / Fitur Utama Beranda):
/// 1. Identitas (avatar 84 dp, nama, @username)
/// 2. Kartu statistik pendakian
/// 3. Hiqeo Plus -> Akun -> Riwayat -> Daftar teman -> Pengaturan
class ProfilPage extends StatefulWidget {
  const ProfilPage({
    super.key,
    this.accountController,
    this.powerController,
    this.themeController,
    this.trackingRepository,
    @Deprecated('Kontak darurat dipindahkan ke Fitur Utama Beranda')
    this.safetyRepository,
    @Deprecated('Kontak darurat dipindahkan ke Fitur Utama Beranda')
    this.contactPicker,
    this.downloadedMountainCount,
  });

  /// Disuntikkan untuk uji; produksi memakai layanan perangkat.
  final AccountController? accountController;
  final PowerProfileController? powerController;
  final ThemeModeController? themeController;
  final TrackingRepository? trackingRepository;
  final Object? safetyRepository;
  final Object? contactPicker;
  final Future<int> Function()? downloadedMountainCount;

  @override
  State<ProfilPage> createState() => _ProfilPageState();
}

class _ProfilPageState extends State<ProfilPage> {
  AppDatabase? _database;
  TrackingRepository? _tracking;

  late final AccountController _account;
  late final bool _ownsAccount;

  ProfileSummary? _summary;
  bool _summaryLoading = true;
  bool _summaryFailed = false;

  @override
  void initState() {
    super.initState();
    final shared = widget.accountController == null
        ? SupabaseServices.sharedAccountController
        : null;
    _ownsAccount = widget.accountController == null && shared == null;
    _account = widget.accountController ??
        shared ??
        SupabaseServices.createAccountController();
    _account.initialize();
    DriftTrackingRepository.historyRevision.addListener(_loadSummary);
    ActiveAccountScope.activeUserId.addListener(_onAccountChanged);
    unawaited(_openLocal());
  }

  @override
  void dispose() {
    ActiveAccountScope.activeUserId.removeListener(_onAccountChanged);
    DriftTrackingRepository.historyRevision.removeListener(_loadSummary);
    if (_ownsAccount) _account.dispose();
    final database = _database;
    if (database != null) {
      DriftTrackingRepository.unregisterDatabase(database);
      unawaited(database.close());
    }
    super.dispose();
  }

  void _onAccountChanged() {
    if (!mounted) return;
    setState(() {
      _summary = ProfileSummary.empty;
      _summaryFailed = false;
    });
    unawaited(_loadSummary());
  }

  Future<void> _openLocal() async {
    AppDatabase? database;
    try {
      if (widget.trackingRepository == null) {
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
    if (_tracking == null) {
      setState(() {
        _summaryLoading = false;
        _summaryFailed = true;
      });
    } else {
      await _loadSummary();
    }
  }

  Future<void> _loadSummary() async {
    final repository = _tracking;
    if (repository == null) return;
    try {
      final sessions = await repository.watchSessions().first;
      if (!mounted) return;
      setState(() {
        _summary = ProfileSummary.fromSessions(sessions);
        _summaryLoading = false;
        _summaryFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _summaryLoading = false;
        _summaryFailed = true;
      });
    }
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

  void _openSettings() {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.push('/pengaturan');
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SettingsPage(accountController: _account),
        ),
      );
    }
  }

  void _openHistory() {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.push('/riwayat');
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HistoryPage(repository: _tracking),
        ),
      );
    }
  }

  void _openFriends() {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.push('/teman');
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const FriendsPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = AppLayout.bottomInset(context);
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: _account,
        builder: (context, _) {
          final signedIn = _account.user != null;
          return RepaintBoundary(
            key: const ValueKey<String>('profil-scroll-boundary'),
            child: ListView(
              clipBehavior: Clip.hardEdge,
              padding: EdgeInsets.fromLTRB(
                16,
                24,
                16,
                bottomInset,
              ),
              children: <Widget>[
                Text(
                  'Profil',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 20),
                if (signedIn) ..._signedIn() else ..._guest(),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _guest() {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final enabled = _account.isConfigured && !_account.isBusy;
    final showApple = defaultTargetPlatform != TargetPlatform.android ||
        SupabaseConfig.isAppleConfigured;

    String? statusText;
    bool statusIsError = false;
    if (_account.isBusy) {
      statusText = 'Menghubungkan akun…';
    } else if (_account.error != null) {
      statusText = _account.error!;
      statusIsError = true;
    } else if (_account.notice != null) {
      statusText = _account.notice!;
    } else if (!_account.isConfigured) {
      statusText = 'Layanan masuk akun sedang tidak tersedia saat ini';
    }

    return <Widget>[
      const _ProfileAvatar(),
      const SizedBox(height: 16),
      Center(
        child: Text(
          'Pendaki tamu',
          style: theme.textTheme.headlineSmall,
        ),
      ),
      const SizedBox(height: 4),
      Center(
        child: Text(
          'Data pendakian tersimpan di HP ini',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ),
      const SizedBox(height: 20),
      _StatsCard(
        summary: _summary,
        loading: _summaryLoading,
        failed: _summaryFailed,
      ),
      const SizedBox(height: 12),
      _PlusAndSettingsSection(
        onOpenSettings: _openSettings,
        onOpenHistory: _openHistory,
        showAccountRow: false,
      ),
      const SizedBox(height: 12),
      const _GuestBenefitsCard(),
      // Spasi profil tamu terukur: 16 dp di bawah kartu "Masuk untuk membuka",
      // 12 dp di atas tombol Google (berlaku juga pada status gagal login).
      if (statusText != null) ...<Widget>[
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            statusText,
            key: ValueKey<String>(
              statusIsError ? 'guest-status-error' : 'guest-status-text',
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: statusIsError ? colors.warningText : colors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 12),
      ] else
        const SizedBox(height: 16),
      _AuthButtons(
        enabled: enabled,
        isBusy: _account.isBusy,
        showApple: showApple,
        onGoogle: () => _signIn(AuthProviderKind.google),
        onApple: () => _signIn(AuthProviderKind.apple),
      ),
      // Catatan kaki 16 dp di bawah tombol, rata tengah, margin horizontal 12.
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          'Isi pesanmu tidak dibaca server. Lokasi hanya tersimpan di HP ini '
          'kecuali kamu menyalakan berbagi lokasi di grup.',
          key: const ValueKey<String>('guest-privacy-footnote'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ),
    ];
  }

  List<Widget> _signedIn() {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final user = _account.user!;
    final profile = _account.profile;
    final name = profile?.fullName?.trim().isNotEmpty == true
        ? profile!.fullName!.trim()
        : (user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : (profile?.username ?? 'Pendaki'));
    final avatarUrl = profile?.avatarUrl?.trim().isNotEmpty == true
        ? profile!.avatarUrl!.trim()
        : user.avatarUrl;
    final localAvatarPath = profile?.localAvatarPath ?? _account.localAvatarPath;
    final hasUsername =
        profile?.username != null && profile!.username!.isNotEmpty;
    final profileCompleted = hasUsername || (profile?.isProfileComplete ?? false);
    final handle = hasUsername
        ? '@${profile.username}'
        : (profileCompleted || _account.isLoading
            ? ''
            : 'Username belum dibuat');

    return <Widget>[
      // 1. Identitas (avatar 84 dp, nama, @username)
      _ProfileAvatar(
        initial: _initialOf(name),
        avatarUrl: avatarUrl,
        localAvatarPath: localAvatarPath,
      ),
      const SizedBox(height: 14),
      Center(
        child: Text(name, style: theme.textTheme.headlineSmall),
      ),
      if (handle.isNotEmpty) ...<Widget>[
        const SizedBox(height: 4),
        Center(
          child: Text(
            handle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
      if (_account.deviceKeyMismatch) ...<Widget>[
        const SizedBox(height: 8),
        Text(
          'Kunci perangkat berbeda dari direktori. Buka Akun untuk '
          'mendaftarkan ulang kunci.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: colors.warningText),
        ),
      ],
      const SizedBox(height: 20),

      // 2. Kartu statistik
      _StatsCard(
        summary: _summary,
        loading: _summaryLoading,
        failed: _summaryFailed,
      ),
      const SizedBox(height: 12),

      // 3. Hiqeo Plus -> Akun -> Riwayat -> Daftar teman -> Pengaturan
      _PlusAndSettingsSection(
        onOpenSettings: _openSettings,
        onOpenHistory: _openHistory,
        onOpenFriends: _openFriends,
        showAccountRow: true,
        onOpenAccount: _openAccount,
      ),
    ];
  }
}

String themeModeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.light => 'Terang',
      ThemeMode.dark => 'Gelap',
      ThemeMode.system => 'Ikuti sistem',
    };

String _initialOf(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  final rune = trimmed.runes.first;
  return String.fromCharCode(rune).toUpperCase();
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    this.initial,
    this.avatarUrl,
    this.localAvatarPath,
  });

  final String? initial;
  final String? avatarUrl;
  final String? localAvatarPath;

  static const double _size = 84;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final signedIn = initial != null;
    final fallbackChild = Center(
      child: signedIn
          ? Text(
              initial!,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: colors.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            )
          : HiqeoIcon(
              HiqeoIcons.user,
              size: 36,
              color: colors.textPrimary,
            ),
    );

    final File? cachedFile =
        AccountController.cachedLocalAvatarFile(localAvatarPath);

    final Widget imageOrFallback;
    if (cachedFile != null) {
      imageOrFallback = ClipOval(
        child: Image.file(
          cachedFile,
          key: const ValueKey<String>('profil-avatar-local-file'),
          width: _size,
          height: _size,
          cacheWidth: 256,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            if (avatarUrl != null && avatarUrl!.trim().isNotEmpty) {
              return PersistentMediaImage(
                url: avatarUrl!,
                width: _size,
                height: _size,
                cacheWidth: 256,
                fit: BoxFit.cover,
                enableRetryOnTap: false,
                placeholder: fallbackChild,
                errorBuilder: (_) => fallbackChild,
              );
            }
            return fallbackChild;
          },
        ),
      );
    } else if (avatarUrl != null && avatarUrl!.trim().isNotEmpty) {
      imageOrFallback = ClipOval(
        child: PersistentMediaImage(
          url: avatarUrl!,
          width: _size,
          height: _size,
          cacheWidth: 256,
          fit: BoxFit.cover,
          enableRetryOnTap: false,
          placeholder: fallbackChild,
          errorBuilder: (_) => fallbackChild,
        ),
      );
    } else {
      imageOrFallback = fallbackChild;
    }

    return Center(
      child: Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: signedIn ? colors.primary : colors.surface,
          border: Border.all(
            color: colors.glassBorder,
            width: 1.5,
          ),
        ),
        child: imageOrFallback,
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.summary,
    required this.loading,
    required this.failed,
  });

  final ProfileSummary? summary;
  final bool loading;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final summary = this.summary;
    final showLoadingSkeleton = loading && summary == null && !failed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        HiqeoGlassCard(
          borderRadius: 24,
          padding: const EdgeInsets.symmetric(
            horizontal: HiqeoSpacing.sm,
            vertical: 20,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: _Stat(
                  key: const ValueKey<String>('profil-stat-pendakian'),
                  value: summary?.hikeCountLabel ?? '—',
                  label: 'Pendakian',
                  loading: showLoadingSkeleton,
                ),
              ),
              Expanded(
                child: _Stat(
                  key: const ValueKey<String>('profil-stat-jarak'),
                  value: summary?.distanceLabel ?? '—',
                  label: 'Jarak',
                  loading: showLoadingSkeleton,
                ),
              ),
              Expanded(
                child: _Stat(
                  key: const ValueKey<String>('profil-stat-tanjakan'),
                  value: summary?.elevationGainLabel ?? '—',
                  label: 'Tanjakan',
                  loading: showLoadingSkeleton,
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
  const _Stat({
    super.key,
    required this.value,
    required this.label,
    this.loading = false,
  });

  final String value;
  final String label;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        if (loading)
          Container(
            width: 44,
            height: 26,
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: colors.hairline.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(8),
            ),
          )
        else
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
    'Grup dan obrolan terenkripsi',
    'Undang teman lewat username',
    'Berbagi lokasi terakhir saat mendaki',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return HiqeoGlassCard(
      key: const ValueKey<String>('guest-benefits-card'),
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Masuk untuk membuka', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final benefit in _benefits)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      benefit,
                      style: theme.textTheme.bodyMedium,
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

class _AuthButtons extends StatelessWidget {
  const _AuthButtons({
    required this.enabled,
    this.isBusy = false,
    required this.showApple,
    required this.onGoogle,
    required this.onApple,
  });

  final bool enabled;
  final bool isBusy;
  final bool showApple;
  final VoidCallback onGoogle;
  final VoidCallback onApple;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return Column(
      children: <Widget>[
        HiqeoButton(
          key: const ValueKey<String>('profil-login-google'),
          label: isBusy ? 'Menghubungkan…' : 'Lanjutkan dengan Google',
          variant: HiqeoButtonVariant.secondary,
          isLoading: isBusy,
          leading: Image.asset(
            'assets/brand/google_g.png',
            width: 20,
            height: 20,
            cacheWidth: 96,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
          ),
          onPressed: enabled && !isBusy ? onGoogle : null,
        ),
        if (showApple) ...<Widget>[
          const SizedBox(height: 12),
          HiqeoButton(
            key: const ValueKey<String>('profil-login-apple'),
            label: 'Lanjutkan dengan Apple',
            leading: Image.asset(
              'assets/brand/apple_logo.png',
              height: 20,
              cacheWidth: 96,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              color: colors.onPrimary,
              colorBlendMode: BlendMode.srcIn,
              excludeFromSemantics: true,
            ),
            onPressed: enabled ? onApple : null,
          ),
        ],
      ],
    );
  }
}

/// Baris menu Hiqeo Plus, Akun, Riwayat, Daftar teman, dan Pengaturan.
class _PlusAndSettingsSection extends StatelessWidget {
  const _PlusAndSettingsSection({
    required this.onOpenSettings,
    required this.onOpenHistory,
    required this.showAccountRow,
    this.onOpenFriends,
    this.onOpenAccount,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onOpenHistory;
  final VoidCallback? onOpenFriends;
  final bool showAccountRow;
  final VoidCallback? onOpenAccount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const RepaintBoundary(
          key: ValueKey<String>('profil-plus-card-boundary'),
          child: _HiqeoPlusRow(),
        ),
        if (showAccountRow && onOpenAccount != null) ...<Widget>[
          const SizedBox(height: 8),
          _ProfilRow(
            key: const ValueKey<String>('profil-row-akun'),
            icon: HiqeoIcons.user,
            title: 'Akun',
            subtitle: 'Username dan akun Google',
            onTap: onOpenAccount!,
          ),
        ],
        const SizedBox(height: 8),
        _ProfilRow(
          key: const ValueKey<String>('profil-row-riwayat'),
          icon: HiqeoIcons.clock,
          title: 'Riwayat',
          subtitle: 'Catatan & detail pendakian offline',
          onTap: onOpenHistory,
        ),
        if (showAccountRow && onOpenFriends != null) ...<Widget>[
          const SizedBox(height: 8),
          _ProfilRow(
            key: const ValueKey<String>('profil-row-teman'),
            icon: HiqeoIcons.group,
            title: 'Daftar teman',
            subtitle: 'Teman dan permintaan pertemanan',
            onTap: onOpenFriends!,
          ),
        ],
        const SizedBox(height: 8),
        _ProfilRow(
          key: const ValueKey<String>('profil-row-pengaturan'),
          icon: HiqeoIcons.more,
          title: 'Pengaturan',
          subtitle: 'Izin, tema, privasi, dan cache',
          onTap: onOpenSettings,
        ),
      ],
    );
  }
}

class _HiqeoPlusRow extends StatelessWidget {
  const _HiqeoPlusRow();

  @override
  Widget build(BuildContext context) {
    final plus = PlusScope.maybeOf(context);
    final hasPlus = plus?.hasPlus ?? false;
    final access = plus?.access;
    final lifetime = access?.lifetime ?? false;
    final grace = access?.isGrace ?? false;
    final everPurchased = access?.planId != null;
    final planTitle = plus?.currentPlan?.title ?? 'Plus';
    final String subtitle;
    if (lifetime) {
      subtitle = '$planTitle · berlaku selamanya';
    } else if (hasPlus && grace) {
      subtitle = '$planTitle · masa tenggang';
    } else if (hasPlus) {
      subtitle = '$planTitle · aktif';
    } else if (everPurchased) {
      subtitle = '$planTitle · berakhir';
    } else {
      subtitle = 'Cuaca rute, estimasi, analitik, dan rekap';
    }
    return _ProfilRow(
      key: const ValueKey<String>('profil-row-plus'),
      icon: HiqeoIcons.mountain,
      title: 'Hiqeo Plus',
      subtitle: subtitle,
      onTap: () {
        if (hasPlus || everPurchased) {
          context.push(PlusRoutes.manage);
        } else {
          openPlusPaywall(context);
        }
      },
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
      child: HiqeoGlassCard(
        borderRadius: 24,
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.secondary,
                    ),
                    child: Center(
                      child: HiqeoIcon(
                        icon,
                        size: 22,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
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
                  const SizedBox(width: 8),
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
