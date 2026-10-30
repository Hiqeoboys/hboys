import 'package:flutter/material.dart';

import '../gooey/gooey_layer.dart';
import '../tokens.dart';

/// Varian tombol mengikuti rancangan: primer isi penuh, sekunder abu, dan
/// invers untuk tombol terang di atas kartu gelap.
enum AltracqButtonVariant { primary, secondary, inverse }

const double _kButtonHeight = 56;

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

class _Pill extends StatelessWidget {
  const _Pill({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(_kButtonHeight / 2),
        ),
      );
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// Badan tombol pill plus dua benjolan cair di tepi atas saat gooey menyala.
class _PillWithBumps extends StatelessWidget {
  const _PillWithBumps({required this.color, required this.bumps});

  final Color color;
  final bool bumps;

  @override
  Widget build(BuildContext context) {
    const double bump = AltracqGooey.bumpSize;
    return SizedBox(
      height: _kButtonHeight,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double width = constraints.maxWidth;
          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(child: _Pill(color: color)),
              if (bumps) ...<Widget>[
                Positioned(
                  left: width * 0.2 - bump / 2,
                  top: -bump * 0.4,
                  child: _Blob(color: color, size: bump),
                ),
                Positioned(
                  left: width * 0.8 - bump / 2,
                  top: -bump * 0.4,
                  child: _Blob(color: color, size: bump),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Tombol primer/sekunder lebar penuh dengan siluet cair.
///
/// Tinggi 56 px (di atas target sentuh minimum 44 px). Saat gooey mati,
/// tombol tetap pill biasa dan tetap berfungsi penuh.
class AltracqButton extends StatefulWidget {
  const AltracqButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AltracqButtonVariant.primary,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final AltracqButtonVariant variant;
  final String? semanticLabel;

  @override
  State<AltracqButton> createState() => _AltracqButtonState();
}

class _AltracqButtonState extends State<AltracqButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AltracqColors.of(context);
    final theme = Theme.of(context);
    final fill = _fillFor(colors, widget.variant);
    final foreground = _foregroundFor(colors, widget.variant);
    final gooey = GooeyLayer.enabledOf(context) && _enabled;

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel ?? widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        onTapDown: _enabled ? (_) => _setPressed(true) : null,
        onTapUp: _enabled ? (_) => _setPressed(false) : null,
        onTapCancel: _enabled ? () => _setPressed(false) : null,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: AltracqMotion.press,
          curve: AltracqMotion.standard,
          child: Opacity(
            opacity: _enabled ? 1 : 0.6,
            child: GooeyLayer(
              shapes: _PillWithBumps(color: fill, bumps: gooey),
              child: Center(
                child: ExcludeSemantics(
                  child: Text(
                    widget.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: foreground,
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

/// Pasangan tombol berdampingan dengan celah 12 px yang dijembatani gooey
/// menjadi leher cair. Tanpa gooey, celahnya tetap 12 px dan keduanya tetap
/// tombol terpisah yang berfungsi penuh.
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
    final gooey = GooeyLayer.enabledOf(context);
    final leftFill = _fillFor(colors, leftVariant);
    final rightFill = _fillFor(colors, rightVariant);

    return SizedBox(
      height: _kButtonHeight,
      child: GooeyLayer(
        shapes: Row(
          children: <Widget>[
            Expanded(
              child: _PillWithBumps(color: leftFill, bumps: gooey),
            ),
            const SizedBox(width: AltracqMetrics.buttonPairGap),
            Expanded(
              child: _PillWithBumps(color: rightFill, bumps: gooey),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _PairZone(
                label: leftLabel,
                semanticLabel: leftSemanticLabel,
                onTap: onLeftTap,
                foreground: _foregroundFor(colors, leftVariant),
              ),
            ),
            const SizedBox(width: AltracqMetrics.buttonPairGap),
            Expanded(
              child: _PairZone(
                label: rightLabel,
                semanticLabel: rightSemanticLabel,
                onTap: onRightTap,
                foreground: _foregroundFor(colors, rightVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PairZone extends StatelessWidget {
  const _PairZone({
    required this.label,
    required this.onTap,
    required this.foreground,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onTap;
  final Color foreground;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel ?? label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: ExcludeSemantics(
            child: Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}
