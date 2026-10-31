import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../glass/glass_surface.dart';
import '../gooey/gooey_layer.dart';
import '../motion/visual_effect_policy.dart';
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

/// Kemajuan kepala blob: pegas kaku dengan pantulan yang dibatasi 4,4%.
///
/// `easeOutBack` memantul sekitar 9,9%; sebagian pantulan itu dibuang agar
/// total pantulan tetap di bawah 5% jarak perpindahan.
@visibleForTesting
double navBarHeadProgress(double t) {
  final eased = Curves.easeOutBack.transform(t);
  return 1 + (eased - 1) * AltracqNavBar.headOvershootScale;
}

/// Kemajuan ekor blob: menyusul lebih lambat dan tanpa pantulan.
@visibleForTesting
double navBarTailProgress(double t) =>
    const Interval(0.12, 1, curve: Curves.easeOutCubic).transform(t);

/// Bagian area pill tab yang tertutup blob, 0..1.
///
/// Dipakai untuk memindahkan warna ikon/label saat blob benar-benar menutup
/// atau meninggalkan tab, bukan serentak di awal atau akhir animasi.
@visibleForTesting
double navBarCoverage({
  required double tabCenter,
  required double headCenter,
  required double tailCenter,
  required double pillWidth,
}) {
  final pillLeft = (headCenter < tailCenter ? headCenter : tailCenter) -
      pillWidth / 2;
  final pillRight = (headCenter > tailCenter ? headCenter : tailCenter) +
      pillWidth / 2;
  final tabLeft = tabCenter - pillWidth / 2;
  final tabRight = tabCenter + pillWidth / 2;
  final overlap = (pillRight < tabRight ? pillRight : tabRight) -
      (pillLeft > tabLeft ? pillLeft : tabLeft);
  if (overlap <= 0) return 0;
  return (overlap / pillWidth).clamp(0.0, 1.0);
}

/// Navigasi bawah melayang: tinggi 64 px, radius 32, menjorok 16 px dari tepi.
///
/// Satu blob krem (warna primer tema) bergerak di antara tab. Kepala bergerak
/// lebih dulu dengan pegas kaku, ekor menyusul dengan pegas lembut; selama
/// bergerak keduanya disatukan [GooeyLayer] sehingga membentuk satu cairan yang
/// memanjang, tanpa gelembung atau tetesan terpisah. Kaca dan bayangan navbar
/// berada di luar lapisan gooey sehingga tidak ikut dikaburkan.
class AltracqNavBar extends StatefulWidget {
  const AltracqNavBar({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
  });

  final int currentIndex;
  final List<AltracqNavBarItem> items;
  final ValueChanged<int> onTap;

  static const Duration slideDuration = Duration(milliseconds: 500);
  static const Duration reducedSlideDuration = Duration(milliseconds: 180);

  /// Bagian pantulan `easeOutBack` yang dipakai (≈4,4% jarak).
  static const double headOvershootScale = 0.45;

  @override
  State<AltracqNavBar> createState() => _AltracqNavBarState();
}

