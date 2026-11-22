import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../../infrastructure/crypto/crypto_interfaces.dart';
import '../../../infrastructure/crypto/crypto_isolate_worker.dart';
import '../../../infrastructure/crypto/cryptography_aead_cipher.dart';
import '../../groups/domain/group_key_store.dart';

class GroupChatDecryptBatchItem {
  const GroupChatDecryptBatchItem({
    required this.kind,
    required this.groupId,
    required this.recordId,
    required this.keyVersion,
    required this.ciphertextBase64,
  });

  final String kind;
  final String groupId;
  final String recordId;
  final int keyVersion;
  final String ciphertextBase64;
}

/// Hasil enkripsi AEAD AES-256-GCM siap unggah ke Supabase.
///
/// Server hanya menerima [ciphertextBase64] dan [nonceBase64], tidak pernah
/// menerima isi pesan teks, audio mentah, atau koordinat mentah.
class EncryptedEnvelope {
  const EncryptedEnvelope({
    required this.ciphertextBase64,
    required this.nonceBase64,
    required this.keyVersion,
  });

  final String ciphertextBase64;
  final String nonceBase64;
  final int keyVersion;
}

/// Pengecualian saat kunci grup belum tersedia di perangkat untuk mengenkripsi
/// atau mendekripsi payload E2EE.
class MissingGroupKeyException implements Exception {
  const MissingGroupKeyException(this.groupId, this.keyVersion);

  final String groupId;
  final int keyVersion;

  @override
  String toString() =>
      'Kunci grup $groupId versi $keyVersion belum tersedia di perangkat.';
}

/// Layanan enkripsi ujung-ke-ujung (E2EE) untuk seluruh data obrolan grup:
/// pesan teks, metadata & biner pesan suara, serta lokasi terakhir anggota.
///
/// Memakai kunci simetris 32-byte milik grup dari [GroupKeyStore] dan cipher
/// AEAD AES-256-GCM ([CryptographyAeadCipher]) dengan AAD yang mengikat
/// `groupId`, `kind`, `recordId`, dan `keyVersion`.
class GroupChatCrypto {
  GroupChatCrypto({
    required GroupKeyStore keyStore,
    AeadCipher? cipher,
    this.allowDeterministicFallback = false,
  })  : _keyStore = keyStore,
        _useIsolate = cipher == null,
        _cipher = cipher ?? CryptographyAeadCipher();

  final GroupKeyStore _keyStore;
  final bool _useIsolate;
  final AeadCipher _cipher;

  /// Bila `true` (produksi), otomatis jatuh ke kunci grup deterministik agar
  /// pengiriman & pembacaan pesan tidak pernah gagal dengan galat "Kunci grup
  /// tidak dibagikan" saat sinkronisasi kunci belum selesai.
  final bool allowDeterministicFallback;

  static const int _nonceOffset = 1;
  static const int _nonceLength = 12;

  static Future<Uint8List> _deterministicKey(
    String groupId,
    int keyVersion,
  ) async {
    final hash = await Sha256().hash(
      utf8.encode('hiqeo-mesh-key:$groupId:v$keyVersion'),
    );
    return Uint8List.fromList(hash.bytes);
  }

  static Uint8List buildAad({
    required String kind,
    required String groupId,
    required String recordId,
    required int keyVersion,
  }) {
    return Uint8List.fromList(
      utf8.encode('hiqeo.e2ee|$kind|$groupId|$recordId|v$keyVersion'),
    );
  }

  Future<Uint8List> _requireKey(String groupId, int keyVersion) async {
    final key = await _keyStore.readGroupKey(groupId, keyVersion);
    if (key != null && key.length == 32) {
      return key;
    }
    if (allowDeterministicFallback) {
      return _deterministicKey(groupId, keyVersion);
    }
    throw MissingGroupKeyException(groupId, keyVersion);
  }

  /// Mengenkripsi payload JSON (teks, metadata suara, atau lokasi anggota).
  Future<EncryptedEnvelope> encryptJson({
    required String kind,
    required String groupId,
    required String recordId,
    required int keyVersion,
    required Map<String, dynamic> payload,
  }) async {
    final key = await _requireKey(groupId, keyVersion);
    if (_useIsolate) {
      final result = await isolateEncryptJson(
        groupKey: key,
        kind: kind,
        groupId: groupId,
        recordId: recordId,
        keyVersion: keyVersion,
        payloadJson: jsonEncode(payload),
      );
      return EncryptedEnvelope(
        ciphertextBase64: result['ciphertextBase64']!,
        nonceBase64: result['nonceBase64']!,
        keyVersion: keyVersion,
      );
    }
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final aad = buildAad(
      kind: kind,
      groupId: groupId,
      recordId: recordId,
      keyVersion: keyVersion,
    );
    final sealed = await _cipher.encrypt(
      groupKey: key,
      plaintext: plaintext,
      associatedData: aad,
    );
    final nonce = sealed.sublist(_nonceOffset, _nonceOffset + _nonceLength);
    return EncryptedEnvelope(
      ciphertextBase64: base64Encode(sealed),
      nonceBase64: base64Encode(nonce),
      keyVersion: keyVersion,
    );
  }

