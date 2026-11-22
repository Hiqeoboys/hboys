import 'dart:io';

/// Konfigurasi [HttpOverrides] aman untuk permintaan jaringan media/R2 & API.
///
/// Menetapkan User-Agent konsisten, batas waktu koneksi wajar, dan batas koneksi
/// per host tanpa pernah menonaktifkan verifikasi sertifikat TLS.
class HiqeoHttpOverrides extends HttpOverrides {
  static const String userAgent = 'Hiqeo/1.0 (Android)';

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.userAgent = userAgent;
    client.connectionTimeout = const Duration(seconds: 12);
    client.idleTimeout = const Duration(seconds: 15);
    client.maxConnectionsPerHost = 6;
    return client;
  }
}
