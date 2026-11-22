import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'crypto_interfaces.dart';

const int _aeadVersion = 1;
const int _aeadNonceLength = 12;
const int _aeadMacLength = 16;

const int _wrapVersion = 1;
const int _wrapPublicKeyLength = 32;
const int _groupKeyLength = 32;
const String _wrapLabel = 'nama.group-key-wrap.v1';

Uint8List _buildGroupChatAad(
  String kind,
  String groupId,
  String recordId,
  int keyVersion,
) {
  return Uint8List.fromList(
    utf8.encode('hiqeo.e2ee|$kind|$groupId|$recordId|v$keyVersion'),
  );
}

Future<Uint8List> _deriveDeterministicKey(
  Sha256 sha256,
  String groupId,
  int keyVersion,
) async {
  final hash = await sha256.hash(
    utf8.encode('hiqeo-mesh-key:$groupId:v$keyVersion'),
  );
  return Uint8List.fromList(hash.bytes);
}

Future<Uint8List> _aeadEncryptSyncArgs(
  AesGcm cipher,
  Uint8List groupKey,
  Uint8List plaintext,
  Uint8List associatedData,
) async {
  if (groupKey.length != _groupKeyLength) {
    throw ArgumentError.value(
      groupKey.length,
      'groupKey',
      'Kunci grup harus 32 byte',
    );
  }
  final box = await cipher.encrypt(
    plaintext,
    secretKey: SecretKey(groupKey),
    aad: associatedData,
  );
  final nonce = box.nonce;
  final mac = box.mac.bytes;
  final output = Uint8List(
    1 + nonce.length + box.cipherText.length + mac.length,
  );
  output[0] = _aeadVersion;
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

Future<Uint8List> _aeadDecryptSyncArgs(
  AesGcm cipher,
  Uint8List groupKey,
  Uint8List ciphertext,
  Uint8List associatedData,
) async {
  if (groupKey.length != _groupKeyLength) {
    throw ArgumentError.value(
      groupKey.length,
      'groupKey',
      'Kunci grup harus 32 byte',
    );
  }
  if (ciphertext.length < 1 + _aeadNonceLength + _aeadMacLength ||
      ciphertext[0] != _aeadVersion) {
    throw const AeadAuthenticationException(
      'Format ciphertext tidak dikenal atau rusak.',
    );
  }
  final nonce = ciphertext.sublist(1, 1 + _aeadNonceLength);
  final macStart = ciphertext.length - _aeadMacLength;
  final body = ciphertext.sublist(1 + _aeadNonceLength, macStart);
  final mac = ciphertext.sublist(macStart);
  try {
    final clear = await cipher.decrypt(
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

Future<Map<String, String>> isolateEncryptJson({
  required Uint8List groupKey,
  required String kind,
  required String groupId,
  required String recordId,
  required int keyVersion,
  required String payloadJson,
}) {
  return Isolate.run(() async {
    final cipher = AesGcm.with256bits();
    final plaintext = Uint8List.fromList(utf8.encode(payloadJson));
    final aad = _buildGroupChatAad(kind, groupId, recordId, keyVersion);
    final sealed = await _aeadEncryptSyncArgs(cipher, groupKey, plaintext, aad);
    final nonce = sealed.sublist(1, 1 + _aeadNonceLength);
    return <String, String>{
      'ciphertextBase64': base64Encode(sealed),
      'nonceBase64': base64Encode(nonce),
    };
  });
}

Future<Map<String, dynamic>> isolateDecryptJson({
  required Uint8List? groupKey,
  required String kind,
  required String groupId,
  required String recordId,
  required int keyVersion,
  required String ciphertextBase64,
  required bool allowDeterministicFallback,
}) {
  return Isolate.run(() async {
    final cipher = AesGcm.with256bits();
    final sha256 = Sha256();
    final resolvedKey = groupKey ??
        (allowDeterministicFallback
            ? await _deriveDeterministicKey(sha256, groupId, keyVersion)
            : null);
    if (resolvedKey == null || resolvedKey.length != _groupKeyLength) {
      throw const AeadAuthenticationException('Kunci grup tidak tersedia.');
    }
    final sealed = Uint8List.fromList(base64Decode(ciphertextBase64));
    final aad = _buildGroupChatAad(kind, groupId, recordId, keyVersion);
    Uint8List clear;
    try {
      clear = await _aeadDecryptSyncArgs(cipher, resolvedKey, sealed, aad);
    } catch (_) {
      if (!allowDeterministicFallback) rethrow;
      final fallbackKey =
          await _deriveDeterministicKey(sha256, groupId, keyVersion);
      clear = await _aeadDecryptSyncArgs(cipher, fallbackKey, sealed, aad);
    }
    final decoded = jsonDecode(utf8.decode(clear));
    if (decoded is! Map<String, dynamic>) {
      throw const AeadAuthenticationException('Payload JSON tidak valid.');
    }
    return decoded;
  });
}

/// Decrypts an entire batch of chat messages or member locations inside a single
/// background isolate. Entries that cannot be authenticated return `null` at
/// their index so other readable items still render cleanly.
Future<List<Map<String, dynamic>?>> isolateDecryptJsonBatch(
  List<Map<String, Object?>> items,
) {
  if (items.isEmpty) return Future<List<Map<String, dynamic>?>>.value(const []);
  return Isolate.run(() async {
    final cipher = AesGcm.with256bits();
    final sha256 = Sha256();
    final deterministicCache = <String, Uint8List>{};

    Future<Uint8List> getDeterministic(String groupId, int version) async {
      final cacheKey = '$groupId|$version';
      return deterministicCache[cacheKey] ??=
          await _deriveDeterministicKey(sha256, groupId, version);
    }

    final results = List<Map<String, dynamic>?>.filled(items.length, null);
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final kind = item['kind'] as String? ?? '';
      final groupId = item['groupId'] as String? ?? '';
      final recordId = item['recordId'] as String? ?? '';
      final keyVersion = item['keyVersion'] as int? ?? 1;
      final ciphertextBase64 = item['ciphertextBase64'] as String? ?? '';
      final groupKey = item['groupKey'] as Uint8List?;
      final allowFallback = item['allowDeterministicFallback'] as bool? ?? false;

      if (groupId.isEmpty || recordId.isEmpty || ciphertextBase64.isEmpty) {
        continue;
      }

      try {
        final key = (groupKey != null && groupKey.length == _groupKeyLength)
            ? groupKey
            : (allowFallback
                ? await getDeterministic(groupId, keyVersion)
                : null);
        if (key == null) continue;

        final sealed = Uint8List.fromList(base64Decode(ciphertextBase64));
        final aad = _buildGroupChatAad(kind, groupId, recordId, keyVersion);
        Uint8List clear;
        try {
          clear = await _aeadDecryptSyncArgs(cipher, key, sealed, aad);
        } catch (_) {
          if (!allowFallback) continue;
          final fallbackKey = await getDeterministic(groupId, keyVersion);
          clear = await _aeadDecryptSyncArgs(cipher, fallbackKey, sealed, aad);
        }
        final decoded = jsonDecode(utf8.decode(clear));
        if (decoded is Map<String, dynamic>) {
          results[i] = decoded;
        }
      } catch (_) {
        // Leave null at index i when row cannot be decrypted yet.
      }
    }
    return results;
  });
}

Future<Uint8List> isolateEncryptBytes({
  required Uint8List groupKey,
  required Uint8List plaintext,
  required Uint8List associatedData,
}) {
  return Isolate.run(() async {
    final cipher = AesGcm.with256bits();
    return _aeadEncryptSyncArgs(cipher, groupKey, plaintext, associatedData);
  });
}

Future<Uint8List> isolateDecryptBytes({
  required Uint8List? groupKey,
  required Uint8List ciphertext,
  required String kind,
  required String groupId,
  required String recordId,
  required int keyVersion,
  required bool allowDeterministicFallback,
}) {
  return Isolate.run(() async {
    final cipher = AesGcm.with256bits();
    final sha256 = Sha256();
    final key = groupKey ??
        (allowDeterministicFallback
            ? await _deriveDeterministicKey(sha256, groupId, keyVersion)
            : null);
    if (key == null || key.length != _groupKeyLength) {
      throw const AeadAuthenticationException('Kunci grup tidak tersedia.');
    }
    final aad = _buildGroupChatAad(kind, groupId, recordId, keyVersion);
    try {
      return await _aeadDecryptSyncArgs(cipher, key, ciphertext, aad);
    } catch (_) {
      if (!allowDeterministicFallback) rethrow;
      final fallbackKey =
          await _deriveDeterministicKey(sha256, groupId, keyVersion);
      return _aeadDecryptSyncArgs(cipher, fallbackKey, ciphertext, aad);
    }
  });
}

Future<Map<String, Uint8List>> isolateGenerateX25519KeyPair() {
  return Isolate.run(() async {
    final x25519 = X25519();
    final pair = await x25519.newKeyPair();
    final privateBytes = await pair.extractPrivateKeyBytes();
    final public = await pair.extractPublicKey();
    return <String, Uint8List>{
      'seed': Uint8List.fromList(privateBytes),
      'publicKey': Uint8List.fromList(public.bytes),
    };
  });
}

Future<Uint8List> isolateExtractX25519PublicKey(Uint8List seed) {
  return Isolate.run(() async {
    final x25519 = X25519();
    final pair = await x25519.newKeyPairFromSeed(seed);
    final public = await pair.extractPublicKey();
    return Uint8List.fromList(public.bytes);
  });
}

Future<Uint8List> _wrapOneInIsolate({
  required X25519 x25519,
  required Hkdf hkdf,
  required AesGcm cipher,
  required Uint8List groupKey,
  required Uint8List memberPublicKey,
  required Uint8List associatedData,
}) async {
  final ephemeral = await x25519.newKeyPair();
  final ephemeralPublic = await ephemeral.extractPublicKey();
  final shared = await x25519.sharedSecretKey(
    keyPair: ephemeral,
    remotePublicKey: SimplePublicKey(
      memberPublicKey,
      type: KeyPairType.x25519,
    ),
  );
  final info = Uint8List.fromList(<int>[
    ...utf8.encode(_wrapLabel),
    ...associatedData,
  ]);
  final derived = await hkdf.deriveKey(
    secretKey: shared,
    nonce: ephemeralPublic.bytes,
    info: info,
  );
  final box = await cipher.encrypt(
    groupKey,
    secretKey: derived,
    aad: associatedData,
  );
  final nonce = box.nonce;
  final mac = box.mac.bytes;
  final output = Uint8List(
    1 +
        ephemeralPublic.bytes.length +
        nonce.length +
        box.cipherText.length +
        mac.length,
  );
  var offset = 0;
  output[offset++] = _wrapVersion;
  output.setRange(
    offset,
    offset + ephemeralPublic.bytes.length,
    ephemeralPublic.bytes,
  );
  offset += ephemeralPublic.bytes.length;
  output.setRange(offset, offset + nonce.length, nonce);
  offset += nonce.length;
  output.setRange(
    offset,
    offset + box.cipherText.length,
    box.cipherText,
  );
  offset += box.cipherText.length;
  output.setRange(offset, output.length, mac);
  return output;
}

Future<Uint8List> isolateWrapGroupKeyForMember({
  required Uint8List groupKey,
  required Uint8List memberPublicKey,
  required Uint8List associatedData,
}) {
  if (groupKey.length != _groupKeyLength) {
    throw ArgumentError.value(
      groupKey.length,
      'groupKey',
      'Kunci grup harus 32 byte',
    );
  }
  if (memberPublicKey.length != _wrapPublicKeyLength) {
    throw const WrappedKeyException(
      'Kunci publik anggota harus $_wrapPublicKeyLength byte.',
    );
  }
  return Isolate.run(() async {
    return _wrapOneInIsolate(
      x25519: X25519(),
      hkdf: Hkdf(hmac: Hmac.sha256(), outputLength: 32),
      cipher: AesGcm.with256bits(),
      groupKey: groupKey,
      memberPublicKey: memberPublicKey,
      associatedData: associatedData,
    );
  });
}

Future<List<Map<String, Object>>> isolateWrapGroupKeyBatch({
  required Uint8List groupKey,
  required List<Map<String, Object>> recipients,
  required Uint8List associatedData,
}) {
  if (recipients.isEmpty) {
    return Future<List<Map<String, Object>>>.value(const []);
  }
  if (groupKey.length != _groupKeyLength) {
    throw ArgumentError.value(
      groupKey.length,
      'groupKey',
      'Kunci grup harus 32 byte',
    );
  }
  return Isolate.run(() async {
    final x25519 = X25519();
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final cipher = AesGcm.with256bits();
    final wrapped = <Map<String, Object>>[];
    for (final entry in recipients) {
      final userId = entry['userId'] as String;
      final publicKey = entry['publicKey'] as Uint8List;
      if (publicKey.length != _wrapPublicKeyLength) {
        throw const WrappedKeyException(
          'Kunci publik anggota harus $_wrapPublicKeyLength byte.',
        );
      }
      final blob = await _wrapOneInIsolate(
        x25519: x25519,
        hkdf: hkdf,
        cipher: cipher,
        groupKey: groupKey,
        memberPublicKey: publicKey,
        associatedData: associatedData,
      );
      wrapped.add(<String, Object>{
        'userId': userId,
        'wrappedKey': blob,
      });
    }
    return wrapped;
  });
}

Future<Uint8List> isolateUnwrapGroupKey({
  required Uint8List privateSeed,
  required Uint8List wrappedKey,
  required Uint8List associatedData,
}) {
  return Isolate.run(() async {
    final x25519 = X25519();
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final cipher = AesGcm.with256bits();

    final nonceLength = cipher.nonceLength;
    final minimum =
        1 + _wrapPublicKeyLength + nonceLength + _aeadMacLength;
    if (wrappedKey.length < minimum || wrappedKey[0] != _wrapVersion) {
      throw const WrappedKeyException(
        'Format kunci terbungkus tidak dikenal atau rusak.',
      );
    }

    var offset = 1;
    final ephemeralPublic =
        wrappedKey.sublist(offset, offset + _wrapPublicKeyLength);
    offset += _wrapPublicKeyLength;
    final nonce = wrappedKey.sublist(offset, offset + nonceLength);
    offset += nonceLength;
    final macStart = wrappedKey.length - _aeadMacLength;
    final body = wrappedKey.sublist(offset, macStart);
    final mac = wrappedKey.sublist(macStart);

    final pair = await x25519.newKeyPairFromSeed(privateSeed);
    final shared = await x25519.sharedSecretKey(
      keyPair: pair,
      remotePublicKey: SimplePublicKey(
        ephemeralPublic,
        type: KeyPairType.x25519,
      ),
    );
    final info = Uint8List.fromList(<int>[
      ...utf8.encode(_wrapLabel),
      ...associatedData,
    ]);
    final derived = await hkdf.deriveKey(
      secretKey: shared,
      nonce: ephemeralPublic,
      info: info,
    );
    try {
      final clear = await cipher.decrypt(
        SecretBox(body, nonce: nonce, mac: Mac(mac)),
        secretKey: derived,
        aad: associatedData,
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const WrappedKeyException(
        'Kunci terbungkus gagal diautentikasi atau bukan untuk perangkat ini.',
      );
    }
  });
}
