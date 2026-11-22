import 'package:flutter/material.dart';

import '../../design/glass/hiqeo_liquid_glass.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/hiqeo_button.dart';
import '../guides/domain/field_sketch_spec.dart';
import '../guides/presentation/widgets/field_sketch_stepper.dart';

/// Kartu sorotan utama "Panduan Pemula" di Beranda (gaya Liquid Glass, 100% gratis & offline).
class BeginnerGuideHomeCard extends StatelessWidget {
  const BeginnerGuideHomeCard({
    super.key,
    required this.onOpenAll,
    required this.onOpenTopic,
  });

  final VoidCallback onOpenAll;
  final ValueChanged<String> onOpenTopic;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);

    return HiqeoGlassCard(
      key: const ValueKey<String>('home-beginner-guide-card'),
      borderRadius: HiqeoRadius.hero,
      padding: const EdgeInsets.all(HiqeoSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'PANDUAN OFFLINE GRATIS',
                      style: HiqeoTypography.overline(colors.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Panduan Pemula',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.explore_outlined,
                  size: 20,
                  color: colors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Bekal dasar naik gunung dengan diagram teknis lapangan: susun carrier, dirikan tenda, hingga etika jalur.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          const FieldSketchCanvas(
            sketchId: FieldSketchId.homeBeginnerPreview,
            height: 112,
            borderRadius: 16,
            enableZoom: false,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _TopicQuickShortcutChip(
                chipKey: const ValueKey<String>('home-guide-shortcut-tent'),
                icon: Icons.holiday_village_outlined,
                label: 'Dirikan Tenda',
                onTap: () => onOpenTopic('pitch_tent'),
              ),
              _TopicQuickShortcutChip(
                chipKey: const ValueKey<String>('home-guide-shortcut-carrier'),
                icon: Icons.backpack_outlined,
                label: 'Susun Carrier',
                onTap: () => onOpenTopic('carrier_packing'),
              ),
              _TopicQuickShortcutChip(
                chipKey: const ValueKey<String>('home-guide-shortcut-layering'),
                icon: Icons.layers_outlined,
                label: 'Lapis Pakaian',
                onTap: () => onOpenTopic('layering'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          HiqeoButton(
            key: const ValueKey<String>('home-guide-open-all'),
            label: 'Buka Panduan Lengkap',
            onPressed: onOpenAll,
          ),
        ],
      ),
    );
  }
}

class _TopicQuickShortcutChip extends StatelessWidget {
  const _TopicQuickShortcutChip({
    this.chipKey,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Key? chipKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        key: chipKey,
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 15, color: colors.primary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.2,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
