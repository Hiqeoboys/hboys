import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion/visual_effect_policy.dart';
import '../tokens.dart';

/// Gaya isi satu item pemilih setelah menerima status pilihan.
@immutable
class GooeySelectorItemState {
  const GooeySelectorItemState({
    required this.selected,
    required this.coverage,
  });

  /// Benar untuk nilai yang sedang dipilih induk.
  final bool selected;

  /// Bagian area item yang tertutup indikator, 0..1.
  ///
  /// Dipakai untuk memindahkan warna teks/ikon saat gumpalan benar-benar
  /// menutupinya, bukan serentak di awal atau akhir animasi.
  final double coverage;
}

typedef GooeySelectorItemBuilder = Widget Function(
  BuildContext context,
  GooeySelectorItemState state,
);

class GooeySelectorItem<T> {
  const GooeySelectorItem({
    required this.value,
    required this.semanticsLabel,
    this.builder,
  });

  final T value;
  final String semanticsLabel;

  /// Isi khusus item. Bila null, [semanticsLabel] digambar sebagai teks
  /// tunggal dengan warna yang mengikuti [GooeySelectorItemState.coverage].
  final GooeySelectorItemBuilder? builder;
}

/// Kontrol pilih-satu dengan indikator satu gumpalan cair.
///
/// Indikator diukur dari render box item (bukan angka tetap), jadi item boleh
/// berbeda ukuran dan pemilih boleh horizontal maupun vertikal. Saat diam
/// indikator digambar sebagai rounded rect biasa tanpa filter. Selama
/// perpindahan, kepala bergerak lebih dulu dengan pegas kaku dan ekor menyusul
/// dengan pegas lembut; keduanya disatukan leher yang menipis, sehingga tidak
/// pernah ada tetesan terpisah. Konten selalu digambar di atas indikator.
class GooeySelector<T> extends StatefulWidget {
  const GooeySelector({
    super.key,
    required this.axis,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.gap = 0,
    this.padding = EdgeInsets.zero,
    this.itemPadding =
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.borderRadius = HiqeoRadius.pill,
    this.indicatorColor,
    this.defaultTextStyle,
    this.expandItems = false,
  });

  final Axis axis;
  final List<GooeySelectorItem<T>> items;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Jarak antar item; indikator tidak melintasi jarak ini saat diam.
  final double gap;

  /// Jarak dari tepi luar pemilih ke item pertama/terakhir.
  final EdgeInsets padding;

  /// Padding di dalam area yang ditutup indikator.
  final EdgeInsets itemPadding;

  /// Radius indikator. Pakai [HiqeoRadius.pill] untuk tab dan 18 untuk kartu.
  final double borderRadius;

  final Color? indicatorColor;

  /// Gaya teks bawaan saat item tidak memakai [GooeySelectorItem.builder].
  final TextStyle? defaultTextStyle;

  /// Bila benar pada sumbu horizontal, setiap item berbagi lebar yang sama.
  final bool expandItems;

  static const Duration slideDuration = Duration(milliseconds: 480);
  static const Duration reducedSlideDuration = Duration(milliseconds: 150);

  /// Bagian pantulan `easeOutBack` yang dipakai (≈4,4% jarak).
  static const double headOvershootScale = 0.45;

  /// Penyempitan leher maksimum terhadap ukuran lintang item terkecil.
  static const double maxNeckThinning = 0.15;

  @override
  State<GooeySelector<T>> createState() => _GooeySelectorState<T>();
}

