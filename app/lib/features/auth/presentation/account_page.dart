import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../design/widgets/hiqeo_back_button.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/supabase_config.dart';
import '../../../design/background/app_background.dart';
import '../../../design/glass/glass_surface.dart';
import '../../../design/glass/hiqeo_liquid_glass.dart';
import '../../../design/layout.dart';
import '../../../design/system_ui.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/account_badges.dart';
import '../../../design/widgets/fullscreen_avatar_viewer_page.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/line_icons.dart';
import '../../../design/widgets/persistent_media_image.dart';
import '../../../infrastructure/database/database_connection.dart';
import '../../../infrastructure/storage/avatar_image_processor.dart';
import '../../../infrastructure/storage/r2_uploader.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../application/account_controller.dart';
import '../domain/auth_service.dart';
import '../domain/username_policy.dart';
import 'change_username_sheet.dart';

/// Halaman Akun: mengelola username (dengan jeda 7 hari & moderasi server),
/// penautan akun Google/Apple, ganti akun, keluar, dan hapus akun.
///
/// Seluruh tampilan grup dan undangan telah dipindahkan ke tab Grup.
class AccountPage extends StatefulWidget {
  AccountPage({
    super.key,
    AccountController? controller,
    this.returnToRoute,
    this.onClearAllLocalData,
    this.pickAvatarBytes,
    this.avatarUploader,
    this.bannerDismissDuration = const Duration(milliseconds: 4500),
  })  : _controller =
            controller ??
                SupabaseServices.sharedAccountController ??
                SupabaseServices.createAccountController(),
        _ownsController =
            controller == null &&
                SupabaseServices.sharedAccountController == null;

  final AccountController _controller;
  final bool _ownsController;
  final String? returnToRoute;
  final Future<void> Function()? onClearAllLocalData;
  final Future<Uint8List?> Function(ImageSource source)? pickAvatarBytes;
  final R2Uploader? avatarUploader;
  final Duration bannerDismissDuration;

  /// Jarak vertikal konsisten di atas dan di bawah tombol "Hapus akun"
  /// agar simetris antara tombol "Keluar" dan tepi atas navbar mengambang.
  static const double deleteActionGap = 28.0;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool _deletingAccount = false;
  late bool _wasSignedIn;
  bool _returnedAfterLogin = false;
  Timer? _bannerAutoDismissTimer;
  Timer? _bannerClearTimer;
  String? _activeBannerKey;
  String? _displayedBannerMessage;
  bool _displayedBannerIsError = false;
  bool _bannerVisible = false;

  @override
  void initState() {
    super.initState();
    _wasSignedIn = widget._controller.user != null;
    widget._controller.addListener(_handleControllerChanged);
    widget._controller.initialize();
    _syncStatusBanner(scheduleSetState: false);
  }

