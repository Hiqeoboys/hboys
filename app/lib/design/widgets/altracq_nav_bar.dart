import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../glass/glass_surface.dart';
import '../gooey/gooey_layer.dart';
import '../tokens.dart';
import 'line_icons.dart';

class AltracqNavBarItem {
  const AltracqNavBarItem({
    required this.label,
    required this.icon,
    required this.route,
  });

  final String label;
  final AltracqIconData icon;
  final String route;
}

/// Navigasi bawah melayang: tinggi 64 px, radius 32, menjorok 16 px dari tepi.
///
/// Tab aktif berupa pill 66×52 berwarna primer; pada M3 pill ini dibungkus
/// [GooeyLayer] sehingga mendapat gelembung dan tetesan cair.
class AltracqNavBar extends StatelessWidget {
  const AltracqNavBar({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
  });

  final int currentIndex;
  final List<AltracqNavBarItem> items;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: GlassSurface(
        borderRadius: AltracqRadius.navbar,
        child: SizedBox(
          height: AltracqMetrics.navbarHeight,
          child: Row(
            children: <Widget>[
              for (int i = 0; i < items.length; i++)
                Expanded(
                  child: _NavBarTab(
                    item: items[i],
                    active: i == currentIndex,
                    trailRight: i < items.length - 1,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBarTab extends StatelessWidget {
  const _NavBarTab({
    required this.item,
    required this.active,
    required this.trailRight,
    required this.onTap,
  });

  final AltracqNavBarItem item;
  final bool active;

  /// Arah jejak gelembung: ke kanan, kecuali tab paling ujung yang ke kiri
  /// supaya tidak terpotong sudut navigasi.
  final bool trailRight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AltracqColors.of(context);
    final theme = Theme.of(context);
    final gooey = GooeyLayer.enabledOf(context);

    final column = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        AltracqIcon(
          item.icon,
          size: 22,
          color: active ? colors.onPrimary : colors.textPrimary,
        ),
        const SizedBox(height: 2),
        // Label tombol diambil dari Semantics di atas; teks terlihat
        // dikecualikan agar nama aksesibel tidak dobel.
        ExcludeSemantics(
          child: Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? colors.onPrimary : colors.textSecondary,
            ),
          ),
        ),
      ],
    );

    Widget body;
    if (active && gooey) {
      body = GooeyLayer(
        shapes: _LiquidPill(color: colors.primary, trailRight: trailRight),
        child: Center(
          child: SizedBox(
            width: AltracqMetrics.navbarPillWidth,
            height: AltracqMetrics.navbarPillHeight,
            child: column,
          ),
        ),
      );
    } else {
      body = AnimatedContainer(
        duration: AltracqMotion.spring,
        curve: AltracqMotion.springy,
        width: active ? AltracqMetrics.navbarPillWidth : null,
        height: active ? AltracqMetrics.navbarPillHeight : null,
        decoration: active
            ? BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(AltracqRadius.pill),
              )
            : null,
        child: column,
      );
    }

    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(child: body),
      ),
    );
  }
}

/// Pill tab aktif 66×52 plus gelembung 20 px dan tetesan 12 px yang menyembul
/// dari tepi pill lalu menetap dengan animasi pegas saat tab dipilih.
class _LiquidPill extends StatelessWidget {
  const _LiquidPill({required this.color, required this.trailRight});

  final Color color;
  final bool trailRight;

  /// Ruang jejak di kedua sisi pill agar gelembung tidak terpotong.
  static const double _trail = 36;
  static const double _bubbleRest = 0.5593;
  static const double _dropletRest = 0.8254;

  @override
  Widget build(BuildContext context) {
    final double dir = trailRight ? 1 : -1;
    return SizedBox(
      width: AltracqMetrics.navbarPillWidth + 2 * _trail,
      height: AltracqMetrics.navbarPillHeight,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: <Widget>[
          Center(
            child: Container(
              width: AltracqMetrics.navbarPillWidth,
              height: AltracqMetrics.navbarPillHeight,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AltracqRadius.pill),
              ),
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: AltracqMotion.spring,
            curve: AltracqMotion.springy,
            builder: (context, t, _) {
              final bubbleX = dir * lerpDouble(0.25, _bubbleRest, t)!;
              final dropletX = dir * lerpDouble(0.45, _dropletRest, t)!;
              return Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Align(
                    alignment: Alignment(bubbleX, 0),
                    child: Transform.scale(
                      scale: lerpDouble(0.4, 1, t)!,
                      child: _circle(AltracqMetrics.navbarBubble),
                    ),
                  ),
                  Align(
                    alignment: Alignment(dropletX, 0),
                    child: Transform.scale(
                      scale: lerpDouble(0.2, 1, t)!,
                      child: _circle(AltracqMetrics.navbarDroplet),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _circle(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
