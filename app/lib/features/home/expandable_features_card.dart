import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../design/glass/glass_surface.dart';
import '../../design/motion/visual_effect_policy.dart';
import '../../design/tokens.dart';
import '../../design/widgets/line_icons.dart';

/// Satu kartu fitur di grid "Fitur Utama". Aksi diserahkan pemanggil supaya
/// kartu lipat ini tidak perlu tahu apa-apa tentang rute.
class FeatureEntry {
  const FeatureEntry({
    required this.icon,
    required this.title,
    this.subtitle = '',
    required this.onTap,
    this.emphasis = false,
    this.tileKey,
  });

  final HiqeoIconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool emphasis;
  final Key? tileKey;
}

const Cubic kExpandCurve = Cubic(0.2, 0.8, 0.2, 1.0);
const Cubic kCollapseCurve = Cubic(0.4, 0.0, 0.2, 1.0);

/// Panel "Fitur Utama" yang bisa dilipat dengan animasi stagger dan tinggi
/// dinamis.
///
/// Panel luar memakai [GlassSurface] tier [GlassTier.card]; setiap tile di
/// dalamnya memakai fill solid (tanpa blur) tinggi 132 dp, radius 22, padding
/// 14, ikon lingkaran 40 dp di kiri atas, dan nama fitur 16 sp bold di kiri
/// bawah tanpa subjudul.
class ExpandableFeaturesCard extends StatefulWidget {
  const ExpandableFeaturesCard({
    super.key,
    required this.features,
    this.title = 'Fitur utama',
    this.initiallyExpanded = false,
  });

  final List<FeatureEntry> features;
  final String title;
  final bool initiallyExpanded;

  static const double collapsedHeight = 52.0;
  static const double cellHeight = 132.0;
  static const double cellRadius = 22.0;
  static const double cellGap = 10.0;
  static const double toggleSize = 36.0;

  @override
  State<ExpandableFeaturesCard> createState() => _ExpandableFeaturesCardState();
}

