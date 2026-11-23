import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/plans.dart';
import '../../../design/glass/glass_surface.dart';
import '../../../design/gooey/gooey_selector.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/line_icons.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../../auth/application/account_controller.dart';
import '../../auth/presentation/account_page.dart';
import '../application/plus_controller.dart';
import '../application/plus_navigation.dart';
import '../application/plus_scope.dart';
import '../domain/plus_entitlement.dart';
import '../domain/plus_plan.dart';
import '../domain/plus_remote_config.dart';
import 'widgets/plus_grace_warning_card.dart';
import 'widgets/plus_subscription_history_card.dart';
import 'widgets/plus_widgets.dart';

/// D1 Paywall.
///
/// Dipilih satu paket, bukan langganan otomatis: tombol utama baru memulai
/// transaksi setelah pengguna mengetuknya. Harga dan masa berlaku sepenuhnya
/// dari konfigurasi jarak jauh; bila konfigurasi belum ada, layar menyatakan
/// belum tersedia dan tidak menampilkan harga karangan.
class PaywallPage extends StatefulWidget {
  const PaywallPage({
    super.key,
    this.notice,
    this.requireFullSocialPlan = false,
    this.accountController,
    this.isSignedInOverride,
  });

  final String? notice;
  final bool requireFullSocialPlan;
  final AccountController? accountController;
  final bool? isSignedInOverride;

  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends State<PaywallPage> {
  String? _selectedPlanId;
  bool _historyRequested = false;

  AccountController? get _account =>
      widget.accountController ?? SupabaseServices.sharedAccountController;

  bool get _isSignedIn {
    final override = widget.isSignedInOverride;
    if (override != null) return override;
    if (_account?.user != null) return true;
    return SupabaseServices.clientOrNull?.auth.currentUser != null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_historyRequested) {
      _historyRequested = true;
      unawaited(PlusScope.maybeOf(context)?.refreshSubscriptionHistory());
    }
  }

