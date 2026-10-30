import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../design/motion/visual_effect_policy.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/line_icons.dart';

/// Trek geser untuk membuka telepon nomor darurat.
///
/// Trek kaca setinggi 64 px selebar wadah, knob kaca 56 px di kiri dengan ikon
/// telepon, dan label di tengah. Knob mengikuti jari; melewati 85% perjalanan
/// memicu [onTrigger] sekali dan knob tetap di ujung sampai aplikasi kembali
/// dari pemanggil telepon. Warna seluruhnya dari token yang sudah ada — tidak
/// ada warna merah dan tidak ada warna baru.
class SlideToCall extends StatefulWidget {
  const SlideToCall({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.onTrigger,
    required this.onConfirmRequest,
    this.interactive = true,
    this.onInteractionChanged,
  });

  final String label;

  /// Label untuk pembaca layar, misalnya "Telepon Basarnas 115".
  final String semanticLabel;

  /// Dipanggil satu kali saat knob melewati ambang. Pemakai yang membuka
  /// aplikasi telepon.
  final VoidCallback onTrigger;

  /// Jalur tanpa geser untuk pembaca layar: pemakai menampilkan dialog
  /// konfirmasi sebelum nomor dibuka.
  final VoidCallback onConfirmRequest;

  /// `false` saat trek lain sedang digeser, supaya hanya satu yang aktif.
  final bool interactive;

  /// Memberi tahu pemakai saat trek ini mulai dan selesai dipakai.
  final ValueChanged<bool>? onInteractionChanged;

  static const double trackHeight = 64;
  static const double knobSize = 56;
  static const double knobInset = 4;
  static const double threshold = 0.85;
  static const double lensMagnification = 1.15;

  @override
  State<SlideToCall> createState() => _SlideToCallState();
}

