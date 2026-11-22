import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../design/background/app_background.dart';
import '../../../design/glass/hiqeo_liquid_glass.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../infrastructure/storage/avatar_image_processor.dart';
import '../../../infrastructure/storage/r2_uploader.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../application/account_controller.dart';
import '../domain/username_policy.dart';

/// Halaman/Kartu Onboarding Profil wajib untuk pengguna yang baru pertama kali
/// masuk lewat Google atau Apple sebelum masuk ke Beranda.
///
/// Berisi:
/// - Foto profil (opsional — ada opsi "Lewati")
/// - Nama tampilan (wajib, maks 40 karakter)
/// - Username (wajib, dengan pengecekan ketersediaan realtime)
class ProfileOnboardingPage extends StatefulWidget {
  ProfileOnboardingPage({
    super.key,
    AccountController? controller,
    this.nextRoute = '/beranda',
    this.pickAvatarBytes,
    this.avatarUploader,
    this.onCompleted,
  })  : _controller =
            controller ??
                SupabaseServices.sharedAccountController ??
                SupabaseServices.createAccountController(),
        _ownsController =
            controller == null &&
                SupabaseServices.sharedAccountController == null;

  final AccountController _controller;
  final bool _ownsController;
  final String nextRoute;
  final Future<Uint8List?> Function(ImageSource source)? pickAvatarBytes;
  final R2Uploader? avatarUploader;
  final VoidCallback? onCompleted;

  @override
  State<ProfileOnboardingPage> createState() => _ProfileOnboardingPageState();
}

