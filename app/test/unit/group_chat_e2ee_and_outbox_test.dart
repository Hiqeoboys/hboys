import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/chat/application/group_chat_crypto.dart';
import 'package:nama_app/features/groups/domain/group_key_store.dart';
import 'package:nama_app/infrastructure/crypto/crypto_interfaces.dart';

class _InMemoryGroupKeyStore implements GroupKeyStore {
  final Map<String, Uint8List> _keys = <String, Uint8List>{};
  final Map<String, String> _sigs = <String, String>{};

  String _k(String groupId, int version) => '$groupId:v$version';

  @override
  Future<void> writeGroupKey(
    String groupId,
    int keyVersion,
    Uint8List groupKey,
  ) async {
    _keys[_k(groupId, keyVersion)] = Uint8List.fromList(groupKey);
  }

  @override
  Future<Uint8List?> readGroupKey(String groupId, int keyVersion) async =>
      _keys[_k(groupId, keyVersion)];

  @override
  Future<void> deleteGroupKey(String groupId, int keyVersion) async {
    _keys.remove(_k(groupId, keyVersion));
  }

  @override
  Future<String?> readDistributionSignature(
    String groupId,
    int keyVersion,
  ) async =>
      _sigs[_k(groupId, keyVersion)];

  @override
  Future<void> writeDistributionSignature(
    String groupId,
    int keyVersion,
    String signature,
  ) async {
    _sigs[_k(groupId, keyVersion)] = signature;
  }

  @override
  Future<void> deleteDistributionSignature(
    String groupId,
    int keyVersion,
  ) async {
    _sigs.remove(_k(groupId, keyVersion));
  }
}

void main() {
  group('GroupChatCrypto (E2EE AES-256-GCM)', () {
    late _InMemoryGroupKeyStore keyStore;
    late GroupChatCrypto crypto;
    final keyV1 = Uint8List.fromList(List<int>.generate(32, (i) => i + 11));
    final otherKey = Uint8List.fromList(List<int>.generate(32, (i) => 200 - i));

    setUp(() async {
      keyStore = _InMemoryGroupKeyStore();
      await keyStore.writeGroupKey('grp-semeru', 1, keyV1);
      crypto = GroupChatCrypto(keyStore: keyStore);
    });

    test('enkripsi & dekripsi pesan teks: ciphertext berbeda dari plaintext',
        () async {
      const secretBody = 'Tim sudah sampai Pos 3 Ranu Kumbolo, aman semua!';
      final env = await crypto.encryptJson(
        kind: 'text',
        groupId: 'grp-semeru',
        recordId: 'client-uuid-1',
        keyVersion: 1,
        payload: <String, dynamic>{
          'sender_name': 'Raka',
          'body': secretBody,
        },
      );

      // Pastikan ciphertext & nonce tidak memuat teks asli sama sekali
      expect(env.ciphertextBase64, isNotEmpty);
      expect(env.nonceBase64, isNotEmpty);
      expect(env.ciphertextBase64.contains('Pos 3'), isFalse);
      expect(
        utf8.decode(base64Decode(env.ciphertextBase64), allowMalformed: true),
        isNot(contains('Ranu Kumbolo')),
      );

      final clear = await crypto.decryptJson(
        kind: 'text',
        groupId: 'grp-semeru',
        recordId: 'client-uuid-1',
        keyVersion: 1,
        ciphertextBase64: env.ciphertextBase64,
      );
      expect(clear['sender_name'], 'Raka');
      expect(clear['body'], secretBody);
    });

    test('enkripsi & dekripsi biner pesan suara serta lokasi anggota',
        () async {
      final rawAudio = Uint8List.fromList(
        List<int>.generate(128, (i) => (i * 17) & 0xFF),
      );
      final sealedAudio = await crypto.encryptVoiceBytes(
        groupId: 'grp-semeru',
        clientId: 'voice-uuid-1',
        keyVersion: 1,
        plainAudioBytes: rawAudio,
      );
      expect(sealedAudio, isNot(equals(rawAudio)));

      final decodedAudio = await crypto.decryptVoiceBytes(
        groupId: 'grp-semeru',
        clientId: 'voice-uuid-1',
        keyVersion: 1,
        encryptedAudioBytes: sealedAudio,
      );
      expect(decodedAudio, equals(rawAudio));

      final locEnv = await crypto.encryptJson(
        kind: 'member_location',
        groupId: 'grp-semeru',
        recordId: 'user-raka',
        keyVersion: 1,
        payload: <String, dynamic>{
          'display_name': 'Raka',
          'lat': -8.1077,
          'lon': 112.9224,
          'altitude_m': 2400.0,
        },
      );
      expect(locEnv.ciphertextBase64.contains('-8.1077'), isFalse);
      final locClear = await crypto.decryptJson(
        kind: 'member_location',
        groupId: 'grp-semeru',
        recordId: 'user-raka',
        keyVersion: 1,
        ciphertextBase64: locEnv.ciphertextBase64,
      );
      expect(locClear['lat'], -8.1077);
      expect(locClear['lon'], 112.9224);
    });

    test('kunci salah atau AAD berubah menolak dekripsi (autentikasi gagal)',
        () async {
      final env = await crypto.encryptJson(
        kind: 'text',
        groupId: 'grp-semeru',
        recordId: 'msg-1',
        keyVersion: 1,
        payload: <String, dynamic>{'body': 'rahasia'},
      );

      // AAD salah (recordId berbeda)
      await expectLater(
        () => crypto.decryptJson(
          kind: 'text',
          groupId: 'grp-semeru',
          recordId: 'msg-2',
          keyVersion: 1,
          ciphertextBase64: env.ciphertextBase64,
        ),
        throwsA(isA<AeadAuthenticationException>()),
      );

      // Kunci berbeda
      await keyStore.writeGroupKey('grp-semeru', 2, otherKey);
      await expectLater(
        () => crypto.decryptJson(
          kind: 'text',
          groupId: 'grp-semeru',
          recordId: 'msg-1',
          keyVersion: 2,
          ciphertextBase64: env.ciphertextBase64,
        ),
        throwsA(isA<AeadAuthenticationException>()),
      );

      // Kunci tidak ada
      await expectLater(
        () => crypto.decryptJson(
          kind: 'text',
          groupId: 'grp-lain',
          recordId: 'msg-1',
          keyVersion: 1,
          ciphertextBase64: env.ciphertextBase64,
        ),
        throwsA(isA<MissingGroupKeyException>()),
      );
    });
  });
}
