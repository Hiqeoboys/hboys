import 'package:flutter/material.dart';

import '../../../../design/tokens.dart';
import '../../domain/plus_format.dart';
import '../../domain/plus_subscription_history.dart';
import 'plus_widgets.dart';

/// Kartu "Riwayat berlangganan" pada halaman Hiqeo Plus.
///
/// Hanya dirender jika pengguna sedang berlangganan atau pernah berlangganan
/// (`entries.isNotEmpty`). Pengguna yang belum pernah berlangganan sama sekali
/// tidak akan melihat kartu ini.
class PlusSubscriptionHistoryCard extends StatelessWidget {
  const PlusSubscriptionHistoryCard({
    super.key,
    required this.entries,
  });

  final List<PlusSubscriptionHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);

    return PlusCard(
      key: const ValueKey<String>('plus-subscription-history-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const PlusOverline('Riwayat berlangganan'),
          const SizedBox(height: HiqeoSpacing.md),
          for (var i = 0; i < entries.length; i++) ...<Widget>[
            if (i > 0) Divider(color: colors.hairline, height: HiqeoSpacing.lg),
            _HistoryRow(
              entry: entries[i],
              colors: colors,
              theme: theme,
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.entry,
    required this.colors,
    required this.theme,
  });

  final PlusSubscriptionHistoryEntry entry;
  final HiqeoColors colors;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final (Color pillBg, Color pillFg) = switch (entry.status) {
      PlusSubscriptionHistoryStatus.active => (
          colors.secondary.withValues(alpha: 0.65),
          colors.primary,
        ),
      PlusSubscriptionHistoryStatus.lifetime => (
          const Color(0xFF1F2430),
          const Color(0xFFFFD875),
        ),
      PlusSubscriptionHistoryStatus.grace => (
          colors.warning.withValues(alpha: 0.16),
          colors.warningText,
        ),
      PlusSubscriptionHistoryStatus.expired ||
      PlusSubscriptionHistoryStatus.cancelled =>
        (
          colors.hairline.withValues(alpha: 0.7),
          colors.textSecondary,
        ),
    };

    final endLabel = entry.isLifetime
        ? 'Seumur hidup'
        : (entry.expiresAtUtc != null
            ? 'Berakhir: ${formatDate(entry.expiresAtUtc!)}'
            : 'Berakhir: -');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                entry.planTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Mulai: ${formatDate(entry.startedAtUtc)} · $endLabel',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: HiqeoSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: pillBg,
            borderRadius: BorderRadius.circular(HiqeoRadius.pill),
          ),
          child: Text(
            entry.status.label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: pillFg,
            ),
          ),
        ),
      ],
    );
  }
}
