import 'dart:async';

enum AuthProviderKind { google, apple }

class AuthUser {
  const AuthUser({
    required this.id,
    this.email,
    this.displayName,
    this.avatarUrl,
    this.provider,
  });

  final String id;
  final String? email;

  /// Nama tampilan dari penyedia identitas. Tidak selalu tersedia, misalnya
  /// Apple hanya mengirim nama pada persetujuan pertama.
  final String? displayName;

  /// URL foto profil dari penyedia identitas (mis. Google avatar_url/picture).
  final String? avatarUrl;

  /// Penyedia yang dipakai untuk sesi ini; null bila tidak dapat dipastikan.
  final AuthProviderKind? provider;
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

  /// Memutus sesi penyedia identitas saat ini agar pemilih akun tampil kembali,
  /// lalu masuk dengan akun yang baru dipilih.
  Future<void> switchAccount(AuthProviderKind provider);

  Future<void> signOut();

  /// Menghapus akun pengguna saat ini beserta datanya di server (RPC `delete_my_account`).
  Future<void> deleteAccount();
}
