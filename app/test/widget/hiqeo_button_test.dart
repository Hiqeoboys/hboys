import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/motion/visual_effect_policy.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/design/widgets/hiqeo_button.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

Widget policyApp(VisualEffectPolicy policy, Widget child) => MaterialApp(
      theme: hiqeoLightTheme,
      home: Scaffold(
        body: Center(
          child: VisualEffectPolicyScope(policy: policy, child: child),
        ),
      ),
    );

VisualEffectPolicy policy({
  PowerProfile power = PowerProfile.normal,
  bool reduceMotion = false,
  DeviceTier tier = DeviceTier.capable,
}) =>
    VisualEffectPolicy(
      powerProfile: power,
      reduceMotion: reduceMotion,
      deviceTier: tier,
    );

Widget button({
  String label = 'Siapkan pendakian',
  VoidCallback? onPressed,
  HiqeoButtonVariant variant = HiqeoButtonVariant.primary,
  Widget? leading,
}) =>
    Padding(
      padding: const EdgeInsets.all(16),
      child: HiqeoButton(
        label: label,
        onPressed: onPressed,
        variant: variant,
        leading: leading,
      ),
    );

/// Bentuk pil sempurna: satu [StadiumBorder] berarti radius = separuh tinggi.
Finder solidPill() => find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration is ShapeDecoration &&
          (widget.decoration as ShapeDecoration).shape is StadiumBorder,
    );

/// Tombol tidak boleh lagi memakai lapisan gooey (blur + pemangkasan alfa).
void expectNoGooey(WidgetTester tester) {
  expect(find.byType(ImageFiltered), findsNothing);
  expect(find.byType(ColorFiltered), findsNothing);
}

void main() {
  testWidgets('tombol primer adalah pil solid 56 px yang dapat ditekan',
      (tester) async {
    int taps = 0;
    await tester.pumpWidget(
      policyApp(
        VisualEffectPolicy.full,
        button(label: 'Siapkan pendakian', onPressed: () => taps++),
      ),
    );
    final handle = tester.ensureSemantics();

    final size = tester.getSize(find.byType(HiqeoButton));
    expect(size.height, 56);
    expect(size.height, greaterThanOrEqualTo(HiqeoMetrics.minTouchTarget));
    expect(solidPill(), findsOneWidget);
    expectNoGooey(tester);

    await tester.tap(find.text('Siapkan pendakian'));
    expect(taps, 1);

    final node = tester.getSemantics(find.text('Siapkan pendakian'));
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.label, 'Siapkan pendakian');
    handle.dispose();
  });

  testWidgets('tombol tanpa balik meredup dan tidak merespons sentuhan',
      (tester) async {
    await tester.pumpWidget(
      policyApp(VisualEffectPolicy.full, button(label: 'Mati')),
    );

    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0.6,
    );
    expect(solidPill(), findsOneWidget);

    await tester.tap(find.text('Mati'));
    await tester.pumpAndSettle();
    expect(find.text('Mati'), findsOneWidget);
  });

  testWidgets('umpan balik tekan: skala 0,97 dan redup tipis lalu pulih',
      (tester) async {
    await tester.pumpWidget(
      policyApp(
        VisualEffectPolicy.full,
        button(label: 'Mulai pendakian', onPressed: () {}),
      ),
    );

    final gesture =
        await tester.startGesture(tester.getCenter(find.text('Mulai pendakian')));
    await tester.pump();

    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      0.97,
    );
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0.92,
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      1,
    );
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );
  });

  testWidgets('kebijakan efek mati tidak mengubah bentuk maupun perilaku',
      (tester) async {
    int taps = 0;
    await tester.pumpWidget(
      policyApp(
        policy(reduceMotion: true),
        button(label: 'Simpan', onPressed: () => taps++),
      ),
    );

    expect(solidPill(), findsOneWidget);
    expectNoGooey(tester);
    await tester.tap(find.text('Simpan'));
    expect(taps, 1);
  });

  testWidgets('tombol invers tetap satu pil solid', (tester) async {
    int taps = 0;
    await tester.pumpWidget(
      policyApp(
        VisualEffectPolicy.full,
        button(
          label: 'Siapkan pendakian',
          variant: HiqeoButtonVariant.inverse,
          onPressed: () => taps++,
        ),
      ),
    );

    expect(solidPill(), findsOneWidget);
    expectNoGooey(tester);
    await tester.tap(find.text('Siapkan pendakian'));
    expect(taps, 1);
  });

  testWidgets('leading berada di dalam satu pil yang sama dengan label',
      (tester) async {
    int taps = 0;
    await tester.pumpWidget(
      policyApp(
        VisualEffectPolicy.full,
        button(
          label: 'Lanjutkan dengan Google',
          leading: const Icon(Icons.circle, key: ValueKey('logo-provider')),
          onPressed: () => taps++,
        ),
      ),
    );

    expect(solidPill(), findsOneWidget);
    expect(find.byKey(const ValueKey('logo-provider')), findsOneWidget);

    final pillRect = tester.getRect(solidPill());
    expect(pillRect.contains(tester.getCenter(find.text('Lanjutkan dengan Google'))), isTrue);
    expect(
      pillRect.contains(
        tester.getCenter(find.byKey(const ValueKey('logo-provider'))),
      ),
      isTrue,
    );

    await tester.tap(find.text('Lanjutkan dengan Google'));
    expect(taps, 1);
  });

  testWidgets('pasangan tombol: dua pil terpisah dengan celah 12 px',
      (tester) async {
    int left = 0;
    int right = 0;
    await tester.pumpWidget(
      policyApp(
        VisualEffectPolicy.full,
        Padding(
          padding: const EdgeInsets.all(16),
          child: HiqeoButtonPair(
            leftLabel: 'Jeda',
            rightLabel: 'Selesai',
            onLeftTap: () => left++,
            onRightTap: () => right++,
          ),
        ),
      ),
    );

    expect(
      tester.widgetList<SizedBox>(find.byType(SizedBox)).any(
            (box) => box.width == HiqeoMetrics.buttonPairGap,
          ),
      isTrue,
    );
    expect(solidPill(), findsNWidgets(2));
    expectNoGooey(tester);

    expect(
      tester.getRect(solidPill().first).overlaps(tester.getRect(solidPill().last)),
      isFalse,
    );

    await tester.tap(find.text('Jeda'));
    expect(left, 1);
    expect(right, 0);
    await tester.tap(find.text('Selesai'));
    expect(right, 1);

    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.text('Jeda')).flagsCollection.isButton,
      isTrue,
    );
    expect(
      tester.getSemantics(find.text('Selesai')).flagsCollection.isButton,
      isTrue,
    );
    handle.dispose();
  });

  testWidgets('pasangan tombol tetap berfungsi saat efek dimatikan',
      (tester) async {
    int left = 0;
    int right = 0;
    await tester.pumpWidget(
      policyApp(
        policy(power: PowerProfile.saver),
        Padding(
          padding: const EdgeInsets.all(16),
          child: HiqeoButtonPair(
            leftLabel: 'Jeda',
            rightLabel: 'Selesai',
            onLeftTap: () => left++,
            onRightTap: () => right++,
          ),
        ),
      ),
    );

    expect(solidPill(), findsNWidgets(2));
    expectNoGooey(tester);
    await tester.tap(find.text('Jeda'));
    await tester.tap(find.text('Selesai'));
    expect(left, 1);
    expect(right, 1);
  });
}
