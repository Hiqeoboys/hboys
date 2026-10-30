import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/app/router.dart';
import 'package:nama_app/design/widgets/altracq_nav_bar.dart';

import '../support/altracq_app_harness.dart';

const List<String> tabLabels = <String>['Beranda', 'Peta', 'Lacak', 'Grup', 'Profil'];

Finder navLabel(String label) => find.descendant(
      of: find.byType(AltracqNavBar),
      matching: find.text(label),
    );

void main() {
  late GoRouter router;

  setUp(() => router = buildAltracqRouter());

  testWidgets('mulai di splash, lalu kerangka lima tab tersedia', (tester) async {
    await tester.pumpWidget(buildAltracqTestApp(router: router));
    expect(find.text('Menyiapkan data lokal di HP'), findsOneWidget);

    router.go('/beranda');
    await tester.pumpAndSettle();

    expect(find.byType(AltracqNavBar), findsOneWidget);
    for (final label in tabLabels) {
      expect(navLabel(label), findsOneWidget, reason: 'tab $label hilang');
    }
  });

  testWidgets('menyentuh tab mengganti isi dan menandai tab terpilih',
      (tester) async {
    await tester.pumpWidget(buildAltracqTestApp(router: router));
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
    await tester.pumpWidget(buildAltracqTestApp(router: router));
    router.go('/sos');
    await tester.pumpAndSettle();

    // Layar SOS nyata memuat kata "SOS" di judul dan di dalam tombol lingkaran;
    // yang diperiksa kasus ini adalah ketiadaan navigasi bawah.
    expect(find.text('SOS'), findsWidgets);
    expect(find.byType(AltracqNavBar), findsNothing);
  });

  testWidgets('setiap tab adalah tombol berlabel untuk pembaca layar',
      (tester) async {
    await tester.pumpWidget(buildAltracqTestApp(router: router));
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