  Future<bool> _ensureSignedInBeforePurchase() async {
    if (_isSignedIn) return true;
    final goLogin = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        final colors = HiqeoColors.of(dialogCtx);
        return AlertDialog(
          key: const ValueKey<String>('paywall-login-guard-dialog'),
          backgroundColor: colors.surface,
          title: const Text('Masuk akun dulu'),
          content: const Text(
            'Silakan masuk dengan Google atau Apple terlebih dahulu supaya langganan Hiqeo Plus terhubung aman ke akunmu.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Nanti saja'),
            ),
            FilledButton(
              key: const ValueKey<String>('paywall-login-confirm'),
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('Masuk sekarang'),
            ),
          ],
        );
      },
    );
    if (goLogin != true || !mounted) return false;

    final router = GoRouter.maybeOf(context);
    if (router != null) {
      await router.push('/akun?returnTo=%2Fplus');
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AccountPage(
            controller: widget.accountController,
            returnToRoute: '/plus',
          ),
        ),
      );
    }
    if (!mounted) return false;
    setState(() {});
    unawaited(PlusScope.maybeOf(context)?.refreshSubscriptionHistory());
    return false;
  }

  PlusPlan? _selectedPlan(List<PlusPlan> plans) {
    if (plans.isEmpty) return null;
    final id = _selectedPlanId;
    if (id != null) {
      for (final plan in plans) {
        if (plan.id == id) return plan;
      }
    }
    for (final plan in plans) {
      if (plan.id == 'annual') return plan;
    }
    return plans.first;
  }

  Future<void> _purchase(PlusController controller, PlusPlan plan) async {
    final signedIn = await _ensureSignedInBeforePurchase();
    if (!signedIn || !mounted) return;
    final result = await controller.purchase(plan.id);
    if (!mounted) return;
    _showMessage(
      result.success
          ? 'Plus aktif. Terima kasih.'
          : result.message ?? 'Pembelian gagal.',
    );
  }

  Future<void> _restore(PlusController controller) async {
    final signedIn = await _ensureSignedInBeforePurchase();
    if (!signedIn || !mounted) return;
    final result = await controller.restore();
    if (!mounted) return;
    _showMessage(
      result.success
          ? 'Pembelian dipulihkan.'
          : result.message ?? 'Tidak ada pembelian.',
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showLegal(String title, String body) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
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
                Text(title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: HiqeoSpacing.sm),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: HiqeoSpacing.md),
                HiqeoButton(
                  label: 'Tutup',
                  variant: HiqeoButtonVariant.secondary,
                  onPressed: () => Navigator.of(sheetContext).maybePop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final plus = PlusScope.maybeOf(context);
    final allPlans = plus != null ? plus.plans : buildDefaultPlusPlans();
    final hasPlus = plus?.hasPlus ?? false;
    final hasFullSocial = plus?.hasFullSocialAccess ?? false;
    final showSocialUpgrade =
        widget.requireFullSocialPlan && hasPlus && !hasFullSocial;
    final plans = showSocialUpgrade
        ? allPlans
            .where((p) => PlusAccess.isFullSocialPlan(p.id))
            .toList(growable: false)
        : allPlans;
    final selected = _selectedPlan(plans);
    final access = plus?.access;
    final isGrace = access?.isGrace ?? false;
    final isExpired = access?.isExpired ?? false;
    final showGraceOrExpiredCard = (isGrace || isExpired) && !showSocialUpgrade;
    // Saat masa tenggang berakhir / dalam masa tenggang, biarkan tombol utama
    // menawarkan pembelian ulang ketika paket tersedia.
    final active = hasPlus && !showSocialUpgrade && !isGrace;
    final busy = plus?.isWorking ?? false;
    final canBuy = !active && !busy && selected != null;
    final noticeText = widget.notice?.trim();
    final graceDays =
        plus?.config?.effectiveGraceDays ?? PlusRemoteConfig.fallbackGraceDays;
    final showHistory = (plus?.hasEverSubscribed ?? false) &&
        (plus?.subscriptionHistory.isNotEmpty ?? false);

    return PlusScrollPage(
      topBar: PlusTopBar(
        close: false,
        lockup: true,
        onBack: () => popPlusRoute(context),
      ),
      bottomBar: HiqeoButton(
        key: const ValueKey('paywall-cta'),
        label: active
            ? 'Kelola langganan'
            : (plans.isEmpty
                ? 'Paket belum tersedia'
                : (busy
                    ? 'Memproses…'
                    : (isGrace || isExpired
                        ? 'Berlangganan lagi'
                        : 'Berlangganan'))),
        onPressed: active
            ? () => context.push(PlusRoutes.manage)
            : (canBuy
                ? () {
                    if (plus != null) {
                      _purchase(plus, selected);
                    } else {
                      _showMessage('Pembayaran belum tersedia');
                    }
                  }
                : null),
      ),
      children: <Widget>[
        if (noticeText != null && noticeText.isNotEmpty) ...<Widget>[
          PlusNotice(
            key: const ValueKey<String>('paywall-custom-notice'),
            icon: HiqeoIcons.lock,
            text: noticeText,
          ),
          const SizedBox(height: HiqeoSpacing.lg),
        ],
        if (showGraceOrExpiredCard && access != null) ...<Widget>[
          PlusGraceWarningCard(
            access: access,
            graceDays: graceDays,
            onSubscribeAgain: () {
              if (plus != null && selected != null) {
                unawaited(_purchase(plus, selected));
              }
            },
          ),
          const SizedBox(height: HiqeoSpacing.lg),
        ],
        Text(
          'Naik lebih siap,\npulang lebih tenang.',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: HiqeoSpacing.sm),
        Text(
          'Cuaca rute, estimasi perjalanan, dan rekap pendakian dalam satu '
          'tempat. Datamu tetap di perangkatmu.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: HiqeoColors.of(context).textSecondary,
              ),
        ),
        const SizedBox(height: HiqeoSpacing.md),
        Row(
          children: <Widget>[
            HiqeoIcon(
              HiqeoIcons.check,
              size: 16,
              color: HiqeoColors.of(context).textSecondary,
            ),
            const SizedBox(width: HiqeoSpacing.xs),
            Expanded(
              child: Text(
                'Semua fitur inti tetap gratis',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: HiqeoColors.of(context).textSecondary,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: HiqeoSpacing.xl),
        _featureGrid(plus),
        const SizedBox(height: HiqeoSpacing.xl),
        if (active)
          _ActivePlanCard(plus: plus)
        else ...<Widget>[
          const PlusOverline('Pilih paket'),
          const SizedBox(height: HiqeoSpacing.sm),
          if (plans.isEmpty)
            _PlansUnavailable(
              failed: plus?.configFetchFailed ?? false,
              onRetry:
                  plus == null ? null : () => plus.refreshRemote(force: true),
            )
          else
            GooeySelector<PlusPlan>(
              key: const ValueKey('paywall-plans'),
              axis: Axis.vertical,
              items: <GooeySelectorItem<PlusPlan>>[
                for (final plan in plans)
                  GooeySelectorItem<PlusPlan>(
                    value: plan,
                    semanticsLabel: _planSemantics(plan),
                    builder: (context, state) => _PlanCard(
                      plan: plan,
                      state: state,
                    ),
                  ),
              ],
              selected: selected!,
              gap: HiqeoSpacing.sm,
              borderRadius: HiqeoRadius.card,
              itemPadding: EdgeInsets.zero,
              onChanged: (plan) => setState(() => _selectedPlanId = plan.id),
            ),
        ],
        const SizedBox(height: HiqeoSpacing.xl),
        _LegalLinks(
          enabled: !busy,
          onRestore: plus != null
              ? () => _restore(plus)
              : () => _showMessage('Pembayaran belum tersedia'),
          onTerms: () => _showLegal(
            'Syarat layanan',
            'Penggunaan layanan dan pembelian Hiqeo Plus mengikuti ketentuan '
                'aplikasi serta kebijakan toko aplikasi.',
          ),
          onPrivacy: () => _showLegal(
            'Kebijakan privasi',
            'Data pendakian tersimpan di HP ini. Pelanggan Hiqeo Plus dapat '
                'mengaktifkan cadangan cloud otomatis terenkripsi sesi agar '
                'riwayat tetap aman saat berganti perangkat.',
          ),
        ),
        const SizedBox(height: HiqeoSpacing.lg),
        if (showHistory) ...<Widget>[
          PlusSubscriptionHistoryCard(entries: plus!.subscriptionHistory),
          const SizedBox(height: HiqeoSpacing.lg),
        ],
        PlusNotice(
          icon: HiqeoIcons.lock,
          text:
              'Status Plus tetap aktif tanpa sinyal sampai masa berlakumu berakhir.',
        ),
      ],
    );
  }

  Widget _featureGrid(PlusController? plus) {
    final items = <PlusFeatureItem>[
      PlusFeatureItem(icon: HiqeoIcons.cloud, title: 'Cuaca rute'),
      PlusFeatureItem(
        icon: HiqeoIcons.clock,
        title: 'Estimasi & itinerary',
      ),
      PlusFeatureItem(
        icon: HiqeoIcons.activity,
        title: 'Analitik lanjutan',
      ),
      PlusFeatureItem(
        icon: HiqeoIcons.calendar,
        title: 'Rekap tahunan',
      ),
      PlusFeatureItem(
        icon: HiqeoIcons.download,
        title: 'Cadangan cloud',
      ),
      if (plus?.leaderboardEnabled ?? false)
        PlusFeatureItem(
          icon: HiqeoIcons.trophy,
          title: 'Leaderboard',
        )
      else if (plus?.peakBadgesEnabled ?? false)
        PlusFeatureItem(
          icon: HiqeoIcons.trophy,
          title: 'Lencana puncak',
        ),
    ];
    return PlusFeatureGrid(items: items);
  }

  String _planSemantics(PlusPlan plan) =>
      '${plan.title}, ${plan.priceLabel} ${plan.periodLabel}';
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.state});

  final PlusPlan plan;
  final GooeySelectorItemState state;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final coverage = state.coverage;
    final foreground = Color.lerp(
      colors.textPrimary,
      colors.onPrimary,
      coverage,
    )!;
    final secondary = Color.lerp(
      colors.textSecondary,
      colors.onPrimary.withValues(alpha: 0.78),
      coverage,
    )!;
    final badge = plan.badge;
    final quota = plan.hasQuota
        ? 'Sisa ${plan.quotaRemaining} dari ${plan.quotaTotal}'
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _RadioDot(
            selected: state.selected,
            coverage: coverage,
          ),
          const SizedBox(width: HiqeoSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        plan.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: foreground,
                        ),
                      ),
                    ),
                    if (badge != null) ...<Widget>[
                      const SizedBox(width: HiqeoSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Color.lerp(
                            colors.secondary.withValues(alpha: 0.55),
                            colors.onPrimary.withValues(alpha: 0.16),
                            coverage,
                          ),
                          borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                        ),
                        child: Text(
                          badge,
                          style: HiqeoTypography.textTheme.labelSmall?.copyWith(
                            fontSize: 9,
                            letterSpacing: 0.6,
                            color: foreground,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      plan.priceLabel,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontSize: 20,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(width: HiqeoSpacing.xs),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          plan.periodLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (plan.note != null || quota != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      quota ?? plan.note!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                      ),
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

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected, required this.coverage});

  final bool selected;
  final double coverage;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final border =
        Color.lerp(colors.textSecondary, colors.onPrimary, coverage)!;
    final fill = Color.lerp(colors.primary, colors.onPrimary, coverage)!;
    final inner = Color.lerp(colors.onPrimary, colors.primary, coverage)!;
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? fill : Colors.transparent,
        border: Border.all(color: border, width: 1.6),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: inner,
                ),
              ),
            )
          : null,
    );
  }
}

