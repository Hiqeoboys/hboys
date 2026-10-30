import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/design/app_theme.dart';
import 'package:nama_app/design/tokens.dart';
import 'package:nama_app/features/splash/presentation/splash_page.dart';

void main() {
  testWidgets('splash menampilkan merek dan menunggu penyiapan lokal',
      (tester) async {
    var initialized = 0;
    var ready = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: altracqLightTheme,
        home: SplashPage(
          initializer: () async => initialized++,
          minimumDuration: const Duration(milliseconds: 50),
          onReady: () => ready++,
        ),
      ),
    );

    expect(find.text('Altracq'), findsOneWidget);
    expect(
      find.text('Pendamping pendakian yang tetap bekerja tanpa sinyal.'),
      findsOneWidget,
    );
    expect(find.text('Menyiapkan data lokal di HP'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(initialized, 1);
    expect(ready, 0);

    await tester.pump(const Duration(milliseconds: 60));
    expect(ready, 1);
  });

  testWidgets('splash tetap biru gelap meski tema aplikasi terang',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: altracqLightTheme,
        home: SplashPage(
          initializer: () async {},
          minimumDuration: Duration.zero,
          onReady: () {},
        ),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AltracqColors.dark.background);
  });

  testWidgets('galat penyiapan lokal tidak menahan splash', (tester) async {
    var ready = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: altracqLightTheme,
        home: SplashPage(
          initializer: () async => throw StateError('gagal'),
          minimumDuration: Duration.zero,
          onReady: () => ready++,
        ),
      ),
    );

    await tester.pump();
    expect(ready, 1);
  });
}
