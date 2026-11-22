import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/app/router.dart';
import 'package:nama_app/design/background/page_background.dart';
import 'package:nama_app/design/system_ui.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/design/widgets/hiqeo_nav_bar.dart';
import 'package:nama_app/features/chat/presentation/chat_page.dart';
import 'package:nama_app/features/home/beranda_page.dart';
import 'package:nama_app/features/map/presentation/map_page.dart';
import 'package:nama_app/features/profile/presentation/profil_page.dart';

import '../support/hiqeo_app_harness.dart';
import '../support/real_font.dart';

const double _gestureInset = 24;
const double _statusInset = 24;

void _phoneWithInsets(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(
    top: _statusInset,
    bottom: _gestureInset,
  );
  tester.view.viewPadding = const FakeViewPadding(
    top: _statusInset,
    bottom: _gestureInset,
  );
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
}

double _bodyBottomPadding(WidgetTester tester, Type page) =>
    MediaQuery.paddingOf(tester.element(find.byType(page))).bottom;

void main() {
  late GoRouter router;

  setUp(() => router = buildHiqeoRouter());

  testWidgets('navbar mengambang di atas inset navigasi sistem',
      (tester) async {
    _phoneWithInsets(tester);
    await loadPlusJakartaSans(tester);
    await tester.pumpWidget(buildHiqeoTestApp(router: router));
    router.go('/beranda');
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.extendBody, isTrue);

    final nav = tester.getRect(find.byType(HiqeoNavBar));
    expect(nav.height, HiqeoMetrics.navbarHeight);
    expect(nav.left, HiqeoMetrics.navbarInset);
    expect(nav.right, 390 - HiqeoMetrics.navbarInset);
    expect(
      nav.bottom,
      844 - HiqeoMetrics.navbarBottomMargin - _gestureInset,
    );
  });

  testWidgets('seluruh tab full-bleed memanjang sampai tepi bawah layar',
      (tester) async {
    _phoneWithInsets(tester);
    await loadPlusJakartaSans(tester);
    await tester.pumpWidget(buildHiqeoTestApp(router: router));
    router.go('/beranda');
    await tester.pumpAndSettle();

    // extendBody aktif di semua tab; isi memanjang penuh hingga tepi bawah (844)
    expect(tester.getRect(find.byType(BerandaPage)).bottom, 844);

    await tester.tap(find.descendant(
      of: find.byType(HiqeoNavBar),
      matching: find.bySemanticsLabel('Grup'),
    ));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(ChatPage)).bottom, 844);

    await tester.tap(find.descendant(
      of: find.byType(HiqeoNavBar),
      matching: find.bySemanticsLabel('Profil'),
    ));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(ProfilPage)).bottom, 844);
  });

  testWidgets('Peta memakai seluruh tinggi layar dan navbar bertint di atasnya',
      (tester) async {
    _phoneWithInsets(tester);
    await loadPlusJakartaSans(tester);
    await tester.pumpWidget(buildHiqeoTestApp(router: router));
    router.go('/peta/jalur');
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.extendBody, isTrue);

    final map = tester.getRect(find.byType(MapPage));
    expect(map.top, 0);
    expect(map.bottom, 844);

    final background = tester.widget<PageBackground>(find.byType(PageBackground));
    expect(background.showBlobs, isFalse);

    final navbar = tester.widget<HiqeoNavBar>(find.byType(HiqeoNavBar));
    expect(navbar.overMap, isTrue);
    expect(
      tester.getRect(find.byType(HiqeoNavBar)).bottom,
      844 - HiqeoMetrics.navbarBottomMargin - _gestureInset,
    );

    // Inset sistem mentah tetap terbaca di dalam Peta walau padding isi
    // sudah dinaikkan setinggi navbar dan viewPadding Scaffold dibuang.
    expect(_bodyBottomPadding(tester, MapPage), HiqeoMetrics.navbarHeight +
        HiqeoMetrics.navbarBottomMargin +
        _gestureInset);
    expect(
      HiqeoSystemInset.bottomOf(tester.element(find.byType(MapPage))),
      _gestureInset,
    );

    router.go('/beranda');
    await tester.pumpAndSettle();
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).extendBody,
      isTrue,
    );
    expect(
      tester.widget<HiqeoNavBar>(find.byType(HiqeoNavBar)).overMap,
      isFalse,
    );
    expect(
      tester.widget<PageBackground>(find.byType(PageBackground)).showBlobs,
      isTrue,
    );
  });
}
