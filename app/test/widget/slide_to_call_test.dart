import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/motion/visual_effect_policy.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/design/widgets/line_icons.dart';
import 'package:nama_app/features/safety/presentation/slide_to_call.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

const Size _phone = Size(390, 844);
const double _trackPadding = 16;

class _Recorder {
  int triggers = 0;
  int confirms = 0;
  final List<bool> interactions = <bool>[];

  /// Umpan balik haptic lewat kanal platform; direkam supaya klaim "haptic
  /// sedang" ikut teruji, bukan sekadar komentar.
  final List<MethodCall> haptics = <MethodCall>[];
}

void _mockPlatformChannel(WidgetTester tester, _Recorder recorder) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      recorder.haptics.add(call);
      return null;
    },
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
}

Future<_Recorder> _pump(
  WidgetTester tester, {
  VisualEffectPolicy policy = VisualEffectPolicy.full,
  bool interactive = true,
  String label = 'Basarnas 115',
}) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final recorder = _Recorder();
  _mockPlatformChannel(tester, recorder);
  await tester.pumpWidget(
    MaterialApp(
      theme: altracqDarkTheme,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _trackPadding),
          child: Center(
            child: VisualEffectPolicyScope(
              policy: policy,
              child: SlideToCall(
                label: label,
                semanticLabel: 'Telepon $label',
                interactive: interactive,
                onTrigger: () => recorder.triggers++,
                onConfirmRequest: () => recorder.confirms++,
                onInteractionChanged: recorder.interactions.add,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return recorder;
}

/// Pemilik semantik tampilan uji. `pipelineOwner` pada binding sudah usang
/// karena satu binding dapat mengelola beberapa tampilan.
SemanticsOwner _semanticsOwner() =>
    RendererBinding.instance.renderViews.single.owner!.semanticsOwner!;

Finder get _track => find.byType(SlideToCall);

/// Jarak knob dari posisi diamnya, diukur dari pusat ikon telepon.
double _knobOffset(WidgetTester tester) {
  final track = tester.getRect(_track);
  final icon = tester.getCenter(find.byType(AltracqIcon));
  return icon.dx -
      SlideToCall.knobSize / 2 -
      track.left -
      SlideToCall.knobInset;
}

double _maxTravel(WidgetTester tester) =>
    tester.getRect(_track).width -
    SlideToCall.knobSize -
    2 * SlideToCall.knobInset;

Future<TestGesture> _grab(WidgetTester tester) async {
  final gesture = await tester.startGesture(tester.getCenter(_track));
  await tester.pump();
  return gesture;
}

/// Geser melewati ambang 85% dan lepas.
Future<void> _slidePast(WidgetTester tester) async {
  final gesture = await _grab(tester);
  await gesture.moveBy(Offset(_maxTravel(tester) * 0.95, 0));
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

void main() {
  testWidgets('geometri diam: trek 64 px, knob 56 px di inset 4 px',
      (tester) async {
    final recorder = await _pump(tester);

    final size = tester.getSize(_track);
    expect(size.height, SlideToCall.trackHeight);
    expect(size.height, 64);
    expect(size.width, _phone.width - 2 * _trackPadding);
    expect(size.height, greaterThanOrEqualTo(AltracqMetrics.minTouchTarget));

    final track = tester.getRect(_track);
    final icon = tester.getCenter(find.byType(AltracqIcon));
    expect(icon.dx - track.left, SlideToCall.knobInset + SlideToCall.knobSize / 2);
    expect(icon.dy, track.center.dy);
    expect(_knobOffset(tester), 0);

    expect(find.text('Basarnas 115'), findsOneWidget);
    expect(recorder.triggers, 0);
    expect(recorder.confirms, 0);
    // Trek tidak memakai lapisan gooey (blur + pemangkasan alfa).
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byType(ColorFiltered), findsNothing);
    // Empat bidang gambar: trek, badan knob, lensa label, dan ikon telepon
    // (AltracqIcon sendiri juga sebuah CustomPaint).
    expect(
      find.descendant(of: _track, matching: find.byType(CustomPaint)),
      findsNWidgets(4),
    );
  });

  testWidgets('geser di bawah ambang membal lagi dan tidak menelepon',
      (tester) async {
    final recorder = await _pump(tester);
    final maxTravel = _maxTravel(tester);
    final gesture = await _grab(tester);

    await gesture.moveBy(Offset(maxTravel * 0.5, 0));
    await tester.pump();
    // Knob mengikuti jari.
    expect(_knobOffset(tester), closeTo(maxTravel * 0.5, 0.5));
    expect(recorder.triggers, 0);
    expect(recorder.interactions, <bool>[true]);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(_knobOffset(tester), 0);
    expect(recorder.triggers, 0);
    expect(recorder.interactions, <bool>[true, false]);
  });

  testWidgets('melewati 85% memicu sekali, haptic sedang, knob tetap di ujung',
      (tester) async {
    final recorder = await _pump(tester);
    final maxTravel = _maxTravel(tester);

    await _slidePast(tester);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(recorder.triggers, 1);
    expect(_knobOffset(tester), closeTo(maxTravel, 0.5));
    final vibrate = recorder.haptics
        .where((call) => call.method == 'HapticFeedback.vibrate')
        .toList();
    expect(vibrate, hasLength(1));
    expect(vibrate.single.arguments, 'HapticFeedbackType.mediumImpact');
  });

  testWidgets('knob pulang saat aplikasi kembali dari pemanggil telepon',
      (tester) async {
    final recorder = await _pump(tester);
    await _slidePast(tester);
    expect(recorder.triggers, 1);
    expect(_knobOffset(tester), greaterThan(0));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(_knobOffset(tester), greaterThan(0));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(_knobOffset(tester), 0);
    expect(recorder.triggers, 1);
  });

  testWidgets('ketukan biasa tidak menelepon; geser wajib melewati ambang',
      (tester) async {
    final recorder = await _pump(tester);

    await tester.tap(_track);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(recorder.triggers, 0);
    expect(recorder.confirms, 0);
    expect(_knobOffset(tester), 0);
  });

  testWidgets('kurangi animasi mematikan lensa tetapi geser tetap berfungsi',
      (tester) async {
    final recorder = await _pump(
      tester,
      policy: const VisualEffectPolicy(
        powerProfile: PowerProfile.normal,
        reduceMotion: true,
        deviceTier: DeviceTier.capable,
      ),
    );

    // Lensa label tidak dibangun; tiga bidang gambar sisanya tetap ada.
    expect(
      find.descendant(of: _track, matching: find.byType(CustomPaint)),
      findsNWidgets(3),
    );

    await _slidePast(tester);
    await tester.pumpAndSettle();
    expect(recorder.triggers, 1);
    expect(_knobOffset(tester), closeTo(_maxTravel(tester), 0.5));
  });

  testWidgets('profil hemat mengganti blur knob dengan isi padat',
      (tester) async {
    final recorder = await _pump(
      tester,
      policy: const VisualEffectPolicy(
        powerProfile: PowerProfile.saver,
        reduceMotion: false,
        deviceTier: DeviceTier.capable,
      ),
    );

    expect(
      find.descendant(of: _track, matching: find.byType(BackdropFilter)),
      findsNothing,
    );

    await _slidePast(tester);
    expect(recorder.triggers, 1);
  });

  testWidgets('interactive false mengunci trek dan menandai semantik nonaktif',
      (tester) async {
    final recorder = await _pump(tester, interactive: false);
    final handle = tester.ensureSemantics();

    final node = tester.getSemantics(_track);
    final data = node.getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isEnabled, ui.Tristate.isFalse);
    expect(data.hasAction(ui.SemanticsAction.tap), isFalse);

    final gesture = await _grab(tester);
    await gesture.moveBy(Offset(_maxTravel(tester), 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(recorder.triggers, 0);
    expect(recorder.interactions, isEmpty);
    expect(_knobOffset(tester), 0);
    handle.dispose();
  });

  testWidgets('aksi semantik membuka jalur konfirmasi, bukan panggilan langsung',
      (tester) async {
    final recorder = await _pump(tester);
    final handle = tester.ensureSemantics();
    await tester.pump();

    final node = tester.getSemantics(_track);
    final data = node.getSemanticsData();
    expect(node.label, 'Telepon Basarnas 115');
    expect(node.hint, 'Geser knob ke kanan untuk membuka telepon');
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isEnabled, ui.Tristate.isTrue);
    expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
    expect(data.customSemanticsActionIds, isNotEmpty);

    _semanticsOwner().performAction(node.id, ui.SemanticsAction.tap);
    await tester.pump();

    expect(recorder.confirms, 1);
    expect(recorder.triggers, 0);
    handle.dispose();
  });
}
