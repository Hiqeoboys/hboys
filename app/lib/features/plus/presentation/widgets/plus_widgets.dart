import 'package:flutter/material.dart';

import '../../../../core/brand/app_brand.dart';
import '../../../../design/background/page_background.dart';
import '../../../../design/glass/glass_surface.dart';
import '../../../../design/glass/hiqeo_liquid_glass.dart';
import '../../../../design/tokens.dart';
import '../../../../design/typography.dart';
import '../../../../design/widgets/line_icons.dart';

/// Tombol bulat 44 px untuk layar Plus. Warnanya mengikuti tema halaman,
/// berbeda dari [HeaderIconButton] yang dikunci krem untuk layar gelap.
class PlusCircleButton extends StatelessWidget {
  const PlusCircleButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final HiqeoIconData icon;
  final String label;
  final VoidCallback onTap;

  static const double size = 44;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return HiqeoGlassCircleButton(
      semanticsLabel: label,
      size: size,
      onTap: onTap,
      child: HiqeoIcon(icon, size: 20, color: colors.textPrimary),
    );
  }
}

/// Lockup "HIQEO" dengan lencana PLUS sejajar.
class PlusLockup extends StatelessWidget {
  const PlusLockup({super.key, this.showPlus = true, this.fontSize = 28});

  final bool showPlus;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          AppBrand.lockup,
          style: HiqeoTypography.textTheme.displayMedium?.copyWith(
            fontSize: fontSize,
            color: colors.primary,
            letterSpacing: 0.5,
          ),
        ),
        if (showPlus) ...<Widget>[
          const SizedBox(width: HiqeoSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(HiqeoRadius.pill),
            ),
            child: Text(
              'PLUS',
              style: HiqeoTypography.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                letterSpacing: 1.4,
                color: colors.onPrimary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Bar atas layar Plus: tombol kembali/tutup dan judul atau lockup.
class PlusTopBar extends StatelessWidget {
  const PlusTopBar({
    super.key,
    required this.onBack,
    this.title,
    this.subtitle,
    this.lockup = false,
    this.close = false,
  });

  final VoidCallback onBack;
  final String? title;
  final String? subtitle;
  final bool lockup;
  final bool close;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        PlusCircleButton(
          icon: close ? HiqeoIcons.close : HiqeoIcons.chevronLeft,
          label: close ? 'Tutup' : 'Kembali',
          onTap: onBack,
        ),
        const SizedBox(width: HiqeoSpacing.md),
        Expanded(
          child: lockup
              ? const Align(
                  alignment: Alignment.centerLeft,
                  child: PlusLockup(),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (title != null)
                      Text(
                        title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge,
                      ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Kerangka layar Plus: latar rancangan, bar atas tetap, isi menggulir, dan
/// bilah bawah opsional untuk tombol utama.
class PlusScrollPage extends StatelessWidget {
  const PlusScrollPage({
    super.key,
    required this.topBar,
    required this.children,
    this.bottomBar,
  });

  final Widget topBar;
  final List<Widget> children;
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return PageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  HiqeoSpacing.lg,
                  HiqeoSpacing.sm,
                  HiqeoSpacing.lg,
                  HiqeoSpacing.sm,
                ),
                child: topBar,
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    HiqeoSpacing.lg,
                    HiqeoSpacing.sm,
                    HiqeoSpacing.lg,
                    HiqeoSpacing.xxl + HiqeoSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
              if (bottomBar != null)
                DecoratedBox(
                  key: const ValueKey<String>('plus-sticky-bottom-bar'),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: colors.hairline, width: 1),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      HiqeoSpacing.lg,
                      HiqeoSpacing.md,
                      HiqeoSpacing.lg,
                      HiqeoSpacing.md,
                    ),
                    child: bottomBar,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlusOverline extends StatelessWidget {
  const PlusOverline(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: HiqeoTypography.overline(HiqeoColors.of(context).textSecondary),
      );
}

class PlusCard extends StatelessWidget {
  const PlusCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(HiqeoSpacing.lg),
    this.radius = HiqeoRadius.card,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      tier: GlassTier.card,
      borderRadius: radius,
      padding: padding,
      child: child,
    );
  }
}

class PlusFeatureItem {
  const PlusFeatureItem({
    required this.icon,
    required this.title,
  });

  final HiqeoIconData icon;
  final String title;
}

/// Grid dua kolom berisi kemampuan Plus.
class PlusFeatureGrid extends StatelessWidget {
  const PlusFeatureGrid({super.key, required this.items});

  final List<PlusFeatureItem> items;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final rows = <Widget>[];
    for (var index = 0; index < items.length; index += 2) {
      final left = items[index];
      final right = index + 1 < items.length ? items[index + 1] : null;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: _tile(context, colors, theme, left)),
              const SizedBox(width: HiqeoSpacing.sm),
              Expanded(
                child: right == null
                    ? const SizedBox.shrink()
                    : _tile(context, colors, theme, right),
              ),
            ],
          ),
        ),
      );
      if (index + 2 < items.length) {
        rows.add(const SizedBox(height: HiqeoSpacing.sm));
      }
    }
    return Column(children: rows);
  }

  Widget _tile(
    BuildContext context,
    HiqeoColors colors,
    ThemeData theme,
    PlusFeatureItem item,
  ) {
    return Container(
      padding: const EdgeInsets.all(HiqeoSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(HiqeoRadius.floating),
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colors.secondary.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: HiqeoIcon(item.icon, size: 18, color: colors.primary),
            ),
          ),
          const SizedBox(height: HiqeoSpacing.sm),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: HiqeoTypography.bold,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class PlusStat {
  const PlusStat({required this.value, required this.label});

  final String value;
  final String label;
}

class PlusStatTile extends StatelessWidget {
  const PlusStatTile({
    super.key,
    required this.stat,
    this.valueColor,
    this.labelColor,
    this.valueSize = 22,
  });

  final PlusStat stat;
  final Color? valueColor;
  final Color? labelColor;
  final double valueSize;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          stat.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontSize: valueSize,
            fontWeight: HiqeoTypography.extraBold,
            color: valueColor ?? colors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          stat.label,
          maxLines: 2,
          style: theme.textTheme.bodySmall?.copyWith(
            color: labelColor ?? colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Catatan pendek dengan ikon, dipakai untuk atribusi dan batasan data.
class PlusNotice extends StatelessWidget {
  const PlusNotice({
    super.key,
    required this.icon,
    required this.text,
    this.warning = false,
  });

  final HiqeoIconData icon;
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final tint = warning ? colors.warningText : colors.textSecondary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: HiqeoIcon(icon, size: 16, color: tint),
        ),
        const SizedBox(width: HiqeoSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: tint),
          ),
        ),
      ],
    );
  }
}

/// Keadaan kosong yang menjelaskan data apa yang belum ada, tanpa angka contoh.
class PlusEmptyState extends StatelessWidget {
  const PlusEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final HiqeoIconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    return PlusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.secondary.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: HiqeoIcon(icon, size: 20, color: colors.primary),
            ),
          ),
          const SizedBox(height: HiqeoSpacing.md),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: HiqeoSpacing.xs),
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          if (action != null) ...<Widget>[
            const SizedBox(height: HiqeoSpacing.md),
            action!,
          ],
        ],
      ),
    );
  }
}
