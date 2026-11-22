import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../glass/glass_surface.dart';
import '../glass/hiqeo_liquid_glass.dart';
import '../motion/visual_effect_policy.dart';
import '../tokens.dart';
import '../typography.dart';
import 'line_icons.dart';
import 'nav_bar_layout.dart';

/// Item navigasi pada navbar Hiqeo.
class HiqeoNavBarItem {
  const HiqeoNavBarItem({
    required this.label,
    required this.icon,
    required this.route,
  });

  final String label;
  final HiqeoIconData icon;
  final String route;
}

/// Matriks saturasi 1,5 (150%) untuk efek kaca navbar.
@visibleForTesting
const List<double> kNavBarSaturate150 = kGlassSaturate150;

/// Status cincin sisa yang sedang berjalan secara mandiri.
class _ResidualRing {
  _ResidualRing({
    required this.center,
    required this.controller,
  });

  final double center;
  final AnimationController controller;

  double get scale {
    final t = controller.value;
    if (t <= 0.12) return 1.0;
    final progress = (t - 0.12) / (1.0 - 0.12);
    final curve = Curves.easeOut.transform(progress.clamp(0.0, 1.0));
    return ui.lerpDouble(1.0, 1.14, curve)!;
  }

  double get opacity {
    final t = controller.value;
    if (t <= 0.12) return 0.95;
    final progress = (t - 0.12) / (1.0 - 0.12);
    final curve = Curves.easeOut.transform(progress.clamp(0.0, 1.0));
    return ui.lerpDouble(0.95, 0.0, curve)!;
  }
}

/// Navigasi bawah melayang 5 tab "lensa kaca" dengan gerak morphing tiga segmen.
///
/// Lapisan kaca memakai komponen tunggal [GlassSurface] tier [GlassTier.navbar]
/// dengan pantulan vertikal simetris dan fill aman. Lensa aktif digambar tanpa
/// [BackdropFilter].
class HiqeoNavBar extends StatefulWidget {
  const HiqeoNavBar({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
    this.overMap = false,
    this.blurEnabledOverride,
    this.badgeCounts = const <int, int>{},
  });

  final int currentIndex;
  final List<HiqeoNavBarItem> items;
  final ValueChanged<int> onTap;
  final bool overMap;
  final bool? blurEnabledOverride;

  /// Jumlah lencana notifikasi per indeks tab (mis. `{3: 2}` untuk tab Grup).
  final Map<int, int> badgeCounts;

  static const Duration slideDuration = Duration(milliseconds: 600);
  static const Duration reducedSlideDuration = Duration(milliseconds: 150);

  @override
  State<HiqeoNavBar> createState() => _HiqeoNavBarState();
}

