import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion/visual_effect_policy.dart';
import '../tokens.dart';

/// Warna trek dan knob untuk satu konteks.
///
/// Nilai bawaan diturunkan dari token tema lewat [GooeySwitchStyle.standard];
/// [GooeySwitchStyle.recap] dipakai di kartu Rekap Tahunan yang selalu gelap,
/// sehingga warna krem diambil dari palet gelap apa pun tema halamannya.
@immutable
class GooeySwitchStyle {
  const GooeySwitchStyle({
    required this.trackOff,
    required this.trackOn,
    required this.knobOff,
    required this.knobOn,
  });

  factory GooeySwitchStyle.standard(HiqeoColors colors) {
    return GooeySwitchStyle(
      trackOff: colors.secondary,
      trackOn: colors.primary,
      knobOff:
          colors.brightness == Brightness.dark
              ? colors.primary
              : colors.background,
      knobOn: colors.onPrimary,
    );
  }

  /// Gaya di atas panel gelap: trek mati krem 22%, trek hidup krem penuh,
  /// knob krem saat mati dan navy saat hidup.
  factory GooeySwitchStyle.recap(HiqeoColors darkColors) {
    return GooeySwitchStyle(
      trackOff: darkColors.primary.withValues(alpha: 0.22),
      trackOn: darkColors.primary,
      knobOff: darkColors.primary,
      knobOn: darkColors.onPrimary,
    );
  }

  final Color trackOff;
  final Color trackOn;
  final Color knobOff;
  final Color knobOn;

  Color trackFor(bool value) => value ? trackOn : trackOff;

  Color knobFor(bool value) => value ? knobOn : knobOff;
}

/// Saklar 48×28 dengan knob bulat 22 yang bergerak sebagai satu gumpalan.
///
/// Knob memanjang ditarik dari ujung lama: kepala memimpin dengan pegas kaku,
/// ekor menyusul dengan pegas lembut, lalu menyusut bulat di tujuan. Tidak ada
/// tetesan terpisah. Warna trek memudar 250 ms dan area sentuh tetap 44×44.
class GooeySwitch extends StatefulWidget {
  const GooeySwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticsLabel,
    this.style,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String semanticsLabel;
  final GooeySwitchStyle? style;

  static const double trackWidth = 48;
  static const double trackHeight = 28;
  static const double knobDiameter = 22;
  static const double pressWiden = 4;
  static const double touchTarget = 44;

  /// Jarak tepi trek ke tepi knob.
  static const double edgePadding = 3;

  static const Duration moveDuration = Duration(milliseconds: 400);
  static const Duration reducedMoveDuration = Duration(milliseconds: 150);
  static const Duration colorDuration = Duration(milliseconds: 250);

  /// Bagian pantulan `easeOutBack` yang dipakai (≈4,4% jarak).
  static const double headOvershootScale = 0.45;

  /// Penyempitan leher maksimum saat regangan puncak.
  static const double maxNeckThinning = 0.15;

  static double knobCenterX(bool value) => value
      ? trackWidth - edgePadding - knobDiameter / 2
      : edgePadding + knobDiameter / 2;

  @override
  State<GooeySwitch> createState() => _GooeySwitchState();
}