class _SlideToCallState extends State<SlideToCall>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const Duration _springDuration = Duration(milliseconds: 380);
  static const Duration _plainDuration = Duration(milliseconds: 150);

  /// Overshoot saat knob balik ke kiri dibatasi sebesar inset knob sehingga
  /// knob tidak pernah keluar dari trek.
  static const double _maxOvershoot = SlideToCall.knobInset;

  final ValueNotifier<double> _offset = ValueNotifier<double>(0);

  late final AnimationController _return = AnimationController(
    vsync: this,
    duration: _springDuration,
  )..addListener(_onReturnTick);

  late VisualEffectPolicy _policy;
  double _maxTravel = 0;
  double _returnFrom = 0;
  double _grabDelta = 0;
  bool _dragging = false;
  bool _triggered = false;

  bool get _reduceMotion => _policy.reduceMotion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _policy = VisualEffectPolicyScope.of(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _return.dispose();
    _offset.dispose();
    super.dispose();
  }

  /// Knob dikembalikan ke posisi awal saat aplikasi kembali dari dialer.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_triggered) return;
    _triggered = false;
    _animateBack();
  }

  void _onReturnTick() {
    final double t = _return.value;
    final double eased =
        _reduceMotion ? t : Curves.easeOutBack.transform(t);
    final double floor = _reduceMotion ? 0 : -_maxOvershoot;
    _offset.value =
        (_returnFrom * (1 - eased)).clamp(floor, _maxTravel).toDouble();
  }

  void _animateBack() {
    final double from = _offset.value;
    if (from <= 0) {
      _offset.value = 0;
      return;
    }
    _returnFrom = from;
    _return
      ..duration = _reduceMotion ? _plainDuration : _springDuration
      ..forward(from: 0);
  }

  void _onDragStart(DragStartDetails details) {
    if (_triggered) return;
    _return.stop();
    _dragging = true;
    _grabDelta = details.localPosition.dx - _offset.value;
    widget.onInteractionChanged?.call(true);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_dragging || _maxTravel <= 0) return;
    _offset.value = (details.localPosition.dx - _grabDelta)
        .clamp(0, _maxTravel)
        .toDouble();
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;
    widget.onInteractionChanged?.call(false);
    if (_maxTravel <= 0) return;
    if (_offset.value >= SlideToCall.threshold * _maxTravel) {
      _offset.value = _maxTravel;
      _triggered = true;
      unawaited(HapticFeedback.mediumImpact());
      widget.onTrigger();
      return;
    }
    _animateBack();
  }

  void _onDragCancel() {
    if (!_dragging) return;
    _dragging = false;
    widget.onInteractionChanged?.call(false);
    _animateBack();
  }

  double _baseLabelOpacity(double offset) {
    if (_maxTravel <= 0) return 1;
    final double t = (offset / _maxTravel).clamp(0.0, 1.0);
    return (1 - t * 2).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AltracqColors.of(context);
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w500,
    );

    return Semantics(
      button: true,
      enabled: widget.interactive,
      label: widget.semanticLabel,
      hint: 'Geser knob ke kanan untuk membuka telepon',
      onTap: widget.interactive ? widget.onConfirmRequest : null,
      customSemanticsActions: widget.interactive
          ? <CustomSemanticsAction, VoidCallback>{
              CustomSemanticsAction(label: widget.semanticLabel):
                  widget.onConfirmRequest,
            }
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double trackWidth =
              constraints.maxWidth.isFinite ? constraints.maxWidth : 0;
          _maxTravel = math.max(
            0,
            trackWidth - SlideToCall.knobSize - 2 * SlideToCall.knobInset,
          );
          final bool draggable = widget.interactive && _maxTravel > 0;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: draggable ? _onDragStart : null,
            onHorizontalDragUpdate: draggable ? _onDragUpdate : null,
            onHorizontalDragEnd: draggable ? _onDragEnd : null,
            onHorizontalDragCancel: draggable ? _onDragCancel : null,
            child: SizedBox(
              height: SlideToCall.trackHeight,
              width: trackWidth,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned.fill(
                    child: CustomPaint(painter: _TrackPainter(colors: colors)),
                  ),
                  Positioned.fill(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _offset,
                      builder: (context, offset, child) => Opacity(
                        opacity: _baseLabelOpacity(offset),
                        child: child,
                      ),
                      child: ExcludeSemantics(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: SlideToCall.knobSize +
                                  SlideToCall.knobInset,
                            ),
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: labelStyle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<double>(
                    valueListenable: _offset,
                    builder: (context, offset, _) {
                      final double knobLeft = SlideToCall.knobInset + offset;
                      return Positioned(
                        left: knobLeft,
                        top: SlideToCall.knobInset,
                        child: _Knob(
                          label: widget.label,
                          labelStyle: labelStyle,
                          colors: colors,
                          blur: _policy.glassBlur,
                          lens: !_reduceMotion,
                          knobLeft: knobLeft,
                          trackWidth: trackWidth,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Knob kaca: blur latar, isi semi-transparan, garis tepi bergradasi, kilau
/// specular, salinan label yang diperbesar sebagai lensa, dan ikon telepon.
class _Knob extends StatelessWidget {
  const _Knob({
    required this.label,
    required this.labelStyle,
    required this.colors,
    required this.blur,
    required this.lens,
    required this.knobLeft,
    required this.trackWidth,
  });

  /// Blur knob lebih halus daripada blur kartu karena luasnya kecil.
  static const double _blurSigma = AltracqGlass.blurSigma / 2;

  final String label;
  final TextStyle? labelStyle;
  final AltracqColors colors;
  final bool blur;
  final bool lens;
  final double knobLeft;
  final double trackWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: SlideToCall.knobSize,
      height: SlideToCall.knobSize,
      child: ClipOval(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: blur
                  ? BackdropFilter(
                      filter: ui.ImageFilter.blur(
                        sigmaX: _blurSigma,
                        sigmaY: _blurSigma,
                      ),
                      child: ColoredBox(color: colors.glassFill),
                    )
                  : ColoredBox(color: colors.glassFillFallback),
            ),
            Positioned.fill(
              child: CustomPaint(painter: _KnobPainter(colors: colors)),
            ),
            if (lens)
              Positioned.fill(
                child: CustomPaint(
                  painter: _LensPainter(
                    text: label,
                    style: labelStyle,
                    colors: colors,
                    knobLeft: knobLeft,
                    trackWidth: trackWidth,
                  ),
                ),
              ),
            Center(
              child: AltracqIcon(
                AltracqIcons.phone,
                size: 22,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  const _TrackPainter({required this.colors});

  static const double _innerShadowBlur = 6;

  final AltracqColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2));
    final path = Path()..addRRect(rrect);

    canvas.drawPath(
      path,
      Paint()
        ..color =
            AltracqColors.light.secondary.withValues(alpha: 0.30),
    );

    canvas.save();
    canvas.clipPath(path);
    final ring = Path.combine(
      PathOperation.difference,
      Path()..addRect(rect.inflate(_innerShadowBlur * 2)),
      path,
    );
    canvas.drawPath(
      ring,
      Paint()
        ..color = colors.glassShadow
        ..maskFilter =
            const MaskFilter.blur(BlurStyle.normal, _innerShadowBlur),
    );
    canvas.restore();

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = AltracqGlass.borderWidth
        ..color = colors.glassBorder,
    );
  }

  @override
  bool shouldRepaint(_TrackPainter oldDelegate) =>
      oldDelegate.colors != colors;
}

class _KnobPainter extends CustomPainter {
  const _KnobPainter({required this.colors});

  final AltracqColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.shortestSide / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          center + Offset(-radius * 0.35, -radius * 0.45),
          radius * 0.95,
          <Color>[
            colors.glassHighlight,
            colors.glassHighlight.withValues(alpha: 0),
          ],
        ),
    );

    canvas.drawCircle(
      center,
      radius - AltracqGlass.borderWidth / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = AltracqGlass.borderWidth
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          <Color>[
            colors.glassHighlight,
            colors.glassBorder.withValues(alpha: 0),
          ],
        ),
    );
  }

  @override
  bool shouldRepaint(_KnobPainter oldDelegate) => oldDelegate.colors != colors;
}

/// Menggambar ulang label trek di dalam lingkaran knob dengan perbesaran
/// [SlideToCall.lensMagnification] seolah dilihat lewat kaca pembesar.
class _LensPainter extends CustomPainter {
  const _LensPainter({
    required this.text,
    required this.style,
    required this.colors,
    required this.knobLeft,
    required this.trackWidth,
  });

  final String text;
  final TextStyle? style;
  final AltracqColors colors;
  final double knobLeft;
  final double trackWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final base = style;
    if (base == null) return;
    final double maxTravel = trackWidth -
        SlideToCall.knobSize -
        2 * SlideToCall.knobInset;
    if (maxTravel <= 0) return;
    final double t =
        ((knobLeft - SlideToCall.knobInset) / maxTravel).clamp(0.0, 1.0);
    final double opacity = (t * 2).clamp(0.0, 1.0);
    if (opacity <= 0) return;

    final Color color = base.color ?? colors.textPrimary;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: base.copyWith(
          color: color.withValues(alpha: color.a * opacity),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    const double m = SlideToCall.lensMagnification;
    final Offset center = size.center(Offset.zero);
    // Pusat label dalam koordinat knob, lalu diperbesar terhadap pusat knob
    // sehingga teks tampak bergeser sedikit seperti dibiaskan kaca.
    final double labelCenterX = trackWidth / 2 - knobLeft;
    final double targetX = center.dx + m * (labelCenterX - center.dx);

    canvas
      ..save()
      ..translate(targetX, center.dy)
      ..scale(m, m);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
    painter.dispose();
  }

  @override
  bool shouldRepaint(_LensPainter oldDelegate) =>
      oldDelegate.text != text ||
      oldDelegate.style != style ||
      oldDelegate.colors != colors ||
      oldDelegate.knobLeft != knobLeft ||
      oldDelegate.trackWidth != trackWidth;
}
