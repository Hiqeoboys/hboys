import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/features/map/domain/mountain_pack.dart';
import 'package:nama_app/features/map/domain/mountain_pack_data.dart';
import 'package:nama_app/features/map/presentation/mountain_detail_page.dart';

Widget _buildTestApp(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      brightness: Brightness.light,
      extensions: const [HiqeoColors.light],
    ),
    home: child,
  );
}

void main() {
  group('MountainDetailPage Tests', () {
    late MountainPack basePack;

    setUp(() {
      final packs = MountainPackData.createDefaultPacks(downloadedIds: {});
      basePack = packs.firstWhere((p) => p.id == 'ciremai');
    });

    testWidgets('State 1 (belum diunduh): menampilkan judul, tombol unduh dan info Wi-Fi', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          MountainDetailPage(
            pack: basePack.copyWith(status: MountainDownloadStatus.notDownloaded),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Gunung Ciremai'), findsOneWidget);
      expect(find.text('KETINGGIAN'), findsOneWidget);
      expect(find.text('JALUR'), findsOneWidget);
      expect(find.text('UKURAN'), findsOneWidget);
      expect(find.text('Peta offline'), findsOneWidget);
      expect(find.textContaining('disarankan lewat Wi-Fi'), findsOneWidget);
      expect(find.text('Unduh peta'), findsOneWidget);
    });

    testWidgets('State 2 (mengunduh): menampilkan progress bar, persentase, jeda dan batal', (tester) async {
      final downloadingPack = basePack.copyWith(
        status: MountainDownloadStatus.downloading,
        progress: 0.42,
      );

      await tester.pumpWidget(
        _buildTestApp(
          MountainDetailPage(pack: downloadingPack),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Mengunduh peta'), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Jeda'), findsOneWidget);
      expect(find.text('Batal'), findsOneWidget);
    });

    testWidgets('State 3 (terunduh): menampilkan tersedia offline, tombol buka dan tautan hapus', (tester) async {
      final downloadedPack = basePack.copyWith(
        status: MountainDownloadStatus.downloaded,
        progress: 1.0,
      );

      await tester.pumpWidget(
        _buildTestApp(
          MountainDetailPage(pack: downloadedPack),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tersedia offline'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.text('Buka peta'), findsOneWidget);
      expect(find.text('Hapus unduhan'), findsOneWidget);
    });

    testWidgets('State 4 (pembaruan tersedia): menampilkan tombol perbarui dan buka versi lama', (tester) async {
      final updatePack = basePack.copyWith(
        status: MountainDownloadStatus.updateAvailable,
        version: 2,
        downloadedVersion: 1,
      );

      await tester.pumpWidget(
        _buildTestApp(
          MountainDetailPage(pack: updatePack),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pembaruan tersedia'), findsOneWidget);
      expect(find.text('Perbarui peta'), findsOneWidget);
      expect(find.text('Buka versi lama'), findsOneWidget);
    });

    testWidgets('State 5 (gagal): menampilkan unduhan gagal, pesan alasan dan tombol coba lagi', (tester) async {
      final failedPack = basePack.copyWith(
        status: MountainDownloadStatus.failed,
        failureReason: 'Batas kuota ubin peta tercapai (maksimal 750 paket ubin). Hapus paket gunung lain yang sudah tidak digunakan untuk melanjutkan unduhan ini.',
      );

      await tester.pumpWidget(
        _buildTestApp(
          MountainDetailPage(pack: failedPack),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Unduhan gagal'), findsOneWidget);
      expect(find.textContaining('maksimal 750 paket ubin'), findsOneWidget);
      expect(find.text('Coba lagi'), findsOneWidget);
    });

    testWidgets('Tombol Hapus unduhan memunculkan dialog konfirmasi', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final downloadedPack = basePack.copyWith(
        status: MountainDownloadStatus.downloaded,
      );

      await tester.pumpWidget(
        _buildTestApp(
          MountainDetailPage(pack: downloadedPack),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hapus unduhan'));
      await tester.pumpAndSettle();

      expect(find.text('Hapus peta offline?'), findsOneWidget);
      expect(find.text('Batal'), findsOneWidget);
      expect(find.text('Hapus'), findsOneWidget);
    });

    testWidgets('Aksi jeda mengubah label tombol menjadi Lanjut', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final downloadingPack = basePack.copyWith(
        status: MountainDownloadStatus.downloading,
        progress: 0.50,
      );

      await tester.pumpWidget(
        _buildTestApp(
          MountainDetailPage(pack: downloadingPack),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Jeda'), findsOneWidget);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Jeda'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Lanjut'), findsOneWidget);
    });

    testWidgets('Card Tersedia offline / Buka peta berada di bawah daftar jalur dan jalur bisa dipilih',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final downloadedPack = basePack.copyWith(
        status: MountainDownloadStatus.downloaded,
        progress: 1.0,
      );

      await tester.pumpWidget(
        _buildTestApp(
          MountainDetailPage(pack: downloadedPack),
        ),
      );
      await tester.pumpAndSettle();

      final routeCard = tester.getRect(
        find.byKey(const ValueKey('mountain-route-list-card')),
      );
      final actionCard = tester.getRect(
        find.byKey(const ValueKey('mountain-action-card')),
      );
      expect(
        actionCard.top,
        greaterThanOrEqualTo(routeCard.bottom),
        reason: 'Card Tersedia offline / Buka peta harus di bawah daftar jalur',
      );

      // Pilih jalur kedua jika ada
      if (downloadedPack.package.trails.length > 1) {
        final secondTrail = downloadedPack.package.trails[1];
        await tester.tap(find.byKey(ValueKey('route-row-${secondTrail.id}')));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      }
    });

    testWidgets(
        'Tombol kembali memakai SafeArea dan tetap diam (pinned) saat konten digulir, teks 3.145 mdpl utuh, dan kartu Tersedia offline tidak tertutup navbar',
        (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final merbabuPacks = MountainPackData.createDefaultPacks(downloadedIds: {'merbabu'});
      final merbabu = merbabuPacks.firstWhere((p) => p.id == 'merbabu').copyWith(
        status: MountainDownloadStatus.downloaded,
        progress: 1.0,
      );
      const statusBarTop = 32.0;
      const simulatedNavbarBottom = HiqeoMetrics.navbarHeight + HiqeoMetrics.navbarBottomMargin + 20.0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.light,
            extensions: const [HiqeoColors.light],
          ),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 780),
              padding: EdgeInsets.only(top: statusBarTop, bottom: simulatedNavbarBottom),
              textScaler: TextScaler.linear(1.15),
            ),
            child: MountainDetailPage(pack: merbabu),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Tombol kembali berada aman di bawah status bar (>= 32 + 12) dan tidak menutupi judul gunung
      final backFinder = find.byKey(const ValueKey('mountain-detail-back-button'));
      expect(backFinder, findsOneWidget);
      final backRectBefore = tester.getRect(backFinder);
      final titleRectBefore = tester.getRect(find.text('Gunung Merbabu'));
      expect(backRectBefore.top, greaterThanOrEqualTo(statusBarTop + 12.0));
      expect(backRectBefore.bottom, lessThan(titleRectBefore.top));

      // 2. Ketinggian 3.145 mdpl tidak memakai ellipsis
      final elevFinder = find.text('3.145 mdpl').last;
      final elevText = tester.widget<Text>(elevFinder);
      expect(elevText.overflow, isNull);

      // 3. Gulir ke bawah -> tombol kembali tetap DIAM (pinned) di pojok kiri atas
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -140));
      await tester.pumpAndSettle();
      final backRectAfter = tester.getRect(backFinder);
      expect(backRectAfter.top, closeTo(backRectBefore.top, 0.5));
      expect(backRectAfter.left, closeTo(backRectBefore.left, 0.5));

      // 4. Gulir sampai paling bawah -> 'Tersedia offline' & 'Hapus unduhan' bersih di atas area navbar
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      final deleteRect = tester.getRect(find.text('Hapus unduhan'));
      expect(
        deleteRect.bottom,
        lessThanOrEqualTo(780.0 - simulatedNavbarBottom),
      );
    });
  });
}
