import 'dart:convert';
import 'dart:typed_data';

import '../../features/groups/domain/group_key_store.dart';
import 'crypto_interfaces.dart';

/// Kunci grup disimpan di keystore/Keychain, bukan di SQLite.
class SecureGroupKeyStore implements GroupKeyStore {
  const SecureGroupKeyStore({required SecretValueStore store}) : _store = store;

  static const String _keyPrefix = 'nama.group_key';
  static const String _signaturePrefix = 'nama.group_distribution';

  final SecretValueStore _store;

  @override
  Future<Uint8List?> readGroupKey(String groupId, int keyVersion) async {
    final storageKey = '$_keyPrefix.$groupId.v$keyVersion';
    final value = await _store.read(storageKey);
    if (value == null) return null;
    try {
      return Uint8List.fromList(base64Decode(value));
    } on FormatException {
      await _store.delete(storageKey);
      return null;
    }
  }

  @override
  Future<void> writeGroupKey(
    String groupId,
    int keyVersion,
    Uint8List groupKey,
  ) =>
      _store.write(
        '$_keyPrefix.$groupId.v$keyVersion',
        base64Encode(groupKey),
      );

  @override
  Future<void> deleteGroupKey(String groupId, int keyVersion) =>
      _store.delete('$_keyPrefix.$groupId.v$keyVersion');

  @override
  Future<String?> readDistributionSignature(
    String groupId,
    int keyVersion,
  ) =>
      _store.read('$_signaturePrefix.$groupId.v$keyVersion');

  @override
  Future<void> writeDistributionSignature(
    String groupId,
    int keyVersion,
    String signature,
  ) =>
      _store.write(
        '$_signaturePrefix.$groupId.v$keyVersion',
        signature,
      );

  @override
  Future<void> deleteDistributionSignature(
    String groupId,
    int keyVersion,
  ) =>
      _store.delete('$_signaturePrefix.$groupId.v$keyVersion');
}