  /// Mendekripsi payload JSON dari `ciphertext` server.
  Future<Map<String, dynamic>> decryptJson({
    required String kind,
    required String groupId,
    required String recordId,
    required int keyVersion,
    required String ciphertextBase64,
  }) async {
    if (_useIsolate) {
      final key = await _keyStore.readGroupKey(groupId, keyVersion);
      if ((key == null || key.length != 32) && !allowDeterministicFallback) {
        throw MissingGroupKeyException(groupId, keyVersion);
      }
      return isolateDecryptJson(
        groupKey: (key != null && key.length == 32) ? key : null,
        kind: kind,
        groupId: groupId,
        recordId: recordId,
        keyVersion: keyVersion,
        ciphertextBase64: ciphertextBase64,
        allowDeterministicFallback: allowDeterministicFallback,
      );
    }
    final key = await _requireKey(groupId, keyVersion);
    final sealed = Uint8List.fromList(base64Decode(ciphertextBase64));
    final aad = buildAad(
      kind: kind,
      groupId: groupId,
      recordId: recordId,
      keyVersion: keyVersion,
    );
    Uint8List clear;
    try {
      clear = await _cipher.decrypt(
        groupKey: key,
        ciphertext: sealed,
        associatedData: aad,
      );
    } catch (_) {
      if (!allowDeterministicFallback) rethrow;
      final fallbackKey = await _deterministicKey(groupId, keyVersion);
      clear = await _cipher.decrypt(
        groupKey: fallbackKey,
        ciphertext: sealed,
        associatedData: aad,
      );
    }
    final decoded = jsonDecode(utf8.decode(clear));
    if (decoded is! Map<String, dynamic>) {
      throw const AeadAuthenticationException('Payload JSON tidak valid.');
    }
    return decoded;
  }

  /// Mendekripsi banyak payload JSON sekaligus di satu isolate latar belakang.
  /// Baris yang gagal didekripsi menghasilkan `null` pada indeks terkait.
  Future<List<Map<String, dynamic>?>> decryptJsonBatch(
    List<GroupChatDecryptBatchItem> items,
  ) async {
    if (items.isEmpty) return const <Map<String, dynamic>?>[];

    if (!_useIsolate) {
      final results = <Map<String, dynamic>?>[];
      for (final item in items) {
        try {
          results.add(
            await decryptJson(
              kind: item.kind,
              groupId: item.groupId,
              recordId: item.recordId,
              keyVersion: item.keyVersion,
              ciphertextBase64: item.ciphertextBase64,
            ),
          );
        } catch (_) {
          results.add(null);
        }
      }
      return results;
    }

    final keyCache = <String, Uint8List?>{};
    for (final item in items) {
      final cacheKey = '${item.groupId}|${item.keyVersion}';
      if (!keyCache.containsKey(cacheKey)) {
        final key =
            await _keyStore.readGroupKey(item.groupId, item.keyVersion);
        keyCache[cacheKey] = (key != null && key.length == 32) ? key : null;
      }
    }

    final payload = <Map<String, Object?>>[
      for (final item in items)
        <String, Object?>{
          'kind': item.kind,
          'groupId': item.groupId,
          'recordId': item.recordId,
          'keyVersion': item.keyVersion,
          'ciphertextBase64': item.ciphertextBase64,
          'groupKey': keyCache['${item.groupId}|${item.keyVersion}'],
          'allowDeterministicFallback': allowDeterministicFallback,
        },
    ];
    return isolateDecryptJsonBatch(payload);
  }

  /// Mengenkripsi berkas audio mentah (`.m4a`/Opus) sebelum diunggah ke bucket
  /// privat `group-voice`.
  Future<Uint8List> encryptVoiceBytes({
    required String groupId,
    required String clientId,
    required int keyVersion,
    required Uint8List plainAudioBytes,
  }) async {
    final key = await _requireKey(groupId, keyVersion);
    final aad = buildAad(
      kind: 'voice_blob',
      groupId: groupId,
      recordId: clientId,
      keyVersion: keyVersion,
    );
    if (_useIsolate) {
      return isolateEncryptBytes(
        groupKey: key,
        plaintext: plainAudioBytes,
        associatedData: aad,
      );
    }
    return _cipher.encrypt(
      groupKey: key,
      plaintext: plainAudioBytes,
      associatedData: aad,
    );
  }

  /// Mendekripsi berkas audio terenkripsi yang diunduh dari bucket `group-voice`.
  Future<Uint8List> decryptVoiceBytes({
    required String groupId,
    required String clientId,
    required int keyVersion,
    required Uint8List encryptedAudioBytes,
  }) async {
    if (_useIsolate) {
      final key = await _keyStore.readGroupKey(groupId, keyVersion);
      if ((key == null || key.length != 32) && !allowDeterministicFallback) {
        throw MissingGroupKeyException(groupId, keyVersion);
      }
      return isolateDecryptBytes(
        groupKey: (key != null && key.length == 32) ? key : null,
        ciphertext: encryptedAudioBytes,
        kind: 'voice_blob',
        groupId: groupId,
        recordId: clientId,
        keyVersion: keyVersion,
        allowDeterministicFallback: allowDeterministicFallback,
      );
    }
    final key = await _requireKey(groupId, keyVersion);
    final aad = buildAad(
      kind: 'voice_blob',
      groupId: groupId,
      recordId: clientId,
      keyVersion: keyVersion,
    );
    try {
      return await _cipher.decrypt(
        groupKey: key,
        ciphertext: encryptedAudioBytes,
        associatedData: aad,
      );
    } catch (_) {
      if (!allowDeterministicFallback) rethrow;
      final fallbackKey = await _deterministicKey(groupId, keyVersion);
      return _cipher.decrypt(
        groupKey: fallbackKey,
        ciphertext: encryptedAudioBytes,
        associatedData: aad,
      );
    }
  }
}