class _HiqeoNavBarState extends State<HiqeoNavBar>
    with TickerProviderStateMixin {
  late final AnimationController _transitionController;
  late final List<AnimationController> _pressControllers;
  final List<_ResidualRing> _residualRings = <_ResidualRing>[];

  late int _activeTabIndex;
  late int _oldActiveTabIndex;

  double _lastPillWidth = 0.0;
  NavBarLayout? _currentLayout;
  NavBarLayout? _startLayout;
  NavBarLayout? _targetLayout;

  double _startLensCenter = 0.0;
  double _startLensWidth = 0.0;
  double _targetLensCenter = 0.0;
  double _targetLensWidth = 0.0;

  bool _reduceMotion = false;

  static const double _kSlotTop = 5.0;
  static const double _kSlotHeight = 52.0;
  static const double _kLensRadius = 26.0;

  @override
  void initState() {
    super.initState();
    _activeTabIndex = widget.currentIndex;
    _oldActiveTabIndex = widget.currentIndex;

    _transitionController = AnimationController(
      vsync: this,
      duration: HiqeoNavBar.slideDuration,
      value: 1.0,
    );

    _pressControllers = List<AnimationController>.generate(
      widget.items.length,
      (index) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 140),
        reverseDuration: const Duration(milliseconds: 160),
        value: 0.0,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = VisualEffectPolicyScope.of(context).reduceMotion ||
        MediaQuery.disableAnimationsOf(context);
    if (reduce != _reduceMotion) {
      _reduceMotion = reduce;
      _transitionController.duration = reduce
          ? HiqeoNavBar.reducedSlideDuration
          : HiqeoNavBar.slideDuration;
    }
  }

  @override
  void didUpdateWidget(HiqeoNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex != oldWidget.currentIndex) {
      if (widget.currentIndex != _activeTabIndex) {
        _startTransition(widget.currentIndex);
      }
    }
  }

  @override
  void dispose() {
    _transitionController.dispose();
    for (final controller in _pressControllers) {
      controller.dispose();
    }
    for (final ring in _residualRings) {
      ring.controller.dispose();
    }
    _residualRings.clear();
    super.dispose();
  }

  void _onTabTapDown(int tabIndex) {
    if (tabIndex == _activeTabIndex) return;
    _pressControllers[tabIndex].animateTo(1.0, curve: Curves.easeOut);
  }

  void _onTabTapUp(int tabIndex) {
    if (tabIndex == _activeTabIndex) return;
    _pressControllers[tabIndex].animateTo(0.0, curve: Curves.easeOut);
  }

  void _onTabTapCancel(int tabIndex) {
    if (tabIndex == _activeTabIndex) return;
    _pressControllers[tabIndex].animateTo(0.0, curve: Curves.easeOut);
  }

  void _handleTap(int targetIndex) {
    if (targetIndex == _activeTabIndex) {
      widget.onTap(targetIndex);
      return;
    }

    widget.onTap(targetIndex);
    _pressControllers[targetIndex].animateTo(0.0, curve: Curves.easeOut);
    _startTransition(targetIndex);
  }

  void _startTransition(int targetIndex) {
    if (_lastPillWidth <= 0) {
      _activeTabIndex = targetIndex;
      _oldActiveTabIndex = targetIndex;
      return;
    }

    final newTargetLayout = computeNavBarLayout(
      pillWidth: _lastPillWidth,
      activeTabIndex: targetIndex,
      items: widget.items,
    );

    if (_reduceMotion) {
      _oldActiveTabIndex = _activeTabIndex;
      _activeTabIndex = targetIndex;
      _startLayout = _currentLayout ?? newTargetLayout;
      _targetLayout = newTargetLayout;
      _currentLayout = newTargetLayout;
      _startLensCenter = newTargetLayout.lensCenter;
      _startLensWidth = newTargetLayout.lensWidth;
      _targetLensCenter = newTargetLayout.lensCenter;
      _targetLensWidth = newTargetLayout.lensWidth;
      _transitionController.forward(from: 0.0);
      return;
    }

    if (_transitionController.isAnimating) {
      final currentCenter = _getLensCenter(_transitionController.value);
      final currentWidth = _getLensWidth(_transitionController.value);
      final currentLayout = _getInterpolatedLayout(_transitionController.value);

      _spawnResidualRing(currentCenter);

      _startLensCenter = currentCenter;
      _startLensWidth = currentWidth;
      _startLayout = currentLayout;
    } else {
      final currentLayout = _targetLayout ??
          computeNavBarLayout(
            pillWidth: _lastPillWidth,
            activeTabIndex: _activeTabIndex,
            items: widget.items,
          );

      _spawnResidualRing(currentLayout.lensCenter);

      _startLensCenter = currentLayout.lensCenter;
      _startLensWidth = currentLayout.lensWidth;
      _startLayout = currentLayout;
    }

    _oldActiveTabIndex = _activeTabIndex;
    _activeTabIndex = targetIndex;
    _targetLayout = newTargetLayout;
    _targetLensCenter = newTargetLayout.lensCenter;
    _targetLensWidth = newTargetLayout.lensWidth;

    _transitionController.forward(from: 0.0);
  }

  void _spawnResidualRing(double center) {
    if (_reduceMotion) return;

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    final ring = _ResidualRing(center: center, controller: controller);
    _residualRings.add(ring);

    controller.addListener(() {
      if (mounted) setState(() {});
    });

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _residualRings.remove(ring);
        ring.controller.dispose();
        if (mounted) setState(() {});
      }
    });

    controller.forward(from: 0.0);
  }

  double _getLensWidth(double t) {
    if (_reduceMotion) return _targetLensWidth;
    if (t <= 0.0) return _startLensWidth;
    if (t >= 1.0) return _targetLensWidth;

    // Segmen 1 (0..28%): menyusut ke 52 dp, Cubic(0.4, 0, 0.2, 1)
    if (t < 0.28) {
      final p = t / 0.28;
      final c = const Cubic(0.4, 0.0, 0.2, 1.0).transform(p);
      return ui.lerpDouble(_startLensWidth, 52.0, c)!;
    }

    // Segmen 2 (28..62%): lebar tetap 52 dp
    if (t < 0.62) {
      return 52.0;
    }

    // Segmen 3 (62..100%): tumbuh ke wA, Cubic(0.3, 1.3, 0.5, 1)
    final p = (t - 0.62) / (1.0 - 0.62);
    final c = const Cubic(0.3, 1.3, 0.5, 1.0).transform(p);
    return ui.lerpDouble(52.0, _targetLensWidth, c)!;
  }

  double _getLensCenter(double t) {
    if (_reduceMotion) return _targetLensCenter;
    if (t <= 0.0) return _startLensCenter;
    if (t >= 1.0) return _targetLensCenter;

    // Segmen 1 (0..28%): bergeser 30% menuju target, Cubic(0.4, 0, 0.2, 1)
    if (t < 0.28) {
      final p = t / 0.28;
      final c = const Cubic(0.4, 0.0, 0.2, 1.0).transform(p);
      return ui.lerpDouble(_startLensCenter, _targetLensCenter, 0.30 * c)!;
    }

    // Segmen 2 (28..62%): bergerak dari 30% ke 94% jarak target, Cubic(0.3, 0.7, 0.3, 1)
    if (t < 0.62) {
      final p = (t - 0.28) / (0.62 - 0.28);
      final c = const Cubic(0.3, 0.7, 0.3, 1.0).transform(p);
      return ui.lerpDouble(
        _startLensCenter,
        _targetLensCenter,
        0.30 + (0.94 - 0.30) * c,
      )!;
    }

    // Segmen 3 (62..100%): tiba di pusat target, Cubic(0.3, 1.3, 0.5, 1)
    final p = (t - 0.62) / (1.0 - 0.62);
    final c = const Cubic(0.3, 1.3, 0.5, 1.0).transform(p);
    return ui.lerpDouble(
      _startLensCenter,
      _targetLensCenter,
      0.94 + (1.0 - 0.94) * c,
    )!;
  }

  NavBarLayout _getInterpolatedLayout(double t) {
    final start = _startLayout;
    final target = _targetLayout;
    if (start == null || target == null || _reduceMotion || t >= 1.0) {
      return target ??
          computeNavBarLayout(
            pillWidth: _lastPillWidth,
            activeTabIndex: _activeTabIndex,
            items: widget.items,
          );
    }
    if (t <= 0.0) return start;

    final curveT = const Cubic(0.3, 1.15, 0.4, 1.0).transform(t.clamp(0.0, 1.0));

    final slots = <NavBarSlotLayout>[];
    for (int i = 0; i < 5; i++) {
      final s = start.slots[i];
      final tgt = target.slots[i];
      slots.add(
        NavBarSlotLayout(
          index: i,
          isActive: i == target.activeSlotIndex,
          left: ui.lerpDouble(s.left, tgt.left, curveT)!,
          width: ui.lerpDouble(s.width, tgt.width, curveT)!,
          iconXInSlot: ui.lerpDouble(s.iconXInSlot, tgt.iconXInSlot, curveT)!,
          labelXInSlot: ui.lerpDouble(s.labelXInSlot, tgt.labelXInSlot, curveT)!,
          labelWidth: tgt.labelWidth,
          hPadding: tgt.hPadding,
        ),
      );
    }

    return NavBarLayout(
      pillWidth: target.pillWidth,
      innerW: target.innerW,
      activeTabIndex: target.activeTabIndex,
      activeSlotIndex: target.activeSlotIndex,
      slots: slots,
      wA: target.wA,
      wI: target.wI,
      lensLeft: slots[target.activeSlotIndex].left,
      lensWidth: slots[target.activeSlotIndex].width,
      lensCenter: slots[target.activeSlotIndex].center,
      reducedPadding: target.reducedPadding,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);

    // Lensa tab aktif dibuat lebih ringan daripada kaca penuh agar pil navbar
    // membiarkan efek blur di belakangnya tetap terasa hidup.
    final lensFillColor = Colors.white.withValues(
      alpha: colors.brightness == Brightness.dark ? 0.18 : 0.42,
    );
    final lensBorderColor = HiqeoGlassTokens.border(colors.brightness);

    final animListenable = Listenable.merge(<Listenable>[
      _transitionController,
      ..._pressControllers,
    ]);

    return HiqeoLiquidGlassSurface(
      key: const ValueKey<String>('navbar-liquid-glass'),
      borderRadius: HiqeoRadius.navbar,
      overMap: widget.overMap,
      blurEnabledOverride: widget.blurEnabledOverride,
      child: SizedBox(
        height: HiqeoMetrics.navbarHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final pillWidth = constraints.maxWidth;
            if (pillWidth != _lastPillWidth) {
              _lastPillWidth = pillWidth;
              _targetLayout = computeNavBarLayout(
                pillWidth: pillWidth,
                activeTabIndex: _activeTabIndex,
                items: widget.items,
              );
              _startLayout ??= _targetLayout;
              _startLensCenter = _targetLayout!.lensCenter;
              _startLensWidth = _targetLayout!.lensWidth;
              _targetLensCenter = _targetLayout!.lensCenter;
              _targetLensWidth = _targetLayout!.lensWidth;
            }

            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // 1. Lapisan Lensa, Cincin Sisa, dan Efek Tekan (di atas kaca, di bawah ikon)
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: animListenable,
                        builder: (context, _) {
                          final t = _transitionController.value;
                          final lensWidth = _getLensWidth(t);
                          final lensCenter = _getLensCenter(t);
                          final currentLayout = _getInterpolatedLayout(t);

                          return CustomPaint(
                            key: const ValueKey<String>('navbar-lens'),
                            painter: _NavBarLensPainter(
                              colors: colors,
                              lensCenter: lensCenter,
                              lensWidth: lensWidth,
                              lensTop: _kSlotTop,
                              lensHeight: _kSlotHeight,
                              lensRadius: _kLensRadius,
                              lensFillColor: lensFillColor,
                              lensBorderColor: lensBorderColor,
                              rings: _residualRings,
                              pressControllers: _pressControllers,
                              layout: currentLayout,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),

                // 2. Lapisan 5 Tab (Beranda, Peta, Track, Grup, Profil)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: animListenable,
                    builder: (context, _) {
                      final t = _transitionController.value;
                      final currentLayout = _getInterpolatedLayout(t);

                      return Stack(
                        children: <Widget>[
                          for (int i = 0; i < widget.items.length; i++)
                            _buildTabSlot(
                              tabIndex: i,
                              layout: currentLayout,
                              colors: colors,
                              t: t,
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTabSlot({
    required int tabIndex,
    required NavBarLayout layout,
    required HiqeoColors colors,
    required double t,
  }) {
    final item = widget.items[tabIndex];
    final slot = layout.slots[tabIndex];
    final isActive = tabIndex == _activeTabIndex;
    final isOldActive =
        tabIndex == _oldActiveTabIndex && _transitionController.isAnimating;

    // Crossfade warna ikon 200 ms (t / 0.333)
    final colorProgress =
        _reduceMotion ? 1.0 : (t / (200.0 / 600.0)).clamp(0.0, 1.0);
    final Color iconColor;
    if (isActive) {
      iconColor =
          Color.lerp(colors.textSecondary, colors.textPrimary, colorProgress)!;
    } else if (isOldActive) {
      iconColor =
          Color.lerp(colors.textPrimary, colors.textSecondary, colorProgress)!;
    } else {
      iconColor = colors.textSecondary;
    }

    // Label opacity
    double labelOpacity = 0.0;
    if (_reduceMotion) {
      labelOpacity = isActive ? 1.0 : 0.0;
    } else if (isActive) {
      // Fade in 200 ms setelah jeda 320 ms (interval 0.533 s.d. 0.867)
      const startT = 320.0 / 600.0;
      const endT = 520.0 / 600.0;
      if (t >= endT) {
        labelOpacity = 1.0;
      } else if (t > startT) {
        labelOpacity = Curves.easeOut.transform((t - startT) / (endT - startT));
      }
    } else if (isOldActive) {
      // Fade out 100 ms (easeIn)
      const fadeOutEnd = 100.0 / 600.0;
      if (t <= fadeOutEnd) {
        labelOpacity = 1.0 - Curves.easeIn.transform(t / fadeOutEnd);
      }
    }

    final badgeCount = widget.badgeCounts[tabIndex] ?? 0;

    return Positioned(
      left: slot.left,
      top: 0,
      width: slot.width,
      height: HiqeoMetrics.navbarHeight,
      child: Semantics(
        button: true,
        selected: isActive,
        label: badgeCount > 0 ? '${item.label}, $badgeCount undangan baru' : item.label,
        tooltip: isActive ? null : item.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _onTabTapDown(tabIndex),
          onTapUp: (_) => _onTabTapUp(tabIndex),
          onTapCancel: () => _onTabTapCancel(tabIndex),
          onTap: () => _handleTap(tabIndex),
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              // Ikon
              Positioned(
                left: slot.iconXInSlot,
                top: _kSlotTop + (_kSlotHeight - 24.0) / 2.0,
                width: 24.0,
                height: 24.0,
                child: ExcludeSemantics(
                  child: HiqeoIcon(
                    item.icon,
                    size: 24.0,
                    color: iconColor,
                    strokeWidth: HiqeoMetrics.iconStroke,
                  ),
                ),
              ),

              // Lencana notifikasi (mis. undangan grup baru di tab Grup)
              if (badgeCount > 0)
                Positioned(
                  left: slot.iconXInSlot + 14.0,
                  top: _kSlotTop + (_kSlotHeight - 24.0) / 2.0 - 5.0,
                  child: ExcludeSemantics(
                    child: Container(
                      key: ValueKey<String>('navbar-badge-$tabIndex'),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: colors.warning,
                        borderRadius: BorderRadius.circular(HiqeoRadius.pill),
                        border: Border.all(
                          color: colors.surface,
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          badgeCount > 9 ? '9+' : '$badgeCount',
                          style: TextStyle(
                            fontFamily: HiqeoTypography.family,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                            color: HiqeoColors.light.glassHighlight,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // Label (hanya aktif atau saat fade out tab lama) tanpa Opacity saveLayer
              if (labelOpacity > 0.0)
                Positioned(
                  left: slot.labelXInSlot,
                  top: _kSlotTop,
                  height: _kSlotHeight,
                  child: ExcludeSemantics(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: const TextStyle(
                          fontFamily: HiqeoTypography.family,
                          fontSize: 12.0,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ).copyWith(
                          color: colors.textPrimary.withValues(
                            alpha: labelOpacity.clamp(0.0, 1.0),
                          ),
                        ),
                      ),
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

/// Melukis lensa (indikator aktif), cincin sisa, dan efek tekan tanpa
/// BackdropFilter dan tanpa bercak putih lokal.
class _NavBarLensPainter extends CustomPainter {
  const _NavBarLensPainter({
    required this.colors,
    required this.lensCenter,
    required this.lensWidth,
    required this.lensTop,
    required this.lensHeight,
    required this.lensRadius,
    required this.lensFillColor,
    required this.lensBorderColor,
    required this.rings,
    required this.pressControllers,
    required this.layout,
  });

  final HiqeoColors colors;
  final double lensCenter;
  final double lensWidth;
  final double lensTop;
  final double lensHeight;
  final double lensRadius;
  final Color lensFillColor;
  final Color lensBorderColor;
  final List<_ResidualRing> rings;
  final List<AnimationController> pressControllers;
  final NavBarLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = lensTop + lensHeight / 2.0;

    // 1. Cincin Sisa di posisi lensa lama
    for (final ring in rings) {
      final ringOpacity = ring.opacity;
      if (ringOpacity > 0.0) {
        final ringRadius = (lensHeight / 2.0) * ring.scale;
        final ringCenter = Offset(ring.center, centerY);

        final ringFill = lensFillColor.withValues(
          alpha: lensFillColor.a * ringOpacity,
        );
        final ringBorder = lensBorderColor.withValues(
          alpha: lensBorderColor.a * ringOpacity,
        );

        canvas.drawCircle(ringCenter, ringRadius, Paint()..color = ringFill);
        canvas.drawCircle(
          ringCenter,
          math.max(0.0, ringRadius - 0.6),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = ringBorder,
        );
      }
    }

    // 2. Efek Tekan di tab tidak aktif
    for (int i = 0; i < pressControllers.length; i++) {
      final val = pressControllers[i].value;
      if (val > 0.0) {
        final slot = layout.slots[i];
        final iconCenter = Offset(
          slot.left + slot.iconXInSlot + 12.0,
          centerY,
        );

        final pressScale = ui.lerpDouble(0.6, 1.0, val)!;
        final pressOpacity = val.clamp(0.0, 1.0);
        final radius = (lensHeight / 2.0) * pressScale;

        final fill = lensFillColor.withValues(
          alpha: lensFillColor.a * pressOpacity,
        );
        final border = colors.hairline.withValues(
          alpha: colors.hairline.a * pressOpacity,
        );

        canvas.drawCircle(iconCenter, radius, Paint()..color = fill);
        canvas.drawCircle(
          iconCenter,
          math.max(0.0, radius - 0.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..color = border,
        );
      }
    }

    // 3. Lensa aktif (fill + border + bayangan lembut; tanpa bercak putih)
    final lensLeft = lensCenter - lensWidth / 2.0;
    final lensRect = Rect.fromLTWH(lensLeft, lensTop, lensWidth, lensHeight);
    final lensRRect = RRect.fromRectAndRadius(
      lensRect,
      Radius.circular(lensRadius),
    );

    final shadowPaint = Paint()
      ..color = colors.glassShadow
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7.0);
    canvas.drawRRect(lensRRect.shift(const Offset(0, 4)), shadowPaint);

    canvas.drawRRect(lensRRect, Paint()..color = lensFillColor);

    canvas.drawRRect(
      lensRRect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = lensBorderColor,
    );
  }

  @override
  bool shouldRepaint(_NavBarLensPainter oldDelegate) {
    if (lensCenter != oldDelegate.lensCenter ||
        lensWidth != oldDelegate.lensWidth ||
        lensFillColor != oldDelegate.lensFillColor ||
        lensBorderColor != oldDelegate.lensBorderColor ||
        colors != oldDelegate.colors ||
        rings.isNotEmpty ||
        oldDelegate.rings.isNotEmpty) {
      return true;
    }
    for (final c in pressControllers) {
      if (c.value > 0.0) return true;
    }
    return false;
  }
}
