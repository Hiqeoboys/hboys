import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'crypto_interfaces.dart';
import 'crypto_isolate_worker.dart';

/// Identitas perangkat X25519 dan pembungkusan kunci grup.
///
/// Skema bungkusan: X25519 ephemeral + HKDF-SHA256 + AES-256-GCM. Format:
/// versi(1) + kunci publik ephemeral(32) + nonce(12) + ciphertext + MAC(16).
/// Komposisi ini belum diaudit; lihat docs/security_review.md.
class CryptographyIdentityService implements IdentityService, GroupKeyService {
  CryptographyIdentityService({
    required SecretValueStore store,
    X25519? keyExchange,
    AesGcm? cipher,
    Hkdf? hkdf,
  })  : _store = store,
        _useIsolate = keyExchange == null && cipher == null && hkdf == null,
        _x25519 = keyExchange ?? X25519(),
        _cipher = cipher ?? AesGcm.with256bits(),
        _hkdf = hkdf ?? Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static const String _privateKeyStorageKey =
      'nama.crypto.x25519.private.v1';
  static const int _wrapVersion = 1;
  static const int _publicKeyLength = 32;
  static const int _groupKeyLength = 32;
  static const String _wrapLabel = 'nama.group-key-wrap.v1';

  final SecretValueStore _store;
  final bool _useIsolate;
  final X25519 _x25519;
  final AesGcm _cipher;
  final Hkdf _hkdf;

  Future<SimpleKeyPair>? _keyPair;
  Future<Uint8List>? _seedFuture;
  Future<Uint8List>? _publicKeyFuture;

  @override
  Future<Uint8List> publicKey() async {
    if (_useIsolate) {
      return _publicKeyFuture ??= _loadPublicKeyInIsolate();
    }
    final pair = await _loadOrCreateKeyPair();
    final public = await pair.extractPublicKey();
    return Uint8List.fromList(public.bytes);
  }

  Future<Uint8List> _loadPublicKeyInIsolate() async {
    final seed = await _loadOrCreateSeed();
    return isolateExtractX25519PublicKey(seed);
  }

  @override
  Future<Uint8List> generateGroupKey() async {
    final random = SecretKeyData.random(length: _groupKeyLength);
    return Uint8List.fromList(random.bytes);
  }

