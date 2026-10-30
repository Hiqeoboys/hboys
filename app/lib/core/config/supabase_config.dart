/// Konfigurasi publik Supabase. Hanya kunci publik yang boleh masuk aplikasi;
/// service role key tidak boleh dipakai di klien.
class SupabaseConfig {
  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const String legacyAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Harus terdaftar di Supabase Auth > URL Configuration dan cocok dengan
  /// intent filter Android serta CFBundleURLTypes iOS.
  static const String oauthRedirect = 'id.nama.namaapp://login-callback';

  /// Batasi sesi yang diambil dari deep link ke callback aplikasi ini saja.
  static bool isOAuthCallback(Uri uri) =>
      uri.scheme == 'id.nama.namaapp' && uri.host == 'login-callback';

  static String get effectiveKey =>
      publishableKey.isNotEmpty ? publishableKey : legacyAnonKey;

  static bool get isConfigured => url.isNotEmpty && effectiveKey.isNotEmpty;
}