class _ExpandableFeaturesCardState extends State<ExpandableFeaturesCard>
    with SingleTickerProviderStateMixin {
  static const int _closeTotalMs = 440;

  int get _openTotalMs => math.max(
        380,
        90 + math.max(0, widget.features.length - 1) * 35 + 280,
      );

  late final AnimationController _controller;
  late bool _expanded;
  late bool _opening;
  double? _initialScrollOffset;
  double _scrollOverflow = 0.0;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _opening = widget.initiallyExpanded;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _openTotalMs),
      value: widget.initiallyExpanded ? 1.0 : 0.0,
    )..addListener(_onTick);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  bool _isReducedMotion() {
    return VisualEffectPolicyScope.of(context).reduceMotion ||
        MediaQuery.disableAnimationsOf(context);
  }

  int get _rows => (widget.features.length + 1) ~/ 2;

  double get _gridHeight => _rows == 0
      ? 0.0
      : _rows * ExpandableFeaturesCard.cellHeight +
          (_rows - 1) * ExpandableFeaturesCard.cellGap +
          16.0;

  void _onTick() {
    if (!mounted || _scrollOverflow <= 0) return;
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null ||
        !scrollable.position.hasPixels ||
        _initialScrollOffset == null) {
      return;
    }

    final t = _controller.value;
    final reduceMotion = _isReducedMotion();
    final double scrollProgress;

    if (reduceMotion) {
      scrollProgress = _opening ? t : (1.0 - t);
    } else if (_opening) {
      scrollProgress = Interval(
        0.0,
        (380 / _openTotalMs).clamp(0.0, 1.0),
        curve: kExpandCurve,
      ).transform(t);
    } else {
      final collapse = const Interval(
        120 / _closeTotalMs,
        1.0,
        curve: kCollapseCurve,
      ).transform(t);
      scrollProgress = 1.0 - collapse;
    }

    final target = _initialScrollOffset! + _scrollOverflow * scrollProgress;
    scrollable.position.jumpTo(target);
  }

  void _toggle() {
    final willExpand = !_expanded;
    final reduceMotion = _isReducedMotion();
    final openHeight = ExpandableFeaturesCard.collapsedHeight + _gridHeight;

    setState(() {
      _expanded = willExpand;
      _opening = willExpand;
    });

    final scrollable = Scrollable.maybeOf(context);

    if (willExpand) {
      if (scrollable != null && scrollable.position.hasPixels) {
        _initialScrollOffset = scrollable.position.pixels;
        final renderObject = context.findRenderObject() as RenderBox?;
        if (renderObject != null) {
          final viewport = RenderAbstractViewport.maybeOf(renderObject);
          if (viewport != null) {
            final cardTopInViewport = renderObject
                .localToGlobal(Offset.zero, ancestor: viewport as RenderObject)
                .dy;
            final viewportHeight = scrollable.position.viewportDimension;
            final overflow = (cardTopInViewport + openHeight) - viewportHeight;
            _scrollOverflow = overflow > 0 ? (overflow + 16.0) : 0.0;
          }
        }
      }

      final duration = reduceMotion
          ? HiqeoMotion.screenFade
          : Duration(milliseconds: _openTotalMs);
      _controller.duration = duration;
      _controller.forward(from: 0.0);
    } else {
      final duration = reduceMotion
          ? HiqeoMotion.screenFade
          : const Duration(milliseconds: _closeTotalMs);
      _controller.duration = duration;
      _controller.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final openHeight = ExpandableFeaturesCard.collapsedHeight + _gridHeight;
    final reduceMotion = _isReducedMotion();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cellWidth = (width - 32.0 - ExpandableFeaturesCard.cellGap) / 2;

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final isAnimating = _controller.isAnimating;

            final double currentHeight;
            if (reduceMotion) {
              if (_opening) {
                currentHeight = ExpandableFeaturesCard.collapsedHeight +
                    (openHeight - ExpandableFeaturesCard.collapsedHeight) * t;
              } else {
                currentHeight = openHeight -
                    (openHeight - ExpandableFeaturesCard.collapsedHeight) * t;
              }
            } else if (isAnimating) {
              if (_opening) {
                final progress = Interval(
                  0.0,
                  (380 / _openTotalMs).clamp(0.0, 1.0),
                  curve: kExpandCurve,
                ).transform(t);
                currentHeight = ExpandableFeaturesCard.collapsedHeight +
                    (openHeight - ExpandableFeaturesCard.collapsedHeight) *
                        progress;
              } else {
                final collapse = const Interval(
                  120 / _closeTotalMs,
                  1.0,
                  curve: kCollapseCurve,
                ).transform(t);
                currentHeight = openHeight -
                    (openHeight - ExpandableFeaturesCard.collapsedHeight) *
                        collapse;
              }
            } else {
              currentHeight = _expanded
                  ? openHeight
                  : ExpandableFeaturesCard.collapsedHeight;
            }

            final double iconProgress;
            if (reduceMotion) {
              iconProgress = _opening ? t : (1.0 - t);
            } else if (isAnimating) {
              if (_opening) {
                iconProgress = Interval(
                  0.0,
                  (200 / _openTotalMs).clamp(0.0, 1.0),
                  curve: Curves.easeOut,
                ).transform(t);
              } else {
                iconProgress = 1.0 -
                    const Interval(
                      0.0,
                      200 / _closeTotalMs,
                      curve: Curves.easeOut,
                    ).transform(t);
              }
            } else {
              iconProgress = _expanded ? 1.0 : 0.0;
            }

            return GlassSurface(
              key: const ValueKey<String>('fitur-utama-panel'),
              tier: GlassTier.card,
              borderRadius: 28,
              child: SizedBox(
                width: width,
                height: currentHeight,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: <Widget>[
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: ExpandableFeaturesCard.collapsedHeight,
                      child: _header(colors, iconProgress),
                    ),
                    if (_expanded || isAnimating)
                      Positioned(
                        top: ExpandableFeaturesCard.collapsedHeight,
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          ignoring: !_expanded || isAnimating,
                          child: ExcludeSemantics(
                            excluding: !_expanded,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: <Widget>[
                                  for (var i = 0;
                                      i < widget.features.length;
                                      i++)
                                    _buildAnimatedTile(
                                      index: i,
                                      cellWidth: cellWidth,
                                      t: t,
                                      isAnimating: isAnimating,
                                      reduceMotion: reduceMotion,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAnimatedTile({
    required int index,
    required double cellWidth,
    required double t,
    required bool isAnimating,
    required bool reduceMotion,
  }) {
    final column = index % 2;
    final row = index ~/ 2;
    final left = column * (cellWidth + ExpandableFeaturesCard.cellGap);
    final top =
        row * (ExpandableFeaturesCard.cellHeight + ExpandableFeaturesCard.cellGap);

    double cardOpacity;
    double cardOffsetY;

    if (reduceMotion) {
      cardOpacity = _opening ? t : (1.0 - t);
      cardOffsetY = 0.0;
    } else if (isAnimating) {
      if (_opening) {
        final delayMs = 90 + index * 35;
        final fadeEnd = delayMs + 220;
        final slideEnd = delayMs + 280;

        cardOpacity = Interval(
          (delayMs / _openTotalMs).clamp(0.0, 1.0),
          (fadeEnd / _openTotalMs).clamp(0.0, 1.0),
          curve: Curves.easeOut,
        ).transform(t);

        final slideProgress = Interval(
          (delayMs / _openTotalMs).clamp(0.0, 1.0),
          (slideEnd / _openTotalMs).clamp(0.0, 1.0),
          curve: kExpandCurve,
        ).transform(t);

        cardOffsetY = 10.0 * (1.0 - slideProgress);
      } else {
        final lastIdx = math.max(0, widget.features.length - 1);
        final delayMs = (lastIdx - index) * 15;
        final fadeEnd = delayMs + 140;

        final fadeProgress = Interval(
          (delayMs / _closeTotalMs).clamp(0.0, 1.0),
          (fadeEnd / _closeTotalMs).clamp(0.0, 1.0),
          curve: Curves.easeIn,
        ).transform(t);

        cardOpacity = (1.0 - fadeProgress).clamp(0.0, 1.0);
        cardOffsetY = 6.0 * fadeProgress;
      }
    } else {
      cardOpacity = _expanded ? 1.0 : 0.0;
      cardOffsetY = _expanded ? 0.0 : 10.0;
    }

    if (!isAnimating && _expanded) {
      return Positioned(
        left: left,
        top: top,
        width: cellWidth,
        height: ExpandableFeaturesCard.cellHeight,
        child: FeatureTile(
          key: widget.features[index].tileKey,
          feature: widget.features[index],
        ),
      );
    }

    return Positioned(
      left: left,
      top: top,
      width: cellWidth,
      height: ExpandableFeaturesCard.cellHeight,
      child: Transform.translate(
        offset: Offset(0, cardOffsetY),
        child: Opacity(
          opacity: cardOpacity.clamp(0.0, 1.0),
          child: FeatureTile(
            key: widget.features[index].tileKey,
            feature: widget.features[index],
          ),
        ),
      ),
    );
  }

  Widget _header(HiqeoColors colors, double iconProgress) {
    final theme = Theme.of(context);
    final labelTarget = widget.title.toLowerCase();
    return Semantics(
      key: const ValueKey<String>('semua-fitur-toggle'),
      container: true,
      button: true,
      expanded: _expanded,
      label: _expanded ? 'Sembunyikan $labelTarget' : 'Tampilkan $labelTarget',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 17,
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: ExpandableFeaturesCard.toggleSize,
                  height: ExpandableFeaturesCard.toggleSize,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.secondary.withValues(alpha: 0.45),
                    ),
                    child: Center(
                      child: Transform.rotate(
                        angle: iconProgress * 0.5 * math.pi,
                        child: Stack(
                          alignment: Alignment.center,
                          children: <Widget>[
                            Opacity(
                              opacity: (1.0 - iconProgress).clamp(0.0, 1.0),
                              child: HiqeoIcon(
                                HiqeoIcons.grid,
                                size: 18,
                                color: colors.textPrimary,
                              ),
                            ),
                            Opacity(
                              opacity: iconProgress.clamp(0.0, 1.0),
                              child: HiqeoIcon(
                                HiqeoIcons.close,
                                size: 18,
                                color: colors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
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

/// Kartu fitur tunggal pada grid 2x2 Fitur Utama.
///
/// Tinggi 132 dp, radius 22, padding 14, ikon lingkaran 40 dp di kiri atas,
/// dan nama fitur 16 sp bold (1–2 baris) di kiri bawah. Fill solid tanpa blur;
/// tile penekanan (SOS) memakai kartu krem [HiqeoColors.light.background].
class FeatureTile extends StatelessWidget {
  const FeatureTile({
    super.key,
    required this.feature,
  });

  final FeatureEntry feature;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final emphasis = feature.emphasis;

    // SOS memakai kartu krem (token background terang #F6F3ED + teks navy #313851)
    final Color cardFill =
        emphasis ? HiqeoColors.light.background : colors.surface;
    final Color titleColor =
        emphasis ? HiqeoColors.light.textPrimary : colors.textPrimary;
    final Color iconBg = emphasis
        ? HiqeoColors.light.warning.withValues(alpha: 0.14)
        : colors.secondary;
    final Color iconColor =
        emphasis ? HiqeoColors.light.warning : colors.textPrimary;
    final Color borderColor = emphasis
        ? HiqeoColors.light.warning.withValues(alpha: 0.28)
        : colors.hairline;

    final surface = Material(
      color: cardFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ExpandableFeaturesCard.cellRadius),
        side: BorderSide(color: borderColor, width: 1.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: feature.onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: iconBg,
                ),
                child: Center(
                  child: HiqeoIcon(
                    feature.icon,
                    size: 20,
                    color: iconColor,
                  ),
                ),
              ),
              Text(
                feature.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 16,
                  height: 1.2,
                  color: titleColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      label: feature.title,
      child: ExcludeSemantics(
        child: surface,
      ),
    );
  }
}
