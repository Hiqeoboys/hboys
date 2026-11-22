import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design/glass/hiqeo_liquid_glass.dart';
import '../../../../design/tokens.dart';
import '../../domain/field_sketch_spec.dart';
import 'field_sketch_beginner_painter.dart';
import 'field_sketch_safety_painter.dart';
import 'field_sketch_survival_painter.dart';
import 'field_sketch_tokens.dart';

/// CustomPainter utama untuk seluruh diagram Technical Field Sketch 100% offline.
class FieldSketchPainter extends CustomPainter {
  const FieldSketchPainter({
    required this.sketchId,
    this.overlay,
  });

  final FieldSketchId sketchId;
  final FieldSketchOverlay? overlay;

  @override
  void paint(Canvas canvas, Size size) {
    FieldSketchPrimitives.withVirtualCanvas(canvas, size, (c) {
      final name = sketchId.name;
      if (name.startsWith('p3k')) {
        paintSafetySketch(c, sketchId);
      } else if (name.startsWith('surv')) {
        paintSurvivalSketch(c, sketchId);
      } else {
        paintBeginnerSketch(c, sketchId, overlay: overlay);
      }
    });
  }

  @override
  bool shouldRepaint(FieldSketchPainter oldDelegate) =>
      oldDelegate.sketchId != sketchId || oldDelegate.overlay != overlay;
}

/// Kanvas sketsa teknis terisolasi `RepaintBoundary` dengan dukungan Tap-to-Zoom layar penuh.
class FieldSketchCanvas extends StatelessWidget {
  const FieldSketchCanvas({
    super.key,
    required this.sketchId,
    this.overlay,
    this.height = 196,
    this.borderRadius = 18,
    this.enableZoom = true,
    this.stepLabel,
    this.stepTitle,
    this.stepInstruction,
  });

  final FieldSketchId sketchId;
  final FieldSketchOverlay? overlay;
  final double height;
  final double borderRadius;
  final bool enableZoom;
  final String? stepLabel;
  final String? stepTitle;
  final String? stepInstruction;

  void _openZoom(BuildContext context) {
    HapticFeedback.selectionClick();
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black87,
        transitionDuration: HiqeoMotion.screenFade,
        reverseTransitionDuration: HiqeoMotion.fast,
        pageBuilder: (_, __, ___) => FieldSketchZoomDialog(
          sketchId: sketchId,
          overlay: overlay,
          stepLabel: stepLabel,
          stepTitle: stepTitle,
          stepInstruction: stepInstruction,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sketch = RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: FieldSketchPalette.canvas,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: FieldSketchPalette.ink.withValues(alpha: 0.16),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                CustomPaint(
                  painter: FieldSketchPainter(
                    sketchId: sketchId,
                    overlay: overlay,
                  ),
                ),
                if (enableZoom)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: FieldSketchPalette.canvas
                              .withValues(alpha: 0.86),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: FieldSketchPalette.ink.withValues(alpha: 0.25),
                          ),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.zoom_in_rounded,
                                size: 15,
                                color: FieldSketchPalette.ink,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Perbesar',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: FieldSketchPalette.ink,
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

    if (!enableZoom) return sketch;

    return Semantics(
      button: true,
      label: stepTitle != null
          ? 'Perbesar diagram langkah: $stepTitle'
          : 'Perbesar diagram sketsa teknis',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openZoom(context),
        child: sketch,
      ),
    );
  }
}

/// Layar penuh Tap-to-Zoom dengan `InteractiveViewer` (pinch, pan, double-tap).
class FieldSketchZoomDialog extends StatefulWidget {
  const FieldSketchZoomDialog({
    super.key,
    required this.sketchId,
    this.overlay,
    this.stepLabel,
    this.stepTitle,
    this.stepInstruction,
  });

  final FieldSketchId sketchId;
  final FieldSketchOverlay? overlay;
  final String? stepLabel;
  final String? stepTitle;
  final String? stepInstruction;

  @override
  State<FieldSketchZoomDialog> createState() => _FieldSketchZoomDialogState();
}

class _FieldSketchZoomDialogState extends State<FieldSketchZoomDialog> {
  final TransformationController _transformCtrl = TransformationController();
  Offset _doubleTapLocal = Offset.zero;