class _GooeySelectorState<T> extends State<GooeySelector<T>>
    with SingleTickerProviderStateMixin {
  final GlobalKey _stackKey = GlobalKey(debugLabel: 'gooey-selector-stack');
  late List<GlobalKey> _itemKeys;
  late final AnimationController _move;
  late int _selectedIndex;
  List<Rect> _rects = const <Rect>[];
  Rect? _headStart;
  Rect? _tailStart;
  Rect? _headEnd;
  Rect? _tailEnd;
  bool _measureScheduled = false;

  @override
  void initState() {
    super.initState();
    _itemKeys = _createKeys(widget.items.length);
    _selectedIndex = _selectedIndexFor(widget.selected);
    _move = AnimationController(
      vsync: this,
      duration: GooeySelector.slideDuration,
      value: 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = VisualEffectPolicyScope.of(context).reduceMotion;
    _move.duration = reduceMotion
        ? GooeySelector.reducedSlideDuration
        : GooeySelector.slideDuration;
  }

  @override
  void didUpdateWidget(GooeySelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length != oldWidget.items.length) {
      _itemKeys = _createKeys(widget.items.length);
      _rects = const <Rect>[];
      _headStart = null;
      _tailStart = null;
      _headEnd = null;
      _tailEnd = null;
      _selectedIndex = _selectedIndexFor(widget.selected);
      _scheduleMeasure();
      return;
    }
    final next = _selectedIndexFor(widget.selected);
    if (next == _selectedIndex) return;
    _selectedIndex = next;
    if (next < _rects.length) {
      _headStart = _currentHeadRect;
      _tailStart = _currentTailRect;
      _headEnd = _rects[next];
      _tailEnd = _rects[next];
      _move.forward(from: 0);
    } else {
      _scheduleMeasure();
    }
  }

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  List<GlobalKey> _createKeys(int count) => List<GlobalKey>.generate(
        count,
        (index) => GlobalKey(debugLabel: 'gooey-selector-item-$index'),
      );

  int _selectedIndexFor(T value) {
    if (widget.items.isEmpty) return 0;
    final index = widget.items.indexWhere((item) => item.value == value);
    assert(index >= 0, 'Nilai GooeySelector tidak ada di daftar item.');
    return index < 0 ? 0 : index;
  }

  Rect? get _targetRect =>
      _selectedIndex < _rects.length ? _rects[_selectedIndex] : null;

  Rect get _currentHeadRect {
    final start = _headStart;
    final end = _headEnd;
    if (start == null || end == null) return Rect.zero;
    return Rect.lerp(
      start,
      end,
      _reduceMotion ? _move.value : gooeySelectorHeadProgress(_move.value),
    )!;
  }

  Rect get _currentTailRect {
    final start = _tailStart;
    final end = _tailEnd;
    if (start == null || end == null) return Rect.zero;
    return Rect.lerp(
      start,
      end,
      _reduceMotion ? _move.value : gooeySelectorTailProgress(_move.value),
    )!;
  }

  bool get _reduceMotion =>
      VisualEffectPolicyScope.of(context).reduceMotion;

  double get _maxSeparation {
    final start = _headStart;
    final end = _headEnd;
    if (start == null || end == null) return 0;
    return widget.axis == Axis.horizontal
        ? (end.center.dx - start.center.dx).abs()
        : (end.center.dy - start.center.dy).abs();
  }

  void _scheduleMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      _measure();
    });
  }

  void _measure() {
    final stack =
        _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null || !stack.hasSize) return;
    final rects = <Rect>[];
    for (final key in _itemKeys) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      rects.add(box.localToGlobal(Offset.zero, ancestor: stack) & box.size);
    }
    if (_sameRects(rects, _rects)) return;
    final hadGeometry = _rects.length == rects.length && _headEnd != null;
    final head = hadGeometry ? _currentHeadRect : null;
    final tail = hadGeometry ? _currentTailRect : null;
    setState(() {
      _rects = rects;
      final target = rects[_selectedIndex.clamp(0, rects.length - 1)];
      if (!hadGeometry || !_move.isAnimating) {
        _headStart = target;
        _tailStart = target;
        _headEnd = target;
        _tailEnd = target;
        _move.value = 1;
      } else {
        _headStart = head;
        _tailStart = tail;
        _headEnd = target;
        _tailEnd = target;
      }
    });
  }

  bool _sameRects(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _handleTap(int index) {
    if (index == _selectedIndex) return;
    unawaited(HapticFeedback.selectionClick());
    widget.onChanged(widget.items[index].value);
  }

  void _selectRelative(int delta) {
    if (widget.items.isEmpty) return;
    final next = (_selectedIndex + delta).clamp(0, widget.items.length - 1);
    if (next == _selectedIndex) return;
    unawaited(HapticFeedback.selectionClick());
    widget.onChanged(widget.items[next].value);
  }

  Map<ShortcutActivator, Intent> get _shortcuts =>
      widget.axis == Axis.horizontal
          ? <ShortcutActivator, Intent>{
              const SingleActivator(LogicalKeyboardKey.arrowRight):
                  const _MoveSelectionIntent(1),
              const SingleActivator(LogicalKeyboardKey.arrowLeft):
                  const _MoveSelectionIntent(-1),
            }
          : <ShortcutActivator, Intent>{
              const SingleActivator(LogicalKeyboardKey.arrowDown):
                  const _MoveSelectionIntent(1),
              const SingleActivator(LogicalKeyboardKey.arrowUp):
                  const _MoveSelectionIntent(-1),
            };

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final colors = HiqeoColors.of(context);
    final policy = VisualEffectPolicyScope.of(context);
    if (!_move.isAnimating) _scheduleMeasure();
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Shortcuts(
        shortcuts: _shortcuts,
        child: Actions(
          actions: <Type, Action<Intent>>{
            _MoveSelectionIntent: CallbackAction<_MoveSelectionIntent>(
              onInvoke: (intent) {
                _selectRelative(intent.delta);
                return null;
              },
            ),
          },
          child: FocusTraversalGroup(
            child: AnimatedBuilder(
              animation: _move,
              builder: (context, _) {
                final target = _targetRect;
                final reduceMotion = policy.reduceMotion;
                final morphing = policy.gooey &&
                    !reduceMotion &&
                    _move.isAnimating &&
                    target != null;
                final head = _currentHeadRect;
                final tail = _currentTailRect;
                return Stack(
                  key: _stackKey,
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    if (target != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ExcludeSemantics(
                            child: RepaintBoundary(
                              child: CustomPaint(
                                key: const ValueKey<String>(
                                  'gooey-selector-indicator',
                                ),
                                painter: GooeySelectorBlobPainter(
                                  headRect: head,
                                  tailRect: tail,
                                  axis: widget.axis,
                                  borderRadius: widget.borderRadius,
                                  color:
                                      widget.indicatorColor ?? colors.primary,
                                  morphing: morphing,
                                  maxSeparation: _maxSeparation,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: widget.padding,
                      child: _buildItems(
                        context,
                        colors,
                        head,
                        tail,
                        morphing,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItems(
    BuildContext context,
    HiqeoColors colors,
    Rect head,
    Rect tail,
    bool morphing,
  ) {
    final children = <Widget>[];
    for (var index = 0; index < widget.items.length; index++) {
      if (index > 0 && widget.gap > 0) {
        children.add(
          SizedBox(
            width: widget.axis == Axis.horizontal ? widget.gap : 0,
            height: widget.axis == Axis.vertical ? widget.gap : 0,
          ),
        );
      }
      final built = _buildItem(context, colors, index, head, tail, morphing);
      children.add(
        widget.axis == Axis.horizontal && widget.expandItems
            ? Expanded(child: built)
            : built,
      );
    }
    if (widget.axis == Axis.horizontal) {
      return Row(
        mainAxisSize:
            widget.expandItems ? MainAxisSize.max : MainAxisSize.min,
        children: children,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _buildItem(
    BuildContext context,
    HiqeoColors colors,
    int index,
    Rect head,
    Rect tail,
    bool morphing,
  ) {
    final item = widget.items[index];
    final rect = index < _rects.length ? _rects[index] : Rect.zero;
    final coverage = rect.isEmpty
        ? 0.0
        : gooeySelectorCoverage(
            item: rect,
            head: head,
            tail: tail,
            morphing: morphing,
          );
    final selected = index == _selectedIndex;
    final state = GooeySelectorItemState(
      selected: selected,
      coverage: coverage,
    );
    final content = item.builder?.call(context, state) ??
        _defaultText(context, item, colors, coverage);
    return Semantics(
      key: _itemKeys[index],
      button: true,
      selected: selected,
      label: item.semanticsLabel,
      onTap: () => _handleTap(index),
      excludeSemantics: true,
      child: Focus(
        canRequestFocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space) {
            _handleTap(index);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: () => _handleTap(index),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: HiqeoMetrics.minTouchTarget,
            ),
            child: Padding(
              padding: widget.itemPadding,
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  Widget _defaultText(
    BuildContext context,
    GooeySelectorItem<T> item,
    HiqeoColors colors,
    double coverage,
  ) {
    final theme = Theme.of(context);
    final base = widget.defaultTextStyle ?? theme.textTheme.labelLarge ??
        const TextStyle();
    return Text(
      item.semanticsLabel,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: base.copyWith(
        color: Color.lerp(colors.textSecondary, colors.onPrimary, coverage),
      ),
    );
  }
}

/// Kemajuan kepala: pegas kaku dengan pantulan dibatasi ≈4,4%.
@visibleForTesting
double gooeySelectorHeadProgress(double t) {
  final eased = Curves.easeOutBack.transform(t);
  return 1 + (eased - 1) * GooeySelector.headOvershootScale;
}

/// Kemajuan ekor: menyusul lebih lambat dan tanpa pantulan.
@visibleForTesting
double gooeySelectorTailProgress(double t) =>
    const Interval(0.12, 1, curve: Curves.easeOutCubic).transform(t);

/// Bagian area item yang tertutup indikator, 0..1.
///
/// Dihitung dari irisan dua dimensi; saat indikator sama dengan item hasilnya
/// tepat 1, sehingga warna teks baru bergeser penuh ketika gumpalan menutup.
@visibleForTesting
double gooeySelectorCoverage({
  required Rect item,
  required Rect head,
  required Rect tail,
  required bool morphing,
}) {
  if (item.isEmpty) return 0;
  final blob = morphing ? head.expandToInclude(tail) : head;
  final overlapX = math.max(
    0.0,
    math.min(blob.right, item.right) - math.max(blob.left, item.left),
  );
  final overlapY = math.max(
    0.0,
    math.min(blob.bottom, item.bottom) - math.max(blob.top, item.top),
  );
  return (overlapX * overlapY / (item.width * item.height)).clamp(0.0, 1.0);
}

class _MoveSelectionIntent extends Intent {
  const _MoveSelectionIntent(this.delta);

  final int delta;
}

/// Melukis indikator sebagai satu bentuk: rounded rect kepala, rounded rect
/// ekor, dan leher yang menyambung keduanya. Leher menipis saat gumpalan
/// memanjang tetapi tidak pernah terputus.
@visibleForTesting
class GooeySelectorBlobPainter extends CustomPainter {
  const GooeySelectorBlobPainter({
    required this.headRect,
    required this.tailRect,
    required this.axis,
    required this.borderRadius,
    required this.color,
    required this.morphing,
    required this.maxSeparation,
  });

  final Rect headRect;
  final Rect tailRect;
  final Axis axis;
  final double borderRadius;
  final Color color;
  final bool morphing;
  final double maxSeparation;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    if (!morphing) {
      canvas.drawRRect(_rounded(headRect), paint);
      return;
    }
    var path = Path.combine(
      ui.PathOperation.union,
      Path()..addRRect(_rounded(headRect)),
      Path()..addRRect(_rounded(tailRect)),
    );
    final separation = axis == Axis.horizontal
        ? (headRect.center.dx - tailRect.center.dx).abs()
        : (headRect.center.dy - tailRect.center.dy).abs();
    if (separation > 0.5) {
      final stretch = maxSeparation <= 0
          ? 0.0
          : (separation / (maxSeparation * 0.6)).clamp(0.0, 1.0);
      final neckThickness =
          math.min(
            axis == Axis.horizontal ? headRect.height : headRect.width,
            axis == Axis.horizontal ? tailRect.height : tailRect.width,
          ) *
              (1 - GooeySelector.maxNeckThinning * stretch);
      final neck = axis == Axis.horizontal
          ? _horizontalNeck(headRect, tailRect, neckThickness)
          : _verticalNeck(headRect, tailRect, neckThickness);
      path = Path.combine(ui.PathOperation.union, path, Path()..addRRect(neck));
    }
    canvas.drawPath(path, paint);
  }

  RRect _rounded(Rect rect) {
    final radius = math.min(
      borderRadius,
      math.min(rect.width, rect.height) / 2,
    );
    return RRect.fromRectAndRadius(rect, Radius.circular(radius));
  }

  RRect _horizontalNeck(Rect head, Rect tail, double thickness) {
    final centerY = (head.center.dy + tail.center.dy) / 2;
    final left = math.min(head.center.dx, tail.center.dx);
    final right = math.max(head.center.dx, tail.center.dx);
    return RRect.fromRectAndRadius(
      Rect.fromLTRB(left, centerY - thickness / 2, right, centerY + thickness / 2),
      Radius.circular(thickness / 2),
    );
  }

  RRect _verticalNeck(Rect head, Rect tail, double thickness) {
    final centerX = (head.center.dx + tail.center.dx) / 2;
    final top = math.min(head.center.dy, tail.center.dy);
    final bottom = math.max(head.center.dy, tail.center.dy);
    return RRect.fromRectAndRadius(
      Rect.fromLTRB(centerX - thickness / 2, top, centerX + thickness / 2, bottom),
      Radius.circular(thickness / 2),
    );
  }

  @override
  bool shouldRepaint(GooeySelectorBlobPainter oldDelegate) =>
      oldDelegate.headRect != headRect ||
      oldDelegate.tailRect != tailRect ||
      oldDelegate.axis != axis ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.color != color ||
      oldDelegate.morphing != morphing ||
      oldDelegate.maxSeparation != maxSeparation;
}
