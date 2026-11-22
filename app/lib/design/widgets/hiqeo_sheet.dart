import 'package:flutter/material.dart';

import '../glass/glass_surface.dart';
import '../tokens.dart';

/// Permukaan bawah kaca dengan gagang tarik dan judul.
///
/// Anak [child] harus bisa menggulir sendiri karena tinggi sheet ditentukan
/// pemanggil (lihat `DraggableScrollableSheet`).
class HiqeoSheet extends StatelessWidget {
  const HiqeoSheet({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return GlassSurface(
      tier: GlassTier.panel,
      borderRadius: HiqeoRadius.hero,
      child: Column(
        children: <Widget>[
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: colors.textSecondary.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(HiqeoRadius.pill),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: theme.textTheme.headlineSmall),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
