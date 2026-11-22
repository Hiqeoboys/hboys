import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/map/presentation/widgets/directions_panel.dart';
import 'package:nama_app/features/trails/application/recovery_guidance_service.dart';
import 'package:nama_app/features/trails/domain/guidance_state.dart';
import 'package:nama_app/features/trails/domain/heading_provider.dart';
import 'package:nama_app/features/trails/domain/track_route.dart';

import '../support/real_font.dart';

class _StaticGuidanceService implements RecoveryGuidanceService {
  _StaticGuidanceService(this._state);

  final StreamController<GuidanceState> _ctrl =
      StreamController<GuidanceState>.broadcast();
  final GuidanceState _state;

  @override
  HeadingProvider? get headingProvider => null;

  @override
  GuidanceState get currentState => _state;

  @override
  Stream<GuidanceState> get states => _ctrl.stream;

  @override
  TrackRoute? get activeRoute => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const LatLng _target = LatLng(-7.5050, 110.4000);

Widget _panelHost({
  required ThemeData theme,
  required GuidanceState state,
  bool straightLineAcknowledged = true,
  bool initialMinimized = false,
  Key? boundaryKey,
}) {
  return MaterialApp(
    theme: theme,
    debugShowCheckedModeBanner: false,
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(390, 480),
        disableAnimations: true,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF9FB29E),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: RepaintBoundary(
              key: boundaryKey,
              child: DirectionsPanel(
                guidanceService: _StaticGuidanceService(state),
                straightLineAcknowledged: straightLineAcknowledged,
                initialMinimized: initialMinimized,
                phoneHeading: 0.0,
                onClose: () {},
                onSos: () {},
                onAcknowledge: () {},
                onOpenWarningDialog: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<Uint8List> _capturePngBytes(
  WidgetTester tester,
  GlobalKey boundaryKey,
) async {
  late Uint8List bytes;
  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    bytes = data!.buffer.asUint8List();
    image.dispose();
  });
  return bytes;
}

void main() {
  group('Golden Tests DirectionsPanel (selalu gelap & identik di terang/gelap)',
      () {
    final cases = <(String, GuidanceState, bool, bool)>[
      (
        'mencari_gps',
        const GuidanceUnavailable(GuidanceUnavailableReason.waitingGps),
        true,
        false,
      ),
      (
        'ikuti_jejak',
        const GuidanceFollowingTrail(
          bearingDeg: 46.0,
          distToNextM: 38.0,
          remainingTrailM: 175.0,
          offRouteM: 90.0,
          progress: 0.4,
          targetPoint: _target,
          guidePath: <LatLng>[LatLng(-7.506, 110.402), _target],
        ),
        true,
        false,
      ),
      (
        'garis_lurus_ringkas',
        const GuidanceStraightLine(
          bearingDeg: 119.0,
          distToRouteM: 71800.0,
          progress: 0.25,
          targetPoint: _target,
          accuracyM: 8.0,
        ),
        true,
        false,
      ),
      (
        'garis_lurus_terbuka',
        const GuidanceStraightLine(
          bearingDeg: 119.0,
          distToRouteM: 71800.0,
          progress: 0.25,
          targetPoint: _target,
          accuracyM: 8.0,
        ),
        false,
        false,
      ),
      (
        'di_jalur',
        const GuidanceOnRoute(8.0),
        true,
        false,
      ),
      (
        'pil_diperkecil',
        const GuidanceStraightLine(
          bearingDeg: 119.0,
          distToRouteM: 71800.0,
          progress: 0.25,
          targetPoint: _target,
          accuracyM: 8.0,
        ),
        true,
        true,
      ),
    ];

    for (final item in cases) {
      testWidgets(
          'DirectionsPanel ${item.$1} identik antara mode terang dan gelap',
          (tester) async {
        tester.view.physicalSize = const Size(390, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await loadPlusJakartaSans(tester);

        // Render di mode terang
        final lightKey = GlobalKey();
        await tester.pumpWidget(
          _panelHost(
            theme: hiqeoLightTheme,
            state: item.$2,
            straightLineAcknowledged: item.$3,
            initialMinimized: item.$4,
            boundaryKey: lightKey,
          ),
        );
        await tester.pumpAndSettle();
        final lightBytes = await _capturePngBytes(tester, lightKey);

        await expectLater(
          find.byKey(lightKey),
          matchesGoldenFile('goldens/directions_panel_${item.$1}.png'),
        );

        // Render di mode gelap dan verifikasi identik piksel-demi-piksel
        final darkKey = GlobalKey();
        await tester.pumpWidget(
          _panelHost(
            theme: hiqeoDarkTheme,
            state: item.$2,
            straightLineAcknowledged: item.$3,
            initialMinimized: item.$4,
            boundaryKey: darkKey,
          ),
        );
        await tester.pumpAndSettle();
        final darkBytes = await _capturePngBytes(tester, darkKey);

        expect(
          darkBytes,
          equals(lightBytes),
          reason: 'DirectionsPanel ${item.$1} harus identik di mode terang & gelap',
        );
      });
    }
  });
}