class _ActivePlanCard extends StatelessWidget {
  const _ActivePlanCard({required this.plus});

  final PlusController? plus;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final access = plus?.access;
    final plan = plus?.currentPlan;
    final lifetime = access?.lifetime ?? false;
    return PlusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              HiqeoIcon(
                HiqeoIcons.check,
                size: 20,
                color: colors.textPrimary,
              ),
              const SizedBox(width: HiqeoSpacing.sm),
              Expanded(
                child: Text('Plus aktif', style: theme.textTheme.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: HiqeoSpacing.sm),
          Text(
            lifetime
                ? 'Founding Member berlaku selamanya.'
                : (access?.isGrace ?? false)
                    ? 'Status Plus tetap tersedia sampai masa tenggang berakhir.'
                    : 'Paket ${plan?.title ?? 'Plus'} berlaku sampai '
                        '${_dateLabel(access?.expiresAtUtc)}.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: HiqeoSpacing.md),
          if (plus?.hasFullPlanIncludingGrace ?? false) ...<Widget>[
            HiqeoButton(
              label: 'Analitik lanjutan',
              variant: HiqeoButtonVariant.secondary,
              onPressed: () => context.push(PlusRoutes.analytics),
            ),
            const SizedBox(height: HiqeoSpacing.sm),
            HiqeoButton(
              label: 'Rekap tahunan',
              variant: HiqeoButtonVariant.secondary,
              onPressed: () => context.push(PlusRoutes.recap),
            ),
            const SizedBox(height: HiqeoSpacing.sm),
          ],
          HiqeoButton(
            label: 'Buka kelola langganan',
            variant: HiqeoButtonVariant.secondary,
            onPressed: () => context.push(PlusRoutes.manage),
          ),
        ],
      ),
    );
  }

  String _dateLabel(DateTime? date) {
    if (date == null) return '—';
    final local = date.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }
}

