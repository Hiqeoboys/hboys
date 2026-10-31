import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/design/gooey/gooey_selector.dart';
import 'package:nama_app/design/widgets/hiqeo_button.dart';
import 'package:nama_app/features/plus/domain/plus_entitlement.dart';
import 'package:nama_app/features/plus/domain/plus_repositories.dart';
import 'package:nama_app/features/plus/presentation/paywall_page.dart';

import '../support/plus_fixtures.dart';
import '../support/plus_widget_harness.dart';

GooeySelectorBlobPainter _painter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byKey(const ValueKey<String>('gooey-selector-indicator')),
  );
  return paint.painter! as GooeySelectorBlobPainter;
}

GoRouter _paywallRouter() => GoRouter(
      initialLocation: '/plus',
      routes: <RouteBase>[
        GoRoute(
          path: '/plus',
          builder: (context, state) => const PaywallPage(),
        ),
        GoRoute(
          path: '/plus/kelola',
          builder: (context, state) =>
              const Scaffold(body: Text('kelola-stub')),
        ),
      ],
    );

void main() {
  testWidgets('menampilkan harga dari konfigurasi dan membeli paket terpilih',
      (tester) async {
    final billing = FakePlusBilling()
      ..purchaseResult = const PlusBillingResult.purchased('tok-founding');
    final controller = await buildPlusController(
      billing: billing,
      verificationTokens: <String, EntitlementPayload>{
        'tok-founding': plusPayload(planId: 'founding'),
      },
    );
    final router = _paywallRouter();
    addTearDown(router.dispose);

    await pumpPlusRouter(tester, router, controller: controller);

    expect(find.text('PILIH PAKET'), findsOneWidget);
    expect(find.text('Hiqeo Plus Tahunan'), findsOneWidget);
    expect(find.text('Founding Member'), findsOneWidget);
    expect(find.text('Sisa 87 dari 500'), findsOneWidget);
    expect(find.text('Mulai berlangganan'), findsOneWidget);
    expect(controller.hasPlus, isFalse);

    await tester.ensureVisible(find.text('Founding Member'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Founding Member'));
    await tester.pumpAndSettle();

    await tapAndSettleSnackBar(
      tester,
      find.byKey(const ValueKey<String>('paywall-cta')),
    );

    expect(billing.purchases, <String>['founding']);
    expect(controller.hasPlus, isTrue);
    expect(find.text('Plus aktif. Terima kasih.'), findsOneWidget);
    expect(find.text('Kelola langganan'), findsOneWidget);
    expect(find.text('Plus aktif'), findsOneWidget);
  });

  testWidgets('pengguna aktif membuka kelola langganan dari paywall',
      (tester) async {
    final controller = await buildPlusController(
      token: 'aktif',
      payload: plusPayload(),
    );
    final router = _paywallRouter();
    addTearDown(router.dispose);

    await pumpPlusRouter(tester, router, controller: controller);

    expect(find.text('Kelola langganan'), findsOneWidget);
    expect(find.text('Buka kelola langganan'), findsOneWidget);
    expect(find.textContaining('berlaku sampai'), findsOneWidget);
    expect(find.text('PILIH PAKET'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('paywall-cta')));
    await tester.pumpAndSettle();

    expect(find.text('kelola-stub'), findsOneWidget);
  });

  testWidgets('tanpa konfigurasi tidak menampilkan harga karangan',
      (tester) async {
    final controller = await buildPlusController(withConfig: false);
    final router = _paywallRouter();
    addTearDown(router.dispose);

    await pumpPlusRouter(tester, router, controller: controller);

    final cta = tester.widget<HiqeoButton>(
      find.byKey(const ValueKey<String>('paywall-cta')),
    );
    expect(cta.onPressed, isNull);
    expect(find.text('Paket belum tersedia'), findsOneWidget);
    expect(find.text('Paket sedang dimuat'), findsOneWidget);
    expect(find.textContaining('Harga dan paket berasal dari konfigurasi'),
        findsOneWidget);
    expect(find.text('Mulai berlangganan'), findsNothing);

    await tester.ensureVisible(find.text('Coba lagi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();

    expect(find.text('Paket belum dapat dimuat'), findsOneWidget);
    expect(controller.configFetchFailed, isTrue);
  });

  testWidgets('pulihkan pembelian menjelaskan bila tidak ada pembelian',
      (tester) async {
    final billing = FakePlusBilling()
      ..restoreResult = const PlusBillingResult.nothingToRestore(
        'Tidak ada pembelian untuk dipulihkan.',
      );
    final controller = await buildPlusController(billing: billing);
    final router = _paywallRouter();
    addTearDown(router.dispose);

    await pumpPlusRouter(tester, router, controller: controller);

    final restore = find.byKey(const ValueKey<String>('paywall-restore'));
    await tester.ensureVisible(restore);
    await tester.pumpAndSettle();
    await tapAndSettleSnackBar(tester, restore);

    expect(billing.restoreCalls, 1);
    expect(
      find.text('Tidak ada pembelian untuk dipulihkan.'),
      findsOneWidget,
    );
  });

  testWidgets('leaderboard hanya muncul bila flag menyala', (tester) async {
    final withLeaderboard = await buildPlusController(leaderboard: true);
    final router = _paywallRouter();
    addTearDown(router.dispose);

    await pumpPlusRouter(tester, router, controller: withLeaderboard);
    expect(find.text('Leaderboard'), findsOneWidget);
    expect(find.text('Lencana puncak'), findsNothing);
  });

  testWidgets('lencana puncak muncul saat leaderboard mati', (tester) async {
    final withBadges = await buildPlusController(peakBadges: true);
    final router = _paywallRouter();
    addTearDown(router.dispose);

    await pumpPlusRouter(tester, router, controller: withBadges);
    expect(find.text('Lencana puncak'), findsOneWidget);
    expect(find.text('Leaderboard'), findsNothing);
  });

  testWidgets('indikator paket bergerak dan mengikuti tinggi kartu tujuan',
      (tester) async {
    final controller = await buildPlusController();
    final router = _paywallRouter();
    addTearDown(router.dispose);

    await pumpPlusRouter(
      tester,
      router,
      controller: controller,
      size: const Size(420, 2600),
    );

    final handle = tester.ensureSemantics();
    final origin =
        tester.getTopLeft(find.byKey(const ValueKey<String>('paywall-plans')));
    final annual = tester
        .getRect(
          find.bySemanticsLabel('Hiqeo Plus Tahunan, Rp 249.000 per tahun'),
        )
        .shift(-origin);
    final founding = tester
        .getRect(
          find.bySemanticsLabel('Founding Member, Rp 349.000 sekali bayar'),
        )
        .shift(-origin);
    expect(founding.height, greaterThan(annual.height));

    var painter = _painter(tester);
    expect(painter.morphing, isFalse);
    expect(painter.headRect, annual);

    await tester.tap(find.text('Founding Member'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    painter = _painter(tester);
    expect(painter.morphing, isTrue);
    expect(painter.headRect.height, greaterThan(annual.height));
    expect(painter.headRect.height, lessThanOrEqualTo(founding.height));

    await tester.pumpAndSettle();

    painter = _painter(tester);
    expect(painter.morphing, isFalse);
    expect(painter.headRect, painter.tailRect);
    expect(painter.headRect, founding);
    handle.dispose();
  });
}
