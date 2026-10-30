import 'dart:async';

enum AuthProviderKind { google, apple }

class AuthUser {
  const AuthUser({required this.id, this.email});

  final String id;
  final String? email;
}

class AccountException implements Exception {
  const AccountException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

/// Autentikasi hanya lewat penyedia identitas. Aplikasi tidak menyimpan
/// kata sandi dan tidak membuat alur login sendiri.
abstract interface class AuthService {
  bool get isConfigured;

  AuthUser? get currentUser;

  Stream<AuthUser?> get authStateChanges;

  /// Memulai alur OAuth di browser/lembar sistem. Keberhasilan sesi diamati
  /// lewat [authStateChanges], bukan dari nilai kembalian metode ini.
  Future<void> signIn(AuthProviderKind provider);

  Future<void> signOut();
}
