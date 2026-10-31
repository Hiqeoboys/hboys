import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/gooey/gooey_selector.dart';
import 'package:nama_app/design/motion/visual_effect_policy.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

const List<String> _days = <String>['Sabtu', 'Minggu', 'Senin'];

VisualEffectPolicy _policy({bool reduceMotion = false}) {
  return VisualEffectPolicy(
    powerProfile: PowerProfile.normal,
    reduceMotion: reduceMotion,
    deviceTier: DeviceTier.capable,
  );
}

class _SelectorHarness extends StatefulWidget {
  const _SelectorHarness({
    required this.policy,
    this.axis = Axis.horizontal,
    this.initial = 'Minggu',
    this.heights,
    this.onChanged,
  });

  final VisualEffectPolicy policy;
  final Axis axis;
  final String initial;
  final List<double>? heights;
  final ValueChanged<String>? onChanged;

  @override
  State<_SelectorHarness> createState() => _SelectorHarnessState();
}

class _SelectorHarnessState extends State<_SelectorHarness> {
  late String _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    final heights = widget.heights;
    return MaterialApp(
      theme: hiqeoLightTheme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: VisualEffectPolicyScope(
              policy: widget.policy,
              child: GooeySelector<String>(
                key: const ValueKey<String>('selector-under-test'),
                axis: widget.axis,
                selected: _selected,
                gap: widget.axis == Axis.vertical ? 8 : 4,
                itemPadding: heights == null
                    ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                    : EdgeInsets.zero,
                borderRadius:
                    widget.axis == Axis.vertical ? HiqeoRadius.card : HiqeoRadius.pill,
                items: <GooeySelectorItem<String>>[
                  for (var index = 0; index < _days.length; index++)
                    GooeySelectorItem<String>(
                      value: _days[index],
                      semanticsLabel: _days[index],
                      builder: heights == null
                          ? null
                          : (context, state) => SizedBox(
                                height: heights[index],
                                child: Center(
                                  child: Text(
                                    _days[index],
                                    style: TextStyle(
                                      color: Color.lerp(
                                        HiqeoColors.light.textSecondary,
                                        HiqeoColors.light.onPrimary,
                                        state.coverage,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                    ),
                ],
                onChanged: (value) {
                  widget.onChanged?.call(value);
                  setState(() => _selected = value);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

GooeySelectorBlobPainter _painter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byKey(const ValueKey<String>('gooey-selector-indicator')),
  );
  return paint.painter! as GooeySelectorBlobPainter;
}

Offset _origin(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(const ValueKey<String>('selector-under-test')));

double _globalCenterX(WidgetTester tester, Rect localRect) =>
    localRect.center.dx + _origin(tester).dx;

Future<void> _pump(
  WidgetTester tester, {
  VisualEffectPolicy policy = const VisualEffectPolicy(
    powerProfile: PowerProfile.normal,
    reduceMotion: false,
    deviceTier: DeviceTier.capable,
  ),
  Axis axis = Axis.horizontal,
  String initial = 'Minggu',
  List<double>? heights,
  ValueChanged<String>? onChanged,
}) async {
  await tester.pumpWidget(
    _SelectorHarness(
      policy: policy,
      axis: axis,
      initial: initial,
      heights: heights,
      onChanged: onChanged,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('indikator mengikuti item terpilih dan bergerak satu gumpalan',
      (tester) async {
    await _pump(tester);
    var painter = _painter(tester);
    expect(painter.morphing, isFalse);
    expect(painter.headRect, painter.tailRect);
    expect(
      _globalCenterX(tester, painter.headRect),
      closeTo(tester.getCenter(find.text('Minggu')).dx, 0.5),
    );

    await tester.tap(find.text('Senin'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    painter = _painter(tester);
    expect(painter.morphing, isTrue);
    expect(
      (painter.headRect.center.dx - painter.tailRect.center.dx).abs(),
      greaterThan(1),
    );
    expect(find.text('Senin'), findsOneWidget);

    await tester.pumpAndSettle();
    painter = _painter(tester);
    expect(painter.morphing, isFalse);
    expect(painter.headRect, painter.tailRect);
    expect(
      _globalCenterX(tester, painter.headRect),
      closeTo(tester.getCenter(find.text('Senin')).dx, 0.5),
    );
    expect(
      tester.widget<Text>(find.text('Senin')).style!.color,
      HiqeoColors.light.onPrimary,
    );
    expect(
      tester.widget<Text>(find.text('Sabtu')).style!.color,
      HiqeoColors.light.textSecondary,
    );
  });

  testWidgets('warna teks bergeser saat gumpalan menutupi item',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Sabtu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final sabtu = tester.widget<Text>(find.text('Sabtu')).style!.color!;
    expect(sabtu, isNot(equals(HiqeoColors.light.onPrimary)));
    expect(sabtu, isNot(equals(HiqeoColors.light.textSecondary)));

    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('Sabtu')).style!.color,
      HiqeoColors.light.onPrimary,
    );
  });

  testWidgets('mengetuk item yang sudah terpilih tidak beranimasi',
      (tester) async {
    var changes = 0;
    await _pump(tester, onChanged: (_) => changes++);
    final before = _painter(tester);

    await tester.tap(find.text('Minggu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(changes, 0);
    expect(_painter(tester).headRect, before.headRect);
  });

  testWidgets('indikator mengikuti ukuran item vertikal yang berbeda',
      (tester) async {
    await _pump(
      tester,
      axis: Axis.vertical,
      initial: 'Sabtu',
      heights: const <double>[56, 84, 64],
    );
    final handle = tester.ensureSemantics();
    final origin = _origin(tester);
    final target =
        tester.getRect(find.bySemanticsLabel('Minggu')).shift(-origin);
    expect(target.height, 84);

    await tester.tap(find.text('Minggu'));
    await tester.pumpAndSettle();

    final painter = _painter(tester);
    expect(painter.headRect, target);
    expect(painter.headRect, painter.tailRect);
    handle.dispose();
  });

  testWidgets('kurangi gerakan memakai geser linear 150 ms tanpa regangan',
      (tester) async {
    await _pump(tester, policy: _policy(reduceMotion: true));
    final start = tester.getCenter(find.text('Minggu')).dx;
    final target = tester.getCenter(find.text('Sabtu')).dx;

    await tester.tap(find.text('Sabtu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));

    final mid = _painter(tester);
    expect(mid.morphing, isFalse);
    expect(
      _globalCenterX(tester, mid.headRect),
      closeTo((start + target) / 2, 1.5),
    );

    await tester.pumpAndSettle();
    expect(
      _globalCenterX(tester, _painter(tester).headRect),
      closeTo(target, 0.5),
    );
  });

  testWidgets('semantik menandai item terpilih dan dapat diaktifkan',
      (tester) async {
    await _pump(tester);
    final handle = tester.ensureSemantics();

    final selected = tester.getSemantics(find.text('Minggu'));
    expect(selected.flagsCollection.isButton, isTrue);
    expect(selected.flagsCollection.isSelected, ui.Tristate.isTrue);
    expect(selected.label, 'Minggu');
    expect(
      selected.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      isTrue,
    );

    final idle = tester.getSemantics(find.text('Sabtu'));
    expect(idle.flagsCollection.isSelected, ui.Tristate.isFalse);
    handle.dispose();
  });

  testWidgets('panah keyboard memindahkan pilihan', (tester) async {
    var last = '';
    await _pump(tester, onChanged: (value) => last = value);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(last, 'Senin');
  });
}
