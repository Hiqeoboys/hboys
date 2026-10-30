import 'package:flutter/material.dart';

import '../tokens.dart';

/// Varian tombol mengikuti rancangan: primer isi penuh, sekunder abu, dan
/// invers untuk tombol terang di atas kartu gelap.
enum AltracqButtonVariant { primary, secondary, inverse }

/// Tinggi tombol. 56 px berada di atas target sentuh minimum 44 px.
const double _kButtonHeight = 56;

/// Umpan balik tekan: mengecil sedikit dan meredup tipis.
const double _kPressedScale = 0.97;
const double _kPressedOpacity = 0.92;
const double _kDisabledOpacity = 0.6;

Color _fillFor(AltracqColors colors, AltracqButtonVariant variant) =>
    switch (variant) {
      AltracqButtonVariant.primary => colors.primary,
      AltracqButtonVariant.secondary => colors.secondary,
      AltracqButtonVariant.inverse => colors.onPrimary,
    };

Color _foregroundFor(AltracqColors colors, AltracqButtonVariant variant) =>
    switch (variant) {
      AltracqButtonVariant.primary => colors.onPrimary,
      AltracqButtonVariant.secondary => colors.textPrimary,
      AltracqButtonVariant.inverse => colors.primary,
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
          duration: AltracqMotion.press,
          curve: AltracqMotion.standard,
          child: AnimatedOpacity(
            opacity: opacity,
            duration: AltracqMotion.press,
            curve: AltracqMotion.standard,
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
                        horizontal: AltracqSpacing.lg,
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
class AltracqButton extends StatelessWidget {
  const AltracqButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AltracqButtonVariant.primary,
    this.semanticLabel,
    this.leading,
  });

  final String label;
  final VoidCallback? onPressed;
  final AltracqButtonVariant variant;
  final String? semanticLabel;

  /// Logo atau ikon di depan label, misalnya logo Google dan Apple.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final colors = AltracqColors.of(context);
    final theme = Theme.of(context);
    final text = Text(
      label,
      maxLines: 1,
      style: theme.textTheme.titleSmall?.copyWith(
        color: _foregroundFor(colors, variant),
      ),
    );
    return _PressablePill(
      fill: _fillFor(colors, variant),
      semanticLabel: semanticLabel ?? label,
      onPressed: onPressed,
      child: leading == null
          ? text
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ExcludeSemantics(child: leading!),
                const SizedBox(width: AltracqSpacing.md),
                text,
              ],
            ),
    );
  }
}

/// Dua pil solid berdampingan dengan celah 12 px. Keduanya tombol terpisah
/// yang utuh; tidak ada bentuk yang menjembatani celah.
class AltracqButtonPair extends StatelessWidget {
  const AltracqButtonPair({
    super.key,
    required this.leftLabel,
    required this.rightLabel,
    required this.onLeftTap,
    required this.onRightTap,
    this.leftVariant = AltracqButtonVariant.secondary,
    this.rightVariant = AltracqButtonVariant.primary,
    this.leftSemanticLabel,
    this.rightSemanticLabel,
  });

  final String leftLabel;
  final String rightLabel;
  final VoidCallback? onLeftTap;
  final VoidCallback? onRightTap;
  final AltracqButtonVariant leftVariant;
  final AltracqButtonVariant rightVariant;
  final String? leftSemanticLabel;
  final String? rightSemanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AltracqColors.of(context);
    final theme = Theme.of(context);
    Widget pill(
      String label,
      String? semanticLabel,
      AltracqButtonVariant variant,
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
        const SizedBox(width: AltracqMetrics.buttonPairGap),
        Expanded(
          child: pill(rightLabel, rightSemanticLabel, rightVariant, onRightTap),
        ),
      ],
    );
  }
}
