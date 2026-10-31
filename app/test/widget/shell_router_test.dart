import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/app/router.dart';
import 'package:nama_app/design/widgets/hiqeo_nav_bar.dart';

import '../support/hiqeo_app_harness.dart';

const List<String> tabLabels = <String>['Beranda', 'Peta', 'Lacak', 'Grup', 'Profil'];

Finder navLabel(String label) => find.descendant(
      of: find.byType(HiqeoNavBar),
      matching: find.text(label),
    );

void main() {
  late GoRouter router;

  setUp(() => router = buildHiqeoRouter());

  testWidgets('mulai di splash, lalu kerangka lima tab tersedia', (tester) async {
    await tester.pumpWidget(buildHiqeoTestApp(router: router));
    expect(find.text('Menyiapkan data lokal di HP'), findsOneWidget);

    router.go('/beranda');
    await tester.pumpAndSettle();

    expect(find.byType(HiqeoNavBar), findsOneWidget);
    for (final label in tabLabels) {
      expect(navLabel(label), findsOneWidget, reason: 'tab $label hilang');
    }
  });

  testWidgets('menyentuh tab mengganti isi dan menandai tab terpilih',
      (tester) async {
    await tester.pumpWidget(buildHiqeoTestApp(router: router));
    router.go('/beranda');
    await tester.pumpAndSettle();
    final handle = tester.ensureSemantics();

    await tester.tap(navLabel('Peta'));
    await tester.pumpAndSettle();

    expect(find.text('Peta offline'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/peta',
    );
    final node = tester.getSemantics(navLabel('Peta'));
    expect(node.flagsCollection.isSelected, ui.Tristate.isTrue);
    final home = tester.getSemantics(navLabel('Beranda'));
    expect(home.flagsCollection.isSelected, isNot(ui.Tristate.isTrue));
    handle.dispose();
  });

  testWidgets('layar di luar tab tidak menampilkan navigasi bawah',
      (tester) async {
    await tester.pumpWidget(buildHiqeoTestApp(router: router));
    router.go('/sos');
    await tester.pumpAndSettle();

    // Layar SOS nyata memuat kata "SOS" di judul dan di dalam tombol lingkaran;
    // yang diperiksa kasus ini adalah ketiadaan navigasi bawah.
    expect(find.text('SOS'), findsWidgets);
    expect(find.byType(HiqeoNavBar), findsNothing);

    // Kartu memuat basis data lokal sungguhan; di uji widget path_provider
    // tidak tersedia sehingga indikator muatnya berputar terus dan
    // pumpAndSettle tidak akan pernah selesai. Cukup beri waktu transisi rute.
    router.go('/kartu');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/kartu',
    );
    expect(find.byType(HiqeoNavBar), findsNothing);

    router.go('/beranda');
    await tester.pumpAndSettle();
  });

  testWidgets('navigasi adalah satu widget yang bertahan antar tab',
      (tester) async {
    await tester.pumpWidget(buildHiqeoTestApp(router: router));
    router.go('/beranda');
    await tester.pumpAndSettle();
    final before = tester.state(find.byType(HiqeoNavBar));

    await tester.tap(navLabel('Lacak'));
    await tester.pumpAndSettle();

    expect(find.byType(HiqeoNavBar), findsOneWidget);
    expect(tester.state(find.byType(HiqeoNavBar)), same(before));
  });

  testWidgets('isi tab baru memudar masuk 180 ms', (tester) async {
    await tester.pumpWidget(buildHiqeoTestApp(router: router));
    router.go('/beranda');
    await tester.pumpAndSettle();
    final fade = find.byKey(const ValueKey<String>('tab-fade'));
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);

    await tester.tap(navLabel('Peta'));
    await tester.pump();
    expect(
      tester.widget<FadeTransition>(fade).opacity.value,
      0,
      reason: 'isi baru mulai dari transparan',
    );

    await tester.pump(const Duration(milliseconds: 90));
    final mid = tester.widget<FadeTransition>(fade).opacity.value;
    expect(mid, greaterThan(0));
    expect(mid, lessThan(1));

    await tester.pump(const Duration(milliseconds: 90));
    expect(
      tester.widget<FadeTransition>(fade).opacity.value,
      moreOrLessEquals(1),
    );
  });

  testWidgets('mengetuk tab aktif tidak menganimasikan apa pun',
      (tester) async {
    await tester.pumpWidget(buildHiqeoTestApp(router: router));
    router.go('/beranda');
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);

    await tester.tap(navLabel('Beranda'));
    await tester.pump();

    expect(tester.hasRunningAnimations, isFalse);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/beranda',
    );
  });

  testWidgets('setiap tab adalah tombol berlabel untuk pembaca layar',
      (tester) async {
    await tester.pumpWidget(buildHiqeoTestApp(router: router));
    router.go('/beranda');
    await tester.pumpAndSettle();
    final handle = tester.ensureSemantics();

    for (final label in tabLabels) {
      final node = tester.getSemantics(navLabel(label));
      expect(node.flagsCollection.isButton, isTrue, reason: label);
      expect(node.label, label);
    }
    handle.dispose();
  });
}
