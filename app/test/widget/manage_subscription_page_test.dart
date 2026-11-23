import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/gooey/gooey_switch.dart';
import 'package:nama_app/features/plus/application/plus_controller.dart';
import 'package:nama_app/features/plus/presentation/manage_subscription_page.dart';
import 'package:nama_app/features/tracking/domain/track_point.dart';
import 'package:nama_app/features/tracking/domain/tracking_session.dart';

import '../support/plus_fixtures.dart';
import '../support/plus_widget_harness.dart';

const String _ownership =
    'Jika berhenti berlangganan, riwayat, data, dan peta unduhan tetap bisa '
    'diakses dan diekspor. Hanya fitur Plus yang berhenti.';

Future<PlusController> _activeController() => buildPlusController(
      token: 'aktif',
      payload: plusPayload(),
    );

Future<PlusController> _graceController() => buildPlusController(
      token: 'tenggang',
      payload: plusPayload(expiresAtUtc: DateTime.utc(2026, 10, 25)),
    );

Future<PlusController> _expiredController() => buildPlusController(
      token: 'lewat',
      payload: plusPayload(expiresAtUtc: DateTime.utc(2026, 10, 1)),
    );

Future<void> _pump(
  WidgetTester tester, {
  required PlusController controller,
  FakeCloudBackupRepository? backup,
  FakeTrackingRepository? repository,
  RecordingGpxExporter? exporter,
}) async {
  await pumpPlusPage(
    tester,
    ManageSubscriptionPage(
      backupRepository: backup ?? FakeCloudBackupRepository(cloudBackupState()),
      repository: repository,
      exporter: exporter ?? RecordingGpxExporter(),
    ),
    controller: controller,
  );
}

