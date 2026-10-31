import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Memuat Plus Jakarta Sans yang dikemas aplikasi.
///
/// Font uji bawaan (Ahem) memberi setiap huruf kotak selebar em, sehingga
/// ukuran dan pembungkusan teks jauh dari perangkat. Uji yang memeriksa ukuran
/// piksel atau "muat tanpa gulir" harus memakai huruf asli lewat helper ini.
Future<void> loadPlusJakartaSans(WidgetTester tester) async {
  // Pemuatan font dan berkas butuh zona async nyata, bukan FakeAsync milik
  // testWidgets.
  await tester.runAsync(() async {
    final loader = FontLoader('PlusJakartaSans');
    for (final weight in <String>['Regular', 'Medium', 'Bold', 'ExtraBold']) {
      loader.addFont(
        File('assets/fonts/PlusJakartaSans-$weight.ttf')
            .readAsBytes()
            .then((bytes) => ByteData.sublistView(bytes)),
      );
    }
    await loader.load();
  });
}
