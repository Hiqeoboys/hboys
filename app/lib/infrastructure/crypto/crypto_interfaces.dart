import 'dart:typed_data';

/// Antarmuka kriptografi. Implementasi (libsodium / paket `cryptography`)
/// ditulis setelah model ancaman ditinjau; JANGAN merancang primitif sendiri.
///
/// Rencana: X25519 untuk pertukaran kunci, Ed25519 untuk tanda tangan,
/// ChaCha20-Poly1305 untuk enkripsi pesan grup.

class AeadAuthenticationException implements Exception {
  const AeadAuthenticationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WrappedKeyException implements Exception {
  const WrappedKeyException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class AeadCipher {
  /// Mengenkripsi [plaintext] dengan kunci grup. [associatedData] (mis. header
  /// routing) ikut diautentikasi tetapi tidak dienkripsi.
  Future<Uint8List> encrypt({
    required Uint8List groupKey,
    required Uint8List plaintext,
    required Uint8List associatedData,
  });

  /// Melempar [AeadAuthenticationException] jika autentikasi gagal.
  Future<Uint8List> decrypt({
    required Uint8List groupKey,
    required Uint8List ciphertext,
    required Uint8List associatedData,
  });
}

abstract interface class Signer {
  Future<Uint8List> sign(Uint8List message);
  Future<bool> verify({
    required Uint8List message,
    required Uint8List signature,
    required Uint8List publicKey,
  });
}

abstract interface class IdentityService {
  /// Kunci publik perangkat ini (didaftarkan ke direktori server).
  Future<Uint8List> publicKey();
}

abstract interface class GroupKeyService {
  /// Membungkus kunci grup untuk satu anggota (dienkripsi dengan kunci publiknya).
  /// [associatedData] mengikat blob ke grup dan versi kunci sehingga blob tidak
  /// bisa dipindahkan ke konteks lain.
  Future<Uint8List> wrapForMember({
    required Uint8List groupKey,
    required Uint8List memberPublicKey,
    required Uint8List associatedData,
  });

  Future<Uint8List> unwrap({
    required Uint8List wrappedKey,
    required Uint8List associatedData,
  });

  /// Membuat kunci grup baru (dipanggil saat rotasi: anggota keluar/perangkat hilang).
  Future<Uint8List> generateGroupKey();
}

/// Penyimpanan nilai rahasia. Implementasi produksi memakai keystore/Keychain;
/// tes memakai penyimpanan dalam memori.
abstract interface class SecretValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}
