import 'package:flutter/material.dart';

import '../tokens.dart';

/// Varian tombol mengikuti rancangan: primer isi penuh, sekunder abu, dan
/// invers untuk tombol terang di atas kartu gelap.
enum HiqeoButtonVariant { primary, secondary, inverse }

/// Tinggi tombol. 56 px berada di atas target sentuh minimum 44 px.
const double _kButtonHeight = 56;

/// Umpan balik tekan: mengecil sedikit dan meredup tipis.
const double _kPressedScale = 0.97;
const double _kPressedOpacity = 0.92;
const double _kDisabledOpacity = 0.6;

Color _fillFor(HiqeoColors colors, HiqeoButtonVariant variant) =>
    switch (variant) {
      HiqeoButtonVariant.primary => colors.primary,
      HiqeoButtonVariant.secondary => colors.secondary,
      HiqeoButtonVariant.inverse => colors.onPrimary,
    };

Color _foregroundFor(HiqeoColors colors, HiqeoButtonVariant variant) =>
    switch (variant) {
      HiqeoButtonVariant.primary => colors.onPrimary,
      HiqeoButtonVariant.secondary => colors.textPrimary,
      HiqeoButtonVariant.inverse => colors.primary,
    };

/// Satu pil solid: radius sama dengan separuh tinggi, satu warna, tepi bersih.
class _PressablePill extends StatefulWidget {
  const _PressablePill({
    required this.fill,
    required this.semanticLabel,
    required this.child,
    this.onPressed,
  });

  final Color fill;
  final String semanticLabel;
  final Widget child;
  final VoidCallback? onPressed;

  @override
  State<_PressablePill> createState() => _PressablePillState();
}

class _PressablePillState extends State<_PressablePill> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final double opacity = !_enabled
        ? _kDisabledOpacity
        : (_pressed ? _kPressedOpacity : 1);
    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        onTapDown: _enabled ? (_) => _setPressed(true) : null,
        onTapUp: _enabled ? (_) => _setPressed(false) : null,
        onTapCancel: _enabled ? () => _setPressed(false) : null,
        child: AnimatedScale(
          scale: _pressed ? _kPressedScale : 1,
          duration: HiqeoMotion.press,
          curve: HiqeoMotion.standard,
          child: AnimatedOpacity(
            opacity: opacity,
            duration: HiqeoMotion.press,
            curve: HiqeoMotion.standard,
            child: SizedBox(
              height: _kButtonHeight,
              width: double.infinity,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: widget.fill,
                  shape: const StadiumBorder(),
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: HiqeoSpacing.lg,
                      ),
                      child: ExcludeSemantics(child: widget.child),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tombol lebar penuh berbentuk pil sempurna.
class HiqeoButton extends StatelessWidget {
  const HiqeoButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = HiqeoButtonVariant.primary,
    this.semanticLabel,
    this.leading,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final HiqeoButtonVariant variant;
  final String? semanticLabel;

  /// Logo atau ikon di depan label, misalnya logo Google dan Apple.
  final Widget? leading;

  /// Indikator sedang memproses aksi. Saat true, tombol dinonaktifkan untuk
  /// mencegah ketukan ganda dan menampilkan indikator loading.
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    final fg = _foregroundFor(colors, variant);
    final text = Text(
      label,
      maxLines: 1,
      style: theme.textTheme.titleSmall?.copyWith(
        color: fg,
      ),
    );
    final effectiveLeading = isLoading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(fg),
            ),
          )
        : leading;
    return _PressablePill(
      fill: _fillFor(colors, variant),
      semanticLabel: semanticLabel ?? label,
      onPressed: isLoading ? null : onPressed,
      child: effectiveLeading == null
          ? text
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ExcludeSemantics(child: effectiveLeading),
                const SizedBox(width: HiqeoSpacing.md),
                text,
              ],
            ),
    );
  }
}

/// Dua pil solid berdampingan dengan celah 12 px. Keduanya tombol terpisah
/// yang utuh; tidak ada bentuk yang menjembatani celah.
class HiqeoButtonPair extends StatelessWidget {
  const HiqeoButtonPair({
    super.key,
    required this.leftLabel,
    required this.rightLabel,
    required this.onLeftTap,
    required this.onRightTap,
    this.leftVariant = HiqeoButtonVariant.secondary,
    this.rightVariant = HiqeoButtonVariant.primary,
    this.leftSemanticLabel,
    this.rightSemanticLabel,
  });

  final String leftLabel;
  final String rightLabel;
  final VoidCallback? onLeftTap;
  final VoidCallback? onRightTap;
  final HiqeoButtonVariant leftVariant;
  final HiqeoButtonVariant rightVariant;
  final String? leftSemanticLabel;
  final String? rightSemanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final theme = Theme.of(context);
    Widget pill(
      String label,
      String? semanticLabel,
      HiqeoButtonVariant variant,
      VoidCallback? onTap,
    ) =>
        _PressablePill(
          fill: _fillFor(colors, variant),
          semanticLabel: semanticLabel ?? label,
          onPressed: onTap,
          child: Text(
            label,
            maxLines: 1,
            style: theme.textTheme.titleSmall?.copyWith(
              color: _foregroundFor(colors, variant),
            ),
          ),
        );

    return Row(
      children: <Widget>[
        Expanded(
          child: pill(leftLabel, leftSemanticLabel, leftVariant, onLeftTap),
        ),
        const SizedBox(width: HiqeoMetrics.buttonPairGap),
        Expanded(
          child: pill(rightLabel, rightSemanticLabel, rightVariant, onRightTap),
        ),
      ],
    );
  }
}
