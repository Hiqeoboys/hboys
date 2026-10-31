import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../design/gooey/gooey_selector.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';
import '../../../design/widgets/hiqeo_button.dart';
import '../../../design/widgets/line_icons.dart';
import '../application/plus_controller.dart';
import '../application/plus_navigation.dart';
import '../application/plus_scope.dart';
import '../domain/plus_plan.dart';
import 'widgets/plus_widgets.dart';

/// D1 Paywall.
///
/// Dipilih satu paket, bukan langganan otomatis: tombol utama baru memulai
/// transaksi setelah pengguna mengetuknya. Harga dan masa berlaku sepenuhnya
/// dari konfigurasi jarak jauh; bila konfigurasi belum ada, layar menyatakan
/// belum tersedia dan tidak menampilkan harga karangan.
class PaywallPage extends StatefulWidget {
  const PaywallPage({super.key});

  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends State<PaywallPage> {
  String? _selectedPlanId;

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
    final result = await controller.purchase(plan.id);
    if (!mounted) return;
    _showMessage(
      result.success
          ? 'Plus aktif. Terima kasih.'
          : result.message ?? 'Pembelian gagal.',
    );
  }

  Future<void> _restore(PlusController controller) async {
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
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(HiqeoSpacing.md),
          child: PlusCard(
            radius: HiqeoRadius.hero,
            padding: const EdgeInsets.all(HiqeoSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
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
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plus = PlusScope.maybeOf(context);
    final plans = plus?.plans ?? const <PlusPlan>[];
    final selected = _selectedPlan(plans);
    final active = plus?.hasPlus ?? false;
    final busy = plus?.isWorking ?? false;
    final hasConfig = plus?.hasConfig ?? false;
    final canBuy = plus != null && !active && !busy && selected != null;

    return PlusScrollPage(
      topBar: PlusTopBar(
        close: true,
        lockup: true,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      bottomBar: HiqeoButton(
        key: const ValueKey('paywall-cta'),
        label: active
            ? 'Kelola langganan'
            : (!hasConfig
                ? 'Paket belum tersedia'
                : (busy ? 'Memproses…' : 'Mulai berlangganan')),
        onPressed: active
            ? () => context.push(PlusRoutes.manage)
            : (canBuy ? () => _purchase(plus, selected) : null),
      ),
      children: <Widget>[
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
          onRestore: plus == null ? null : () => _restore(plus),
          onTerms: () => _showLegal(
            'Syarat layanan',
            'Dokumen syarat resmi belum disambungkan di build ini. '
                'Pembelian di toko aplikasi tetap mengikuti syarat toko.',
          ),
          onPrivacy: () => _showLegal(
            'Kebijakan privasi',
            'Data pendakian tersimpan di HP ini. Cadangan cloud belum aktif '
                'pada tahap ini; tidak ada data yang dikirim ke server.',
          ),
        ),
        const SizedBox(height: HiqeoSpacing.lg),
        PlusNotice(
          icon: HiqeoIcons.lock,
          text: 'Status Plus diverifikasi offline dari token bertanda tangan. '
              'Tanpa sinyal, Plus tetap aktif sampai masa berlaku berakhir.',
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
    final badge = plan.badge ?? (plan.id == 'annual' ? 'PALING PAS' : null);
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
                          badge.toUpperCase(),
                          style: HiqeoTypography.textTheme.labelSmall?.copyWith(
                            fontSize: 9,
                            letterSpacing: 1,
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
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        plan.periodLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
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
                : (access?.isGrace ?? false
                    ? 'Aktif tanpa sinyal sampai masa tenggang berakhir.'
                    : 'Paket ${plan?.title ?? 'Plus'} berlaku sampai '
                        '${_dateLabel(access?.expiresAtUtc)}.'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: HiqeoSpacing.md),
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
            'Harga dan paket berasal dari konfigurasi server. Tidak ada '
            'pembelian sebelum daftar paket tersedia.',
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
