import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:nama_app/services/auth_service.dart';

void main() {
  group('AuthService - Pemetaan Error Bahasa Indonesia yang Ramah', () {
    final service = AuthService.instance;

    test('ApiException 10 menghasilkan pesan konfigurasi SHA-1 / package name', () {
      final platformError = PlatformException(
        code: '10',
        message: 'com.google.android.gms.common.api.ApiException: 10',
      );
      final mapped = service.mapGooglePlatformException(platformError);
      expect(mapped.code, 'GOOGLE_DEVELOPER_ERROR');
      expect(mapped.message, contains('ApiException: 10'));
      expect(mapped.message, contains('id.nama.nama_app'));
      expect(mapped.message, contains('SHA-1'));
    });

    test('ApiException 12500 menghasilkan pesan OAuth consent screen & Client ID', () {
      final platformError = PlatformException(
        code: '12500',
        message: 'com.google.android.gms.common.api.ApiException: 12500',
      );
      final mapped = service.mapGooglePlatformException(platformError);
      expect(mapped.code, 'GOOGLE_SIGN_IN_FAILED');
      expect(mapped.message, contains('ApiException: 12500'));
      expect(mapped.message, contains('OAuth Consent Screen'));
    });

    test('Pembatalan pengguna (12501 / kSignInCanceledError) memetakan ke AUTH_CANCELLED', () {
      final cancelError1 = PlatformException(
        code: GoogleSignIn.kSignInCanceledError,
        message: 'Sign in was cancelled',
      );
      expect(
        service.mapGooglePlatformException(cancelError1).code,
        'AUTH_CANCELLED',
      );

      final cancelError2 = PlatformException(
        code: '12501',
        message: 'com.google.android.gms.common.api.ApiException: 12501',
      );
      expect(
        service.mapGooglePlatformException(cancelError2).code,
        'AUTH_CANCELLED',
      );
    });

    test('Masalah jaringan (kNetworkError / 7:) memetakan ke NETWORK_ERROR', () {
      final netError = PlatformException(
        code: GoogleSignIn.kNetworkError,
        message: 'Network error 7:',
      );
      final mapped = service.mapGooglePlatformException(netError);
      expect(mapped.code, 'NETWORK_ERROR');
      expect(mapped.message, contains('koneksi internet'));
    });

    test('Akun bukan test user memetakan ke GOOGLE_TEST_USER_REQUIRED', () {
      final testUserError = PlatformException(
        code: 'access_denied',
        message: 'The user is not a test user for this project',
      );
      final mapped = service.mapGooglePlatformException(testUserError);
      expect(mapped.code, 'GOOGLE_TEST_USER_REQUIRED');
      expect(mapped.message, contains('Test User'));
    });
  });
}
