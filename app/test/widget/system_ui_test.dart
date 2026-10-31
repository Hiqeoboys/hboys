import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/system_ui.dart';

void main() {
  test('mode terang memakai ikon bilah sistem gelap di atas bilah transparan',
      () {
    final style = altracqOverlayStyle(Brightness.light);

    expect(style.statusBarColor, Colors.transparent);
    expect(style.systemNavigationBarColor, Colors.transparent);
    expect(style.systemNavigationBarDividerColor, Colors.transparent);
    expect(style.statusBarIconBrightness, Brightness.dark);
    expect(style.systemNavigationBarIconBrightness, Brightness.dark);
    // iOS memakai kebalikan Android: terang berarti ikon gelap.
    expect(style.statusBarBrightness, Brightness.light);
    expect(style.systemStatusBarContrastEnforced, isFalse);
    expect(style.systemNavigationBarContrastEnforced, isFalse);
  });

  test('mode gelap memakai ikon bilah sistem terang', () {
    final style = altracqOverlayStyle(Brightness.dark);

    expect(style.statusBarIconBrightness, Brightness.light);
    expect(style.systemNavigationBarIconBrightness, Brightness.light);
    expect(style.statusBarBrightness, Brightness.dark);
  });

  testWidgets('region memasang gaya untuk seluruh isi di bawahnya',
      (tester) async {
    await tester.pumpWidget(
      const AltracqSystemUiRegion(
        brightness: Brightness.dark,
        child: ColoredBox(color: Colors.black),
      ),
    );

    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
    );
    expect(region.value.statusBarIconBrightness, Brightness.light);
    expect(region.value.systemNavigationBarColor, Colors.transparent);
  });
}
