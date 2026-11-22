import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../core/config/supabase_config.dart';
import '../features/auth/domain/auth_service.dart';

/// Layanan autentikasi native untuk aplikasi Hiqeo.
///
/// Menyediakan alur masuk native Google di Android (dan iOS), keluar sesi
/// dari Google maupun Supabase secara serempak, serta stream pemantauan sesi
/// [onAuthStateChange].
class AuthService {
  AuthService({
    SupabaseClient? client,
    GoogleSignIn? googleSignIn,
  })  : _client = client,
        _googleSignIn = googleSignIn;

  static final AuthService instance = AuthService();

  final SupabaseClient? _client;
  GoogleSignIn? _googleSignIn;

  SupabaseClient get _effectiveClient => _client ?? Supabase.instance.client;

  GoogleSignIn get _effectiveGoogleSignIn {
    return _googleSignIn ??= GoogleSignIn(
      clientId: !kIsWeb &&
              Platform.isIOS &&
              SupabaseConfig.googleIosClientId.isNotEmpty
          ? SupabaseConfig.googleIosClientId
          : null,
      serverClientId: SupabaseConfig.googleWebClientId.isNotEmpty
          ? SupabaseConfig.googleWebClientId
          : SupabaseConfig.defaultGoogleWebClientId,
      scopes: const <String>['email', 'profile'],
    );
  }

  /// Pengguna Supabase saat ini.
  User? get currentUser {
    try {
      return _effectiveClient.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  /// Stream perubahan status autentikasi Supabase.
  Stream<AuthState> get onAuthStateChange {
    return _effectiveClient.auth.onAuthStateChange;
  }

  /// Masuk dengan akun Google secara native (Android & iOS).
  Future<AuthResponse> signInWithGoogle() async {
    try {
      final googleSignIn = _effectiveGoogleSignIn;
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        throw const AccountException(
          'AUTH_CANCELLED',
          'Login Google dibatalkan pengguna',
        );
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null || idToken.isEmpty) {
        throw const AccountException(
          'GOOGLE_ID_TOKEN_MISSING',
          'ID Token Google tidak diterima. Pastikan Web Client ID sudah benar',
        );
      }

      return await _effectiveClient.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
    } on AccountException {
      rethrow;
    } on PlatformException catch (error) {
      throw mapGooglePlatformException(error);
    } on SocketException {
      throw const AccountException(
        'NETWORK_ERROR',
        'Tidak ada koneksi internet. Periksa jaringan Anda lalu coba lagi',
      );
    } on AuthException catch (error) {
      final msg = error.message.toLowerCase();
      if (msg.contains('nonce')) {
        throw const AccountException(
          'NONCE_CHECK_FAILED',
          'Supabase menolak token karena verifikasi nonce. Aktifkan opsi "Skip nonce checks" pada konfigurasi Google Provider di Dashboard Supabase.',
        );
      }
      if (msg.contains('access_denied') || msg.contains('not a test user')) {
        throw const AccountException(
          'GOOGLE_TEST_USER_REQUIRED',
          'Akun Google ini belum terdaftar sebagai Test User di Google Cloud Console (status aplikasi masih Testing). Tambahkan email Anda di OAuth Consent Screen > Test Users.',
        );
      }
      throw AccountException(
        'AUTH_FAILED',
        'Login Supabase gagal: ${error.message}',
      );
    } catch (error) {
      final text = error.toString().toLowerCase();
      if (text.contains('10:') || text.contains('apiexception: 10')) {
        throw const AccountException(
          'GOOGLE_DEVELOPER_ERROR',
          'Konfigurasi OAuth Android belum cocok (ApiException: 10). Pastikan SHA-1 debug/release dan package id.nama.nama_app terdaftar di Google Cloud Console',
        );
      }
      if (text.contains('12500') || text.contains('apiexception: 12500')) {
        throw const AccountException(
          'GOOGLE_SIGN_IN_FAILED',
          'Layanan Google Sign-In menolak konfigurasi (ApiException: 12500). Periksa email dukungan di OAuth Consent Screen dan Web Client ID',
        );
      }
      if (text.contains('12501') || text.contains('apiexception: 12501')) {
        throw const AccountException(
          'AUTH_CANCELLED',
          'Login Google dibatalkan pengguna',
        );
      }
      if (text.contains('network_error') || text.contains('7:')) {
        throw const AccountException(
          'NETWORK_ERROR',
          'Tidak ada koneksi internet. Periksa jaringan Anda lalu coba lagi',
        );
      }
      throw AccountException(
        'AUTH_FAILED',
        'Login Google gagal: $error',
      );
    }
  }

  /// Memaksa Google Sign-In menampilkan pemilih akun dengan memutus sesi
  /// lokal terlebih dahulu, lalu memulai alur masuk baru.
  Future<AuthResponse> switchGoogleAccount() async {
    try {
      await _effectiveGoogleSignIn.disconnect();
    } catch (_) {
      try {
        await _effectiveGoogleSignIn.signOut();
      } catch (_) {}
    }
    try {
      await _effectiveClient.auth.signOut();
    } catch (_) {}
    return signInWithGoogle();
  }

  /// Keluar dari Google dan Supabase secara bersamaan.
  Future<void> signOut() async {
    try {
      await _effectiveClient.auth.signOut();
      try {
        await _effectiveGoogleSignIn.signOut();
      } catch (_) {
        // Abaikan bila sesi GoogleSignIn lokal tidak ada
      }
    } on AuthException catch (error) {
      throw AccountException(
        'SIGN_OUT_FAILED',
        'Keluar gagal: ${error.message}',
      );
    }
  }

  AccountException mapGooglePlatformException(PlatformException error) {
    final code = error.code;
    final details =
        '${error.message ?? ''} ${error.details ?? ''}'.toLowerCase();
    if (code == GoogleSignIn.kSignInCanceledError ||
        details.contains('12501') ||
        details.contains('cancel')) {
      return const AccountException(
        'AUTH_CANCELLED',
        'Login Google dibatalkan pengguna',
      );
    }
    if (code == GoogleSignIn.kNetworkError || details.contains('7:')) {
      return const AccountException(
        'NETWORK_ERROR',
        'Tidak ada koneksi internet. Periksa jaringan Anda lalu coba lagi',
      );
    }
    if (details.contains('10:') || details.contains('apiexception: 10')) {
      return const AccountException(
        'GOOGLE_DEVELOPER_ERROR',
        'Konfigurasi OAuth Android belum cocok (ApiException: 10). Pastikan SHA-1 debug/release dan package id.nama.nama_app terdaftar di Google Cloud Console',
      );
    }
    if (details.contains('12500') || details.contains('apiexception: 12500')) {
      return const AccountException(
        'GOOGLE_SIGN_IN_FAILED',
        'Layanan Google Sign-In menolak konfigurasi (ApiException: 12500). Periksa email dukungan di OAuth Consent Screen dan Web Client ID',
      );
    }
    if (details.contains('test user') || details.contains('access_denied')) {
      return const AccountException(
        'GOOGLE_TEST_USER_REQUIRED',
        'Akun Google ini belum terdaftar sebagai Test User di Google Cloud Console (status aplikasi masih Testing). Tambahkan email Anda di OAuth Consent Screen > Test Users',
      );
    }
    return AccountException(
      'AUTH_FAILED',
      'Login Google gagal (${error.code}): ${error.message ?? "kesalahan sistem"}',
    );
  }
}
