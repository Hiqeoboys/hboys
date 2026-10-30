import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/app/app.dart';
import 'package:nama_app/app/router.dart';
import 'package:nama_app/bootstrap.dart';
import 'package:nama_app/design/widgets/altracq_nav_bar.dart';

// Catatan: kasus lama memeriksa teks "115" dan "112" karena beranda versi
// sebelumnya menampilkan nomor darurat. Pada rancangan sepuluh layar, nomor
// itu pindah ke layar SOS; pemeriksaannya ikut pindah ke uji layar SOS (M9).
void main() {
  testWidgets('aplikasi tampil dari splash dan kerangka navigasi hidup',
      (tester) async {
    await tester
        .pumpWidget(const NamaApp(config: AppConfig(flavor: Flavor.dev)));
    expect(find.text('Menyiapkan data lokal di HP'), findsOneWidget);

    altracqRouter.go('/beranda');
    await tester.pumpAndSettle();
    expect(find.byType(AltracqNavBar), findsOneWidget);

    altracqRouter.go('/splash');
    await tester.pumpAndSettle();
  });
}
