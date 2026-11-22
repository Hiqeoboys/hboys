import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../design/background/app_background.dart';
import '../../../design/background/page_background.dart';
import '../../../design/glass/hiqeo_liquid_glass.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/hiqeo_back_button.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/hiqeo_state_view.dart';
import '../../../design/widgets/persistent_avatar_image.dart';
import '../../../infrastructure/cache/public_profile_cache_service.dart';
import '../../social/data/friends_service.dart';
import '../../social/data/moderation_service.dart';

/// Halaman Profil Pengguna Lain (dibuka saat mengetuk nama/foto teman).
/// Menampilkan lencana Hiqeo Plus HANYA untuk Paket Mahasiswa & Tahunan,
/// jumlah gunung didaki, total jarak, total waktu, dan tombol "Laporkan akun".
class OtherUserProfilePage extends StatefulWidget {
  const OtherUserProfilePage({
    super.key,
    required this.userId,
    this.initialName,
    this.initialUsername,
    this.initialAvatarUrl,
  });

  final String userId;
  final String? initialName;
  final String? initialUsername;
  final String? initialAvatarUrl;

  @override
  State<OtherUserProfilePage> createState() => _OtherUserProfilePageState();
}

class _OtherUserProfilePageState extends State<OtherUserProfilePage> {
  OtherUserProfileData? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await FriendsService.instance.fetchUserProfile(widget.userId);
      if (!mounted) return;
      setState(() {
        _profile = data;
        _loading = false;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('OtherUserProfilePage load failed: $e');
      }
      if (!mounted) return;
      setState(() {
        _error = 'Belum bisa memuat profil pendaki. Periksa sinyal lalu coba lagi.';
        _loading = false;
      });
    }
  }

  Future<void> _reportAccount() async {
    var reason = ModerationService.defaultReasons.first;
    final detailsCtrl = TextEditingController();
    var submitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Laporkan akun'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Pilih alasan pelaporan akun ini untuk ditinjau tim moderasi.',
                  style: TextStyle(fontSize: 13.5),
                ),
                const SizedBox(height: 10),
                for (final r in ModerationService.defaultReasons)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: submitting
                        ? null
                        : () => setDialogState(() => reason = r),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            reason == r
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            size: 20,
                            color: reason == r
                                ? HiqeoColors.of(ctx).primary
                                : HiqeoColors.of(ctx).textSecondary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              r,
                              style: const TextStyle(fontSize: 13.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: detailsCtrl,
                  maxLines: 2,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Detail tambahan (opsional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      setDialogState(() => submitting = true);
                      try {
                        await ModerationService.instance.submitReport(
                          targetType: ModerationTargetType.userAccount,
                          targetId: widget.userId,
                          reportedUserId: widget.userId,
                          reason: reason,
                          details: detailsCtrl.text,
                        );
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Laporan akun berhasil dikirim.'),
                            ),
                          );
                        }
                      } catch (e) {
                        if (kDebugMode) {
                          debugPrint('OtherUserProfilePage report failed: $e');
                        }
                        setDialogState(() => submitting = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Laporan belum terkirim. Periksa koneksi lalu coba lagi.',
                              ),
                            ),
                          );
                        }
                      }
                    },
              child: Text(submitting ? 'Mengirim…' : 'Kirim laporan'),
            ),
          ],
        ),
      ),
    );
    detailsCtrl.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final mins = (totalSeconds % 3600) ~/ 60;
    if (hours > 0) return '${hours}j ${mins}m';
    return '$mins mnt';
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final profile = _profile;
    final cached = PublicProfileCacheService.instance.getCached(widget.userId);
    final displayName = profile?.label ??
        (widget.initialName?.trim().isNotEmpty == true
            ? widget.initialName!.trim()
            : null) ??
        cached?.displayName ??
        'Pendaki';
    final username = (profile?.username.trim().isNotEmpty == true
            ? profile!.username
            : null) ??
        (widget.initialUsername?.trim().isNotEmpty == true
            ? widget.initialUsername!.trim()
            : null) ??
        cached?.username ??
        '';
    final avatarUrl = profile?.avatarUrl ??
        widget.initialAvatarUrl ??
        cached?.avatarUrl;

    return PageBackground(
      page: AppBackgroundPage.profil,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: const HiqeoBackButton(inAppBar: true),
          leadingWidth: HiqeoBackButton.appBarWidth,
          title: const Text('Profil pendaki'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_error != null && profile == null && cached == null &&
                    (widget.initialName == null || widget.initialName!.isEmpty))
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: HiqeoStateView(
                        icon: Icons.wifi_off_rounded,
                        title: 'Profil belum bisa dimuat',
                        message: _error!,
                        isError: true,
                        actionLabel: 'Coba lagi',
                        onAction: () => unawaited(_load()),
                      ),
                    ),
                  )
                : RepaintBoundary(
                    child: SingleChildScrollView(
                      clipBehavior: Clip.hardEdge,
                      padding: EdgeInsets.fromLTRB(
                        20,
                        20,
                        20,
                        20 + MediaQuery.paddingOf(context).bottom,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Center(
                            child: PersistentAvatarImage(
                              cacheKey: widget.userId,
                              avatarUrl: avatarUrl,
                              size: 92,
                              backgroundColor: colors.hairline,
                              fallback: Center(
                                child: Text(
                                  displayName.isNotEmpty
                                      ? displayName[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w700,
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                displayName,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: colors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (profile?.showPlusBadge == true) ...<Widget>[
                              const SizedBox(width: 8),
                              Container(
                                key: const ValueKey('other-user-plus-badge'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.primary,
                                  borderRadius: BorderRadius.circular(
                                    HiqeoRadius.pill,
                                  ),
                                ),
                                child: Text(
                                  'Hiqeo Plus',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: colors.onPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (username.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 4),
                          Text(
                            '@$username',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: _StatTile(
                                label: 'Gunung didaki',
                                value: '${profile?.mountainsClimbed ?? 0}',
                                colors: colors,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _StatTile(
                                label: 'Total jarak',
                                value:
                                    '${((profile?.totalDistanceM ?? 0) / 1000).toStringAsFixed(1)} km',
                                colors: colors,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _StatTile(
                                label: 'Total waktu',
                                value: _formatDuration(
                                  profile?.totalMovingSeconds ?? 0,
                                ),
                                colors: colors,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        HiqeoButton(
                          key: const ValueKey('other-user-report-button'),
                          label: 'Laporkan akun',
                          variant: HiqeoButtonVariant.secondary,
                          leading: Icon(
                            Icons.flag_outlined,
                            size: 18,
                            color: colors.warningText,
                          ),
                          onPressed: _reportAccount,
                        ),
                      ],
                    ),
                  ),
                ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.colors,
  });

  final String label;
  final String value;
  final HiqeoColors colors;

  @override
  Widget build(BuildContext context) {
    return HiqeoGlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      child: Column(
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