  @override
  void dispose() {
    _transformCtrl.dispose();
    super.dispose();
  }

  void _toggleDoubleTapZoom() {
    final currentScale = _transformCtrl.value.getMaxScaleOnAxis();
    if (currentScale > 1.2) {
      _transformCtrl.value = Matrix4.identity();
    } else {
      const targetScale = 2.4;
      final dx = -_doubleTapLocal.dx * (targetScale - 1);
      final dy = -_doubleTapLocal.dy * (targetScale - 1);
      _transformCtrl.value = Matrix4.identity()
        ..translateByDouble(dx, dy, 0.0, 1.0)
        ..scaleByDouble(targetScale, targetScale, 1.0, 1.0);
    }
  }

  void _resetZoom() {
    HapticFeedback.selectionClick();
    _transformCtrl.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FieldSketchPalette.canvas,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (widget.stepLabel != null)
                          Text(
                            widget.stepLabel!,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: FieldSketchPalette.sage,
                            ),
                          ),
                        Text(
                          widget.stepTitle ?? 'Detail Sketsa Lapangan',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: FieldSketchPalette.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    label: 'Reset zoom',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _resetZoom,
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: Icon(
                            Icons.fit_screen_rounded,
                            color: FieldSketchPalette.ink,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  HiqeoGlassCircleButton(
                    key: const ValueKey<String>('field-sketch-zoom-close'),
                    semanticsLabel: 'Tutup tampilan zoom',
                    brightness: Brightness.dark,
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: FieldSketchPalette.ink,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GestureDetector(
                onDoubleTapDown: (d) => _doubleTapLocal = d.localPosition,
                onDoubleTap: _toggleDoubleTapZoom,
                child: InteractiveViewer(
                  key: const ValueKey<String>('field-sketch-interactive-viewer'),
                  transformationController: _transformCtrl,
                  minScale: 1.0,
                  maxScale: 4.5,
                  boundaryMargin: const EdgeInsets.all(64),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 400 / 240,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: FieldSketchPainter(
                            sketchId: widget.sketchId,
                            overlay: widget.overlay,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: FieldSketchPalette.ink.withValues(alpha: 0.16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (widget.stepInstruction != null)
                    Text(
                      widget.stepInstruction!,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: FieldSketchPalette.ink,
                      ),
                    ),
                  const SizedBox(height: 6),
                  const Text(
                    'Cubit atau ketuk dua kali untuk memperbesar detail sudut, pasak, dan simpul.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: FieldSketchPalette.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pemutar langkah interaktif (1 Langkah = 1 Kanvas Sketsa) dengan sinkronisasi
/// otomatis antara swipe/tap nomor langkah, tombol Sebelumnya/Berikutnya, & daftar langkah.
class IllustratedStepDeck extends StatefulWidget {
  const IllustratedStepDeck({
    super.key,
    required this.steps,
    this.sectionTitle,
    this.sectionIcon = Icons.architecture_rounded,
    this.accentColor,
    this.deckKeyPrefix = 'guide',
  });

  final List<GuideStep> steps;
  final String? sectionTitle;
  final IconData sectionIcon;
  final Color? accentColor;
  final String deckKeyPrefix;

  @override
  State<IllustratedStepDeck> createState() => _IllustratedStepDeckState();
}

class _IllustratedStepDeckState extends State<IllustratedStepDeck> {
  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void didUpdateWidget(covariant IllustratedStepDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.steps.isEmpty) {
      _currentIndex = 0;
      return;
    }
    if (_currentIndex >= widget.steps.length) {
      final clamped = widget.steps.length - 1;
      _currentIndex = clamped;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(clamped);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToStep(int index) {
    if (index < 0 || index >= widget.steps.length) return;
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: HiqeoMotion.fast,
        curve: HiqeoMotion.standard,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final accent = widget.accentColor ?? colors.primary;
    if (widget.steps.isEmpty) return const SizedBox.shrink();

    final safeIndex = _currentIndex.clamp(0, widget.steps.length - 1);
    final activeStep = widget.steps[safeIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.sectionTitle != null) ...<Widget>[
          Row(
            children: <Widget>[
              Icon(widget.sectionIcon, size: 17, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.sectionTitle!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
              Text(
                'Langkah ${safeIndex + 1}/${widget.steps.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],

        // Kanvas sketsa per langkah (1 Langkah = 1 Sketsa, bisa digeser & tap-to-zoom)
        SizedBox(
          height: 198,
          child: PageView.builder(
            key: ValueKey<String>('${widget.deckKeyPrefix}-pageview'),
            controller: _pageController,
            itemCount: widget.steps.length,
            onPageChanged: (index) {
              if (_currentIndex != index) {
                setState(() => _currentIndex = index);
              }
            },
            itemBuilder: (context, index) {
              final step = widget.steps[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: FieldSketchCanvas(
                  key: ValueKey<String>(
                    '${widget.deckKeyPrefix}-sketch-${step.sketchId.name}-$index',
                  ),
                  sketchId: step.sketchId,
                  overlay: step.overlay,
                  height: 196,
                  stepLabel: 'Langkah ${index + 1} dari ${widget.steps.length}',
                  stepTitle: step.title,
                  stepInstruction: step.instruction,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),

        // Baris nomor langkah + kontrol Sebelumnya/Berikutnya (>= 44x44 dp)
        Row(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    for (var i = 0; i < widget.steps.length; i++)
                      Padding(
                        padding: EdgeInsets.only(
                          right: i < widget.steps.length - 1 ? 6 : 0,
                        ),
                        child: Semantics(
                          button: true,
                          selected: i == safeIndex,
                          label: 'Pilih langkah ${i + 1}',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _goToStep(i),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                minWidth: 44,
                                minHeight: 44,
                              ),
                              child: Center(
                                child: AnimatedContainer(
                                  duration: HiqeoMotion.fast,
                                  width: 34,
                                  height: 34,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: i == safeIndex
                                        ? colors.primary
                                        : colors.background,
                                    borderRadius: BorderRadius.circular(11),
                                    border: Border.all(
                                      color: i == safeIndex
                                          ? colors.primary
                                          : colors.hairline,
                                    ),
                                  ),
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: i == safeIndex
                                          ? colors.onPrimary
                                          : colors.textSecondary,
                                    ),
                                  ),
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
            Semantics(
              button: true,
              enabled: safeIndex > 0,
              label: 'Langkah sebelumnya',
              child: IconButton(
                onPressed:
                    safeIndex > 0 ? () => _goToStep(safeIndex - 1) : null,
                icon: const Icon(Icons.chevron_left_rounded),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            ),
            Semantics(
              button: true,
              enabled: safeIndex < widget.steps.length - 1,
              label: 'Langkah berikutnya',
              child: IconButton(
                onPressed: safeIndex < widget.steps.length - 1
                    ? () => _goToStep(safeIndex + 1)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Kartu ringkasan langkah aktif
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${safeIndex + 1}. ${activeStep.title}',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                activeStep.instruction,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.42,
                  color: colors.textPrimary,
                ),
              ),
              if (activeStep.tip != null) ...<Widget>[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 16,
                      color: colors.successText,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        activeStep.tip!,
                        style: TextStyle(
                          fontSize: 12.2,
                          fontWeight: FontWeight.w600,
                          color: colors.successText,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (activeStep.warning != null) ...<Widget>[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.cancel_outlined,
                      size: 16,
                      color: colors.warningText,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        activeStep.warning!,
                        style: TextStyle(
                          fontSize: 12.2,
                          fontWeight: FontWeight.w600,
                          color: colors.warningText,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Daftar klik semua langkah agar seluruh materi tetap terbaca cepat tanpa kehilangan teks
        for (var i = 0; i < widget.steps.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i < widget.steps.length - 1 ? 4 : 0),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _goToStep(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 20,
                      child: Text(
                        '${i + 1}.',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: i == safeIndex
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: i == safeIndex
                              ? colors.primary
                              : colors.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        widget.steps[i].instruction,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.38,
                          fontWeight: i == safeIndex
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: i == safeIndex
                              ? colors.textPrimary
                              : colors.textSecondary,
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
}