class _GooeySwitchState extends State<GooeySwitch>
    with SingleTickerProviderStateMixin {
  late final AnimationController _move;
  late bool _value;
  late double _headStart;
  late double _tailStart;
  late double _headEnd;
  late double _tailEnd;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
    final center = GooeySwitch.knobCenterX(_value);
    _headStart = center;
    _tailStart = center;
    _headEnd = center;
    _tailEnd = center;
    _move = AnimationController(
      vsync: this,
      duration: GooeySwitch.moveDuration,
      value: 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _move.duration = _reduceMotion
        ? GooeySwitch.reducedMoveDuration
        : GooeySwitch.moveDuration;
  }

  @override
  void didUpdateWidget(GooeySwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == _value) return;
    _headStart = _headX;
    _tailStart = _tailX;
    _headEnd = GooeySwitch.knobCenterX(widget.value);
    _tailEnd = _headEnd;
    _value = widget.value;
    _move.forward(from: 0);
  }

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  bool get _reduceMotion =>
      VisualEffectPolicyScope.of(context).reduceMotion;

  double get _headX => ui.lerpDouble(
        _headStart,
        _headEnd,
        _reduceMotion ? _move.value : gooeySwitchHeadProgress(_move.value),
      )!;

  double get _tailX => ui.lerpDouble(
        _tailStart,
        _tailEnd,
        _reduceMotion ? _move.value : gooeySwitchTailProgress(_move.value),
      )!;

  double get _maxSeparation => (_headEnd - _headStart).abs();

  void _toggle() {
    unawaited(HapticFeedback.selectionClick());
    widget.onChanged(!widget.value);
  }

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final policy = VisualEffectPolicyScope.of(context);
    final style = widget.style ?? GooeySwitchStyle.standard(colors);
    return Semantics(
      container: true,
      toggled: widget.value,
      label: widget.semanticsLabel,
      onTap: _toggle,
      child: Focus(
        canRequestFocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space) {
            _toggle();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTapDown: (_) => _setPressed(true),
          onTapCancel: () => _setPressed(false),
          onTapUp: (_) => _setPressed(false),
          onTap: _toggle,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: GooeySwitch.touchTarget,
              minHeight: GooeySwitch.touchTarget,
            ),
            child: Center(
              child: SizedBox(
                width: GooeySwitch.trackWidth,
                height: GooeySwitch.trackHeight,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: AnimatedContainer(
                        duration: GooeySwitch.colorDuration,
                        curve: Curves.ease,
                        decoration: BoxDecoration(
                          color: style.trackFor(widget.value),
                          borderRadius: BorderRadius.circular(
                            GooeySwitch.trackHeight / 2,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _move,
                          builder: (context, _) {
                            final morphing = policy.gooey &&
                                !policy.reduceMotion &&
                                _move.isAnimating;
                            return CustomPaint(
                              key: const ValueKey<String>(
                                'gooey-switch-knob',
                              ),
                              painter: GooeySwitchKnobPainter(
                                headX: _headX,
                                tailX: _tailX,
                                knobWidth: _pressed
                                    ? GooeySwitch.knobDiameter +
                                        GooeySwitch.pressWiden
                                    : GooeySwitch.knobDiameter,
                                knobHeight: GooeySwitch.knobDiameter,
                                color: style.knobFor(widget.value),
                                morphing: morphing,
                                maxSeparation: _maxSeparation,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kemajuan kepala knob: pegas kaku dengan pantulan dibatasi ≈4,4%.
@visibleForTesting
double gooeySwitchHeadProgress(double t) {
  final eased = Curves.easeOutBack.transform(t);
  return 1 + (eased - 1) * GooeySwitch.headOvershootScale;
}

/// Kemajuan ekor knob: menyusul lebih lambat dan tanpa pantulan.
@visibleForTesting
double gooeySwitchTailProgress(double t) =>
    const Interval(0.12, 1, curve: Curves.easeOutCubic).transform(t);

/// Melukis knob sebagai satu bentuk: dua rounded rect (kepala dan ekor) yang
/// disatukan leher. Saat diam hanya satu bentuk tajam yang digambar.
@visibleForTesting
class GooeySwitchKnobPainter extends CustomPainter {
  const GooeySwitchKnobPainter({
    required this.headX,
    required this.tailX,
    required this.knobWidth,
    required this.knobHeight,
    required this.color,
    required this.morphing,
    required this.maxSeparation,
  });

  final double headX;
  final double tailX;
  final double knobWidth;
  final double knobHeight;
  final Color color;
  final bool morphing;
  final double maxSeparation;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    final centerY = size.height / 2;
    if (!morphing) {
      canvas.drawRRect(_rounded(headX, centerY), paint);
      return;
    }
    var path = Path.combine(
      ui.PathOperation.union,
      Path()..addRRect(_rounded(headX, centerY)),
      Path()..addRRect(_rounded(tailX, centerY)),
    );
    final separation = (headX - tailX).abs();
    if (separation > 0.5) {
      final stretch = maxSeparation <= 0
          ? 0.0
          : (separation / (maxSeparation * 0.5)).clamp(0.0, 1.0);
      final neckHeight =
          knobHeight * (1 - GooeySwitch.maxNeckThinning * stretch);
      final neck = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          math.min(headX, tailX),
          centerY - neckHeight / 2,
          math.max(headX, tailX),
          centerY + neckHeight / 2,
        ),
        Radius.circular(neckHeight / 2),
      );
      path = Path.combine(ui.PathOperation.union, path, Path()..addRRect(neck));
    }
    canvas.drawPath(path, paint);
  }

  RRect _rounded(double centerX, double centerY) {
    return RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(centerX, centerY),
        width: knobWidth,
        height: knobHeight,
      ),
      Radius.circular(knobHeight / 2),
    );
  }

  @override
  bool shouldRepaint(GooeySwitchKnobPainter oldDelegate) =>
      oldDelegate.headX != headX ||
      oldDelegate.tailX != tailX ||
      oldDelegate.knobWidth != knobWidth ||
      oldDelegate.knobHeight != knobHeight ||
      oldDelegate.color != color ||
      oldDelegate.morphing != morphing ||
      oldDelegate.maxSeparation != maxSeparation;
}
