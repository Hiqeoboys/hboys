import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/motion/visual_effect_policy.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/design/widgets/altracq_button.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

Widget policyApp(VisualEffectPolicy policy, Widget child) => MaterialApp(
      theme: altracqLightTheme,
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

void main() {
  testWidgets('tombol primer menekan memanggil balik dan berlabel',
      (tester) async {
    int taps = 0;
    await tester.pumpWidget(
      policyApp(
        VisualEffectPolicy.full,
        Padding(
          padding: const EdgeInsets.all(16),
          child: AltracqButton(label: 'Siapkan pendakian', onPressed: () => taps++),
        ),
      ),
    );
    final handle = tester.ensureSemantics();

    expect(tester.getSize(find.byType(AltracqButton)).height, 56);
    expect(
      tester.getSize(find.byType(AltracqButton)).height,
      greaterThanOrEqualTo(AltracqMetrics.minTouchTarget),
    );
    expect(find.byType(ImageFiltered), findsOneWidget);

    await tester.tap(find.text('Siapkan pendakian'));
    expect(taps, 1);

    final node = tester.getSemantics(find.text('Siapkan pendakian'));
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.label, 'Siapkan pendakian');
    handle.dispose();
  });

  testWidgets('tombol tanpa balik tidak merespons sentuhan', (tester) async {
    await tester.pumpWidget(
      policyApp(
        VisualEffectPolicy.full,
        const Padding(
          padding: EdgeInsets.all(16),
          child: AltracqButton(label: 'Mati'),
        ),
      ),
    );

    await tester.tap(find.text('Mati'));
    await tester.pumpAndSettle();
    expect(find.text('Mati'), findsOneWidget);
  });

  testWidgets('gooey mati tidak mengubah perilaku tombol', (tester) async {
    int taps = 0;
    await tester.pumpWidget(
      policyApp(
        policy(reduceMotion: true),
        Padding(
          padding: const EdgeInsets.all(16),
          child: AltracqButton(label: 'Simpan', onPressed: () => taps++),
        ),
      ),
    );

    expect(find.byType(ImageFiltered), findsNothing);
    await tester.tap(find.text('Simpan'));
    expect(taps, 1);
  });

  testWidgets('pasangan tombol: masing-masing zona terpisah, celah 12 px',
      (tester) async {
    int left = 0;
    int right = 0;
    await tester.pumpWidget(
      policyApp(
        VisualEffectPolicy.full,
        Padding(
          padding: const EdgeInsets.all(16),
          child: AltracqButtonPair(
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
            (box) => box.width == AltracqMetrics.buttonPairGap,
          ),
      isTrue,
    );

    await tester.tap(find.text('Jeda'));
    expect(left, 1);
    expect(right, 0);
    await tester.tap(find.text('Selesai'));
    expect(right, 1);

    final handle = tester.ensureSemantics();
    expect(tester.getSemantics(find.text('Jeda')).flagsCollection.isButton, isTrue);
    expect(
      tester.getSemantics(find.text('Selesai')).flagsCollection.isButton,
      isTrue,
    );
    handle.dispose();
  });

  testWidgets('pasangan tombol tetap berfungsi saat gooey mati',
      (tester) async {
    int left = 0;
    int right = 0;
    await tester.pumpWidget(
      policyApp(
        policy(power: PowerProfile.saver),
        Padding(
          padding: const EdgeInsets.all(16),
          child: AltracqButtonPair(
            leftLabel: 'Jeda',
            rightLabel: 'Selesai',
            onLeftTap: () => left++,
            onRightTap: () => right++,
          ),
        ),
      ),
    );

    expect(find.byType(ImageFiltered), findsNothing);
    await tester.tap(find.text('Jeda'));
    await tester.tap(find.text('Selesai'));
    expect(left, 1);
    expect(right, 1);
  });
}
