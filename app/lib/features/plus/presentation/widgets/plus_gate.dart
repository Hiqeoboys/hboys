import 'package:flutter/material.dart';

import '../../../../design/tokens.dart';
import '../../../../design/widgets/hiqeo_button.dart';
import '../../../../design/widgets/line_icons.dart';
import '../../application/plus_navigation.dart';
import '../../application/plus_scope.dart';
import 'plus_widgets.dart';

/// Menampilkan [child] hanya bila status Plus aktif (termasuk masa tenggang).
///
/// Gerbang ini ada di dalam rute, bukan di titik masuk, supaya tautan dalam
/// atau pembukaan langsung tetap terlindungi. Tombol di layar terkunci membuka
/// paywall; setelah pembelian, gerbang ikut terbuka tanpa memuat ulang rute.
class PlusGate extends StatelessWidget {
  const PlusGate({
    super.key,
    required this.title,
    required this.description,
    required this.child,
    this.requireFullPlan = false,
  });

  final String title;
  final String description;
  final Widget child;
  final bool requireFullPlan;

  @override
  Widget build(BuildContext context) {
    final plus = PlusScope.maybeOf(context);
    final allowed = requireFullPlan
        ? (plus?.hasFullSocialAccess ?? false)
        : (plus?.hasPlus ?? false);
    if (allowed) return child;
    return PlusLockedView(
      title: title,
      description: description,
      requireFullPlan: requireFullPlan,
    );
  }
}

class PlusLockedView extends StatelessWidget {
  const PlusLockedView({
    super.key,
    required this.title,
    required this.description,
    this.requireFullPlan = false,
  });

  final String title;
  final String description;
  final bool requireFullPlan;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return PlusScrollPage(
      topBar: PlusTopBar(
        title: 'Fitur Plus',
        onBack: () => popPlusRoute(context),
      ),
      children: <Widget>[
        const SizedBox(height: HiqeoSpacing.md),
        const PlusLockup(),
        const SizedBox(height: HiqeoSpacing.lg),
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: HiqeoSpacing.sm),
        Text(
          description,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: HiqeoSpacing.lg),
        PlusCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  HiqeoIcon(HiqeoIcons.lock, size: 18, color: colors.primary),
                  const SizedBox(width: HiqeoSpacing.sm),
                  Expanded(
                    child: Text(
                      requireFullPlan
                          ? 'Khusus Hiqeo Plus Mahasiswa & Tahunan'
                          : 'Butuh Hiqeo Plus',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HiqeoSpacing.sm),
              Text(
                requireFullPlan
                    ? 'Fitur ini tersedia khusus pelanggan Paket Mahasiswa atau '
                        'Paket Tahunan.'
                    : 'Semua fitur inti tetap gratis. Plus hanya menambah cuaca '
                        'rute, estimasi, analitik, rekap, dan cadangan cloud.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: HiqeoSpacing.lg),
        HiqeoButton(
          label: 'Buka Hiqeo Plus',
          onPressed: () => openPlusPaywall(context),
        ),
        const SizedBox(height: HiqeoSpacing.md),
        Text(
          'Status Plus bisa diperiksa tanpa sinyal dan tetap berlaku selama '
          'masa tenggang.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}
