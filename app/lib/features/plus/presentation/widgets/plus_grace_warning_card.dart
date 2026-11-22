import 'package:flutter/material.dart';

import '../../../../design/tokens.dart';
import '../../../../design/widgets/hiqeo_button.dart';
import '../../../../design/widgets/line_icons.dart';
import '../../domain/plus_entitlement.dart';
import '../../domain/plus_format.dart';
import '../../domain/plus_remote_config.dart';
import 'plus_widgets.dart';

/// Kartu peringatan ketika masa aktif Hiqeo Plus sudah berakhir.
///
/// Menjelaskan secara tegas bahwa pengguna masih mendapat masa tenggang 3 hari
/// untuk fitur umum Plus sebelum terkunci lagi, KECUALI obrolan Komunitas
/// dan Leaderboard yang langsung terkunci saat langganan berakhir.
class PlusGraceWarningCard extends StatelessWidget {
  const PlusGraceWarningCard({
    super.key,
    required this.access,
    required this.onSubscribeAgain,
    this.graceDays = PlusRemoteConfig.fallbackGraceDays,
  });

  final PlusAccess access;
  final VoidCallback onSubscribeAgain;
  final int graceDays;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final isGrace = access.isGrace;
    final graceEndText = access.graceEndsAtUtc == null
        ? ''
        : ' hingga ${formatDate(access.graceEndsAtUtc!)}';

    final title = isGrace
        ? 'Masa aktif Hiqeo Plus telah berakhir'
        : 'Langganan Hiqeo Plus kamu berakhir';
    final body = isGrace
        ? 'Kamu masih mendapat masa tenggang $graceDays hari$graceEndText '
            'untuk memakai fitur umum Plus sebelum terkunci kembali. '
            'Khusus fitur obrolan Komunitas dan Leaderboard langsung terkunci '
            'begitu masa aktif berakhir.'
        : 'Masa tenggang $graceDays hari sudah berakhir dan fitur Plus telah '
            'terkunci kembali. Riwayat pendakian serta peta offline kamu tetap aman.';

    return PlusCard(
      key: const ValueKey<String>('plus-grace-warning-card'),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(HiqeoRadius.card - 6),
          border: Border.all(
            color: colors.warning.withValues(alpha: 0.45),
          ),
          color: colors.warning.withValues(alpha: 0.08),
        ),
        padding: const EdgeInsets.all(HiqeoSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: HiqeoIcon(
                    HiqeoIcons.warning,
                    size: 18,
                    color: colors.warningText,
                  ),
                ),
                const SizedBox(width: HiqeoSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.warningText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: HiqeoSpacing.xs),
            Text(
              body,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.45,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: HiqeoSpacing.md),
            HiqeoButton(
              key: const ValueKey<String>('plus-grace-resubscribe-button'),
              label: 'Berlangganan lagi',
              onPressed: onSubscribeAgain,
            ),
          ],
        ),
      ),
    );
  }
}
