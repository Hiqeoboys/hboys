import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/features/plus/application/plus_controller.dart';
import 'package:nama_app/features/plus/application/plus_scope.dart';

import 'real_font.dart';

/// Ukuran ponsel tinggi dipakai agar seluruh isi layar Plus terbangun tanpa
/// menggulir dulu saat diperiksa.
const Size plusTestSize = Size(420, 1600);

Future<void> _prepare(WidgetTester tester, Size size) async {
  await loadPlusJakartaSans(tester);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> pumpPlusPage(
  WidgetTester tester,
  Widget page, {
  PlusController? controller,
  Size size = plusTestSize,
}) async {
  await _prepare(tester, size);
  final app = MaterialApp(theme: hiqeoLightTheme, home: page);
  await tester.pumpWidget(
    controller == null ? app : PlusScope(controller: controller, child: app),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpPlusRouter(
  WidgetTester tester,
  GoRouter router, {
  PlusController? controller,
  Size size = plusTestSize,
}) async {
  await _prepare(tester, size);
  final app = MaterialApp.router(
    theme: hiqeoLightTheme,
    routerConfig: router,
  );
  await tester.pumpWidget(
    controller == null ? app : PlusScope(controller: controller, child: app),
  );
  await tester.pumpAndSettle();
}

/// Mengetuk lalu memberi waktu untuk Future pendek dan SnackBar masuk, tanpa
/// menunggu sampai SnackBar menutup sendiri.
Future<void> tapAndSettleSnackBar(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