  @override
  Future<Uint8List> wrapForMember({
    required Uint8List groupKey,
    required Uint8List memberPublicKey,
    required Uint8List associatedData,
  }) async {
    if (_useIsolate) {
      return isolateWrapGroupKeyForMember(
        groupKey: groupKey,
        memberPublicKey: memberPublicKey,
        associatedData: associatedData,
      );
    }
    if (groupKey.length != _groupKeyLength) {
      throw ArgumentError.value(
        groupKey.length,
        'groupKey',
        'Kunci grup harus 32 byte',
      );
    }
    if (memberPublicKey.length != _publicKeyLength) {
      throw const WrappedKeyException(
        'Kunci publik anggota harus $_publicKeyLength byte.',
      );
    }

    final ephemeral = await _x25519.newKeyPair();
    final ephemeralPublic = await ephemeral.extractPublicKey();
    final derived = await _deriveWrapKey(
      ephemeral: ephemeral,
      ephemeralPublic: ephemeralPublic.bytes,
      recipientPublicKey: memberPublicKey,
      associatedData: associatedData,
    );
    final box = await _cipher.encrypt(
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

  /// Wraps a group key for multiple recipients in one background isolate batch.
  Future<List<Map<String, Object>>> wrapForMembersBatch({
    required Uint8List groupKey,
    required List<Map<String, Object>> recipients,
    required Uint8List associatedData,
  }) async {
    if (_useIsolate) {
      return isolateWrapGroupKeyBatch(
        groupKey: groupKey,
        recipients: recipients,
        associatedData: associatedData,
      );
    }
    final result = <Map<String, Object>>[];
    for (final item in recipients) {
      final userId = item['userId'] as String;
      final publicKey = item['publicKey'] as Uint8List;
      final wrappedKey = await wrapForMember(
        groupKey: groupKey,
        memberPublicKey: publicKey,
        associatedData: associatedData,
      );
      result.add(<String, Object>{
        'userId': userId,
        'wrappedKey': wrappedKey,
      });
    }
    return result;
  }

  @override
  Future<Uint8List> unwrap({
    required Uint8List wrappedKey,
    required Uint8List associatedData,
  }) async {
    if (_useIsolate) {
      final seed = await _loadOrCreateSeed();
      return isolateUnwrapGroupKey(
        privateSeed: seed,
        wrappedKey: wrappedKey,
        associatedData: associatedData,
      );
    }
    final nonceLength = _cipher.nonceLength;
    const macLength = 16;
    final minimum =
        1 + _publicKeyLength + nonceLength + macLength;
    if (wrappedKey.length < minimum || wrappedKey[0] != _wrapVersion) {
      throw const WrappedKeyException(
        'Format kunci terbungkus tidak dikenal atau rusak.',
      );
    }

    var offset = 1;
    final ephemeralPublic =
        wrappedKey.sublist(offset, offset + _publicKeyLength);
    offset += _publicKeyLength;
    final nonce = wrappedKey.sublist(offset, offset + nonceLength);
    offset += nonceLength;
    final macStart = wrappedKey.length - macLength;
    final body = wrappedKey.sublist(offset, macStart);
    final mac = wrappedKey.sublist(macStart);

    final pair = await _loadOrCreateKeyPair();
    final derived = await _deriveWrapKey(
      ephemeral: pair,
      ephemeralPublic: ephemeralPublic,
      recipientPublicKey: null,
      associatedData: associatedData,
    );
    try {
      final clear = await _cipher.decrypt(
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
  }

  Future<SecretKey> _deriveWrapKey({
    required SimpleKeyPair ephemeral,
    required List<int> ephemeralPublic,
    required List<int>? recipientPublicKey,
    required Uint8List associatedData,
  }) async {
    final remote = recipientPublicKey ?? ephemeralPublic;
    final shared = await _x25519.sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: SimplePublicKey(
        remote,
        type: KeyPairType.x25519,
      ),
    );
    final info = Uint8List.fromList([
      ...utf8.encode(_wrapLabel),
      ...associatedData,
    ]);
    return _hkdf.deriveKey(
      secretKey: shared,
      nonce: ephemeralPublic,
      info: info,
    );
  }

  Future<Uint8List> _loadOrCreateSeed() {
    return _seedFuture ??= _loadOrCreateSeedOnce();
  }

  Future<Uint8List> _loadOrCreateSeedOnce() async {
    final stored = await _store.read(_privateKeyStorageKey);
    if (stored != null) {
      try {
        final bytes = base64Decode(stored);
        if (bytes.length == 32) {
          return Uint8List.fromList(bytes);
        }
      } on FormatException {
        // Nilai rusak dihapus dan diganti; kunci lama tidak bisa dipulihkan.
      }
      await _store.delete(_privateKeyStorageKey);
    }
    final generated = await isolateGenerateX25519KeyPair();
    final seed = generated['seed']!;
    final publicKey = generated['publicKey']!;
    _publicKeyFuture = Future<Uint8List>.value(publicKey);
    await _store.write(
      _privateKeyStorageKey,
      base64Encode(seed),
    );
    return seed;
  }

  Future<SimpleKeyPair> _loadOrCreateKeyPair() {
    return _keyPair ??= _loadOrCreateKeyPairOnce();
  }

  Future<SimpleKeyPair> _loadOrCreateKeyPairOnce() async {
    final stored = await _store.read(_privateKeyStorageKey);
    if (stored != null) {
      try {
        final bytes = base64Decode(stored);
        if (bytes.length == 32) {
          return await _x25519.newKeyPairFromSeed(bytes);
        }
      } on FormatException {
        // Nilai rusak dihapus dan diganti; kunci lama tidak bisa dipulihkan.
      }
      await _store.delete(_privateKeyStorageKey);
    }
    final pair = await _x25519.newKeyPair();
    final privateBytes = await pair.extractPrivateKeyBytes();
    await _store.write(
      _privateKeyStorageKey,
      base64Encode(privateBytes),
    );
    return pair;
  }
}
