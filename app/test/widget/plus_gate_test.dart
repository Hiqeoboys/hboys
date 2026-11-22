import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/features/plus/domain/plus_entitlement.dart';
import 'package:nama_app/features/plus/domain/plus_repositories.dart';
import 'package:nama_app/features/plus/presentation/paywall_page.dart';
import 'package:nama_app/features/plus/presentation/widgets/plus_gate.dart';

import '../support/plus_fixtures.dart';
import '../support/plus_widget_harness.dart';

const String _lockedNotice =
    'Semua fitur inti tetap gratis. Plus hanya menambah cuaca rute, '
    'estimasi, analitik, rekap, dan cadangan cloud.';

GoRouter _gateRouter() => GoRouter(
      initialLocation: '/fitur',
      routes: <RouteBase>[
        GoRoute(
          path: '/fitur',
          builder: (context, state) => const PlusGate(
            title: 'Cuaca rute',
            description: 'Prakiraan rute dengan label perkiraan.',
            child: Scaffold(body: Text('isi-plus')),
          ),
        ),
        GoRoute(
          path: '/plus',
          builder: (context, state) => const PaywallPage(),
        ),
      ],
    );

void main() {
  testWidgets('pengguna gratis melihat layar terkunci dan bisa membuka paywall',
      (tester) async {
    final controller = await buildPlusController();
    final router = _gateRouter();
    addTearDown(router.dispose);

    await pumpPlusRouter(tester, router, controller: controller);

    expect(find.text('Fitur Plus'), findsOneWidget);
    expect(find.text('HIQEO'), findsOneWidget);
    expect(find.text('Cuaca rute'), findsOneWidget);
    expect(
      find.text('Prakiraan rute dengan label perkiraan.'),
      findsOneWidget,
    );
    expect(find.text('Butuh Hiqeo Plus'), findsOneWidget);
    expect(find.text(_lockedNotice), findsOneWidget);
    expect(
      find.text(
        'Status Plus bisa diperiksa tanpa sinyal dan tetap berlaku selama '
        'masa tenggang.',
      ),
      findsOneWidget,
    );
    expect(find.text('isi-plus'), findsNothing);

    await tester.tap(find.text('Buka Hiqeo Plus'));
    await tester.pumpAndSettle();

    expect(find.text('isi-plus'), findsNothing);
    expect(find.text('PILIH PAKET'), findsOneWidget);
    expect(find.text('Hiqeo Plus Tahunan'), findsOneWidget);
  });

  testWidgets('status aktif langsung menampilkan isi', (tester) async {
    final controller = await buildPlusController(
      token: 'aktif',
      payload: plusPayload(),
    );
    final router = _gateRouter();
    addTearDown(router.dispose);

    await pumpPlusRouter(tester, router, controller: controller);

    expect(find.text('isi-plus'), findsOneWidget);
    expect(find.text('Butuh Hiqeo Plus'), findsNothing);
    expect(find.text('Buka Hiqeo Plus'), findsNothing);
  });

  testWidgets('masa tenggang tetap membuka isi Plus', (tester) async {
    final controller = await buildPlusController(
      token: 'tenggang',
      payload: plusPayload(expiresAtUtc: DateTime.utc(2026, 10, 25)),
    );
    final router = _gateRouter();
    addTearDown(router.dispose);

    await pumpPlusRouter(tester, router, controller: controller);

    expect(controller.access.isGrace, isTrue);
    expect(find.text('isi-plus'), findsOneWidget);
    expect(find.text('Buka Hiqeo Plus'), findsNothing);
  });

  testWidgets('pembelian membuka gerbang tanpa memuat ulang rute',
      (tester) async {
    final billing = FakePlusBilling()
      ..purchaseResult = const PlusBillingResult.purchased('tok-gerbang');
    final controller = await buildPlusController(
      billing: billing,
      verificationTokens: <String, EntitlementPayload>{
        'tok-gerbang': plusPayload(),
      },
    );
    final router = _gateRouter();
    addTearDown(router.dispose);

    await pumpPlusRouter(tester, router, controller: controller);

    expect(find.text('isi-plus'), findsNothing);

    final result = await controller.purchase('annual');
    await tester.pump();

    expect(result.success, isTrue);
    expect(controller.hasPlus, isTrue);
    expect(find.text('isi-plus'), findsOneWidget);
    expect(find.text('Butuh Hiqeo Plus'), findsNothing);
  });

  testWidgets(
      'requireFullPlan mengunci Tiket 1x Naik dan membuka Mahasiswa serta Tahunan',
      (tester) async {
    GoRouter fullPlanRouter() => GoRouter(
          initialLocation: '/eksklusif',
          routes: <RouteBase>[
            GoRoute(
              path: '/eksklusif',
              builder: (context, state) => const PlusGate(
                title: 'Analitik lanjutan',
                description: 'Khusus Mahasiswa & Tahunan.',
                requireFullPlan: true,
                child: Scaffold(body: Text('isi-eksklusif')),
              ),
            ),
            GoRoute(
              path: '/plus',
              builder: (context, state) => const PaywallPage(),
            ),
          ],
        );

    final tripPass = await buildPlusController(
      token: 'trip',
      payload: plusPayload(planId: 'trip_pass_3d'),
    );
    final router1 = fullPlanRouter();
    addTearDown(router1.dispose);
    await pumpPlusRouter(tester, router1, controller: tripPass);
    expect(find.text('isi-eksklusif'), findsNothing);
    expect(find.text('Buka Hiqeo Plus'), findsOneWidget);

    final student = await buildPlusController(
      token: 'student',
      payload: plusPayload(planId: 'student_annual'),
    );
    final router2 = fullPlanRouter();
    addTearDown(router2.dispose);
    await pumpPlusRouter(tester, router2, controller: student);
    expect(find.text('isi-eksklusif'), findsOneWidget);

    final annual = await buildPlusController(
      token: 'annual',
      payload: plusPayload(planId: 'annual'),
    );
    final router3 = fullPlanRouter();
    addTearDown(router3.dispose);
    await pumpPlusRouter(tester, router3, controller: annual);
    expect(find.text('isi-eksklusif'), findsOneWidget);
  });
}
