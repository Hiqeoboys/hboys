import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/design/widgets/line_icons.dart';
import 'package:nama_app/features/map/application/map_track_source.dart';
import 'package:nama_app/features/map/domain/map_package.dart';
import 'package:nama_app/features/map/presentation/map_page.dart';
import 'package:nama_app/features/tracking/application/tracking_runtime.dart'
    show TrackingAccess;
import 'package:nama_app/features/tracking/application/tracking_controller.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/trails/domain/track_route.dart';
import 'package:nama_app/infrastructure/location/shared_location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/location_fakes.dart';

class _EmptyTrackSource implements MapTrackSource {
  @override
  Future<MapTrackSnapshot> load() async =>
      const MapTrackSnapshot(points: <TrackPoint>[], latestPoint: null);
}

final DateTime _now = DateTime.utc(2026, 11, 9, 8);

TrackRoute _route() => TrackRoute.fromPoints(
      id: 'uji',
      name: 'Jalur uji',
      points: const <TrackRoutePoint>[
        TrackRoutePoint(lat: -7.5, lon: 110.4, ele: 100),
        TrackRoutePoint(lat: -7.49, lon: 110.41, ele: 140),
      ],
    );

TrackPoint _fix() => TrackPoint(
      lat: -7.5,
      lon: 110.4,
      timestampUtc: _now,
      accuracyM: 5,
    );

const ValueKey<String> _directionsKey = ValueKey<String>('map-directions-button');
const ValueKey<String> _recenterKey = ValueKey<String>('map-recenter-button');
const ValueKey<String> _compassKey = ValueKey<String>('map-compass-button');
const ValueKey<String> _panelKey = ValueKey<String>('map-directions-panel');
const ValueKey<String> _reasonKey = ValueKey<String>('map-directions-reason');

void _setPhone(WidgetTester tester, {FakeViewPadding? padding}) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  if (padding != null) {
    tester.view.padding = padding;
    tester.view.viewPadding = padding;
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
  }
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _Harness {
  _Harness({
    TrackingAccess access = TrackingAccess.whileInUse,
  })  : backend = FakeForegroundBackend(access: access),
        feed = FakeRecordingFeed() {
    service = SharedLocationService(
      backend: backend,
      recordingFeed: feed,
      clock: FakeClock(_now),
    );
  }

  final FakeForegroundBackend backend;
  final FakeRecordingFeed feed;
  late final SharedLocationService service;
}

Widget _app(
  _Harness harness, {
  bool withRoute = true,
  bool tabVisible = true,
}) =>
    TickerMode(
      enabled: tabVisible,
      child: MaterialApp(
        theme: hiqeoLightTheme,
        home: MapPage(
          catalogLoader: () async =>
              MapPackageCatalog(const <MountainMapPackage>[]),
          gpxRouteLoader: () async => withRoute ? _route() : null,
          trackSource: _EmptyTrackSource(),
          locationService: harness.service,
        ),
      ),
    );

Future<void> _settleFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
}

