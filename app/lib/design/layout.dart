import 'package:flutter/widgets.dart';

import 'system_ui.dart';
import 'tokens.dart';

/// Helper tata letak bersama untuk memastikan padding dan inset seragam di seluruh aplikasi.
class AppLayout {
  const AppLayout._();

  /// Inset bawah untuk semua konten yang bisa di-scroll agar item terakhir
  /// tembus di belakang navbar yang melayang dan tetap bisa di-scroll sampai tidak tertutup.
  ///
  /// Spesifikasi: 64 + 12 + safe area bawah + 16
  static double bottomInset(BuildContext context) {
    // Pada Scaffold dengan extendBody: true, Scaffold menaikkan padding bawah MediaQuery
    // sebanding tinggi navbar. Gunakan HiqeoSystemInset.bottomOf(context) untuk
    // mendapatkan inset sistem mentah (gesture bar atau 3-button navigation).
    final systemInset = HiqeoSystemInset.bottomOf(context);
    return HiqeoMetrics.navbarHeight +
        HiqeoMetrics.navbarBottomMargin +
        systemInset +
        16.0;
  }
}

