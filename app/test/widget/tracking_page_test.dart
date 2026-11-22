import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/tracking/application/tracking_controller.dart';
import 'package:nama_app/features/tracking/application/tracking_status.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';
import 'package:nama_app/features/tracking/presentation/tracking_page.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

final t0 = DateTime.utc(2027, 6, 1, 8);

TrackingStatus _status({
  TrackingSessionStatus sessionStatus = TrackingSessionStatus.active,
  int pointCount = 42,
  int movingSeconds = 9710,
  double distanceM = 6420,
  double? paceSecPerKm = 1450,
  double? verticalSpeedMph = 312,
  double elevationGainM = 842,
  int? batteryPercent = 62,
  bool isPaused = false,
  PowerProfile profile = PowerProfile.normal,
  DateTime? lastValidFixAtUtc,
}) =>
    TrackingStatus(
      sessionId: 'sesi-1',
      sessionStatus: sessionStatus,
      startedAtUtc: t0,
      distanceM: distanceM,
      movingSeconds: movingSeconds,
      elapsedSeconds: movingSeconds + 120,
      elevationGainM: elevationGainM,
      elevationLossM: 0,
      isMoving: !isPaused,
      pointCount: pointCount,
      profile: profile,
      paceSecPerKm: paceSecPerKm,
      verticalSpeedMph: verticalSpeedMph,
      batteryPercent: batteryPercent,
      isPaused: isPaused,
      lastValidFixAtUtc: lastValidFixAtUtc,
    );

Finder _plain(String text) => find.byWidgetPredicate(
      (widget) => widget is Text && widget.textSpan?.toPlainText() == text,
    );

Widget _app(TrackingView view) => MaterialApp(
      theme: hiqeoLightTheme,
      home: Scaffold(body: view),
    );

