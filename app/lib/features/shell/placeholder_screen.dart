import 'package:flutter/material.dart';

import '../../design/background/page_background.dart';
import '../../design/tokens.dart';

/// Penampung sementara sebuah layar sampai desainnya dikerjakan.
///
/// Dipakai router agar seluruh rute ada sejak awal; tiap milestone mengganti
/// pemakaiannya dengan halaman sungguhan lalu berkas ini menyusut.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = AltracqColors.of(context);
    final theme = Theme.of(context);
    return PageBackground(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AltracqSpacing.lg,
            AltracqSpacing.xxl,
            AltracqSpacing.lg,
            AltracqSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: theme.textTheme.displaySmall),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: AltracqSpacing.sm),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: colors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