void main() {
  testWidgets('pengguna gratis melihat status dan ekspor GPX tetap terbuka',
      (tester) async {
    final controller = await buildPlusController();
    await _pump(tester, controller: controller);

    expect(find.text('Plus belum aktif'), findsOneWidget);
    expect(find.text('Fitur inti tetap gratis'), findsOneWidget);
    expect(find.text('Gratis'), findsOneWidget);
    expect(
      find.text(
        'Plus menambah cuaca rute, estimasi, analitik, dan rekap tahunan. '
        'Fitur inti serta peta offline tetap gratis.',
      ),
      findsOneWidget,
    );
    expect(find.text('Ekspor data (GPX) · gratis'), findsOneWidget);
    expect(find.text('Aktifkan Plus'), findsOneWidget);
    expect(find.text('Kelola langganan di app store'), findsNothing);
    expect(find.text('Cadangan cloud'), findsNothing);
    expect(find.text('Cadangkan otomatis'), findsNothing);
    expect(find.text('Kode pemulihan'), findsNothing);
    expect(find.text(_ownership), findsOneWidget);
  });

  testWidgets('status aktif menampilkan alat eksklusif, cadangan cloud, perangkat, dan toko',
      (tester) async {
    await _pump(tester, controller: await _activeController());

    expect(find.text('Plus aktif'), findsOneWidget);
    expect(find.text('Aktif tanpa sinyal'), findsNothing);
    expect(find.byKey(const ValueKey('manage-status-pill')), findsNothing);
    expect(
      find.text('Hiqeo Plus Tahunan · berakhir 1 Jun 2027'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Status tersimpan di HP dengan masa tenggang 10 hari, agar fitur '
        'tidak terkunci di tengah pendakian.',
      ),
      findsOneWidget,
    );

    expect(find.text('Analitik lanjutan'), findsOneWidget);
    expect(find.text('Rekap tahunan'), findsOneWidget);
    expect(find.text('Cadangan cloud'), findsOneWidget);
    expect(find.text('Cadangkan otomatis'), findsOneWidget);
    expect(find.text('Hanya lewat Wi-Fi'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('manage-backup-switch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('manage-wifi-only-switch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('manage-sync-now')),
      findsOneWidget,
    );
    expect(
      find.text('Menunggu sinkronisasi pertama'),
      findsOneWidget,
    );
    expect(find.text('Kode pemulihan'), findsNothing);
    expect(find.text('Perangkat ini'), findsWidgets);
    expect(find.text('Aktif'), findsOneWidget);
    expect(
      find.textContaining('Server cadangan cloud belum ada di build ini'),
      findsNothing,
    );
    expect(find.text('Kelola langganan di app store'), findsOneWidget);
    expect(find.text('Ekspor data (GPX) · gratis'), findsOneWidget);
    expect(find.text(_ownership), findsOneWidget);
  });

  testWidgets('masa tenggang menyebut tanggal berakhir tenggang', (tester) async {
    await _pump(tester, controller: await _graceController());

    expect(find.text('Plus aktif'), findsOneWidget);
    expect(find.text('Masa tenggang'), findsOneWidget);
    expect(
      find.text('Hiqeo Plus Tahunan · tenggang sampai 4 Nov 2026'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Tanggal berlaku sudah lewat. Fitur Plus tetap terbuka sampai masa '
        'tenggang 10 hari habis; data tidak dihapus.',
      ),
      findsOneWidget,
    );
    expect(find.text('Cadangan cloud'), findsOneWidget);
    expect(find.text('Kelola langganan di app store'), findsOneWidget);
  });

  testWidgets('status berakhir menutup cadangan tetapi mempertahankan GPX',
      (tester) async {
    await _pump(tester, controller: await _expiredController());

    expect(find.text('Masa aktif berakhir'), findsOneWidget);
    expect(find.text('Berakhir'), findsOneWidget);
    expect(
      find.text('Hiqeo Plus Tahunan · berakhir 1 Okt 2026'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Masa tenggang sudah habis. Riwayat, data, peta unduhan, dan ekspor '
        'tetap bisa dipakai; hanya fitur Plus yang berhenti.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Cadangan cloud berhenti bersama Plus. Riwayat, data, peta unduhan, '
        'dan ekspor GPX tetap bisa dipakai.',
      ),
      findsOneWidget,
    );
    expect(find.text('Cadangan cloud'), findsNothing);
    expect(find.text('Ekspor data (GPX) · gratis'), findsOneWidget);
    expect(find.text('Kelola langganan di app store'), findsOneWidget);
    expect(find.text(_ownership), findsOneWidget);
  });

  testWidgets('saklar cadangan menyimpan pilihan ke repositori',
      (tester) async {
    final backup = FakeCloudBackupRepository(cloudBackupState());
    await _pump(
      tester,
      controller: await _activeController(),
      backup: backup,
    );

    final switchFinder =
        find.byKey(const ValueKey('manage-backup-switch'));
    expect(
      tester.widget<GooeySwitch>(switchFinder).value,
      isFalse,
    );

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(backup.state.autoBackup, isTrue);
    expect(backup.writes, 1);
    expect(tester.widget<GooeySwitch>(switchFinder).value, isTrue);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(backup.state.autoBackup, isFalse);
    expect(backup.writes, 2);
  });

  testWidgets('saklar cadangan kembali ke nilai lama bila gagal menyimpan',
      (tester) async {
    final backup = FakeCloudBackupRepository(cloudBackupState(), failSet: true);
    await _pump(
      tester,
      controller: await _activeController(),
      backup: backup,
    );

    final switchFinder =
        find.byKey(const ValueKey('manage-backup-switch'));

    await tester.tap(switchFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.widget<GooeySwitch>(switchFinder).value, isFalse);
    expect(backup.writes, 0);
    expect(
      find.text('Pilihan cadangan belum bisa disimpan.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'analitik lanjutan dan rekap tahunan tampil untuk Mahasiswa & Tahunan tetapi tersembunyi untuk Tiket 1x Naik',
      (tester) async {
    final student = await buildPlusController(
      token: 'student-tok',
      payload: plusPayload(planId: 'student_annual'),
    );
    await _pump(tester, controller: student);
    expect(find.byKey(const ValueKey('plus-row-analitik')), findsOneWidget);
    expect(find.byKey(const ValueKey('plus-row-rekap')), findsOneWidget);

    final tripPass = await buildPlusController(
      token: 'trip-tok',
      payload: plusPayload(planId: 'trip_pass_3d'),
    );
    await _pump(tester, controller: tripPass);
    expect(find.byKey(const ValueKey('plus-row-analitik')), findsNothing);
    expect(find.byKey(const ValueKey('plus-row-rekap')), findsNothing);
  });

  testWidgets('saklar hanya Wi-Fi dan tombol sinkronkan memperbarui cadangan cloud',
      (tester) async {
    final backup = FakeCloudBackupRepository(
      cloudBackupState(autoBackup: true, wifiOnly: true),
    );
    await _pump(
      tester,
      controller: await _activeController(),
      backup: backup,
    );

    final wifiSwitch = find.byKey(const ValueKey('manage-wifi-only-switch'));
    expect(tester.widget<GooeySwitch>(wifiSwitch).value, isTrue);

    await tester.tap(wifiSwitch);
    await tester.pumpAndSettle();
    expect(backup.state.wifiOnly, isFalse);
    expect(tester.widget<GooeySwitch>(wifiSwitch).value, isFalse);

    await tapAndSettleSnackBar(
      tester,
      find.byKey(const ValueKey('manage-sync-now')),
    );
    expect(backup.syncCalls, 1);
    expect(
      find.text('Riwayat dan statistik tersinkron dengan server.'),
      findsOneWidget,
    );
  });

  testWidgets('ekspor GPX tetap tersedia untuk pengguna gratis',
      (tester) async {
    final exporter = RecordingGpxExporter();
    final session = completedSession(
      id: 'gpx1',
      startedAtUtc: DateTime.utc(2026, 3, 1, 8, 30),
      distanceM: 2500,
      movingSeconds: 3600,
      elevationGainM: 200,
    );
    final repository = FakeTrackingRepository(
      sessions: <TrackingSession>[session],
      pointsBySession: <String, List<TrackPoint>>{
        'gpx1': samplePoints(count: 3),
      },
    );

    await _pump(
      tester,
      controller: await buildPlusController(),
      repository: repository,
      exporter: exporter,
    );

    final gpxBtn = find.text('Ekspor data (GPX) · gratis');
    await tester.ensureVisible(gpxBtn);
    await tester.pumpAndSettle();
    await tester.tap(gpxBtn);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('gpx-sheet')), findsOneWidget);
    expect(find.text('EKSPOR GPX · GRATIS'), findsOneWidget);
    expect(find.text('Ekspor data pendakian'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gpx-session-gpx1')),
      findsOneWidget,
    );
    expect(find.textContaining('1 Mar'), findsOneWidget);
    expect(find.text('2,5 km · 1j 00m'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('gpx-session-gpx1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(exporter.calls, hasLength(1));
    expect(exporter.calls.single.fileName, 'hiqeo-gpx-2026-03-01.gpx');
    expect(exporter.calls.single.contents, contains('creator="Hiqeo"'));
    expect(exporter.calls.single.subject, 'GPX pendakian Hiqeo');
    expect(find.text('Berkas GPX siap dibagikan.'), findsOneWidget);
  });

  testWidgets('lembar GPX menjelaskan saat belum ada sesi selesai',
      (tester) async {
    await _pump(
      tester,
      controller: await buildPlusController(),
      repository: FakeTrackingRepository(),
    );

    final gpxBtn = find.text('Ekspor data (GPX) · gratis');
    await tester.ensureVisible(gpxBtn);
    await tester.pumpAndSettle();
    await tester.tap(gpxBtn);
    await tester.pumpAndSettle();

    expect(find.text('Belum ada sesi selesai'), findsOneWidget);
    expect(
      find.textContaining('GPX dibuat dari pendakian yang sudah selesai'),
      findsOneWidget,
    );
  });

  testWidgets('galat pengaturan cadangan bisa dicoba lagi', (tester) async {
    final backup = FakeCloudBackupRepository(cloudBackupState(), failLoad: true);
    await _pump(
      tester,
      controller: await _activeController(),
      backup: backup,
    );

    expect(find.text('Cadangan belum bisa dibuka'), findsOneWidget);
    expect(
      find.text('Pengaturan cadangan belum dapat dibaca.'),
      findsOneWidget,
    );
    expect(find.text('Cadangan cloud'), findsNothing);

    backup.failLoad = false;
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();

    expect(find.text('Cadangan belum bisa dibuka'), findsNothing);
    expect(find.text('Cadangan cloud'), findsOneWidget);
    expect(find.text('Perangkat ini'), findsNWidgets(2));
  });

  testWidgets('sheet kelola langganan menegaskan data tetap tersimpan',
      (tester) async {
    await _pump(tester, controller: await _activeController());

    final storeBtn = find.text('Kelola langganan di Google Play');
    await tester.ensureVisible(storeBtn);
    await tester.pumpAndSettle();
    await tester.tap(storeBtn);
    await tester.pumpAndSettle();

    expect(find.text('Kelola langganan'), findsOneWidget);
    expect(
      find.textContaining('Langganan dikelola melalui Google Play'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Membatalkan langganan tidak menghapus riwayat, data, peta unduhan, '
        'atau ekspor GPX.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Mengerti'));
    await tester.pumpAndSettle();

    expect(find.text('Kelola langganan'), findsNothing);
  });

  testWidgets(
      'tombol Ekspor GPX dan Kelola langganan tidak sticky di bawah dan ikut bergulir di posisi paling bawah halaman',
      (tester) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await _activeController();
    addTearDown(controller.dispose);
    const safeBottom = 24.0;

    await pumpPlusPage(
      tester,
      MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 640),
          padding: EdgeInsets.only(top: 24, bottom: safeBottom),
        ),
        child: ManageSubscriptionPage(
          backupRepository: FakeCloudBackupRepository(cloudBackupState()),
          exporter: RecordingGpxExporter(),
        ),
      ),
      controller: controller,
      size: const Size(390, 640),
    );

    final gpxFinder = find.byKey(const ValueKey('manage-export-gpx'));
    final storeFinder = find.byKey(const ValueKey('manage-store'));

    // Tidak ada sticky bottom bar yang mengambang menutupi konten
    expect(
      find.byKey(const ValueKey('plus-sticky-bottom-bar')),
      findsNothing,
    );

    final gpxRectBefore = tester.getRect(gpxFinder);
    final storeRectBefore = tester.getRect(storeFinder);

    // Gulir konten daftar ke paling bawah
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    // Kedua tombol berpindah naik mengikuti guliran dan tampil bersih di bawah kepemilikan data
    final gpxRectAfter = tester.getRect(gpxFinder);
    final storeRectAfter = tester.getRect(storeFinder);
    expect(gpxRectAfter.top, lessThan(gpxRectBefore.top));
    expect(storeRectAfter.top, lessThan(storeRectBefore.top));

    final ownershipRect = tester.getRect(find.text(_ownership));
    expect(gpxRectAfter.top, greaterThan(ownershipRect.bottom));
    expect(storeRectAfter.top, greaterThan(gpxRectAfter.bottom));
    expect(storeRectAfter.bottom, lessThanOrEqualTo(640.0 - safeBottom));
  });

  testWidgets(
      'Plus aktif dengan lencana Ultima tetap utuh satu baris di layar sempit tanpa Aktif tanpa sinyal',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await buildPlusController(
      token: 'ultima-tok',
      payload: plusPayload(planId: 'ultima'),
    );
    addTearDown(controller.dispose);

    await pumpPlusPage(
      tester,
      ManageSubscriptionPage(
        backupRepository: FakeCloudBackupRepository(cloudBackupState()),
        exporter: RecordingGpxExporter(),
      ),
      controller: controller,
      size: const Size(320, 700),
    );

    expect(find.text('Plus aktif'), findsOneWidget);
    expect(find.text('Ultima'), findsOneWidget);
    expect(find.text('Aktif tanpa sinyal'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
