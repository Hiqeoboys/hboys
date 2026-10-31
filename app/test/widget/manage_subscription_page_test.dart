import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('status aktif menampilkan cadangan cloud, perangkat, dan toko',
      (tester) async {
    await _pump(tester, controller: await _activeController());

    expect(find.text('Plus aktif'), findsOneWidget);
    expect(find.text('Aktif tanpa sinyal'), findsOneWidget);
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

    expect(find.text('Cadangan cloud'), findsOneWidget);
    expect(find.text('Cadangkan otomatis'), findsOneWidget);
    expect(find.text('Hanya lewat Wi-Fi'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('manage-backup-switch')),
      findsOneWidget,
    );
    expect(
      find.text('Belum ada · server cadangan belum tersambung'),
      findsOneWidget,
    );
    expect(find.text('Kode pemulihan'), findsOneWidget);
    expect(find.text('Perangkat ini'), findsNWidgets(2));
    expect(find.text('Aktif'), findsOneWidget);
    expect(
      find.textContaining('Perangkat lain muncul di sini'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Server cadangan cloud belum ada di build ini'),
      findsOneWidget,
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

  testWidgets('kode pemulihan bisa dibuka dan disalin', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await _pump(tester, controller: await _activeController());

    await tester.tap(find.byKey(const ValueKey('manage-recovery-code')));
    await tester.pumpAndSettle();

    expect(find.text('Kode pemulihan'), findsNWidgets(2));
    expect(find.text('ABCD-EFGH-JKLM-NPQR'), findsOneWidget);
    expect(
      find.textContaining('pada build ini tidak ada data yang dikirim'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('manage-copy-recovery')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(copied, 'ABCD-EFGH-JKLM-NPQR');
    expect(find.text('Kode pemulihan disalin.'), findsOneWidget);
    expect(find.text('ABCD-EFGH-JKLM-NPQR'), findsNothing);
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

    await tester.tap(find.text('Ekspor data (GPX) · gratis'));
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

    await tester.tap(find.text('Ekspor data (GPX) · gratis'));
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

    await tester.tap(find.text('Kelola langganan di app store'));
    await tester.pumpAndSettle();

    expect(find.text('Kelola langganan'), findsOneWidget);
    expect(
      find.textContaining('belum tersambung ke toko'),
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
}
