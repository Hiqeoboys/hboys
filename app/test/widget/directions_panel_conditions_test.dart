import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/features/map/presentation/widgets/directions_panel.dart';
import 'package:nama_app/features/trails/application/recovery_guidance_service.dart';
import 'package:nama_app/features/trails/domain/guidance_state.dart';
import 'package:nama_app/features/trails/domain/heading_provider.dart';
import 'package:nama_app/features/trails/domain/straight_line_guidance_texts.dart';
import 'package:nama_app/features/trails/domain/track_route.dart';

class _MockGuidanceService implements RecoveryGuidanceService {
  _MockGuidanceService(GuidanceState initialState) : _state = initialState;

  final StreamController<GuidanceState> _controller =
      StreamController<GuidanceState>.broadcast();
  GuidanceState _state;

  @override
  HeadingProvider? get headingProvider => null;

  @override
  GuidanceState get currentState => _state;

  @override
  Stream<GuidanceState> get states => _controller.stream;

  void emit(GuidanceState next) {
    _state = next;
    _controller.add(next);
  }

  @override
  TrackRoute? get activeRoute => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrapWithTheme({
  required Widget child,
  required ThemeData theme,
}) {
  return MaterialApp(
    theme: theme,
    home: Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: SizedBox(
          width: 366,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  const targetPoint = LatLng(-7.5050, 110.4000);
  final guidePath = <LatLng>[
    const LatLng(-7.5060, 110.4020),
    const LatLng(-7.5055, 110.4010),
    targetPoint,
  ];

  group('DirectionsPanel 5 Kondisi - Mode Terang & Gelap', () {
    testWidgets('1. GuidanceUnavailable (Terang & Gelap)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final theme in [hiqeoLightTheme, hiqeoDarkTheme]) {
        final service = _MockGuidanceService(
          const GuidanceUnavailable(GuidanceUnavailableReason.needsLocation),
        );

        await tester.pumpWidget(
          _wrapWithTheme(
            theme: theme,
            child: DirectionsPanel(
              guidanceService: service,
              straightLineAcknowledged: false,
              onClose: () {},
              onSos: () {},
              onAcknowledge: () {},
              onOpenWarningDialog: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Petunjuk belum tersedia'), findsOneWidget);
        expect(find.text('Mencari sinyal GPS'), findsOneWidget);
        expect(find.byIcon(Icons.location_off_rounded), findsOneWidget);
      }
    });

    testWidgets('2. GuidanceOnRoute (Terang & Gelap)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final theme in [hiqeoLightTheme, hiqeoDarkTheme]) {
        final service = _MockGuidanceService(
          const GuidanceOnRoute(14.0),
        );

        await tester.pumpWidget(
          _wrapWithTheme(
            theme: theme,
            child: DirectionsPanel(
              guidanceService: service,
              straightLineAcknowledged: false,
              onClose: () {},
              onSos: () {},
              onAcknowledge: () {},
              onOpenWarningDialog: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Di jalur utama'), findsOneWidget);
        expect(find.text('Kamu masih di jalur'), findsOneWidget);
        expect(find.textContaining('14 m dari garis jalur'), findsOneWidget);
      }
    });

    testWidgets('3. GuidanceFollowingTrail (Terang & Gelap)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final theme in [hiqeoLightTheme, hiqeoDarkTheme]) {
        // bearing 46 derajat, arah hadap HP 0 derajat -> Belok kanan 46°
        final service = _MockGuidanceService(
          GuidanceFollowingTrail(
            bearingDeg: 46.0,
            distToNextM: 38.0,
            remainingTrailM: 342.0,
            offRouteM: 110.0,
            progress: 0.28,
            targetPoint: targetPoint,
            guidePath: guidePath,
          ),
        );

        var closeCalled = false;
        await tester.pumpWidget(
          _wrapWithTheme(
            theme: theme,
            child: DirectionsPanel(
              key: ValueKey(theme.brightness),
              guidanceService: service,
              straightLineAcknowledged: false,
              phoneHeading: 0.0,
              onClose: () => closeCalled = true,
              onSos: () {},
              onAcknowledge: () {},
              onOpenWarningDialog: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Jejak rekamanmu'), findsOneWidget);
        expect(find.text('Belok kanan 46°'), findsOneWidget);
        expect(find.textContaining('38 m ke titik jejak berikutnya'), findsOneWidget);
        expect(find.textContaining('342 m menyusuri jejak ke jalur'), findsOneWidget);
        expect(find.text('Selesai memandu'), findsOneWidget);
        expect(find.byIcon(Icons.navigation), findsOneWidget);

        // Uji tombol ghost "Selesai memandu"
        await tester.tap(find.text('Selesai memandu'));
        await tester.pumpAndSettle();
        expect(closeCalled, isTrue);
      }
    });

    testWidgets('4. GuidanceStraightLine (Terang & Gelap)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final theme in [hiqeoLightTheme, hiqeoDarkTheme]) {
        // bearing 311 derajat (setara -49 derajat dari utara) -> Belok kiri 49°
        final service = _MockGuidanceService(
          const GuidanceStraightLine(
            bearingDeg: 311.0,
            distToRouteM: 106.0,
            progress: 0.35,
            targetPoint: targetPoint,
            accuracyM: 8.0,
          ),
        );

        var sosCalled = false;
        await tester.pumpWidget(
          _wrapWithTheme(
            theme: theme,
            child: DirectionsPanel(
              guidanceService: service,
              straightLineAcknowledged: true,
              phoneHeading: 0.0,
              onClose: () {},
              onSos: () => sosCalled = true,
              onAcknowledge: () {},
              onOpenWarningDialog: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(StraightLineGuidanceTexts.modeLabel), findsOneWidget);
        expect(find.text('Belok kiri 49°'), findsOneWidget);
        expect(find.textContaining('106 m ke titik jalur terdekat'), findsOneWidget);
        expect(find.byKey(const ValueKey('straight-line-warning-card')), findsOneWidget);

        // Card Petunjuk Arah selalu bergaya Mode Gelap meski app di Mode Terang.
        final labelElem = tester.element(find.text(StraightLineGuidanceTexts.modeLabel));
        expect(HiqeoColors.of(labelElem).brightness, Brightness.dark);
        expect(
          HiqeoColors.of(labelElem).glassFillMap,
          HiqeoColors.dark.glassFillMap,
        );

        // Kotak "Peringatan penting" default dalam kondisi diminimalkan ("Baca").
        expect(find.text('Peringatan penting'), findsOneWidget);
        expect(find.text('Baca'), findsOneWidget);
        expect(find.text(StraightLineGuidanceTexts.warningCardText), findsNothing);

        // Ketuk untuk memperluas isi Peringatan penting -> muncul "Tutup" & teks.
        await tester.tap(find.byKey(const ValueKey('straight-line-warning-toggle')));
        await tester.pumpAndSettle();
        expect(find.text('Tutup'), findsOneWidget);
        expect(find.text(StraightLineGuidanceTexts.warningCardText), findsOneWidget);

        // Ketuk lagi untuk meminimalkan kembali.
        await tester.tap(find.byKey(const ValueKey('straight-line-warning-toggle')));
        await tester.pumpAndSettle();
        expect(find.text('Baca'), findsOneWidget);
        expect(find.text(StraightLineGuidanceTexts.warningCardText), findsNothing);

        final sosButton = find.byKey(const ValueKey('straight-line-panel-sos-button'));
        expect(sosButton, findsOneWidget);
        await tester.tap(sosButton);
        expect(sosCalled, isTrue);
      }
    });

    testWidgets('5. GuidanceReturned (Terang & Gelap)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final theme in [hiqeoLightTheme, hiqeoDarkTheme]) {
        final service = _MockGuidanceService(
          const GuidanceReturned(),
        );

        var closeCalled = false;
        await tester.pumpWidget(
          _wrapWithTheme(
            theme: theme,
            child: DirectionsPanel(
              key: ValueKey(theme.brightness),
              guidanceService: service,
              straightLineAcknowledged: false,
              onClose: () => closeCalled = true,
              onSos: () {},
              onAcknowledge: () {},
              onOpenWarningDialog: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Di jalur utama'), findsOneWidget);
        expect(find.text('Kamu sudah kembali di jalur'), findsOneWidget);
        expect(find.text('Petunjuk jalur menutup otomatis'), findsOneWidget);
        expect(closeCalled, isTrue);
      }
    });

    testWidgets('6. Minimize dan Expand panel Petunjuk Arah', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = _MockGuidanceService(
        const GuidanceStraightLine(
          bearingDeg: 119.0,
          distToRouteM: 71800.0,
          progress: 0.25,
          targetPoint: targetPoint,
          accuracyM: 8.0,
        ),
      );

      bool? lastMinimized;
      await tester.pumpWidget(
        _wrapWithTheme(
          theme: hiqeoLightTheme,
          child: DirectionsPanel(
            guidanceService: service,
            straightLineAcknowledged: true,
            phoneHeading: 0.0,
            onClose: () {},
            onSos: () {},
            onAcknowledge: () {},
            onOpenWarningDialog: () {},
            onMinimizedChanged: (v) => lastMinimized = v,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('map-directions-minimize')));
      await tester.pumpAndSettle();

      expect(lastMinimized, isTrue);
      expect(find.byKey(const ValueKey('map-directions-minimized-bar')), findsOneWidget);
      expect(find.text('71,8 km · Belok kanan 119°'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('map-directions-expand')));
      await tester.pumpAndSettle();

      expect(lastMinimized, isFalse);
      expect(find.byKey(const ValueKey('map-directions-minimized-bar')), findsNothing);
      expect(find.text('Belok kanan 119°'), findsOneWidget);
    });
  });
}
