import 'dart:convert';
import 'dart:typed_data';

import '../../features/groups/domain/group_key_store.dart';
import 'crypto_interfaces.dart';
import 'flutter_secure_value_store.dart';

/// Kunci grup disimpan di keystore/Keychain, bukan di SQLite.
class SecureGroupKeyStore implements GroupKeyStore {
  const SecureGroupKeyStore({required SecretValueStore store}) : _store = store;

  static const String _keyPrefix = 'nama.group_key';
  static const String _signaturePrefix = 'nama.group_distribution';

  static final Map<String, Uint8List> _memoryKeyCache =
      <String, Uint8List>{};
  static final Map<String, String> _memorySigCache = <String, String>{};

  static void clearMemoryCache([String? groupId]) {
    if (groupId == null || groupId.isEmpty) {
      _memoryKeyCache.clear();
      _memorySigCache.clear();
      return;
    }
    final keyPrefix = '$_keyPrefix.$groupId.';
    final sigPrefix = '$_signaturePrefix.$groupId.';
    _memoryKeyCache.removeWhere((key, _) => key.startsWith(keyPrefix));
    _memorySigCache.removeWhere((key, _) => key.startsWith(sigPrefix));
  }

  final SecretValueStore _store;

  bool get _useStaticCache => _store is FlutterSecureValueStore;

  @override
  Future<Uint8List?> readGroupKey(String groupId, int keyVersion) async {
    final storageKey = '$_keyPrefix.$groupId.v$keyVersion';
    if (_useStaticCache) {
      final cached = _memoryKeyCache[storageKey];
      if (cached != null) {
        return Uint8List.fromList(cached);
      }
    }
    final value = await _store.read(storageKey);
    if (value == null) return null;
    try {
      final decoded = Uint8List.fromList(base64Decode(value));
      if (_useStaticCache && decoded.length == 32) {
        _memoryKeyCache[storageKey] = Uint8List.fromList(decoded);
      }
      return decoded;
    } on FormatException {
      await _store.delete(storageKey);
      if (_useStaticCache) {
        _memoryKeyCache.remove(storageKey);
      }
      return null;
    }
  }

  @override
  Future<void> writeGroupKey(
    String groupId,
    int keyVersion,
    Uint8List groupKey,
  ) async {
    final storageKey = '$_keyPrefix.$groupId.v$keyVersion';
    if (_useStaticCache) {
      _memoryKeyCache[storageKey] = Uint8List.fromList(groupKey);
    }
    await _store.write(storageKey, base64Encode(groupKey));
  }

  @override
  Future<void> deleteGroupKey(String groupId, int keyVersion) async {
    final storageKey = '$_keyPrefix.$groupId.v$keyVersion';
    if (_useStaticCache) {
      _memoryKeyCache.remove(storageKey);
    }
    await _store.delete(storageKey);
  }

  @override
  Future<String?> readDistributionSignature(
    String groupId,
    int keyVersion,
  ) async {
    final storageKey = '$_signaturePrefix.$groupId.v$keyVersion';
    if (_useStaticCache) {
      final cached = _memorySigCache[storageKey];
      if (cached != null) return cached;
    }
    final value = await _store.read(storageKey);
    if (value != null && _useStaticCache) {
      _memorySigCache[storageKey] = value;
    }
    return value;
  }

  @override
  Future<void> writeDistributionSignature(
    String groupId,
    int keyVersion,
    String signature,
  ) async {
    final storageKey = '$_signaturePrefix.$groupId.v$keyVersion';
    if (_useStaticCache) {
      _memorySigCache[storageKey] = signature;
    }
    await _store.write(storageKey, signature);
  }

  @override
  Future<void> deleteDistributionSignature(
    String groupId,
    int keyVersion,
  ) async {
    final storageKey = '$_signaturePrefix.$groupId.v$keyVersion';
    if (_useStaticCache) {
      _memorySigCache.remove(storageKey);
    }
    await _store.delete(storageKey);
  }
}
