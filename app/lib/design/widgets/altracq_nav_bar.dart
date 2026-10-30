import 'package:flutter/material.dart';

import '../glass/glass_surface.dart';
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
    required this.onTap,
  });

  final AltracqNavBarItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AltracqColors.of(context);
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
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
            child: Column(
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
                      fontWeight:
                          active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? colors.onPrimary : colors.textSecondary,
                    ),
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