void _setPhoneSize(WidgetTester tester, [Size size = const Size(360, 640)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
      'tata letak Bento Opsi B muat di layar 640 dp tanpa overflow dan menampilkan kartu metrik',
      (tester) async {
    _setPhoneSize(tester, const Size(360, 640));
    var opened = 0;
    await tester.pumpWidget(_app(TrackingView(
      phase: TrackingPhase.idle,
      profile: PowerProfile.normal,
      permissionSummary: 'Belum aktif: izin "Selalu".',
      onOpenPermissions: () => opened++,
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Tersimpan di HP'), findsNothing);
    expect(find.textContaining('Baterai '), findsNothing);
    expect(find.text('Waktu bergerak'), findsOneWidget);
    expect(find.text('00:00:00'), findsOneWidget);
    expect(find.text('Izin belum lengkap'), findsOneWidget);
    expect(find.text('Belum aktif: izin "Selalu".'), findsOneWidget);
    expect(find.text('Belum ada data ketinggian'), findsOneWidget);
    expect(find.text('Sensor langkah tidak tersedia'), findsOneWidget);
    for (final label in <String>[
      'Jarak',
      'Pace',
      'Tanjakan',
      'Kec. vertikal',
      'Langkah',
      'Kalori',
    ]) {
      expect(find.text(label), findsOneWidget, reason: 'kartu $label hilang');
    }
    expect(_plain('—'), findsNWidgets(6));

    await tester.tap(find.text('Lengkapi izin'));
    expect(opened, 1);
  });

  testWidgets('sesi aktif menampilkan metrik nyata dan pasangan Jeda/Selesai',
      (tester) async {
    _setPhoneSize(tester, const Size(360, 640));
    var paused = 0;
    var finished = 0;
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(TrackingView(
      phase: TrackingPhase.recording,
      status: _status(),
      permissionReady: true,
      profile: PowerProfile.normal,
      elevation: <double>[1000, 1004, 1002, 1009, 1018],
      onPause: () => paused++,
      onFinish: () => finished++,
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('02:41:50'), findsOneWidget);
    expect(_plain('6,4 km'), findsOneWidget);
    expect(_plain('24:10 /km'), findsOneWidget);
    expect(_plain('842 m'), findsOneWidget);
    expect(_plain('312 m/jam'), findsOneWidget);
    expect(_plain('—'), findsNWidgets(2));
    expect(find.text('Jeda'), findsOneWidget);
    expect(find.text('Selesai'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Jarak: 6,4 kilometer')),
      isNotNull,
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Waktu bergerak 02:41:50')),
      isNotNull,
    );
    expect(
      tester.getSemantics(
        find.bySemanticsLabel('Profil ketinggian dari 5 sampel'),
      ),
      isNotNull,
    );

    await tester.tap(find.bySemanticsLabel('Jeda rekaman'));
    expect(paused, 1);
    await tester.tap(find.bySemanticsLabel('Selesai dan akhiri sesi'));
    expect(finished, 1);
    handle.dispose();
  });

  testWidgets(
      'menampilkan Mencari sinyal GPS sebelum fix valid dan peringatan hemat baterai hanya saat OS power save aktif',
      (tester) async {
    _setPhoneSize(tester, const Size(360, 640));
    await tester.pumpWidget(_app(TrackingView(
      phase: TrackingPhase.recording,
      status: _status(pointCount: 0, lastValidFixAtUtc: null),
      permissionReady: true,
      profile: PowerProfile.saver,
      isPowerSaveMode: true,
      onPause: () {},
      onFinish: () {},
    )));
    await tester.pumpAndSettle();

    expect(find.text('Mencari sinyal GPS'), findsOneWidget);
    expect(
      find.text('Mode hemat baterai aktif, akurasi GPS bisa menurun'),
      findsOneWidget,
    );
  });

  testWidgets('overlay diagnosa GPS dapat dibuka dan ditutup di kDebugMode',
      (tester) async {
    _setPhoneSize(tester, const Size(360, 640));
    await tester.pumpWidget(_app(TrackingView(
      phase: TrackingPhase.recording,
      status: _status(),
      permissionReady: true,
      profile: PowerProfile.normal,
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('track-debug-toggle')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('track-debug-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Diagnosa pipeline lokasi (kDebugMode)'), findsOneWidget);
  });

  testWidgets('sesi dijeda menampilkan Lanjut dan berhenti menghitung waktu',
      (tester) async {
    _setPhoneSize(tester, const Size(360, 640));
    var resumed = 0;
    await tester.pumpWidget(_app(TrackingView(
      phase: TrackingPhase.paused,
      status: _status(isPaused: true),
      permissionReady: true,
      profile: PowerProfile.normal,
      onResume: () => resumed++,
      onFinish: () {},
    )));
    await tester.pumpAndSettle();

    expect(find.text('· Dijeda'), findsOneWidget);
    expect(find.text('Lanjut'), findsOneWidget);
    expect(
      find.text('Waktu bergerak berhenti selama rekaman dijeda'),
      findsOneWidget,
    );
    await tester.tap(find.text('Lanjut'));
    expect(resumed, 1);
  });

  testWidgets('tanpa sesi dengan izin siap menawarkan mulai tracking',
      (tester) async {
    _setPhoneSize(tester, const Size(360, 640));
    var started = 0;
    await tester.pumpWidget(_app(TrackingView(
      phase: TrackingPhase.idle,
      profile: PowerProfile.normal,
      permissionReady: true,
      onStart: () => started++,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Izin belum lengkap'), findsNothing);
    expect(find.text('Mulai tracking'), findsOneWidget);
    expect(find.text('Tersimpan di HP'), findsNothing);
    await tester.tap(find.text('Mulai tracking'));
    expect(started, 1);
  });

  testWidgets('sesi selesai mempertahankan metrik dan menawarkan mulai baru',
      (tester) async {
    _setPhoneSize(tester, const Size(360, 640));
    await tester.pumpWidget(_app(TrackingView(
      phase: TrackingPhase.finished,
      status: _status(
        sessionStatus: TrackingSessionStatus.completed,
        movingSeconds: 3600,
        distanceM: 3210,
      ),
      permissionReady: true,
      profile: PowerProfile.saver,
      isPowerSaveMode: true,
    )));
    await tester.pumpAndSettle();

    expect(find.text('01:00:00'), findsOneWidget);
    expect(_plain('3,2 km'), findsOneWidget);
    expect(find.text('Mulai tracking baru'), findsOneWidget);
    expect(
      find.text('Mode hemat baterai aktif, akurasi GPS bisa menurun'),
      findsOneWidget,
    );
  });

  testWidgets('galat rekaman tampil jujur tanpa tombol mulai', (tester) async {
    _setPhoneSize(tester, const Size(360, 640));
    await tester.pumpWidget(_app(const TrackingView(
      phase: TrackingPhase.error,
      profile: PowerProfile.normal,
      error: 'Gagal menyiapkan rekaman: layanan tidak tersedia.',
    )));
    await tester.pumpAndSettle();

    expect(find.text('Rekaman tidak tersedia'), findsOneWidget);
    expect(
      find.text('Gagal menyiapkan rekaman: layanan tidak tersedia.'),
      findsOneWidget,
    );
    expect(find.text('Mulai tracking'), findsNothing);
  });

  testWidgets('layar mengikuti rancangan saat layanan platform tidak ada',
      (tester) async {
    _setPhoneSize(tester, const Size(360, 640));
    await tester.pumpWidget(MaterialApp(
      theme: hiqeoLightTheme,
      home: const TrackingPage(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Rekaman tidak tersedia'), findsOneWidget);
    expect(
      find.textContaining('Pelacakan GPS hanya untuk Android/iOS'),
      findsOneWidget,
    );
    expect(find.text('Lengkapi izin'), findsNothing);
  });
}
