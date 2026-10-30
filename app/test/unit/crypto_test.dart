import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/infrastructure/crypto/crypto_interfaces.dart';
import 'package:nama_app/infrastructure/crypto/cryptography_aead_cipher.dart';
import 'package:nama_app/infrastructure/crypto/cryptography_identity_service.dart';

class MemorySecretStore implements SecretValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

final Uint8List aad = Uint8List.fromList(
  utf8.encode('nama.group-key|group-1|v1'),
);

void main() {
  group('CryptographyIdentityService', () {
    test('membungkus dan membuka kunci grup untuk penerima yang benar',
        () async {
      final sender = CryptographyIdentityService(
        store: MemorySecretStore(),
      );
      final recipient = CryptographyIdentityService(
        store: MemorySecretStore(),
      );
      final groupKey = await sender.generateGroupKey();
      final recipientPublicKey = await recipient.publicKey();

      final wrapped = await sender.wrapForMember(
        groupKey: groupKey,
        memberPublicKey: recipientPublicKey,
        associatedData: aad,
      );
      final recovered = await recipient.unwrap(
        wrappedKey: wrapped,
        associatedData: aad,
      );

      expect(groupKey.length, 32);
      expect(recovered, groupKey);
      expect(wrapped[0], 1);
    });

    test('kunci publik tetap sama untuk penyimpanan yang sama', () async {
      final store = MemorySecretStore();
      final first = await CryptographyIdentityService(store: store).publicKey();
      final second =
          await CryptographyIdentityService(store: store).publicKey();
      expect(second, first);
    });

    test('blob yang diubah ditolak', () async {
      final sender = CryptographyIdentityService(store: MemorySecretStore());
      final recipient = CryptographyIdentityService(
        store: MemorySecretStore(),
      );
      final wrapped = await sender.wrapForMember(
        groupKey: await sender.generateGroupKey(),
        memberPublicKey: await recipient.publicKey(),
        associatedData: aad,
      );
      final tampered = Uint8List.fromList(wrapped);
      tampered[tampered.length - 1] ^= 0x01;

      expect(
        () => recipient.unwrap(wrappedKey: tampered, associatedData: aad),
        throwsA(isA<WrappedKeyException>()),
      );
    });

    test('AAD berbeda ditolak', () async {
      final sender = CryptographyIdentityService(store: MemorySecretStore());
      final recipient = CryptographyIdentityService(
        store: MemorySecretStore(),
      );
      final wrapped = await sender.wrapForMember(
        groupKey: await sender.generateGroupKey(),
        memberPublicKey: await recipient.publicKey(),
        associatedData: aad,
      );

      expect(
        () => recipient.unwrap(
          wrappedKey: wrapped,
          associatedData: Uint8List.fromList(utf8.encode('lain|v1')),
        ),
        throwsA(isA<WrappedKeyException>()),
      );
    });

    test('penerima lain tidak dapat membuka blob', () async {
      final sender = CryptographyIdentityService(store: MemorySecretStore());
      final recipient = CryptographyIdentityService(
        store: MemorySecretStore(),
      );
      final other = CryptographyIdentityService(store: MemorySecretStore());
      final wrapped = await sender.wrapForMember(
        groupKey: await sender.generateGroupKey(),
        memberPublicKey: await recipient.publicKey(),
        associatedData: aad,
      );

      expect(
        () => other.unwrap(wrappedKey: wrapped, associatedData: aad),
        throwsA(isA<WrappedKeyException>()),
      );
    });

    test('kunci publik anggota harus 32 byte', () async {
      final sender = CryptographyIdentityService(store: MemorySecretStore());
      final groupKey = await sender.generateGroupKey();
      expect(
        () => sender.wrapForMember(
          groupKey: groupKey,
          memberPublicKey: Uint8List(31),
          associatedData: aad,
        ),
        throwsA(isA<WrappedKeyException>()),
      );
    });

    test('kunci privat rusak diganti, bukan dipakai', () async {
      final store = MemorySecretStore();
      store.values['nama.crypto.x25519.private.v1'] = 'bukan-base64';
      final service = CryptographyIdentityService(store: store);

      final first = await service.publicKey();
      final second = await service.publicKey();

      expect(first.length, 32);
      expect(second, first);
      expect(store.values['nama.crypto.x25519.private.v1'], isNotNull);
    });
  });

  group('CryptographyAeadCipher', () {
    test('enkripsi dan dekripsi dengan AAD yang sama', () async {
      final cipher = CryptographyAeadCipher();
      final key = await CryptographyIdentityService(
        store: MemorySecretStore(),
      ).generateGroupKey();
      final plaintext = Uint8List.fromList(utf8.encode('halo grup'));

      final ciphertext = await cipher.encrypt(
        groupKey: key,
        plaintext: plaintext,
        associatedData: aad,
      );
      final recovered = await cipher.decrypt(
        groupKey: key,
        ciphertext: ciphertext,
        associatedData: aad,
      );

      expect(utf8.decode(recovered), 'halo grup');
    });

    test('ciphertext atau MAC yang diubah gagal diautentikasi', () async {
      final cipher = CryptographyAeadCipher();
      final key = await CryptographyIdentityService(
        store: MemorySecretStore(),
      ).generateGroupKey();
      final ciphertext = await cipher.encrypt(
        groupKey: key,
        plaintext: Uint8List.fromList(utf8.encode('halo')),
        associatedData: aad,
      );
      final tampered = Uint8List.fromList(ciphertext);
      tampered[tampered.length - 1] ^= 0x01;

      expect(
        () => cipher.decrypt(
          groupKey: key,
          ciphertext: tampered,
          associatedData: aad,
        ),
        throwsA(isA<AeadAuthenticationException>()),
      );
    });

    test('AAD berbeda gagal diautentikasi', () async {
      final cipher = CryptographyAeadCipher();
      final key = await CryptographyIdentityService(
        store: MemorySecretStore(),
      ).generateGroupKey();
      final ciphertext = await cipher.encrypt(
        groupKey: key,
        plaintext: Uint8List.fromList(utf8.encode('halo')),
        associatedData: aad,
      );

      expect(
        () => cipher.decrypt(
          groupKey: key,
          ciphertext: ciphertext,
          associatedData: Uint8List.fromList(utf8.encode('nama.group-key|g|v2')),
        ),
        throwsA(isA<AeadAuthenticationException>()),
      );
    });
  });
}
