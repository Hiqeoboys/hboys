import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/app/app.dart';
import 'package:nama_app/bootstrap.dart';

void main() {
  testWidgets('aplikasi tampil dan menyebut nomor darurat', (tester) async {
    await tester
        .pumpWidget(const NamaApp(config: AppConfig(flavor: Flavor.dev)));
    expect(find.textContaining('115'), findsOneWidget);
    expect(find.textContaining('112'), findsOneWidget);
  });
}
