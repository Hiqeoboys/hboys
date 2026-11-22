import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/map/data/mountain_catalog_repository.dart';
import 'package:nama_app/features/map/domain/mountain_pack.dart';
import 'package:nama_app/features/map/presentation/mountain_list_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MountainCatalogRepository.setMockInstance(null);
  });

  Widget createSubject({
    MountainCatalogRepository? repository,
    void Function(MountainPack)? onOpenMountain,
    bool disableAnimations = true,
  }) {
    final repo = repository ?? MountainCatalogRepository(mockOnline: true);
    return MaterialApp(
      theme: hiqeoLightTheme,
      home: MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(top: 44, bottom: 34),
          disableAnimations: true,
        ),
        child: Scaffold(
          body: MountainListPage(
            repository: repo,
            onOpenMountain: onOpenMountain,
          ),
        ),
      ),
    );
  }

  testWidgets('menampilkan judul, subjudul, dan kolom pencarian', (tester) async {
    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    expect(find.text('Peta'), findsOneWidget);
    expect(find.text('Pilih gunung untuk dibuka'), findsOneWidget);
    expect(find.text('Cari gunung atau daerah'), findsOneWidget);
  });

  testWidgets('menampilkan chip filter: Semua, Terunduh, dan provinsi', (tester) async {
    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    expect(find.text('Semua'), findsOneWidget);
    expect(find.text('Terunduh'), findsOneWidget);
    expect(find.text('Jawa Barat'), findsOneWidget);
    expect(find.text('Jawa Tengah'), findsOneWidget);
    expect(find.text('Nusa Tenggara Barat'), findsOneWidget);
  });

  testWidgets('pencarian menyaring daftar gunung berdasarkan nama (tidak peka huruf besar-kecil)',
      (tester) async {
    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    expect(find.text('Gunung Ciremai'), findsOneWidget);
    expect(find.text('Gunung Prau'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'prau');
    await tester.pumpAndSettle();

    expect(find.text('Gunung Prau'), findsOneWidget);
    expect(find.text('Gunung Ciremai'), findsNothing);
  });

  testWidgets('pencarian kosong menampilkan pesan dan tombol hapus pencarian',
      (tester) async {
    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'xyz123tidakada');
    await tester.pumpAndSettle();

    expect(find.text('Tidak ada gunung yang cocok'), findsOneWidget);
    expect(find.text('Hapus pencarian'), findsOneWidget);

    await tester.tap(find.text('Hapus pencarian'));
    await tester.pumpAndSettle();

    expect(find.text('Gunung Ciremai'), findsOneWidget);
  });

  testWidgets('filter chip Terunduh menyaring gunung yang sudah diunduh', (tester) async {
    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    // Default Ciremai sudah terunduh
    expect(find.text('Terunduh'), findsWidgets);
    await tester.tap(find.text('Terunduh').first);
    await tester.pumpAndSettle();

    expect(find.text('Gunung Ciremai'), findsOneWidget);
    // Prau belum diunduh, tidak boleh muncul
    expect(find.text('Gunung Prau'), findsNothing);
  });

  testWidgets('mengetuk tombol Buka memanggil aksi membuka peta jalur', (tester) async {
    MountainPack? openedPack;
    await tester.pumpWidget(createSubject(
      onOpenMountain: (pack) => openedPack = pack,
    ));
    await tester.pumpAndSettle();

    // Gunung Ciremai terunduh -> memiliki tombol Buka
    expect(find.text('Buka'), findsOneWidget);

    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();

    expect(openedPack, isNotNull);
    expect(openedPack!.name, 'Gunung Ciremai');
  });

  testWidgets('mode offline menampilkan banner informasi', (tester) async {
    final repo = MountainCatalogRepository(mockOnline: false);

    await tester.pumpWidget(createSubject(repository: repo));
    await tester.pumpAndSettle();

    expect(find.text('Mode offline: hanya gunung terunduh yang bisa dibuka'), findsOneWidget);
  });
}
