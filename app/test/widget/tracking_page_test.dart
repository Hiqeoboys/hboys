import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/tracking/presentation/tracking_page.dart';

void main() {
  testWidgets('menampilkan galat platform tanpa memulai layanan',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TrackingPage()));
    await tester.pumpAndSettle();

    expect(find.text('Rekam Perjalanan'), findsOneWidget);
    expect(find.textContaining('Pelacakan GPS hanya untuk Android/iOS'),
        findsOneWidget);
    expect(find.text('Lengkapi izin untuk merekam'), findsNothing);
  });
}