Future<_Harness> _pumpMap(
  WidgetTester tester, {
  TrackingAccess access = TrackingAccess.whileInUse,
  bool withFix = false,
  bool withRoute = true,
  bool trackingActive = false,
}) async {
  final harness = _Harness(access: access);
  addTearDown(harness.service.dispose);
  if (trackingActive) {
    TrackingController.instance.setRecordingForTesting(recording: true);
  }
  await tester.pumpWidget(_app(harness, withRoute: withRoute));
  await _settleFrame(tester);
  if (withFix) {
    harness.backend.emit(_fix());
    await _settleFrame(tester);
  }
  return harness;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TrackingController.instance.startOverride = null;
    TrackingController.instance.setRecordingForTesting(recording: false);
  });

  tearDown(() {
    TrackingController.instance.startOverride = null;
    TrackingController.instance.setRecordingForTesting(recording: false);
  });

  group('tata letak tombol kanan atas', () {
    testWidgets(
        'tombol petunjuk arah tersembunyi sebelum tracking, tampil setelah tracking, '
        'dan ikon lokasi tidak tertukar', (tester) async {
      _setPhone(tester);
      await _pumpMap(tester, trackingActive: false);

      expect(find.byKey(_compassKey), findsOneWidget);
      expect(find.byKey(_recenterKey), findsOneWidget);
      expect(find.byKey(_directionsKey), findsNothing);

      final recenterIcon = tester.widget<HiqeoIcon>(
        find.descendant(
          of: find.byKey(_recenterKey),
          matching: find.byType(HiqeoIcon),
        ),
      );
      expect(recenterIcon.data, same(HiqeoIcons.crosshair));

      TrackingController.instance.setRecordingForTesting(recording: true);
      await _settleFrame(tester);

      expect(find.byKey(_directionsKey), findsOneWidget);
      final directionsIcon = tester.widget<HiqeoIcon>(
        find.descendant(
          of: find.byKey(_directionsKey),
          matching: find.byType(HiqeoIcon),
        ),
      );
      expect(directionsIcon.data, same(HiqeoIcons.locate));
    });

    testWidgets(
        'petunjuk jalur sejajar kompas dan lokasi, kolom 44 dp, kanan 16, atas 104, jarak 8',
        (tester) async {
      _setPhone(tester);
      await _pumpMap(tester, trackingActive: true);

      final compass = tester.getRect(find.byKey(_compassKey));
      final recenter = tester.getRect(find.byKey(_recenterKey));
      final directions = tester.getRect(find.byKey(_directionsKey));

      expect(compass.top, mapControlTopOffset);
      expect(mapControlTopOffset, 104);
      expect(recenter.left, compass.left);
      expect(recenter.top - compass.bottom, mapControlGap);
      expect(directions.left, compass.left);
      expect(directions.right, compass.right);
      expect(directions.top - recenter.bottom, mapControlGap);
      expect(mapControlGap, 8);
      expect(directions.right, 390 - mapControlRightMargin);
      expect(mapControlRightMargin, 16);
      expect(directions.width, mapControlSize);
      expect(directions.height, mapControlSize);
      expect(mapControlSize, 44);
      expect(directions.left, greaterThanOrEqualTo(0));
      expect(directions.bottom, lessThanOrEqualTo(844));
    });

    testWidgets('margin kanan 16 dp ditambah inset aman', (tester) async {
      _setPhone(
        tester,
        padding: const FakeViewPadding(top: 24, right: 20, bottom: 24),
      );
      await _pumpMap(tester, trackingActive: true);

      final directions = tester.getRect(find.byKey(_directionsKey));
      expect(directions.right, 390 - 20 - mapControlRightMargin);
      final compass = tester.getRect(find.byKey(_compassKey));
      expect(directions.right, compass.right);
    });

    testWidgets('tombol tidak tertutup widget lain dan bisa disentuh',
        (tester) async {
      _setPhone(tester);
      await _pumpMap(tester, trackingActive: true);

      expect(find.byKey(_directionsKey).hitTestable(), findsOneWidget);
      expect(find.byKey(_compassKey).hitTestable(), findsOneWidget);

      // Seluruh sisi 48x48 menerima sentuhan, bukan hanya ikon di tengah.
      final rect = tester.getRect(find.byKey(_directionsKey));
      for (final point in <Offset>[
        rect.topLeft + const Offset(2, 2),
        rect.topRight + const Offset(-2, 2),
        rect.bottomLeft + const Offset(2, -2),
        rect.bottomRight + const Offset(-2, -2),
        rect.center,
      ]) {
        final result = HitTestResult();
        tester.binding.hitTestInView(result, point, tester.view.viewId);
        final hitsButton = result.path.any((entry) {
          final target = entry.target;
          return target is RenderObject &&
              find
                  .byKey(_directionsKey)
                  .evaluate()
                  .any((element) => element.renderObject == target ||
                      _isDescendant(target, element.renderObject));
        });
        expect(hitsButton, isTrue, reason: 'sentuhan di $point meleset');
      }
    });
  });

  group('ketika syarat terpenuhi', () {
    testWidgets('bisa ditekan, membuka panel Petunjuk jalur, dan jadi aktif',
        (tester) async {
      _setPhone(tester);
      await _pumpMap(tester, withFix: true, trackingActive: true);

      final colors = HiqeoColors.of(tester.element(find.byType(MapPage)));
      expect(find.byKey(_panelKey), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(_directionsKey),
          matching: find.byKey(const ValueKey('map-circle-button-active')),
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(_directionsKey));
      await _settleFrame(tester);

      expect(find.byKey(_panelKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_panelKey),
          matching: find.text('Petunjuk jalur'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(_reasonKey), findsNothing);

      final active = tester.widget<DecoratedBox>(find.descendant(
        of: find.byKey(_directionsKey),
        matching: find.byKey(const ValueKey('map-circle-button-active')),
      ));
      expect((active.decoration as BoxDecoration).color, colors.primary);
      final icon = tester.widget<HiqeoIcon>(find.descendant(
        of: find.byKey(_directionsKey),
        matching: find.byType(HiqeoIcon),
      ));
      expect(icon.color, colors.onPrimary);

      // Ketuk lagi menutup panel dan mengembalikan tombol ke kaca biasa.
      await tester.tap(find.byKey(_directionsKey));
      await _settleFrame(tester);
      expect(find.byKey(_panelKey), findsNothing);
      expect(
        find.byKey(const ValueKey('map-circle-button-active')),
        findsNothing,
      );
    });

    testWidgets('tombol Tutup di panel menutup panel', (tester) async {
      _setPhone(tester);
      await _pumpMap(tester, withFix: true, trackingActive: true);
      await tester.tap(find.byKey(_directionsKey));
      await _settleFrame(tester);
      expect(find.byKey(_panelKey), findsOneWidget);
      expect(find.text('Di jalur utama'), findsOneWidget);
      expect(find.text('Kamu masih di jalur'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('map-directions-close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.byKey(_panelKey), findsNothing);
    });

    testWidgets('selama merekam memakai titik rekaman tanpa aliran kedua',
        (tester) async {
      _setPhone(tester);
      TrackingController.instance.setRecordingForTesting(recording: true);
      final harness = _Harness();
      addTearDown(harness.service.dispose);
      harness.feed
        ..recording = true
        ..latest = _fix();
      await tester.pumpWidget(_app(harness));
      await _settleFrame(tester);

      expect(harness.backend.streamsOpened, 0);
      await tester.tap(find.byKey(_directionsKey));
      await _settleFrame(tester);
      expect(find.byKey(_panelKey), findsOneWidget);
    });
  });

  group('ketika syarat belum terpenuhi tombol tetap bisa ditekan', () {
    testWidgets('lokasi mati: alasan dan tombol Buka pengaturan lokasi',
        (tester) async {
      _setPhone(tester);
      final harness = await _pumpMap(
        tester,
        access: TrackingAccess.serviceDisabled,
        trackingActive: true,
      );

      await tester.tap(find.byKey(_directionsKey));
      await _settleFrame(tester);

      expect(find.byKey(_reasonKey), findsOneWidget);
      expect(find.text('Lokasi mati'), findsOneWidget);
      expect(find.byKey(_panelKey), findsNothing);

      await tester.tap(find.text('Buka pengaturan lokasi'));
      await _settleFrame(tester);
      expect(harness.backend.openLocationCalls, 1);
      expect(find.byKey(_reasonKey), findsNothing);
    });

    testWidgets('izin ditolak: alasan dan tombol Beri izin', (tester) async {
      _setPhone(tester);
      final harness = await _pumpMap(
        tester,
        access: TrackingAccess.denied,
        trackingActive: true,
      );

      await tester.tap(find.byKey(_directionsKey));
      await _settleFrame(tester);

      expect(find.text('Izin lokasi belum diberikan'), findsOneWidget);
      await tester.tap(find.text('Beri izin'));
      await _settleFrame(tester);
      expect(harness.backend.requestCalls, 1);
      expect(find.byKey(_reasonKey), findsNothing);
    });

    testWidgets('izin ditolak permanen: Beri izin membuka pengaturan aplikasi',
        (tester) async {
      _setPhone(tester);
      final harness = await _pumpMap(
        tester,
        access: TrackingAccess.deniedForever,
        trackingActive: true,
      );

      await tester.tap(find.byKey(_directionsKey));
      await _settleFrame(tester);

      expect(find.text('Izin lokasi ditolak'), findsOneWidget);
      await tester.tap(find.text('Beri izin'));
      await _settleFrame(tester);
      expect(harness.backend.openAppCalls, 1);
      expect(harness.backend.requestCalls, 0);
    });

    testWidgets('menunggu sinyal GPS: membuka card Petunjuk Arah mode gelap dengan kondisi Mencari sinyal GPS',
        (tester) async {
      _setPhone(tester);
      await _pumpMap(tester, trackingActive: true); // izin ada, belum ada fix

      await tester.tap(find.byKey(_directionsKey));
      await _settleFrame(tester);

      // Setelah timeout memeriksa posisi 3 dtk -> card menampilkan "Mencari sinyal GPS" dalam Mode Gelap
      await tester.pump(const Duration(seconds: 3));
      await _settleFrame(tester);

      expect(find.byKey(_panelKey), findsOneWidget);
      expect(find.text('Mencari sinyal GPS'), findsOneWidget);
      expect(
        find.text('Tunggu sebentar atau pindah ke tempat terbuka.'),
        findsOneWidget,
      );
      expect(
        HiqeoColors.of(tester.element(find.text('Mencari sinyal GPS'))).brightness,
        Brightness.dark,
      );

      await tester.tap(find.byKey(const ValueKey('map-directions-close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.byKey(_panelKey), findsNothing);
    });

    testWidgets('belum ada jalur: Pilih jalur dulu lalu buka peta offline',
        (tester) async {
      _setPhone(tester);
      await _pumpMap(
        tester,
        withFix: true,
        withRoute: false,
        trackingActive: true,
      );

      await tester.tap(find.byKey(_directionsKey));
      await _settleFrame(tester);

      expect(find.text('Pilih jalur dulu'), findsOneWidget);
      await tester.tap(find.text('Pilih jalur'));
      await _settleFrame(tester);
      expect(find.text('Belum ada paket gunung'), findsOneWidget);
    });

    testWidgets('setelah GPS tiba, card Petunjuk Arah beralih otomatis ke panduan aktif',
        (tester) async {
      _setPhone(tester);
      final harness = await _pumpMap(tester, trackingActive: true);

      await tester.tap(find.byKey(_directionsKey));
      await _settleFrame(tester);
      expect(find.byKey(_panelKey), findsOneWidget);

      harness.backend.emit(_fix());
      await _settleFrame(tester);
      expect(find.text('Kamu masih di jalur'), findsOneWidget);
    });
  });

  group('langganan lokasi mengikuti keterlihatan Peta', () {
    testWidgets('lease dilepas saat tab tidak terlihat dan diambil lagi',
        (tester) async {
      _setPhone(tester);
      final harness = await _pumpMap(tester);
      expect(harness.service.leaseCount, 1);
      expect(harness.backend.activeStreams, 1);

      await tester.pumpWidget(_app(harness, tabVisible: false));
      await tester.pumpAndSettle();
      expect(harness.service.leaseCount, 0);
      expect(harness.backend.activeStreams, 0);

      await tester.pumpWidget(_app(harness, tabVisible: true));
      await tester.pumpAndSettle();
      expect(harness.service.leaseCount, 1);
      expect(harness.backend.activeStreams, 1);
    });

    testWidgets('lease dilepas saat halaman dibuang', (tester) async {
      _setPhone(tester);
      final harness = await _pumpMap(tester);
      expect(harness.service.leaseCount, 1);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(harness.service.leaseCount, 0);
      expect(harness.backend.activeStreams, 0);
    });

    testWidgets('lease dilepas saat aplikasi ke latar dan diambil saat kembali',
        (tester) async {
      _setPhone(tester);
      final harness = await _pumpMap(tester);
      expect(harness.service.leaseCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(harness.service.leaseCount, 1, reason: 'dialog izin = inactive');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(harness.service.leaseCount, 0);
      expect(harness.backend.activeStreams, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(harness.service.leaseCount, 1);
      expect(harness.backend.activeStreams, 1);
    });
  });
}

bool _isDescendant(RenderObject target, RenderObject? ancestor) {
  if (ancestor == null) return false;
  RenderObject? current = target;
  while (current != null) {
    if (identical(current, ancestor)) return true;
    current = current.parent;
  }
  return false;
}
