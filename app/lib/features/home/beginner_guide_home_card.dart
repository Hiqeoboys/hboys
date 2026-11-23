import 'package:flutter/material.dart';

import '../../design/glass/hiqeo_liquid_glass.dart';
import '../../design/tokens.dart';
import '../../design/widgets/hiqeo_button.dart';
import '../guides/domain/field_sketch_spec.dart';
import '../guides/presentation/widgets/field_sketch_stepper.dart';

/// Kartu sorotan utama "Panduan Pemula" di Beranda (gaya Liquid Glass, 100% gratis & offline).
class BeginnerGuideHomeCard extends StatelessWidget {
  const BeginnerGuideHomeCard({
    super.key,
    required this.onOpenAll,
  });

  final VoidCallback onOpenAll;

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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Text(
                  'Panduan Pemula',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
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
          const SizedBox(height: 8),
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
