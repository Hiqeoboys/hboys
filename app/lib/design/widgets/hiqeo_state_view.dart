import 'package:flutter/material.dart';

import '../glass/hiqeo_liquid_glass.dart';
import '../tokens.dart';
import 'hiqeo_button.dart';

/// Tampilan seragam untuk keadaan kosong maupun galat dengan aksi pemulihan.
class HiqeoStateView extends StatelessWidget {
  const HiqeoStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.isError = false,
    this.wrapInCard = true,
    this.darkRoom = false,
    this.actionKey,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isError;
  final bool wrapInCard;
  final bool darkRoom;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final titleColor =
        darkRoom ? HiqeoColors.dark.textPrimary : colors.textPrimary;
    final bodyColor =
        darkRoom ? HiqeoColors.dark.textSecondary : colors.textSecondary;
    final badgeBg = darkRoom
        ? Colors.white.withValues(alpha: 0.12)
        : (isError
            ? colors.warning.withValues(alpha: 0.14)
            : colors.primary.withValues(alpha: 0.10));
    final iconColor = darkRoom
        ? (isError ? HiqeoColors.dark.warningText : HiqeoColors.dark.textPrimary)
        : (isError ? colors.warningText : colors.primary);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: badgeBg,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 24, color: iconColor),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: titleColor,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: bodyColor),
        ),
        if (actionLabel != null && onAction != null) ...<Widget>[
          const SizedBox(height: 16),
          HiqeoButton(
            key: actionKey,
            label: actionLabel!,
            variant: darkRoom
                ? HiqeoButtonVariant.inverse
                : HiqeoButtonVariant.secondary,
            onPressed: onAction,
          ),
        ],
      ],
    );

    if (wrapInCard && !darkRoom) {
      return HiqeoGlassCard(
        borderRadius: 20,
        padding: const EdgeInsets.all(24),
        child: content,
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: content,
    );
  }
}
