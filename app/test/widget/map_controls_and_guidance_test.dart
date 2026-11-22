import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_utils/geo_utils.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/app/router.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/design/widgets/hiqeo_nav_bar.dart';
import 'package:nama_app/design/widgets/line_icons.dart';
import 'package:nama_app/design/widgets/nav_bar_visibility.dart';
import 'package:nama_app/features/map/application/map_track_source.dart';
import 'package:nama_app/features/map/domain/map_package.dart';
import 'package:nama_app/features/map/presentation/map_page.dart';
import 'package:nama_app/features/map/presentation/widgets/directions_panel.dart';
import 'package:nama_app/features/tracking/application/tracking_controller.dart';
import 'package:nama_app/features/tracking/application/tracking_runtime.dart'
    show TrackingAccess;
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/trails/application/recovery_guidance_service.dart';
import 'package:nama_app/features/trails/domain/guidance_state.dart';
import 'package:nama_app/features/trails/domain/heading_provider.dart';
import 'package:nama_app/features/trails/domain/straight_line_guidance_texts.dart';
import 'package:nama_app/features/trails/domain/track_route.dart';
import 'package:nama_app/infrastructure/location/shared_location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/hiqeo_app_harness.dart';
import '../support/location_fakes.dart';

class _EmptyTrackSource implements MapTrackSource {
  @override
  Future<MapTrackSnapshot> load() async =>
      const MapTrackSnapshot(points: <TrackPoint>[], latestPoint: null);
}

class _FakeGuidanceService implements RecoveryGuidanceService {
  _FakeGuidanceService(this._state);

  final StreamController<GuidanceState> _ctrl =
      StreamController<GuidanceState>.broadcast();
  GuidanceState _state;

  @override
  HeadingProvider? get headingProvider => null;

  @override
  GuidanceState get currentState => _state;

  @override
  Stream<GuidanceState> get states => _ctrl.stream;

  void emit(GuidanceState next) {
    _state = next;
    _ctrl.add(next);
  }