class _ProfileOnboardingPageState extends State<ProfileOnboardingPage> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _usernameCtrl = TextEditingController();
  Timer? _debounce;
  int _checkGen = 0;

  Uint8List? _selectedAvatarWebp;
  bool _avatarSkipped = false;
  bool _checkingUsername = false;
  bool? _usernameAvailable;
  String? _usernameStatusError;
  String? _nameError;
  String? _submitError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    widget._controller.initialize();
    final user = widget._controller.user;
    final profile = widget._controller.profile;
    final initialName = profile?.fullName?.trim().isNotEmpty == true
        ? profile!.fullName!.trim()
        : (user?.displayName?.trim() ?? '');
    if (initialName.isNotEmpty) {
      _nameCtrl.text = initialName;
      _nameError = UsernamePolicy.validateDisplayName(
        initialName,
        userEmail: user?.email,
      );
    }
    final initialUsername = profile?.username?.trim() ?? '';
    if (initialUsername.isNotEmpty) {
      _usernameCtrl.text = initialUsername;
      _scheduleAvailabilityCheck(initialUsername);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    if (widget._ownsController) {
      widget._controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      Uint8List? rawBytes;
      if (widget.pickAvatarBytes != null) {
        rawBytes = await widget.pickAvatarBytes!(ImageSource.gallery);
      } else {
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 2160,
          maxHeight: 2160,
        );
        if (picked != null) {
          rawBytes = await picked.readAsBytes();
        }
      }
      if (rawBytes == null || rawBytes.isEmpty || !mounted) return;
      final webp =
          await AvatarImageProcessor.cropSquareAndCompressWebp(rawBytes);
      if (!mounted) return;
      setState(() {
        _selectedAvatarWebp = webp;
        _avatarSkipped = false;
        _submitError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitError = 'Foto belum bisa diproses. Kamu bisa lewati dulu atau pilih foto lain.';
      });
    }
  }

  void _skipPhoto() {
    setState(() {
      _selectedAvatarWebp = null;
      _avatarSkipped = true;
    });
  }

  void _onNameChanged(String value) {
    final userEmail = widget._controller.user?.email;
    setState(() {
      _nameError = UsernamePolicy.validateDisplayName(value, userEmail: userEmail);
      _submitError = null;
    });
  }

  void _onUsernameChanged(String value) {
    _scheduleAvailabilityCheck(value);
  }

  void _scheduleAvailabilityCheck(String rawValue) {
    _debounce?.cancel();
    final userEmail = widget._controller.user?.email;
    final validation = UsernamePolicy.validate(rawValue, userEmail: userEmail);

    if (rawValue.trim().isEmpty) {
      _checkGen++;
      setState(() {
        _checkingUsername = false;
        _usernameAvailable = null;
        _usernameStatusError = null;
        _submitError = null;
      });
      return;
    }

    if (!validation.isValid) {
      _checkGen++;
      setState(() {
        _checkingUsername = false;
        _usernameAvailable = false;
        _usernameStatusError = validation.errorMessage;
        _submitError = null;
      });
      return;
    }

    setState(() {
      _checkingUsername = true;
      _usernameAvailable = null;
      _usernameStatusError = null;
      _submitError = null;
    });

    final gen = ++_checkGen;
    _debounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_runAvailabilityCheck(validation.normalized, gen));
    });
  }

  Future<void> _runAvailabilityCheck(String username, int gen) async {
    final result = await widget._controller.checkUsernameAvailability(username);
    if (!mounted || gen != _checkGen) return;
    setState(() {
      _checkingUsername = false;
      _usernameAvailable = result.available;
      if (result.available) {
        _usernameStatusError = null;
      } else if (result.reason == 'taken') {
        _usernameStatusError = 'Username sudah dipakai. Pilih yang lain.';
      } else if (result.reason == 'blocked') {
        _usernameStatusError = 'Username ini tidak diperbolehkan. Pilih yang lain.';
      } else if (result.reason == 'network_error') {
        _usernameStatusError = 'Tidak bisa mengecek sekarang. Periksa koneksi internet.';
      } else {
        _usernameStatusError = 'Format username tidak sesuai aturan.';
      }
    });
  }

  Future<void> _submit() async {
    final userEmail = widget._controller.user?.email;
    final nameErr = UsernamePolicy.validateDisplayName(
      _nameCtrl.text,
      userEmail: userEmail,
    );
    final usernameVal = UsernamePolicy.validate(
      _usernameCtrl.text,
      userEmail: userEmail,
    );
    if (nameErr != null || !usernameVal.isValid) {
      setState(() {
        _nameError = nameErr;
        _usernameStatusError = usernameVal.errorMessage;
      });
      return;
    }

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    final err = await widget._controller.completeOnboardingProfile(
      fullName: _nameCtrl.text.trim(),
      username: usernameVal.normalized,
      avatarWebpBytes: _selectedAvatarWebp,
      avatarUploader: widget.avatarUploader,
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _submitting = false;
        _submitError = err;
      });
      return;
    }

    if (widget.onCompleted != null) {
      widget.onCompleted!();
      return;
    }
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.go(widget.nextRoute);
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final userEmail = widget._controller.user?.email;
    final nameValid = UsernamePolicy.validateDisplayName(
          _nameCtrl.text,
          userEmail: userEmail,
        ) ==
        null;
    final usernameVal = UsernamePolicy.validate(
      _usernameCtrl.text,
      userEmail: userEmail,
    );
    final canSubmit = !_submitting &&
        !_checkingUsername &&
        nameValid &&
        usernameVal.isValid &&
        _usernameAvailable == true;

    return PopScope(
      canPop: false,
      child: AppBackground(
        page: AppBackgroundPage.pengaturan,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Lengkapi profilmu',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Atur nama dan username unik sebelum mulai memakai Hiqeo.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Kartu Onboarding Utama
                  HiqeoGlassCard(
                    key: const ValueKey<String>('profile-onboarding-card'),
                    borderRadius: 26,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        // 1. Foto Profil (Opsional)
                        Row(
                          children: <Widget>[
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colors.secondary,
                                border: Border.all(color: colors.hairline),
                              ),
                              child: _selectedAvatarWebp != null
                                  ? ClipOval(
                                      child: Image.memory(
                                        _selectedAvatarWebp!,
                                        width: 72,
                                        height: 72,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : Icon(
                                      Icons.person_outline_rounded,
                                      size: 32,
                                      color: colors.textSecondary,
                                    ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    'Foto profil (opsional)',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _selectedAvatarWebp != null
                                        ? 'Foto dipilih'
                                        : (_avatarSkipped
                                            ? 'Dilewati. Kamu bisa mengaturnya nanti di Akun.'
                                            : 'Tambahkan foto atau lewati untuk sekarang.'),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: <Widget>[
                                      SizedBox(
                                        height: 44,
                                        child: FilledButton.tonal(
                                          key: const ValueKey<String>(
                                            'onboarding-pick-photo',
                                          ),
                                          onPressed: _submitting ? null : _pickPhoto,
                                          child: Text(
                                            _selectedAvatarWebp != null
                                                ? 'Ganti foto'
                                                : 'Pilih foto',
                                          ),
                                        ),
                                      ),
                                      if (!_avatarSkipped || _selectedAvatarWebp != null)
                                        SizedBox(
                                          height: 44,
                                          child: TextButton(
                                            key: const ValueKey<String>(
                                              'onboarding-skip-photo',
                                            ),
                                            onPressed:
                                                _submitting ? null : _skipPhoto,
                                            child: const Text('Lewati'),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // 2. Nama Tampilan (Wajib)
                        TextField(
                          key: const ValueKey<String>('onboarding-name-input'),
                          controller: _nameCtrl,
                          enabled: !_submitting,
                          maxLength: AccountController.maxAccountNameLength,
                          textCapitalization: TextCapitalization.words,
                          onChanged: _onNameChanged,
                          decoration: InputDecoration(
                            labelText: 'Nama tampilan *',
                            hintText: 'Contoh: Raka Pratama',
                            counterText: '',
                            filled: true,
                            fillColor: colors.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            errorText: _nameError,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // 3. Username (Wajib + Cek Ketersediaan Realtime)
                        TextField(
                          key: const ValueKey<String>('onboarding-username-input'),
                          controller: _usernameCtrl,
                          enabled: !_submitting,
                          autocorrect: false,
                          enableSuggestions: false,
                          maxLength: UsernamePolicy.maxLength,
                          onChanged: _onUsernameChanged,
                          decoration: InputDecoration(
                            labelText: 'Username *',
                            hintText: 'huruf kecil, angka, titik, _',
                            prefixText: '@',
                            counterText: '',
                            filled: true,
                            fillColor: colors.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            suffixIcon: _checkingUsername
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : (_usernameAvailable == true
                                    ? Icon(
                                        Icons.check_circle_rounded,
                                        key: const ValueKey<String>(
                                          'onboarding-username-available-icon',
                                        ),
                                        color: colors.primary,
                                      )
                                    : null),
                            errorText: _usernameStatusError,
                            errorMaxLines: 2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _checkingUsername
                              ? 'Mengecek ketersediaan username…'
                              : (_usernameAvailable == true
                                  ? 'Username @${usernameVal.normalized} tersedia.'
                                  : '3–20 karakter huruf kecil, angka, titik (.), atau garis bawah (_).'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _usernameAvailable == true
                                ? colors.primary
                                : colors.textSecondary,
                            fontWeight: _usernameAvailable == true
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),

                        if (_submitError != null) ...<Widget>[
                          const SizedBox(height: 12),
                          Text(
                            _submitError!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.warningText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),

                        SizedBox(
                          height: 52,
                          child: HiqeoButton(
                            key: const ValueKey<String>('onboarding-submit-button'),
                            label: _submitting ? 'Menyimpan…' : 'Simpan profil',
                            isLoading: _submitting,
                            onPressed: canSubmit ? _submit : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: SizedBox(
                      height: 44,
                      child: TextButton(
                        key: const ValueKey<String>('onboarding-signout-button'),
                        onPressed: _submitting
                            ? null
                            : () async {
                                await widget._controller.signOut();
                                if (!context.mounted) return;
                                final router = GoRouter.maybeOf(context);
                                if (router != null) {
                                  router.go('/beranda');
                                }
                              },
                        child: Text(
                          'Keluar akun',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
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