  @override
  void didUpdateWidget(covariant AccountPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._controller != widget._controller) {
      oldWidget._controller.removeListener(_handleControllerChanged);
      _wasSignedIn = widget._controller.user != null;
      _returnedAfterLogin = false;
      widget._controller.addListener(_handleControllerChanged);
      _syncStatusBanner(scheduleSetState: false);
    }
  }

  @override
  void dispose() {
    widget._controller.removeListener(_handleControllerChanged);
    _bannerAutoDismissTimer?.cancel();
    _bannerClearTimer?.cancel();
    if (widget._ownsController) widget._controller.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    _syncStatusBanner(scheduleSetState: true);
    _checkReturnAfterLogin();
  }

  void _checkReturnAfterLogin() {
    final returnTo = widget.returnToRoute;
    if (returnTo == null || returnTo.isEmpty || _returnedAfterLogin) return;
    final signedInNow = widget._controller.user != null;
    if (_wasSignedIn || !signedInNow) {
      _wasSignedIn = signedInNow;
      return;
    }
    if (widget._controller.isLoading || !widget._controller.isProfileResolved) {
      return;
    }
    _wasSignedIn = true;
    _returnedAfterLogin = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final router = GoRouter.maybeOf(context);
      if (widget._controller.needsProfileOnboarding) {
        if (router != null) {
          router.go('/lengkapi-profil?next=${Uri.encodeQueryComponent(returnTo)}');
        }
        return;
      }
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      } else if (router != null) {
        router.go(returnTo);
      }
    });
  }

  void _syncStatusBanner({required bool scheduleSetState}) {
    final err = widget._controller.error?.trim();
    final notice = widget._controller.notice?.trim();
    final nextMsg = (err != null && err.isNotEmpty)
        ? err
        : ((notice != null && notice.isNotEmpty) ? notice : null);
    final isErr = err != null && err.isNotEmpty;
    final nextKey = nextMsg == null ? null : '${isErr ? 'e' : 'n'}:$nextMsg';

    if (nextKey == _activeBannerKey) return;

    _bannerAutoDismissTimer?.cancel();
    _bannerClearTimer?.cancel();

    if (nextKey == null) {
      _activeBannerKey = null;
      if (_bannerVisible && scheduleSetState && mounted) {
        setState(() => _bannerVisible = false);
      } else {
        _bannerVisible = false;
      }
      return;
    }

    _activeBannerKey = nextKey;
    void applyVisible() {
      _displayedBannerMessage = nextMsg;
      _displayedBannerIsError = isErr;
      _bannerVisible = true;
    }

    if (scheduleSetState && mounted) {
      setState(applyVisible);
    } else {
      applyVisible();
    }

    _bannerAutoDismissTimer = Timer(widget.bannerDismissDuration, () {
      if (!mounted || _activeBannerKey != nextKey) return;
      setState(() => _bannerVisible = false);
      _bannerClearTimer = Timer(const Duration(milliseconds: 230), () {
        if (!mounted || _activeBannerKey != nextKey) return;
        if (isErr && widget._controller.error?.trim() == nextMsg) {
          widget._controller.clearError();
        } else if (!isErr && widget._controller.notice?.trim() == nextMsg) {
          widget._controller.clearNotice();
        }
      });
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openChangeUsername(AccountController controller) async {
    final saved = await showChangeUsernameSheet(
      context,
      controller: controller,
    );
    if (saved == true && mounted) {
      final username = controller.profile?.username;
      if (username != null && username.isNotEmpty) {
        _showSnack('Username diubah menjadi @$username.');
      }
    }
  }

  Future<void> _openChangeAccountName(AccountController controller) async {
    final current = controller.profile?.fullName?.trim().isNotEmpty == true
        ? controller.profile!.fullName!.trim()
        : (controller.user?.displayName?.trim() ?? '');
    final saved = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChangeAccountNameSheet(
        controller: controller,
        initialName: current,
      ),
    );
    if (saved == true && mounted) {
      _showSnack('Nama akun diperbarui.');
    }
  }

  Future<void> _openChangeAvatar(AccountController controller) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final colors = HiqeoColors.of(sheetCtx);
        final safeBottom = MediaQuery.paddingOf(sheetCtx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + safeBottom),
          child: GlassSurface(
            tier: GlassTier.panel,
            borderRadius: 28,
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                const SizedBox(height: 8),
                ListTile(
                  key: const ValueKey<String>('avatar-source-camera'),
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Ambil dari kamera'),
                  onTap: () => Navigator.of(sheetCtx).pop(ImageSource.camera),
                ),
                ListTile(
                  key: const ValueKey<String>('avatar-source-gallery'),
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Pilih dari galeri'),
                  onTap: () => Navigator.of(sheetCtx).pop(ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (source == null || !mounted) return;

    Uint8List? rawBytes;
    if (widget.pickAvatarBytes != null) {
      rawBytes = await widget.pickAvatarBytes!(source);
    } else {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2160,
        maxHeight: 2160,
      );
      if (picked != null) {
        rawBytes = await picked.readAsBytes();
      }
    }
    if (rawBytes == null || rawBytes.isEmpty || !mounted) return;

    try {
      final webpBytes =
          await AvatarImageProcessor.cropSquareAndCompressWebp(rawBytes);
      if (!mounted) return;
      final err = await controller.updateProfilePhoto(
        webpBytes,
        uploader: widget.avatarUploader,
      );
      if (!mounted) return;
      _showSnack(err ?? 'Foto profil diperbarui.');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AccountPage._openChangeAvatar failed: $e');
      }
      if (!mounted) return;
      _showSnack('Foto profil belum bisa diperbarui. Coba pilih foto lain.');
    }
  }

  Future<void> _confirmSignOut(AccountController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = HiqeoColors.of(dialogContext);
        return AlertDialog(
          backgroundColor: colors.surface,
          title: const Text('Keluar dari akun?'),
          content: const Text(
            'Kamu akan kembali ke mode tamu. Riwayat pendakian dan kontak '
            'darurat yang tersimpan di HP ini tidak akan dihapus.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Batal'),
            ),
            TextButton(
              key: const ValueKey<String>('account-confirm-signout'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Keluar'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await controller.signOut();
    if (!mounted) return;
    if (controller.user == null && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _confirmDeleteAccount(AccountController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const DeleteAccountConfirmDialog(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingAccount = true);
    final deleted = await controller.deleteAccount();
    if (!mounted) return;

    if (!deleted) {
      setState(() => _deletingAccount = false);
      if (controller.error != null) {
        _showSnack(controller.error!);
      }
      return;
    }

    try {
      final localClearer = widget.onClearAllLocalData;
      if (localClearer != null) {
        await localClearer();
      } else {
        await _wipeAllLocalData();
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() => _deletingAccount = false);
    _showSnack('Akun dan seluruh data telah dihapus.');

    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.go('/profil');
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _wipeAllLocalData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}
    try {
      final dbFile = await defaultAppDatabaseFile();
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
    } catch (_) {}
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

  Future<void> _confirmKeyReplacement(AccountController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ganti kunci perangkat?'),
        content: const Text(
          'Anggota grup harus membagikan ulang kunci. Pesan dan kunci grup '
          'lama yang hanya dimiliki kunci sebelumnya tidak dapat dipulihkan.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Ganti kunci'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.registerCurrentDeviceKey();
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);

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
            'Akun',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: ListenableBuilder(
            listenable: widget._controller,
            builder: (context, _) {
              final controller = widget._controller;
              if (!controller.isConfigured) {
                return _buildNotConfiguredView(context, colors, theme);
              }
              final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
              final inShell = HiqeoSystemInset.isPresent(context);
              final bottomOccupied = keyboardOpen
                  ? 0.0
                  : (inShell
                      ? HiqeoMetrics.floatingBottomInset(
                          HiqeoSystemInset.bottomOf(context),
                        )
                      : MediaQuery.paddingOf(context).bottom);
              final bottomSafePadding =
                  bottomOccupied + AccountPage.deleteActionGap;
              return RepaintBoundary(
                key: const ValueKey<String>('account-scroll-boundary'),
                child: ListView(
                  clipBehavior: Clip.hardEdge,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    bottomSafePadding,
                  ),
                  children: <Widget>[
                  if (controller.isLoading || controller.isBusy)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(),
                    ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _bannerVisible ? 1 : 0,
                      child: _bannerVisible && _displayedBannerMessage != null
                          ? _StatusBanner(
                              key: const ValueKey<String>(
                                'account-status-banner',
                              ),
                              message: _displayedBannerMessage!,
                              isError: _displayedBannerIsError,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                  if (controller.user == null)
                    _buildSignedOutView(context, controller, colors, theme)
                  else ...<Widget>[
                    _buildAvatarCard(context, controller, colors, theme),
                    const SizedBox(height: 12),
                    _buildAccountNameCard(context, controller, colors, theme),
                    const SizedBox(height: 12),
                    _buildUsernameCard(context, controller, colors, theme),
                    const SizedBox(height: 12),
                    if (controller.deviceKeyMismatch) ...<Widget>[
                      _buildKeyMismatchCard(context, controller, colors, theme),
                      const SizedBox(height: 12),
                    ],
                    _buildProviderCard(context, controller, colors, theme),
                    const SizedBox(height: 12),
                    _buildLinkedAccountsCard(context, controller, colors, theme),
                    const SizedBox(height: 16),
                    HiqeoButton(
                      key: const ValueKey<String>('account-switch-button'),
                      label: 'Ganti akun',
                      variant: HiqeoButtonVariant.secondary,
                      onPressed: controller.isBusy || _deletingAccount
                          ? null
                          : () => unawaited(
                                controller.switchAccount(
                                  controller.user?.provider ??
                                      AuthProviderKind.google,
                                ),
                              ),
                    ),
                    const SizedBox(height: 8),
                    HiqeoButton(
                      key: const ValueKey<String>('account-signout-button'),
                      label: 'Keluar',
                      variant: HiqeoButtonVariant.secondary,
                      onPressed: controller.isBusy || _deletingAccount
                          ? null
                          : () => unawaited(_confirmSignOut(controller)),
                    ),
                    const SizedBox(height: AccountPage.deleteActionGap),
                    Center(
                      child: TextButton(
                        key: const ValueKey<String>('account-delete-button'),
                        onPressed: controller.isBusy || _deletingAccount
                            ? null
                            : () =>
                                unawaited(_confirmDeleteAccount(controller)),
                        child: Text(
                          _deletingAccount ? 'Menghapus akun…' : 'Hapus akun',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.warningText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarCard(
    BuildContext context,
    AccountController controller,
    HiqeoColors colors,
    ThemeData theme,
  ) {
    final user = controller.user!;
    final profile = controller.profile;
    final avatarUrl = profile?.avatarUrl?.trim().isNotEmpty == true
        ? profile!.avatarUrl!.trim()
        : user.avatarUrl?.trim();
    final localPath = profile?.localAvatarPath ?? controller.localAvatarPath;
    final name = profile?.fullName?.trim().isNotEmpty == true
        ? profile!.fullName!.trim()
        : (user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : (profile?.username ?? 'Pendaki'));
    final initial = name.trim().isEmpty
        ? 'P'
        : String.fromCharCode(name.trim().runes.first).toUpperCase();
    final File? localFile = AccountController.cachedLocalAvatarFile(localPath);

    Widget avatarChild = Center(
      child: Text(
        initial,
        style: theme.textTheme.headlineSmall?.copyWith(
          color: colors.onPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    if (localFile != null) {
      avatarChild = ClipOval(
        child: Image.file(
          localFile,
          width: 64,
          height: 64,
          cacheWidth: 256,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => avatarChild,
        ),
      );
    } else if (avatarUrl != null && avatarUrl.isNotEmpty) {
      avatarChild = ClipOval(
        child: PersistentMediaImage(
          url: avatarUrl,
          width: 64,
          height: 64,
          cacheWidth: 256,
          fit: BoxFit.cover,
          enableRetryOnTap: false,
          placeholder: avatarChild,
          errorBuilder: (_) => avatarChild,
        ),
      );
    }

    final hasPhoto =
        localFile != null || (avatarUrl != null && avatarUrl.isNotEmpty);
    final avatarHeroTag = profileAvatarHeroTag('account_${user.id}');
    final isOfficial = (profile?.isOfficial == true) ||
        UsernamePolicy.isOfficialUsername(profile?.username);

    Widget avatarCircle = Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.primary,
      ),
      child: avatarChild,
    );
    if (hasPhoto) {
      avatarCircle = Semantics(
        button: true,
        label: 'Lihat foto profil $name',
        child: GestureDetector(
          key: const ValueKey<String>('account-avatar-tap'),
          onTap: () => unawaited(
            openFullscreenAvatarViewer(
              context,
              heroTag: avatarHeroTag,
              displayName: name,
              avatarUrl: avatarUrl,
              localFile: localFile,
              cacheKey: user.id,
              isOfficial: isOfficial,
            ),
          ),
          child: Hero(
            tag: avatarHeroTag,
            child: avatarCircle,
          ),
        ),
      );
    }

    return HiqeoGlassCard(
      key: const ValueKey<String>('account-avatar-card'),
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          avatarCircle,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Foto profil',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Ketuk Ubah untuk mengganti foto',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            key: const ValueKey<String>('account-change-avatar-button'),
            style: FilledButton.styleFrom(
              backgroundColor: colors.secondary,
              foregroundColor: colors.textPrimary,
              minimumSize: const Size(76, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(HiqeoRadius.pill),
              ),
            ),
            onPressed: controller.isBusy
                ? null
                : () => unawaited(_openChangeAvatar(controller)),
            child: const Text(
              'Ubah',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountNameCard(
    BuildContext context,
    AccountController controller,
    HiqeoColors colors,
    ThemeData theme,
  ) {
    final profile = controller.profile;
    final user = controller.user!;
    final resolved = profile?.fullName?.trim().isNotEmpty == true
        ? profile!.fullName!.trim()
        : (user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : (profile?.username?.trim().isNotEmpty == true
                ? profile!.username!.trim()
                : null));

    return HiqeoGlassCard(
      key: const ValueKey<String>('account-name-card'),
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Nama akun',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Expanded(
                child: Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        resolved ?? 'Belum diatur',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    if ((profile?.isOfficial == true) ||
                        UsernamePolicy.isOfficialUsername(
                          profile?.username,
                        )) ...<Widget>[
                      const SizedBox(width: 6),
                      const OfficialVerifiedBadge(size: 20),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                key: const ValueKey<String>('account-change-name-button'),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.secondary,
                  foregroundColor: colors.textPrimary,
                  minimumSize: const Size(76, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                  ),
                ),
                onPressed: controller.isBusy
                    ? null
                    : () => unawaited(_openChangeAccountName(controller)),
                child: const Text(
                  'Ganti',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Tampil di Beranda, Profil, dan ruang obrolan.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsernameCard(
    BuildContext context,
    AccountController controller,
    HiqeoColors colors,
    ThemeData theme,
  ) {
    final username = controller.profile?.username;
    final hasUsername = username != null && username.isNotEmpty;
    final cooldownDays = controller.usernameCooldownDaysRemaining;
    final nonCompliant = controller.hasNonCompliantUsername;

    final String limitNote;
    if (nonCompliant) {
      limitNote =
          'Username lamamu belum sesuai aturan baru. Kamu bisa langsung menggantinya sekarang.';
    } else if (cooldownDays > 0) {
      limitNote = 'Username baru bisa diganti lagi dalam $cooldownDays hari';
    } else {
      limitNote = 'Bisa diganti sekali tiap 7 hari.';
    }

    return HiqeoGlassCard(
      key: const ValueKey<String>('account-username-card'),
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Username',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  hasUsername ? '@$username' : 'Belum ada username',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                key: const ValueKey<String>('account-change-username-button'),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.secondary,
                  foregroundColor: colors.textPrimary,
                  minimumSize: const Size(76, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                  ),
                ),
                onPressed: controller.isBusy
                    ? null
                    : () => unawaited(_openChangeUsername(controller)),
                child: Text(
                  hasUsername ? 'Ganti' : 'Buat',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            limitNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: (cooldownDays > 0 || nonCompliant)
                  ? colors.warningText
                  : colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderCard(
    BuildContext context,
    AccountController controller,
    HiqeoColors colors,
    ThemeData theme,
  ) {
    final user = controller.user!;
    final isApple = user.provider == AuthProviderKind.apple;
    final providerLabel =
        isApple ? 'Masuk dengan Apple' : 'Masuk dengan Google';

    return HiqeoGlassCard(
      key: const ValueKey<String>('account-provider-card'),
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Akun yang digunakan',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.secondary,
                ),
                child: Center(
                  child: isApple
                      ? Image.asset(
                          'assets/brand/apple_logo.png',
                          height: 20,
                          cacheWidth: 96,
                          color: colors.textPrimary,
                          colorBlendMode: BlendMode.srcIn,
                          excludeFromSemantics: true,
                        )
                      : Image.asset(
                          'assets/brand/google_g.png',
                          width: 20,
                          height: 20,
                          cacheWidth: 96,
                          fit: BoxFit.contain,
                          excludeFromSemantics: true,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      user.email ?? user.displayName ?? 'Akun terhubung',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      providerLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLinkedAccountsCard(
    BuildContext context,
    AccountController controller,
    HiqeoColors colors,
    ThemeData theme,
  ) {
    final linkingProvider = controller.linkingProvider;
    final isGoogleLinked = controller.isProviderLinked(AuthProviderKind.google);
    final isAppleLinked = controller.isProviderLinked(AuthProviderKind.apple);
    final linkErr = controller.linkingError;
    final linkNotice = controller.linkingNotice;

    return HiqeoGlassCard(
      key: const ValueKey<String>('account-linked-accounts-card'),
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Akun tertaut',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tautkan Google dan Apple ke akun ini agar data tetap aman saat login dari Android maupun iOS.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          _LinkedProviderRow(
            rowKey: const ValueKey<String>('account-link-row-google'),
            buttonKey: const ValueKey<String>('account-link-button-google'),
            label: 'Google',
            icon: Image.asset(
              'assets/brand/google_g.png',
              width: 20,
              height: 20,
              cacheWidth: 96,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
            isLinked: isGoogleLinked,
            isLinking: linkingProvider == AuthProviderKind.google,
            disabled: controller.isBusy || linkingProvider != null,
            onLink: () => unawaited(
              controller.linkProvider(AuthProviderKind.google),
            ),
          ),
          Divider(color: colors.hairline, height: 20),
          _LinkedProviderRow(
            rowKey: const ValueKey<String>('account-link-row-apple'),
            buttonKey: const ValueKey<String>('account-link-button-apple'),
            label: 'Apple',
            icon: Image.asset(
              'assets/brand/apple_logo.png',
              height: 20,
              cacheWidth: 96,
              color: colors.textPrimary,
              colorBlendMode: BlendMode.srcIn,
              excludeFromSemantics: true,
            ),
            isLinked: isAppleLinked,
            isLinking: linkingProvider == AuthProviderKind.apple,
            disabled: controller.isBusy || linkingProvider != null,
            onLink: () => unawaited(
              controller.linkProvider(AuthProviderKind.apple),
            ),
          ),
          if (linkErr != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              linkErr,
              key: const ValueKey<String>('account-link-error'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.warningText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else if (linkNotice != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              linkNotice,
              key: const ValueKey<String>('account-link-notice'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKeyMismatchCard(
    BuildContext context,
    AccountController controller,
    HiqeoColors colors,
    ThemeData theme,
  ) {
    return HiqeoGlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      borderColor: colors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Kunci perangkat berbeda dari direktori',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.warningText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Kunci grup lama tidak dapat dibuka di perangkat ini. Daftarkan '
            'ulang kunci bila perangkat lama hilang atau direset.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          HiqeoButton(
            label: 'Daftarkan kunci perangkat ini',
            variant: HiqeoButtonVariant.secondary,
            onPressed: controller.isBusy
                ? null
                : () => unawaited(_confirmKeyReplacement(controller)),
          ),
        ],
      ),
    );
  }

  Widget _buildSignedOutView(
    BuildContext context,
    AccountController controller,
    HiqeoColors colors,
    ThemeData theme,
  ) {
    final showApple = defaultTargetPlatform != TargetPlatform.android ||
        SupabaseConfig.isAppleConfigured;
    return HiqeoGlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Masuk ke akun Hiqeo',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Kelola username publik dan sinkronisasi grup. Riwayat pendakian '
            'di HP ini tetap tersimpan lokal.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: HiqeoButton(
              label: 'Masuk dengan Google',
              variant: HiqeoButtonVariant.secondary,
              leading: Image.asset(
                'assets/brand/google_g.png',
                width: 20,
                height: 20,
                cacheWidth: 96,
                excludeFromSemantics: true,
              ),
              onPressed: controller.isBusy
                  ? null
                  : () => unawaited(controller.signIn(AuthProviderKind.google)),
            ),
          ),
          if (showApple) ...<Widget>[
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: HiqeoButton(
                label: 'Masuk dengan Apple',
                onPressed: controller.isBusy
                    ? null
                    : () =>
                        unawaited(controller.signIn(AuthProviderKind.apple)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNotConfiguredView(
    BuildContext context,
    HiqeoColors colors,
    ThemeData theme,
  ) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        AppLayout.bottomInset(context),
      ),
      children: <Widget>[
        HiqeoGlassCard(
          borderRadius: 24,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  HiqeoIcon(HiqeoIcons.lock, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Layanan akun sedang tidak tersedia',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Masuk akun dan pengaturan username belum dapat digunakan '
                'saat ini. Rekaman GPS, peta offline, kontak darurat, dan '
                'SOS tetap berjalan normal di HP ini.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    super.key,
    required this.message,
    this.isError = false,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isError
              ? colors.warning.withValues(alpha: 0.14)
              : colors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isError
                ? colors.warning.withValues(alpha: 0.45)
                : colors.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          message,
          style: TextStyle(
            fontSize: 13,
            color: isError ? colors.warningText : colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// Dialog konfirmasi bertingkat untuk penghapusan akun permanen (ketik HAPUS
/// atau tunggu hitung mundur 5 detik).
class DeleteAccountConfirmDialog extends StatefulWidget {
  const DeleteAccountConfirmDialog({super.key});

  @override
  State<DeleteAccountConfirmDialog> createState() =>
      _DeleteAccountConfirmDialogState();
}

class _DeleteAccountConfirmDialogState
    extends State<DeleteAccountConfirmDialog> {
  final TextEditingController _controller = TextEditingController();
  int _remainingSeconds = 5;
  Timer? _countdownTimer;

  bool get _canConfirm =>
      _controller.text.trim().toUpperCase() == 'HAPUS' ||
      _remainingSeconds <= 0;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        'Hapus akun permanen?',
        style: TextStyle(color: colors.warningText),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Tindakan ini tidak dapat dibatalkan. Akun Hiqeo dan seluruh '
            'data pendakian di HP ini akan dihapus permanen.',
          ),
          const SizedBox(height: HiqeoSpacing.md),
          Text(
            _remainingSeconds > 0
                ? 'Ketik HAPUS di bawah (atau tunggu $_remainingSeconds detik) untuk mengonfirmasi:'
                : 'Ketik HAPUS atau tekan tombol konfirmasi di bawah:',
          ),
          const SizedBox(height: HiqeoSpacing.sm),
          TextField(
            key: const ValueKey<String>('account-delete-confirm-input'),
            controller: _controller,
            maxLength: 16,
            decoration: const InputDecoration(
              hintText: 'HAPUS',
              counterText: '',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        TextButton(
          key: const ValueKey<String>('account-confirm-delete-button'),
          onPressed:
              _canConfirm ? () => Navigator.of(context).pop(true) : null,
          child: Text(
            'Hapus permanen',
            style: TextStyle(
              color: _canConfirm ? colors.warningText : colors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ChangeAccountNameSheet extends StatefulWidget {
  const _ChangeAccountNameSheet({
    required this.controller,
    required this.initialName,
  });

  final AccountController controller;
  final String initialName;

  @override
  State<_ChangeAccountNameSheet> createState() =>
      _ChangeAccountNameSheetState();
}

class _ChangeAccountNameSheetState extends State<_ChangeAccountNameSheet> {
  late final TextEditingController _input =
      TextEditingController(text: widget.initialName);
  String? _errorText;
  bool _hasEdited = false;
  bool _submitting = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  String? _validate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'Nama akun tidak boleh kosong.';
    }
    if (trimmed.length > AccountController.maxAccountNameLength) {
      return 'Nama akun maksimal ${AccountController.maxAccountNameLength} karakter.';
    }
    return null;
  }

  Future<void> _submit() async {
    final validationError = _validate(_input.text);
    if (validationError != null) {
      setState(() {
        _hasEdited = true;
        _errorText = validationError;
      });
      return;
    }
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    final error = await widget.controller.updateFullName(_input.text.trim());
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _submitting = false;
        _errorText = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final trimmed = _input.text.trim();
    final liveError =
        _errorText ?? (_hasEdited ? _validate(_input.text) : null);
    final canSave =
        !_submitting && _validate(_input.text) == null && trimmed != widget.initialName.trim();

    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardBottom),
      child: GlassSurface(
        key: const ValueKey<String>('change-name-sheet'),
        tier: GlassTier.panel,
        borderRadius: 28,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 28 + safeBottom),
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
                    borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Ganti nama akun',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Maksimal ${AccountController.maxAccountNameLength} karakter. Langsung tampil di Beranda, Profil, dan chat.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey<String>('change-name-input'),
                controller: _input,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.words,
                maxLength: AccountController.maxAccountNameLength,
                onChanged: (value) {
                  setState(() {
                    _hasEdited = true;
                    _errorText = _validate(value);
                  });
                },
                decoration: InputDecoration(
                  labelText: 'Nama akun',
                  hintText: 'Masukkan nama tampilan',
                  filled: true,
                  fillColor: colors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  errorText: liveError,
                  errorMaxLines: 2,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: HiqeoButton(
                  key: const ValueKey<String>('change-name-save-button'),
                  label: _submitting ? 'Menyimpan…' : 'Simpan nama',
                  isLoading: _submitting,
                  onPressed: canSave ? _submit : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkedProviderRow extends StatelessWidget {
  const _LinkedProviderRow({
    required this.rowKey,
    required this.buttonKey,
    required this.label,
    required this.icon,
    required this.isLinked,
    required this.isLinking,
    required this.disabled,
    required this.onLink,
  });

  final Key rowKey;
  final Key buttonKey;
  final String label;
  final Widget icon;
  final bool isLinked;
  final bool isLinking;
  final bool disabled;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);

    return Row(
      key: rowKey,
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.secondary,
          ),
          child: Center(child: icon),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              Text(
                isLinked ? 'Terhubung ke akun ini' : 'Belum ditautkan',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isLinked ? colors.primary : colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (isLinked)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: colors.secondary.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(HiqeoRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.check_rounded, size: 15, color: colors.primary),
                const SizedBox(width: 4),
                Text(
                  'Terhubung',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          )
        else
          FilledButton.tonal(
            key: buttonKey,
            style: FilledButton.styleFrom(
              backgroundColor: colors.secondary,
              foregroundColor: colors.textPrimary,
              minimumSize: const Size(84, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(HiqeoRadius.pill),
              ),
            ),
            onPressed: disabled ? null : onLink,
            child: isLinking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Tautkan',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
          ),
      ],
    );
  }
}
