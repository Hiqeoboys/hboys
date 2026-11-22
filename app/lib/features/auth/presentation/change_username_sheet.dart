import 'package:flutter/material.dart';

import '../../../design/glass/glass_surface.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/line_icons.dart';
import '../application/account_controller.dart';
import '../domain/username_policy.dart';

/// Menampilkan sheet kaca untuk mengganti username dengan validasi langsung,
/// daftar aturan, jeda 7 hari, dan penegakan moderasi sisi server.
Future<bool?> showChangeUsernameSheet(
  BuildContext context, {
  required AccountController controller,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (sheetContext) => _ChangeUsernameSheet(controller: controller),
  );
}

class _ChangeUsernameSheet extends StatefulWidget {
  const _ChangeUsernameSheet({required this.controller});

  final AccountController controller;

  @override
  State<_ChangeUsernameSheet> createState() => _ChangeUsernameSheetState();
}

class _ChangeUsernameSheetState extends State<_ChangeUsernameSheet> {
  late final TextEditingController _input;
  String? _serverError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController(
      text: widget.controller.profile?.username ?? '',
    );
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final validation = UsernamePolicy.validate(_input.text);
    if (!validation.isValid) {
      setState(() => _serverError = validation.errorMessage);
      return;
    }
    setState(() {
      _submitting = true;
      _serverError = null;
    });
    final error = await widget.controller.changeUsername(validation.normalized);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _submitting = false;
        _serverError = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
    final cooldownDays = widget.controller.usernameCooldownDaysRemaining;
    final isLocked = cooldownDays > 0;
    final currentUsername = widget.controller.profile?.username;
    final validation = UsernamePolicy.validate(_input.text);
    final isUnchanged = currentUsername != null &&
        currentUsername.toLowerCase() == validation.normalized;
    final canSave =
        !isLocked && !_submitting && validation.isValid && !isUnchanged;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardBottom),
      child: GlassSurface(
        key: const ValueKey<String>('change-username-sheet'),
        tier: GlassTier.panel,
        borderRadius: 28,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 32 + safeBottom),
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
                currentUsername == null || currentUsername.isEmpty
                    ? 'Buat username'
                    : 'Ganti username',
                style: TextStyle(
                  fontFamily: HiqeoTypography.family,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Bisa diganti sekali tiap 7 hari.',
                style: TextStyle(
                  fontFamily: HiqeoTypography.family,
                  fontSize: 13.5,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),

              if (isLocked) ...<Widget>[
                Container(
                  key: const ValueKey<String>('username-cooldown-banner'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.warning.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colors.warning.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    'Username baru bisa diganti lagi dalam $cooldownDays hari',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.warningText,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              TextField(
                key: const ValueKey<String>('change-username-input'),
                controller: _input,
                enabled: !isLocked && !_submitting,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: UsernamePolicy.maxLength,
                onChanged: (_) {
                  setState(() => _serverError = null);
                },
                decoration: InputDecoration(
                  labelText: 'Username',
                  prefixText: '@',
                  counterText: '',
                  filled: true,
                  fillColor: colors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  errorText: _serverError ??
                      (_input.text.isNotEmpty && !validation.isValid
                          ? validation.errorMessage
                          : null),
                  errorMaxLines: 2,
                ),
              ),
              const SizedBox(height: 12),

              // Daftar aturan langsung
              _RuleCheckRow(
                label: '3–20 karakter',
                passed: _input.text.isEmpty ? null : validation.lengthOk,
              ),
              const SizedBox(height: 4),
              _RuleCheckRow(
                label: 'Hanya huruf kecil, angka, titik (.), dan garis bawah (_)',
                passed: _input.text.isEmpty ? null : validation.charsOk,
              ),
              const SizedBox(height: 4),
              _RuleCheckRow(
                label: 'Tidak diawali atau diakhiri titik / garis bawah',
                passed: _input.text.isEmpty ? null : validation.edgesOk,
              ),
              const SizedBox(height: 4),
              _RuleCheckRow(
                label: 'Tidak ada dua titik berurutan (..)',
                passed: _input.text.isEmpty ? null : validation.noDoubleDot,
              ),

              const SizedBox(height: 20),
              HiqeoButton(
                key: const ValueKey<String>('change-username-save-button'),
                label: _submitting ? 'Menyimpan…' : 'Simpan username',
                isLoading: _submitting,
                onPressed: canSave ? _submit : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleCheckRow extends StatelessWidget {
  const _RuleCheckRow({required this.label, required this.passed});

  final String label;
  final bool? passed;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final Color color = switch (passed) {
      true => colors.primary,
      false => colors.warningText,
      null => colors.textSecondary,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: HiqeoIcon(
            passed == false ? HiqeoIcons.close : HiqeoIcons.check,
            size: 14,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
