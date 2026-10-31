import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/gooey/gooey_switch.dart';
import 'package:nama_app/design/motion/visual_effect_policy.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

VisualEffectPolicy _policy({bool reduceMotion = false}) {
  return VisualEffectPolicy(
    powerProfile: PowerProfile.normal,
    reduceMotion: reduceMotion,
    deviceTier: DeviceTier.capable,
  );
}

class _SwitchHarness extends StatefulWidget {
  const _SwitchHarness({
    this.initial = false,
    this.policy = const VisualEffectPolicy(
      powerProfile: PowerProfile.normal,
      reduceMotion: false,
      deviceTier: DeviceTier.capable,
    ),
    this.style,
    this.onChanged,
  });

  final bool initial;
  final VisualEffectPolicy policy;
  final GooeySwitchStyle? style;
  final ValueChanged<bool>? onChanged;

  @override
  State<_SwitchHarness> createState() => _SwitchHarnessState();
}

class _SwitchHarnessState extends State<_SwitchHarness> {
  late bool _value = widget.initial;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: hiqeoLightTheme,
      home: Scaffold(
        body: Center(
          child: VisualEffectPolicyScope(
            policy: widget.policy,
            child: GooeySwitch(
              value: _value,
              semanticsLabel: 'Cadangkan otomatis',
              style: widget.style,
              onChanged: (value) {
                widget.onChanged?.call(value);
                setState(() => _value = value);
              },
            ),
          ),
        ),
      ),
    );
  }
}

GooeySwitchKnobPainter _knob(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byKey(const ValueKey<String>('gooey-switch-knob')),
  );
  return paint.painter! as GooeySwitchKnobPainter;
}

AnimatedContainer _track(WidgetTester tester) {
  return tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byType(GooeySwitch),
      matching: find.byType(AnimatedContainer),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  bool initial = false,
  VisualEffectPolicy? policy,
  GooeySwitchStyle? style,
  ValueChanged<bool>? onChanged,
}) async {
  await tester.pumpWidget(
    _SwitchHarness(
      initial: initial,
      policy: policy ?? _policy(),
      style: style,
      onChanged: onChanged,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ketukan memindahkan knob dan memudarkan warna trek',
      (tester) async {
    bool? last;
    await _pump(tester, onChanged: (value) => last = value);

    expect(_knob(tester).headX, GooeySwitch.knobCenterX(false));
    expect(_knob(tester).tailX, GooeySwitch.knobCenterX(false));
    expect(_knob(tester).morphing, isFalse);
    expect(
      (_track(tester).decoration! as BoxDecoration).color,
      HiqeoColors.light.secondary,
    );
    expect(_track(tester).duration, GooeySwitch.colorDuration);

    await tester.tap(find.byType(GooeySwitch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    final mid = _knob(tester);
    expect(last, isTrue);
    expect(mid.morphing, isTrue);
    expect(mid.headX, greaterThan(mid.tailX));
    expect(mid.knobWidth, GooeySwitch.knobDiameter);

    await tester.pumpAndSettle();
    final settled = _knob(tester);
    expect(settled.headX, closeTo(GooeySwitch.knobCenterX(true), 0.01));
    expect(settled.tailX, closeTo(GooeySwitch.knobCenterX(true), 0.01));
    expect(settled.morphing, isFalse);
    expect(
      (_track(tester).decoration! as BoxDecoration).color,
      HiqeoColors.light.primary,
    );
  });

  testWidgets('menekan knob melebarkan 4 px lalu kembali saat dilepas',
      (tester) async {
    await _pump(tester);
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(GooeySwitch)));
    await tester.pump();
    expect(
      _knob(tester).knobWidth,
      GooeySwitch.knobDiameter + GooeySwitch.pressWiden,
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_knob(tester).knobWidth, GooeySwitch.knobDiameter);
  });

  testWidgets('kurangi gerakan menggeser knob linear 150 ms tanpa regangan',
      (tester) async {
    await _pump(tester, policy: _policy(reduceMotion: true));

    await tester.tap(find.byType(GooeySwitch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));

    final mid = _knob(tester);
    expect(mid.morphing, isFalse);
    expect(
      mid.headX,
      closeTo(
        (GooeySwitch.knobCenterX(false) + GooeySwitch.knobCenterX(true)) / 2,
        0.5,
      ),
    );

    await tester.pumpAndSettle();
    expect(
      _knob(tester).headX,
      closeTo(GooeySwitch.knobCenterX(true), 0.01),
    );
  });

  testWidgets('semantik menyatakan status dan aksi ketuk', (tester) async {
    await _pump(tester);
    final handle = tester.ensureSemantics();

    final node = tester.getSemantics(find.bySemanticsLabel('Cadangkan otomatis'));
    expect(node.flagsCollection.isToggled, ui.Tristate.isFalse);
    expect(
      node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      isTrue,
    );

    await tester.tap(find.byType(GooeySwitch));
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Cadangkan otomatis'))
          .flagsCollection
          .isToggled,
      ui.Tristate.isTrue,
    );
    handle.dispose();
  });

  testWidgets('spasi keyboard menyalakan saklar', (tester) async {
    bool? last;
    await _pump(tester, onChanged: (value) => last = value);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(last, isTrue);
    expect(_knob(tester).headX, closeTo(GooeySwitch.knobCenterX(true), 0.01));
  });

  testWidgets('gaya recap memakai trek krem transparan saat mati',
      (tester) async {
    await _pump(
      tester,
      style: GooeySwitchStyle.recap(HiqeoColors.dark),
    );

    expect(
      (_track(tester).decoration! as BoxDecoration).color,
      HiqeoColors.dark.primary.withValues(alpha: 0.22),
    );
    expect(_knob(tester).color, HiqeoColors.dark.primary);

    await tester.tap(find.byType(GooeySwitch));
    await tester.pumpAndSettle();

    expect(
      (_track(tester).decoration! as BoxDecoration).color,
      HiqeoColors.dark.primary,
    );
    expect(_knob(tester).color, HiqeoColors.dark.onPrimary);
  });
}
