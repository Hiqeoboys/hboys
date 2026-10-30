import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'crypto_interfaces.dart';

/// AES-256-GCM dari paket `cryptography`. Format ciphertext:
/// versi(1) + nonce(12) + ciphertext + MAC(16).
class CryptographyAeadCipher implements AeadCipher {
  CryptographyAeadCipher({AesGcm? cipher})
      : _cipher = cipher ?? AesGcm.with256bits();

  static const int _version = 1;
  static const int _groupKeyLength = 32;

  final AesGcm _cipher;

  @override
  Future<Uint8List> encrypt({
    required Uint8List groupKey,
    required Uint8List plaintext,
    required Uint8List associatedData,
  }) async {
    _validateKey(groupKey);
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: SecretKey(groupKey),
      aad: associatedData,
    );
    final nonce = box.nonce;
    final mac = box.mac.bytes;
    final output = Uint8List(
      1 + nonce.length + box.cipherText.length + mac.length,
    );
    output[0] = _version;
    output.setRange(1, 1 + nonce.length, nonce);
    output.setRange(
      1 + nonce.length,
      1 + nonce.length + box.cipherText.length,
      box.cipherText,
    );
    output.setRange(
      1 + nonce.length + box.cipherText.length,
      output.length,
      mac,
    );
    return output;
  }

  @override
  Future<Uint8List> decrypt({
    required Uint8List groupKey,
    required Uint8List ciphertext,
    required Uint8List associatedData,
  }) async {
    _validateKey(groupKey);
    final nonceLength = _cipher.nonceLength;
    const macLength = 16;
    if (ciphertext.length < 1 + nonceLength + macLength ||
        ciphertext[0] != _version) {
      throw const AeadAuthenticationException(
        'Format ciphertext tidak dikenal atau rusak.',
      );
    }
    final nonce = ciphertext.sublist(1, 1 + nonceLength);
    final macStart = ciphertext.length - macLength;
    final body = ciphertext.sublist(1 + nonceLength, macStart);
    final mac = ciphertext.sublist(macStart);
    try {
      final clear = await _cipher.decrypt(
        SecretBox(body, nonce: nonce, mac: Mac(mac)),
        secretKey: SecretKey(groupKey),
        aad: associatedData,
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const AeadAuthenticationException(
        'Autentikasi pesan gagal: data atau header diubah.',
      );
    }
  }

  void _validateKey(Uint8List key) {
    if (key.length != _groupKeyLength) {
      throw ArgumentError.value(
        key.length,
        'groupKey',
        'Kunci grup harus 32 byte',
      );
    }
  }
}
