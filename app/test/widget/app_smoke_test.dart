import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/app/app.dart';
import 'package:nama_app/app/router.dart';
import 'package:nama_app/bootstrap.dart';
import 'package:nama_app/design/widgets/hiqeo_nav_bar.dart';
import 'package:nama_app/features/splash/presentation/startup_gate_screen.dart';

// Catatan: kasus lama memeriksa teks "115" dan "112" karena beranda versi
// sebelumnya menampilkan nomor darurat. Pada rancangan sepuluh layar, nomor
// itu pindah ke layar SOS; pemeriksaannya ikut pindah ke uji layar SOS (M9).
void main() {
  testWidgets('aplikasi tampil dari StartupGateScreen dan kerangka navigasi hidup',
      (tester) async {
    await tester
        .pumpWidget(const NamaApp(config: AppConfig(flavor: Flavor.dev)));
    expect(find.byType(StartupGateScreen), findsOneWidget);

    hiqeoRouter.go('/beranda');
    await tester.pumpAndSettle();
    expect(find.byType(HiqeoNavBar), findsOneWidget);

    hiqeoRouter.go('/splash');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
  });
}
