import 'package:flutter/services.dart';

/// Konfigurasi publik Supabase. Hanya kunci publik yang boleh masuk aplikasi;
/// service role key dan client secret tidak boleh dipakai di klien.
class SupabaseConfig {
  static const String _defineUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _definePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const String _defineLegacyAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String _defineGoogleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const String _defineGoogleIosClientId =
      String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  static const String _defineMapboxAccessToken =
      String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
  static const bool _defineAppleEnabled =
      bool.fromEnvironment('ENABLE_APPLE_SIGN_IN');

  static final Map<String, String> _runtimeEnv = <String, String>{};
  static bool _envLoaded = false;

  /// Membaca berkas `.env` saat runtime bila `--dart-define` tidak diberikan.
  /// Kunci rahasia (`*SECRET*`, `*SERVICE_ROLE*`) selalu diabaikan.
  static Future<void> loadEnv() async {
    if (_envLoaded) return;
    _envLoaded = true;
    try {
      final raw = await rootBundle.loadString('.env');
      parseEnvString(raw);
    } catch (_) {
      // Berkas .env opsional bila nilai sudah dikirim lewat --dart-define.
    }
  }

  static void parseEnvString(String raw) {
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      final key = trimmed.substring(0, eq).trim();
      final upperKey = key.toUpperCase();
      if (upperKey.contains('SECRET') ||
          upperKey.contains('SERVICE_ROLE') ||
          upperKey.contains('PRIVATE_KEY') ||
          upperKey.contains('R2_ACCESS') ||
          upperKey.contains('WEBHOOK')) {
        continue;
      }
      var value = trimmed.substring(eq + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      if (upperKey == 'MAPBOX_ACCESS_TOKEN' && value.startsWith('sk.')) {
        continue;
      }
      if ((upperKey == 'SUPABASE_ANON_KEY' ||
              upperKey == 'SUPABASE_PUBLISHABLE_KEY') &&
          value.startsWith('sb_secret_')) {
        continue;
      }
      if (value.isNotEmpty) {
        _runtimeEnv[key] = value;
      }
    }
  }

  static String get url =>
      _defineUrl.isNotEmpty ? _defineUrl : (_runtimeEnv['SUPABASE_URL'] ?? '');

  static String get publishableKey => _definePublishableKey.isNotEmpty
      ? _definePublishableKey
      : (_runtimeEnv['SUPABASE_PUBLISHABLE_KEY'] ?? '');

  static String get legacyAnonKey => _defineLegacyAnonKey.isNotEmpty
      ? _defineLegacyAnonKey
      : (_runtimeEnv['SUPABASE_ANON_KEY'] ?? '');

  /// Fallback bawaan Google Web Client ID bila tidak disediakan lewat `--dart-define` atau `.env`.
  static const String defaultGoogleWebClientId =
      '447033994713-egutiu8viek4lravfih8innpoo8begbd.apps.googleusercontent.com';

  /// Google Web Client ID dari Google Cloud Console untuk native Google Sign-In.
  static String get googleWebClientId {
    if (_defineGoogleWebClientId.isNotEmpty) return _defineGoogleWebClientId;
    final fromEnv = _runtimeEnv['GOOGLE_WEB_CLIENT_ID'];
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    return defaultGoogleWebClientId;
  }

  /// Google iOS Client ID dari Google Cloud Console (khusus iOS).
  static String get googleIosClientId => _defineGoogleIosClientId.isNotEmpty
      ? _defineGoogleIosClientId
      : (_runtimeEnv['GOOGLE_IOS_CLIENT_ID'] ?? '');

  /// Token publik Mapbox (`pk....`) dari `--dart-define=MAPBOX_ACCESS_TOKEN=...`
  /// atau berkas `.env` lokal yang diabaikan git.
  static String get mapboxAccessToken => _defineMapboxAccessToken.isNotEmpty
      ? _defineMapboxAccessToken
      : (_runtimeEnv['MAPBOX_ACCESS_TOKEN'] ?? '');

  /// Apple Sign-In hanya ditampilkan di Android bila dikonfigurasi eksplisit.
  static bool get isAppleConfigured =>
      _defineAppleEnabled || _runtimeEnv['ENABLE_APPLE_SIGN_IN'] == 'true';

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

/// URL kebijakan privasi resmi aplikasi untuk dibuka di browser eksternal.
const String kPrivacyPolicyUrl = String.fromEnvironment(
  'PRIVACY_POLICY_URL',
  defaultValue: 'https://hiqeo.com/privacy',
);
