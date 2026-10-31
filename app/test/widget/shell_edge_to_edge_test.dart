import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/app/router.dart';
import 'package:nama_app/design/background/page_background.dart';
import 'package:nama_app/design/system_ui.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/design/widgets/altracq_nav_bar.dart';
import 'package:nama_app/features/home/beranda_page.dart';
import 'package:nama_app/features/map/presentation/map_page.dart';
import 'package:nama_app/features/profile/presentation/profil_page.dart';
import 'package:nama_app/features/tracking/presentation/tracking_page.dart';

import '../support/altracq_app_harness.dart';
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

  setUp(() => router = buildAltracqRouter());

  testWidgets('navbar mengambang di atas inset navigasi sistem',
      (tester) async {
    _phoneWithInsets(tester);
    await loadPlusJakartaSans(tester);
    await tester.pumpWidget(buildAltracqTestApp(router: router));
    router.go('/beranda');
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.extendBody, isTrue);

    final nav = tester.getRect(find.byType(AltracqNavBar));
    expect(nav.height, AltracqMetrics.navbarHeight);
    expect(nav.left, AltracqMetrics.navbarInset);
    expect(nav.right, 390 - AltracqMetrics.navbarInset);
    expect(
      nav.bottom,
      844 - AltracqMetrics.navbarInset - _gestureInset,
    );
  });

  testWidgets('isi tab mendapat jarak bawah navbar, celah, dan inset sistem',
      (tester) async {
    _phoneWithInsets(tester);
    await loadPlusJakartaSans(tester);
    await tester.pumpWidget(buildAltracqTestApp(router: router));
    router.go('/beranda');
    await tester.pumpAndSettle();

    const clearance =
        AltracqMetrics.navbarHeight + AltracqMetrics.navbarInset + _gestureInset;
    expect(_bodyBottomPadding(tester, BerandaPage), clearance);

    await tester.tap(find.descendant(
      of: find.byType(AltracqNavBar),
      matching: find.text('Lacak'),
    ));
    await tester.pumpAndSettle();
    expect(_bodyBottomPadding(tester, TrackingPage), clearance);

    await tester.tap(find.descendant(
      of: find.byType(AltracqNavBar),
      matching: find.text('Profil'),
    ));
    await tester.pumpAndSettle();
    expect(_bodyBottomPadding(tester, ProfilPage), clearance);
  });

  testWidgets('Peta memakai seluruh tinggi layar dan navbar bertint di atasnya',
      (tester) async {
    _phoneWithInsets(tester);
    await loadPlusJakartaSans(tester);
    await tester.pumpWidget(buildAltracqTestApp(router: router));
    router.go('/peta');
    await tester.pumpAndSettle();

    final map = tester.getRect(find.byType(MapPage));
    expect(map.top, 0);
    expect(map.bottom, 844);

    final background = tester.widget<PageBackground>(find.byType(PageBackground));
    expect(background.showBlobs, isFalse);

    final navbar = tester.widget<AltracqNavBar>(find.byType(AltracqNavBar));
    expect(navbar.overMap, isTrue);
    expect(
      tester.getRect(find.byType(AltracqNavBar)).bottom,
      844 - AltracqMetrics.navbarInset - _gestureInset,
    );

    // Inset sistem mentah tetap terbaca di dalam Peta walau padding isi
    // sudah dinaikkan setinggi navbar dan viewPadding Scaffold dibuang.
    expect(_bodyBottomPadding(tester, MapPage), AltracqMetrics.navbarHeight +
        AltracqMetrics.navbarInset +
        _gestureInset);
    expect(
      AltracqSystemInset.bottomOf(tester.element(find.byType(MapPage))),
      _gestureInset,
    );

    router.go('/beranda');
    await tester.pumpAndSettle();
    expect(
      tester.widget<AltracqNavBar>(find.byType(AltracqNavBar)).overMap,
      isFalse,
    );
    expect(
      tester.widget<PageBackground>(find.byType(PageBackground)).showBlobs,
      isTrue,
    );
  });
}
