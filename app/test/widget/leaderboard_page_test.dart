import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/design/gooey/gooey_switch.dart';
import 'package:nama_app/design/motion/visual_effect_policy.dart';
import 'package:nama_app/features/plus/application/plus_controller.dart';
import 'package:nama_app/features/plus/application/plus_navigation.dart';
import 'package:nama_app/features/plus/domain/leaderboard.dart';
import 'package:nama_app/features/plus/infrastructure/local_plus_stores.dart';
import 'package:nama_app/features/plus/presentation/leaderboard_page.dart';
import 'package:nama_app/infrastructure/power/power_profile_manager.dart';

import '../support/plus_fixtures.dart';
import '../support/plus_widget_harness.dart';

const VisualEffectPolicy _reduceMotion = VisualEffectPolicy(
  powerProfile: PowerProfile.normal,
  reduceMotion: true,
  deviceTier: DeviceTier.capable,
);

const String _footerNational =
    '10 besar per kategori. Server menghitung ulang dari jejak mentah dan '
    'papan diperbarui terjadwal, bukan real-time.';

Future<void> _pump(
  WidgetTester tester, {
  required PlusController controller,
  required FakeLeaderboardRepository repository,
  required InMemoryLeaderboardConsentStore consent,
  VisualEffectPolicy? policy,
}) async {
  final router = GoRouter(
    initialLocation: PlusRoutes.leaderboard,
    routes: <RouteBase>[
      GoRoute(
        path: PlusRoutes.leaderboard,
        builder: (context, state) => LeaderboardPage(
          repository: repository,
          consentStore: consent,
        ),
      ),
      GoRoute(
        path: PlusRoutes.paywall,
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('Tujuan Paywall')),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await pumpPlusRouter(
    tester,
    router,
    controller: controller,
    policy: policy,
  );
}

void main() {
  testWidgets('papan nasional memuat podium, baris 4-10, dan catatan',
      (tester) async {
    final controller = await buildPlusController(leaderboard: true);
    final repository = FakeLeaderboardRepository();
    final consent = InMemoryLeaderboardConsentStore();

    await _pump(
      tester,
      controller: controller,
      repository: repository,
      consent: consent,
    );

    expect(find.text('Nasional'), findsOneWidget);
    expect(find.text('Grup'), findsOneWidget);
    expect(find.text('Total gunung'), findsOneWidget);
    expect(find.text('Total jarak'), findsOneWidget);
    expect(find.text('Mingguan'), findsOneWidget);
    expect(find.text('Bulanan'), findsOneWidget);
    expect(find.text('Tahunan'), findsOneWidget);

    expect(find.text('Dimas A.'), findsOneWidget);
    expect(find.text('Sari W.'), findsOneWidget);
    expect(find.text('Bayu P.'), findsOneWidget);
    expect(find.text('Nadia R.'), findsOneWidget);
    expect(find.text('Ayu L.'), findsOneWidget);
    expect(find.text('9 gunung'), findsOneWidget);
    expect(find.text('8 gunung'), findsNWidgets(2));

    expect(find.text('Papan nasional untuk pengguna Plus'), findsOneWidget);
    expect(find.text('Butuh Plus'), findsOneWidget);
    expect(find.text(_footerNational), findsOneWidget);

    expect(repository.loads, hasLength(1));
    expect(repository.loads.single.scope, LeaderboardScope.national);
    expect(repository.loads.single.metric, LeaderboardMetric.totalMountains);
    expect(repository.loads.single.period, LeaderboardPeriod.monthly);
  });

  testWidgets('mengganti kategori dan periode memuat ulang papan',
      (tester) async {
    final controller = await buildPlusController(leaderboard: true);
    final repository = FakeLeaderboardRepository();

    await _pump(
      tester,
      controller: controller,
      repository: repository,
      consent: InMemoryLeaderboardConsentStore(),
    );

    await tester.tap(find.text('Total jarak'));
    await tester.pumpAndSettle();

    expect(repository.loads.last.metric, LeaderboardMetric.totalDistance);
    expect(repository.loads.last.period, LeaderboardPeriod.monthly);
    expect(repository.loads.last.scope, LeaderboardScope.national);
    expect(find.text('128 km'), findsOneWidget);
    expect(find.text('Nasional'), findsOneWidget);

    await tester.tap(find.text('Tahunan'));
    await tester.pumpAndSettle();

    expect(repository.loads.last.period, LeaderboardPeriod.yearly);
    expect(repository.loads.last.metric, LeaderboardMetric.totalDistance);
    expect(find.text('Nasional'), findsOneWidget);
    expect(find.text('Grup'), findsOneWidget);
  });

  testWidgets('papan lama bertahan saat memuat lalu baris muncul bertahap',
      (tester) async {
    final controller = await buildPlusController(leaderboard: true);
    final repository = FakeLeaderboardRepository();

    await _pump(
      tester,
      controller: controller,
      repository: repository,
      consent: InMemoryLeaderboardConsentStore(),
    );

    await tester.tap(find.text('Total jarak'));
    await tester.pump();

    expect(find.text('128 km'), findsOneWidget);
    expect(find.text('9 gunung'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 30));

    double opacityOf(int index) => tester
        .widget<Opacity>(
          find.byKey(ValueKey<String>('leaderboard-reveal-$index')).last,
        )
        .opacity;

    expect(opacityOf(0), greaterThan(opacityOf(3)));
    expect(opacityOf(3), lessThan(0.05));

    await tester.pumpAndSettle();

    expect(opacityOf(0), 1);
    expect(opacityOf(3), 1);
    expect(find.text('9 gunung'), findsNothing);
    expect(find.text('128 km'), findsOneWidget);
  });

  testWidgets('kurangi gerakan melewatkan kemunculan baris bertahap',
      (tester) async {
    final controller = await buildPlusController(leaderboard: true);
    final repository = FakeLeaderboardRepository();

    await _pump(
      tester,
      controller: controller,
      repository: repository,
      consent: InMemoryLeaderboardConsentStore(),
      policy: _reduceMotion,
    );

    expect(
      find.byKey(const ValueKey<String>('leaderboard-reveal-0')),
      findsNothing,
    );

    await tester.tap(find.text('Total jarak'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(
      find.byKey(const ValueKey<String>('leaderboard-reveal-3')),
      findsNothing,
    );
    expect(find.text('128 km'), findsOneWidget);
  });

  testWidgets('tab grup menampilkan anggota, baris sendiri, dan promo Plus',
      (tester) async {
    final controller = await buildPlusController(leaderboard: true);
    final repository = FakeLeaderboardRepository();

    await _pump(
      tester,
      controller: controller,
      repository: repository,
      consent: InMemoryLeaderboardConsentStore(),
    );

    await tester.tap(find.text('Grup'));
    await tester.pumpAndSettle();

    expect(repository.loads.last.scope, LeaderboardScope.group);
    expect(find.text('Rombongan Sabtu · 4 anggota'), findsOneWidget);
    expect(find.text('Rani (kamu)'), findsOneWidget);
    expect(find.text('Dimas'), findsOneWidget);
    expect(find.text('Sari'), findsOneWidget);
    expect(find.text('Bayu'), findsOneWidget);
    expect(find.text('5 gunung'), findsOneWidget);
    expect(find.text('4 gunung'), findsOneWidget);
    expect(
      find.text(
        'Semua anggota ikut bersaing, gratis. Statistik dibagikan ke grup saat '
        'bergabung.',
      ),
      findsOneWidget,
    );
    expect(find.text('Ingin bersaing di papan nasional?'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey<String>('leaderboard-plus-cta')));
    await tester.pumpAndSettle();

    expect(find.text('Tujuan Paywall'), findsOneWidget);
  });

  testWidgets('pengguna gratis menekan baris sendiri dan membuka paywall',
      (tester) async {
    final controller = await buildPlusController(leaderboard: true);

    await _pump(
      tester,
      controller: controller,
      repository: FakeLeaderboardRepository(),
      consent: InMemoryLeaderboardConsentStore(),
    );

    await tester
        .tap(find.byKey(const ValueKey<String>('leaderboard-self-card')));
    await tester.pumpAndSettle();

    expect(find.text('Tujuan Paywall'), findsOneWidget);
  });

  testWidgets('pengguna Plus menyetujui tampil lalu bisa menariknya',
      (tester) async {
    final controller = await buildPlusController(
      token: 'aktif',
      payload: plusPayload(),
      leaderboard: true,
    );
    final repository = FakeLeaderboardRepository();
    final consent = InMemoryLeaderboardConsentStore();

    await _pump(
      tester,
      controller: controller,
      repository: repository,
      consent: consent,
    );

    expect(find.text('Ikut papan nasional'), findsOneWidget);
    expect(find.text('Kelola'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey<String>('leaderboard-self-card')));
    await tester.pumpAndSettle();

    expect(find.text('Ikut Leaderboard Nasional?'), findsOneWidget);
    expect(find.text('YANG TAMPIL'), findsOneWidget);
    expect(find.text('TIDAK TAMPIL'), findsOneWidget);
    expect(find.text('Nama profil: Rani'), findsOneWidget);
    expect(find.text('Titik awal'), findsOneWidget);
    expect(find.text('Jalur lengkap'), findsOneWidget);
    expect(find.text('Tanggal selain bulan'), findsOneWidget);

    final switchFinder =
        find.byKey(const ValueKey<String>('leaderboard-consent-switch'));
    expect(tester.widget<GooeySwitch>(switchFinder).value, isFalse);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<GooeySwitch>(switchFinder).value, isTrue);

    await tapAndSettleSnackBar(
      tester,
      find.byKey(const ValueKey<String>('leaderboard-consent-agree')),
    );

    expect(consent.visible, isTrue);
    expect(consent.writes, 1);
    expect(find.text('Kamu tampil sebagai Rani'), findsOneWidget);
    expect(find.text('Kamu ikut papan nasional.'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey<String>('leaderboard-self-card')));
    await tester.pumpAndSettle();

    expect(find.text('Papan nasional'), findsOneWidget);
    expect(find.text('Simpan pengaturan'), findsOneWidget);
    expect(tester.widget<GooeySwitch>(switchFinder).value, isTrue);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    await tapAndSettleSnackBar(
      tester,
      find.byKey(const ValueKey<String>('leaderboard-consent-agree')),
    );

    expect(consent.visible, isFalse);
    expect(consent.writes, 2);
    expect(find.text('Kamu tidak tampil di papan'), findsOneWidget);
    expect(find.text('Nama kamu tidak ditampilkan.'), findsOneWidget);
  });

  testWidgets('laporan terkirim ke repositori dan blokir menyembunyikan baris',
      (tester) async {
    final controller = await buildPlusController(leaderboard: true);
    final repository = FakeLeaderboardRepository();
    final consent = InMemoryLeaderboardConsentStore();

    await _pump(
      tester,
      controller: controller,
      repository: repository,
      consent: consent,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('leaderboard-more-Dimas A.')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dimas A.'), findsNWidgets(2));
    expect(find.text('Peringkat 1 · 9 gunung'), findsOneWidget);

    await tapAndSettleSnackBar(
      tester,
      find.byKey(const ValueKey<String>('leaderboard-option-report')),
    );

    expect(repository.reports, <String>['Dimas A.']);
    expect(
      find.text(
        'Laporan belum dapat dikirim. Periksa koneksi internet lalu coba lagi.',
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('leaderboard-more-Dimas A.')),
    );
    await tester.pumpAndSettle();

    await tapAndSettleSnackBar(
      tester,
      find.byKey(const ValueKey<String>('leaderboard-option-block')),
    );

    expect(repository.blocks, <String>['Dimas A.']);
    expect(
      find.text(
        'Dimas A. disembunyikan dari papan peringkat di perangkat ini.',
      ),
      findsOneWidget,
    );
    expect(find.text('Dimas A.'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('leaderboard-more-Dimas A.')),
      findsNothing,
    );
    expect(find.text('Nadia R.'), findsOneWidget);
  });

  testWidgets('gagal memuat menampilkan pesan dan tombol coba lagi',
      (tester) async {
    final controller = await buildPlusController(leaderboard: true);
    final repository = FakeLeaderboardRepository(
      failLoad: true,
      failMessage: 'Jaringan papan sedang sibuk.',
    );

    await _pump(
      tester,
      controller: controller,
      repository: repository,
      consent: InMemoryLeaderboardConsentStore(),
    );

    expect(find.text('Papan belum bisa dibuka'), findsOneWidget);
    expect(find.text('Jaringan papan sedang sibuk.'), findsOneWidget);
    expect(repository.loads, hasLength(1));
    expect(find.text('Dimas A.'), findsNothing);

    repository.failLoad = false;
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();

    expect(repository.loads, hasLength(2));
    expect(find.text('Dimas A.'), findsOneWidget);
  });

  testWidgets('flag mati menampilkan layar belum tersedia tanpa memuat papan',
      (tester) async {
    final controller = await buildPlusController();
    final repository = FakeLeaderboardRepository();

    await _pump(
      tester,
      controller: controller,
      repository: repository,
      consent: InMemoryLeaderboardConsentStore(),
    );

    expect(find.text('Leaderboard belum tersedia'), findsOneWidget);
    expect(
      find.text(
        'Papan peringkat sedang dibuka secara bertahap dan segera hadir.',
      ),
      findsOneWidget,
    );
    expect(repository.loads, isEmpty);
    expect(find.text('Nasional'), findsNothing);
    expect(find.text('Mingguan'), findsNothing);
  });
}