  @override
  TrackRoute? get activeRoute => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final DateTime _now = DateTime.utc(2026, 11, 9, 8);

TrackRoute _route() => TrackRoute.fromPoints(
      id: 'uji',
      name: 'Jalur uji',
      points: const <TrackRoutePoint>[
        TrackRoutePoint(lat: -7.5000, lon: 110.4000, ele: 100),
        TrackRoutePoint(lat: -7.4900, lon: 110.4100, ele: 140),
      ],
    );

void _setPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    NavBarVisibilityController.instance.reset();
    TrackingController.instance.startOverride = null;
    TrackingController.instance.setRecordingForTesting(recording: false);
  });

  tearDown(() {
    NavBarVisibilityController.instance.reset();
    TrackingController.instance.startOverride = null;
    TrackingController.instance.setRecordingForTesting(recording: false);
  });

  testWidgets(
      'setiap tombol kanan atas (diidentifikasi Key) memiliki ikon dan memanggil aksi yang benar',
      (tester) async {
    _setPhone(tester);
    final backend = FakeForegroundBackend(access: TrackingAccess.whileInUse);
    final feed = FakeRecordingFeed();
    final location = SharedLocationService(
      backend: backend,
      recordingFeed: feed,
      clock: FakeClock(_now),
    );
    addTearDown(location.dispose);

    var compassCalls = 0;
    var recenterCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: MapPage(
          catalogLoader: () async =>
              MapPackageCatalog(const <MountainMapPackage>[]),
          gpxRouteLoader: () async => _route(),
          trackSource: _EmptyTrackSource(),
          locationService: location,
          onCompassReset: () => compassCalls++,
          onRecenterPressed: () => recenterCalls++,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    backend.emit(
      TrackPoint(lat: -7.5, lon: 110.4, timestampUtc: _now, accuracyM: 5),
    );
    await tester.pump(const Duration(milliseconds: 200));

    const compassKey = ValueKey<String>('map-compass-button');
    const recenterKey = ValueKey<String>('map-recenter-button');
    const directionsKey = ValueKey<String>('map-directions-button');

    // Sebelum tracking: Kompas & Lokasiku tampil; Petunjuk jalur TIDAK tampil
    expect(find.byKey(compassKey), findsOneWidget);
    expect(find.byKey(recenterKey), findsOneWidget);
    expect(find.byKey(directionsKey), findsNothing);

    // Cek ikon (a) Kompas = compass, (b) Lokasiku = crosshair
    final compassIcon = tester.widget<HiqeoIcon>(
      find.descendant(of: find.byKey(compassKey), matching: find.byType(HiqeoIcon)),
    );
    expect(compassIcon.data, same(HiqeoIcons.compass));

    final recenterIcon = tester.widget<HiqeoIcon>(
      find.descendant(of: find.byKey(recenterKey), matching: find.byType(HiqeoIcon)),
    );
    expect(recenterIcon.data, same(HiqeoIcons.crosshair));

    // Ketuk Kompas -> hanya panggil reset arah ke utara
    await tester.tap(find.byKey(compassKey));
    await tester.pump();
    expect(compassCalls, 1);
    expect(recenterCalls, 0);

    // Ketuk Lokasiku -> hanya panggil pusatkan kamera ke posisi pengguna
    await tester.tap(find.byKey(recenterKey));
    await tester.pump();
    expect(compassCalls, 1);
    expect(recenterCalls, 1);

    // Mulai tracking -> tombol (c) Petunjuk jalur muncul paling bawah dengan ikon panah navigasi
    TrackingController.instance.setRecordingForTesting(recording: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(directionsKey), findsOneWidget);
    final directionsIcon = tester.widget<HiqeoIcon>(
      find.descendant(of: find.byKey(directionsKey), matching: find.byType(HiqeoIcon)),
    );
    expect(directionsIcon.data, same(HiqeoIcons.locate));

    // Posisi Kompas dan Lokasiku tetap, tombol (c) berada di bawah Lokasiku
    expect(
      tester.getRect(find.byKey(directionsKey)).top,
      greaterThan(tester.getRect(find.byKey(recenterKey)).bottom),
    );

    // Ketuk Petunjuk jalur -> membuka panel petunjuk (tidak memanggil kompas/lokasiku)
    await tester.tap(find.byKey(directionsKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey<String>('map-directions-panel')), findsOneWidget);
    expect(compassCalls, 1);
    expect(recenterCalls, 1);

    // Tracking selesai -> tombol (c) hilang DAN panel petunjuk ikut tertutup
    TrackingController.instance.setRecordingForTesting(recording: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(directionsKey), findsNothing);
    expect(find.byKey(const ValueKey<String>('map-directions-panel')), findsNothing);
  });

  testWidgets('navbar disembunyikan saat tracking di rute peta dan tampil lagi saat selesai',
      (tester) async {
    _setPhone(tester);
    final GoRouter router = buildHiqeoRouter();
    await tester.pumpWidget(buildHiqeoTestApp(router: router));
    router.go('/peta/jalur');
    await tester.pumpAndSettle();

    // Sebelum tracking: navbar tampil
    expect(find.byType(HiqeoNavBar), findsOneWidget);

    // Tracking aktif: navbar turun 90 dp + fade 300 ms dan keluar dari hit-test
    TrackingController.instance.setRecordingForTesting(recording: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(HiqeoNavBar), findsNothing);

    // Tracking selesai: navbar muncul kembali
    TrackingController.instance.setRecordingForTesting(recording: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(HiqeoNavBar), findsOneWidget);
  });

  testWidgets(
      'DirectionsPanel selalu gelap, tanpa kata "aman", peringatan auto-buka pertama kali, dan pil 56 dp memulihkan panel',
      (tester) async {
    _setPhone(tester);
    var ackCount = 0;
    final service = _FakeGuidanceService(
      const GuidanceStraightLine(
        bearingDeg: 119.0,
        distToRouteM: 71800.0,
        progress: 0.25,
        targetPoint: LatLng(-7.505, 110.4),
        accuracyM: 45.0,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: hiqeoLightTheme,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DirectionsPanel(
                guidanceService: service,
                straightLineAcknowledged: false,
                phoneHeading: 0.0,
                onClose: () {},
                onSos: () {},
                onAcknowledge: () => ackCount++,
                onOpenWarningDialog: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Selalu gelap walau tema app terang
    final modeElem = tester.element(find.text(StraightLineGuidanceTexts.modeLabel));
    expect(HiqeoColors.of(modeElem).brightness, Brightness.dark);

    // Tidak boleh ada kata "aman" pada teks peringatan garis lurus
    expect(
      StraightLineGuidanceTexts.warningCardText.toLowerCase().contains('aman'),
      isFalse,
    );

    // Pertama kali masuk garis lurus -> peringatan terbuka otomatis dengan tombol Mengerti
    expect(find.text(StraightLineGuidanceTexts.warningCardText), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('straight-line-warning-ack')), findsOneWidget);
    expect(find.text(StraightLineGuidanceTexts.farFromRouteWarning), findsOneWidget);
    expect(find.text(StraightLineGuidanceTexts.lowAccuracyWarning), findsOneWidget);

    // Ketuk Mengerti -> menutup peringatan dan memanggil onAcknowledge
    await tester.tap(find.byKey(const ValueKey<String>('straight-line-warning-ack')));
    await tester.pumpAndSettle();
    expect(ackCount, 1);
    expect(find.text('Baca'), findsOneWidget);

    // Perkecil ke pil tinggi 56 dp
    await tester.tap(find.byKey(const ValueKey<String>('map-directions-minimize')));
    await tester.pumpAndSettle();
    final pillFinder = find.byKey(const ValueKey<String>('map-directions-minimized-bar'));
    expect(pillFinder, findsOneWidget);
    expect(tester.getSize(pillFinder).height, 56.0);
    expect(find.byKey(const ValueKey<String>('directions-pill-warning-dot')), findsOneWidget);
    expect(find.text('71,8 km · Belok kanan 119°'), findsOneWidget);

    // Ketuk area badan pil memulihkan panel
    await tester.tap(find.text('71,8 km · Belok kanan 119°'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('directions-expanded-card')), findsOneWidget);
  });
}