class _PlansUnavailable extends StatelessWidget {
  const _PlansUnavailable({required this.failed, required this.onRetry});

  final bool failed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return PlusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            failed ? 'Paket belum dapat dimuat' : 'Paket sedang dimuat',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: HiqeoSpacing.xs),
          Text(
            'Daftar paket sedang diperbarui. Sambungkan ke internet lalu coba '
            'muat ulang.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: HiqeoSpacing.md),
            HiqeoButton(
              label: 'Coba lagi',
              variant: HiqeoButtonVariant.secondary,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}

class _LegalLinks extends StatelessWidget {
  const _LegalLinks({
    required this.enabled,
    required this.onRestore,
    required this.onTerms,
    required this.onPrivacy,
  });

  final bool enabled;
  final VoidCallback? onRestore;
  final VoidCallback onTerms;
  final VoidCallback onPrivacy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = HiqeoColors.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: colors.textSecondary,
      decoration: TextDecoration.underline,
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: HiqeoSpacing.md,
      runSpacing: HiqeoSpacing.xs,
      children: <Widget>[
        TextButton(
          key: const ValueKey('paywall-restore'),
          onPressed: enabled ? onRestore : null,
          child: Text('Pulihkan pembelian', style: style),
        ),
        TextButton(
          onPressed: onTerms,
          child: Text('Syarat', style: style),
        ),
        TextButton(
          onPressed: onPrivacy,
          child: Text('Privasi', style: style),
        ),
      ],
    );
  }
}
