import 'package:supabase_flutter/supabase_flutter.dart';

import '../crypto/crypto_interfaces.dart';

/// Menyimpan sesi Supabase dan code verifier PKCE di keystore/Keychain,
/// bukan di SharedPreferences biasa.
class SecureSupabaseLocalStorage extends LocalStorage {
  const SecureSupabaseLocalStorage(this._store);

  static const String _sessionKey = 'nama.supabase.session.v1';

  final SecretValueStore _store;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async =>
      (await _store.read(_sessionKey))?.isNotEmpty ?? false;

  @override
  Future<String?> accessToken() => _store.read(_sessionKey);

  @override
  Future<void> removePersistedSession() => _store.delete(_sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _store.write(_sessionKey, persistSessionString);
}

class SecureGotrueAsyncStorage extends GotrueAsyncStorage {
  const SecureGotrueAsyncStorage(this._store);

  static const String _prefix = 'nama.supabase.pkce.';

  final SecretValueStore _store;

  @override
  Future<String?> getItem({required String key}) =>
      _store.read('$_prefix$key');

  @override
  Future<void> setItem({
    required String key,
    required String value,
  }) =>
      _store.write('$_prefix$key', value);

  @override
  Future<void> removeItem({required String key}) =>
      _store.delete('$_prefix$key');
}