class _AltracqNavBarState extends State<AltracqNavBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide;
  late double _startHead;
  late double _startTail;
  late double _target;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _target = widget.currentIndex.toDouble();
    _startHead = _target;
    _startTail = _target;
    _slide = AnimationController(
      vsync: this,
      duration: AltracqNavBar.slideDuration,
      value: 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = VisualEffectPolicyScope.of(context).reduceMotion;
    if (reduceMotion == _reduceMotion) return;
    _reduceMotion = reduceMotion;
    _slide.duration = reduceMotion
        ? AltracqNavBar.reducedSlideDuration
        : AltracqNavBar.slideDuration;
  }

  @override
  void didUpdateWidget(AltracqNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex == oldWidget.currentIndex) return;
    // Mulai dari posisi yang sedang terlihat supaya ketukan beruntun tidak
    // melompat; kepala dan ekor lalu mengejar tab baru dari tempat masing-masing.
    _startHead = _headPosition;
    _startTail = _tailPosition;
    _target = widget.currentIndex.toDouble();
    _slide.forward(from: 0);
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  double get _headPosition => ui.lerpDouble(
        _startHead,
        _target,
        _reduceMotion ? _slide.value : navBarHeadProgress(_slide.value),
      )!;

  double get _tailPosition => ui.lerpDouble(
        _startTail,
        _target,
        _reduceMotion ? _slide.value : navBarTailProgress(_slide.value),
      )!;

  @override
  Widget build(BuildContext context) {
    final colors = AltracqColors.of(context);
    final gooey = GooeyLayer.enabledOf(context) && !_reduceMotion;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: GlassSurface(
        borderRadius: AltracqRadius.navbar,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final count = widget.items.length;
            final cellWidth = width / count;
            return AnimatedBuilder(
              animation: _slide,
              builder: (context, _) {
                final headCenter = (_headPosition + 0.5) * cellWidth;
                final tailCenter = (_tailPosition + 0.5) * cellWidth;
                final blob = CustomPaint(
                  key: const ValueKey<String>('navbar-blob'),
                  painter: NavBarBlobPainter(
                    headCenter: headCenter,
                    tailCenter: tailCenter,
                    pillWidth: AltracqMetrics.navbarPillWidth,
                    pillHeight: AltracqMetrics.navbarPillHeight,
                    color: colors.primary,
                  ),
                );
                // Hanya selama bergerak bentuknya cair; saat diam digambar
                // tajam supaya tepi pill bersih dan tidak ada filter tersisa.
                // Nilai 0 berarti belum ada perpindahan, jadi belum perlu cair.
                final morphing = _slide.isAnimating && _slide.value > 0;
                return SizedBox(
                  height: AltracqMetrics.navbarHeight,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ExcludeSemantics(
                            child: morphing && gooey
                                ? GooeyLayer(shapes: blob)
                                : blob,
                          ),
                        ),
                      ),
                      Row(
                        children: <Widget>[
                          for (int i = 0; i < count; i++)
                            Expanded(
                              child: _NavBarTab(
                                item: widget.items[i],
                                active: i == widget.currentIndex,
                                coverage: navBarCoverage(
                                  tabCenter: (i + 0.5) * cellWidth,
                                  headCenter: headCenter,
                                  tailCenter: tailCenter,
                                  pillWidth:
                                      AltracqMetrics.navbarPillWidth,
                                ),
                                onTap: () => widget.onTap(i),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _NavBarTab extends StatelessWidget {
  const _NavBarTab({
    required this.item,
    required this.active,
    required this.coverage,
    required this.onTap,
  });

  final AltracqNavBarItem item;
  final bool active;

  /// 0 = blob jauh, 1 = blob menutup penuh area pill tab ini.
  final double coverage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AltracqColors.of(context);
    final theme = Theme.of(context);
    final iconColor =
        Color.lerp(colors.textPrimary, colors.onPrimary, coverage)!;
    final labelColor =
        Color.lerp(colors.textSecondary, colors.onPrimary, coverage)!;
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              AltracqIcon(item.icon, size: 22, color: iconColor),
              const SizedBox(height: 2),
              // Label diambil dari Semantics di atas; teks terlihat
              // dikecualikan agar nama aksesibel tidak dobel.
              ExcludeSemantics(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight:
                        coverage >= 0.5 ? FontWeight.w700 : FontWeight.w500,
                    color: labelColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Melukis blob sebagai satu bentuk: pill kepala, pill ekor, dan leher yang
/// menyambung keduanya. Leher menipis saat blob memanjang, tetapi tidak pernah
/// terputus, jadi tidak ada bagian yang terlepas.
@visibleForTesting
class NavBarBlobPainter extends CustomPainter {
  const NavBarBlobPainter({
    required this.headCenter,
    required this.tailCenter,
    required this.pillWidth,
    required this.pillHeight,
    required this.color,
  });

  final double headCenter;
  final double tailCenter;
  final double pillWidth;
  final double pillHeight;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(pillHeight / 2);
    final centerY = size.height / 2;
    Path pill(double centerX) => Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(centerX, centerY),
            width: pillWidth,
            height: pillHeight,
          ),
          radius,
        ),
      );

    var path = Path.combine(
      ui.PathOperation.union,
      pill(headCenter),
      pill(tailCenter),
    );
    final gap = (headCenter - tailCenter).abs();
    if (gap > 0.5) {
      final stretch = (gap / (pillWidth * 2)).clamp(0.0, 1.0);
      final neckHeight = pillHeight * (1 - 0.5 * stretch);
      final neck = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              headCenter < tailCenter ? headCenter : tailCenter,
              centerY - neckHeight / 2,
              headCenter > tailCenter ? headCenter : tailCenter,
              centerY + neckHeight / 2,
            ),
            Radius.circular(neckHeight / 2),
          ),
        );
      path = Path.combine(ui.PathOperation.union, path, neck);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(NavBarBlobPainter oldDelegate) =>
      oldDelegate.headCenter != headCenter ||
      oldDelegate.tailCenter != tailCenter ||
      oldDelegate.pillWidth != pillWidth ||
      oldDelegate.pillHeight != pillHeight ||
      oldDelegate.color != color;
}
