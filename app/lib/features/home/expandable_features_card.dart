import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../design/glass/glass_surface.dart';
import '../../design/gooey/gooey_layer.dart';
import '../../design/motion/visual_effect_policy.dart';
import '../../design/tokens.dart';
import '../../design/widgets/line_icons.dart';

/// Satu kartu fitur di grid "Semua fitur". Aksi diserahkan pemanggil supaya
/// kartu lipat ini tidak perlu tahu apa-apa tentang rute.
class FeatureEntry {
  const FeatureEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.emphasis = false,
  });

  final AltracqIconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool emphasis;
}

/// Kartu "Semua fitur" yang bisa dilipat.
///
/// Tertutup: satu baris kaca 64 px berisi judul dan satu tombol bulat.
/// Terbuka: persegi panjang radius 28 dengan grid fitur yang keluar dari posisi
/// tombol. Selama morph, latar kartu dan latar tiap fitur digambar lewat
/// [GooeyLayer] sehingga terlepas lewat leher cair; setelah animasi selesai
/// lapisan itu dibuang dan diganti kaca tajam, jadi tidak ada filter ambang alfa
/// yang tertinggal aktif.
class ExpandableFeaturesCard extends StatefulWidget {
  const ExpandableFeaturesCard({
    super.key,
    required this.features,
    this.title = 'Semua fitur',
  });

  final List<FeatureEntry> features;
  final String title;

  static const double collapsedHeight = 64;
  static const double cellHeight = 140;
  static const double cellGap = AltracqSpacing.md;
  static const double toggleSize = AltracqMetrics.minTouchTarget;

  @override
  State<ExpandableFeaturesCard> createState() => _ExpandableFeaturesCardState();
}

class _ExpandableFeaturesCardState extends State<ExpandableFeaturesCard>
    with SingleTickerProviderStateMixin {
  static const Duration _morphDuration = Duration(milliseconds: 550);
  static const Duration _plainDuration = AltracqMotion.screenFade;

  /// Jeda antar kartu 35 ms, dinyatakan sebagai bagian dari durasi total.
  static const double _staggerFraction = 35 / 550;

  /// Kaca memudar jadi bentuk cair, lalu bentuk cair memudar jadi kaca tajam.
  static const double _gooeyIn = 0.15;
  static const double _gooeyOutStart = 0.6;
  static const double _gooeyOutEnd = 0.88;

  /// Skala awal kartu fitur saat keluar dari tombol.
  static const double _cellScaleStart = 0.6;

  final GlobalKey _cardKey = GlobalKey();
  late final AnimationController _controller;
  bool _expanded = false;
  bool _reduceMotion = false;
  bool _gooeyAllowed = false;
  bool _glassBlur = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _morphDuration);
    _controller.addStatusListener(_onStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final policy = VisualEffectPolicyScope.of(context);
    _reduceMotion = policy.reduceMotion;
    _gooeyAllowed = policy.gooey;
    _glassBlur = policy.glassBlur;
    _controller.duration = _reduceMotion ? _plainDuration : _morphDuration;
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    // Satu bingkai ditunggu supaya tinggi akhir kartu sudah terpasang saat
    // digulir; status selesai tiba sebelum bingkai itu dibangun.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_reveal());
    });
  }

  /// Setelah terbuka, kartu digulir sampai terlihat seluruhnya.
  Future<void> _reveal() async {
    final target = _cardKey.currentContext;
    if (target == null || Scrollable.maybeOf(target) == null) return;
    await Scrollable.ensureVisible(
      target,
      alignment: 1,
      duration: AltracqMotion.spring,
      curve: AltracqMotion.standard,
    );
  }

  void _toggle() {
    final expand = !_expanded;
    setState(() => _expanded = expand);
    if (expand) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  int get _rows => (widget.features.length + 1) ~/ 2;

  double get _gridHeight =>
      _rows * ExpandableFeaturesCard.cellHeight +
      (_rows - 1) * ExpandableFeaturesCard.cellGap +
      AltracqSpacing.lg;

  double get _staggerTotal => _reduceMotion
      ? 0
      : (widget.features.length - 1) * _staggerFraction;

  /// Kemajuan 0..1 kartu fitur ke-[index]; makin belakang makin telat.
  double _tileT(int index, double t) {
    final span = 1 - _staggerTotal;
    final start =
        index * _staggerTotal / math.max(1, widget.features.length - 1);
    return ((t - start) / span).clamp(0.0, 1.0);
  }

  double _tileProgress(int index, double t) =>
      Curves.easeOutCubic.transform(_tileT(index, t));

  /// Tinggi wadah mengikuti kartu terakhir supaya kartu yang lebih dulu jalan
  /// menonjol keluar dan membentuk leher cair.
  double _grow(double t) => _reduceMotion
      ? t
      : _tileProgress(math.max(0, widget.features.length - 1), t);

  double _radiusFor(double t) => ExpandableFeaturesCard.collapsedHeight / 2 +
      (AltracqRadius.hero - ExpandableFeaturesCard.collapsedHeight / 2) * t;

  /// 0 berarti kaca tajam, 1 berarti seluruhnya bentuk cair.
  double _gooeyOpacity(double t) {
    if (!_gooeyAllowed || t <= 0 || t >= 1) return 0;
    if (t < _gooeyIn) return t / _gooeyIn;
    if (t < _gooeyOutStart) return 1;
    return 1 -
        ((t - _gooeyOutStart) / (_gooeyOutEnd - _gooeyOutStart)).clamp(0.0, 1.0);
  }

  Offset _toggleCenter(double width) => Offset(
        width -
            AltracqSpacing.lg -
            ExpandableFeaturesCard.toggleSize / 2,
        ExpandableFeaturesCard.collapsedHeight / 2,
      );

  /// Kotak tujuan kartu fitur, dalam koordinat kartu (bukan koordinat grid).
  Rect _cellRect(int index, double width) {
    final cellWidth =
        (width - AltracqSpacing.lg * 2 - ExpandableFeaturesCard.cellGap) / 2;
    final column = index % 2;
    final row = index ~/ 2;
    return Rect.fromLTWH(
      AltracqSpacing.lg + column * (cellWidth + ExpandableFeaturesCard.cellGap),
      ExpandableFeaturesCard.collapsedHeight +
          row * (ExpandableFeaturesCard.cellHeight + ExpandableFeaturesCard.cellGap),
      cellWidth,
      ExpandableFeaturesCard.cellHeight,
    );
  }

  Offset _cellDelta(int index, double width, double t) {
    final progress = _tileProgress(index, t);
    final rect = _cellRect(index, width);
    final from = _toggleCenter(width);
    final to = rect.center;
    return Offset.lerp(from, to, progress)! - to;
  }

  double _cellScale(int index, double t) => _cellScaleStart +
      (1 - _cellScaleStart) * _tileProgress(index, t);

  @override
  Widget build(BuildContext context) {
    final colors = AltracqColors.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final gooey = _gooeyOpacity(t);
            return SizedBox(
              key: _cardKey,
              width: width,
              height: ExpandableFeaturesCard.collapsedHeight +
                  _grow(t) * _gridHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned.fill(
                    child: _background(colors, t, width, gooey),
                  ),
                  Positioned.fill(child: _content(t, width, gooey)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _background(
    AltracqColors colors,
    double t,
    double width,
    double gooey,
  ) {
    final radius = BorderRadius.circular(_radiusFor(t));
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        if (gooey < 1)
          Positioned.fill(
            child: Opacity(
              opacity: 1 - gooey,
              child: GlassSurface(borderRadius: _radiusFor(t)),
            ),
          ),
        if (gooey > 0)
          Positioned.fill(
            child: Opacity(
              opacity: gooey,
              child: GooeyLayer(
                shapes: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: radius,
                        ),
                      ),
                    ),
                    for (var index = 0; index < widget.features.length; index++)
                      Positioned.fromRect(
                        rect: _cellRect(index, width)
                            .shift(_cellDelta(index, width, t)),
                        child: Transform.scale(
                          scale: _cellScale(index, t),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius:
                                  BorderRadius.circular(AltracqRadius.card),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _content(double t, double width, double gooey) {
    final opened = t >= 1;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: ExpandableFeaturesCard.collapsedHeight,
          child: _header(),
        ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !opened,
            child: ExcludeSemantics(
              excluding: !opened,
              child: _tiles(t, width, gooey, opened),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tiles(double t, double width, double gooey, bool opened) {
    // Saat tertutup penuh tidak ada yang terlihat, jadi grid tidak dibangun:
    // tidak ada blur atau opacity yang tertinggal bekerja diam-diam.
    if (!opened && t <= 0) return const SizedBox.shrink();
    final layer = Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        for (var index = 0; index < widget.features.length; index++)
          Positioned.fromRect(
            rect: _cellRect(index, width).shift(_cellDelta(index, width, t)),
            child: Transform.scale(
              scale: _cellScale(index, t),
              child: FeatureTile(
                feature: widget.features[index],
                backgroundOpacity: 1 - gooey,
              ),
            ),
          ),
      ],
    );
    if (opened) return layer;
    final faded = Opacity(opacity: t.clamp(0.0, 1.0), child: layer);
    if (!_glassBlur || _reduceMotion) return faded;
    // Isi kabur 8 -> 0 sambil muncul, sesuai rancangan.
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(
        sigmaX: 8 * (1 - t),
        sigmaY: 8 * (1 - t),
      ),
      child: faded,
    );
  }

  Widget _header() {
    final colors = AltracqColors.of(context);
    final theme = Theme.of(context);
    return Semantics(
      key: const ValueKey<String>('semua-fitur-toggle'),
      container: true,
      button: true,
      expanded: _expanded,
      label: _expanded
          ? 'Sembunyikan semua fitur'
          : 'Tampilkan semua fitur',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        // Satu tombol dengan satu label; judul dan ikon visual tidak dibacakan
        // dua kali.
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AltracqSpacing.lg,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: colors.textPrimary),
                  ),
                ),
                const SizedBox(width: AltracqSpacing.md),
                SizedBox(
                  width: ExpandableFeaturesCard.toggleSize,
                  height: ExpandableFeaturesCard.toggleSize,
                  child: GlassSurface(
                    borderRadius: AltracqRadius.pill,
                    child: Center(
                      child: AltracqIcon(
                        _expanded ? AltracqIcons.close : AltracqIcons.grid,
                        size: 22,
                        color: colors.textPrimary,
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

/// Kartu fitur tunggal. [backgroundOpacity] 0 saat latarnya sedang digambar di
/// lapisan gooey supaya tidak ada latar ganda.
class FeatureTile extends StatelessWidget {
  const FeatureTile({
    super.key,
    required this.feature,
    this.backgroundOpacity = 1,
  });

  final FeatureEntry feature;
  final double backgroundOpacity;

  @override
  Widget build(BuildContext context) {
    final colors = AltracqColors.of(context);
    final theme = Theme.of(context);
    final emphasis = feature.emphasis;
    final titleColor = emphasis ? colors.onPrimary : colors.textPrimary;
    final subtitleColor = emphasis
        ? colors.onPrimary.withValues(alpha: 0.74)
        : colors.textSecondary;
    final content = Padding(
      padding: const EdgeInsets.all(AltracqSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: emphasis
                  ? colors.onPrimary.withValues(alpha: 0.14)
                  : colors.secondary.withValues(alpha: 0.62),
            ),
            child: Center(
              child: AltracqIcon(
                feature.icon,
                size: 22,
                color: emphasis ? colors.onPrimary : colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            feature.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(color: titleColor),
          ),
          const SizedBox(height: AltracqSpacing.xs),
          Text(
            feature.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: subtitleColor),
          ),
        ],
      ),
    );

    final surface = emphasis
        ? Container(
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(AltracqRadius.card),
            ),
            child: content,
          )
        : GlassSurface(
            borderRadius: AltracqRadius.card,
            child: content,
          );

    return Semantics(
      button: true,
      label: '${feature.title}. ${feature.subtitle}',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: feature.onTap,
          child: backgroundOpacity >= 1
              ? surface
              : Opacity(opacity: backgroundOpacity, child: surface),
        ),
      ),
    );
  }
}
