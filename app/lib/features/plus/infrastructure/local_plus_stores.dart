import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../infrastructure/crypto/crypto_interfaces.dart';
import '../../../infrastructure/crypto/flutter_secure_value_store.dart';
import '../domain/leaderboard.dart';
import '../domain/plus_remote_config.dart';
import '../domain/plus_repositories.dart';

class SharedPreferencesPlusConfigStore implements PlusConfigStore {
  const SharedPreferencesPlusConfigStore();

  static const String key = 'plus_remote_config_v1';

  @override
  Future<PlusRemoteConfig?> read() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return PlusRemoteConfig.fromJson(
        Map<String, Object?>.from(decoded),
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(PlusRemoteConfig config) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, jsonEncode(config.toJson()));
  }
}

class InMemoryPlusConfigStore implements PlusConfigStore {
  InMemoryPlusConfigStore([this.config]);

  PlusRemoteConfig? config;
  int writes = 0;

  @override
  Future<PlusRemoteConfig?> read() async => config;

  @override
  Future<void> write(PlusRemoteConfig config) async {
    this.config = config;
    writes++;
  }
}

class SharedPreferencesEntitlementLocalStore implements EntitlementLocalStore {
  const SharedPreferencesEntitlementLocalStore();

  static const String tokenKey = 'plus_entitlement_token_v1';
  static const String lastSeenKey = 'plus_entitlement_last_seen_v1';

  @override
  Future<String?> readToken() async {
    final preferences = await SharedPreferences.getInstance();
    final token = preferences.getString(tokenKey);
    return token == null || token.isEmpty ? null : token;
  }

  @override
  Future<void> writeToken(String token) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(tokenKey, token);
  }

  @override
  Future<void> clearToken() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(tokenKey);
  }

  @override
  Future<DateTime?> readLastSeenUtc() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(lastSeenKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  @override
  Future<void> writeLastSeenUtc(DateTime value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      lastSeenKey,
      value.toUtc().toIso8601String(),
    );
  }
}

class SharedPreferencesLeaderboardConsentStore
    implements LeaderboardConsentStore {
  const SharedPreferencesLeaderboardConsentStore();

  static const String visibleKey = 'leaderboard_consent_visible_v1';

  @override
  Future<bool?> readVisible() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(visibleKey);
  }

  @override
  Future<void> writeVisible(bool visible) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(visibleKey, visible);
  }
}

class InMemoryLeaderboardConsentStore implements LeaderboardConsentStore {
  InMemoryLeaderboardConsentStore([this.visible]);

  bool? visible;
  int writes = 0;

  @override
  Future<bool?> readVisible() async => visible;

  @override
  Future<void> writeVisible(bool value) async {
    visible = value;
    writes++;
  }
}

class InMemoryEntitlementLocalStore implements EntitlementLocalStore {
  InMemoryEntitlementLocalStore({this.token, this.lastSeenUtc});

  String? token;
  DateTime? lastSeenUtc;
  int tokenWrites = 0;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> writeToken(String token) async {
    this.token = token;
    tokenWrites++;
  }

  @override
  Future<void> clearToken() async {
    token = null;
  }

  @override
  Future<DateTime?> readLastSeenUtc() async => lastSeenUtc;

  @override
  Future<void> writeLastSeenUtc(DateTime value) async {
    lastSeenUtc = value;
  }
}

class SharedPreferencesAccountPlusCacheStore implements AccountPlusCacheStore {
  const SharedPreferencesAccountPlusCacheStore();

  static const String key = 'plus_account_entitlement_v1';

  @override
  Future<AccountPlusGrant?> read() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return AccountPlusGrant.tryParse(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(AccountPlusGrant grant) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, jsonEncode(grant.toJson()));
  }

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(key);
  }
}

class InMemoryAccountPlusCacheStore implements AccountPlusCacheStore {
  InMemoryAccountPlusCacheStore([this.grant]);

  AccountPlusGrant? grant;
  int writes = 0;

  @override
  Future<AccountPlusGrant?> read() async => grant;

  @override
  Future<void> write(AccountPlusGrant value) async {
    grant = value;
    writes++;
  }

  @override
  Future<void> clear() async {
    grant = null;
  }
}

/// Keystore/Keychain-backed entitlement store with one-time SharedPreferences migration.
class SecureEntitlementLocalStore implements EntitlementLocalStore {
  const SecureEntitlementLocalStore({
    SecretValueStore store = const FlutterSecureValueStore(),
  }) : _store = store;

  final SecretValueStore _store;

  @override
  Future<String?> readToken() async {
    final token = await _store.read(SharedPreferencesEntitlementLocalStore.tokenKey);
    if (token != null && token.isNotEmpty) return token;
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(SharedPreferencesEntitlementLocalStore.tokenKey);
    if (legacy != null && legacy.isNotEmpty) {
      await _store.write(SharedPreferencesEntitlementLocalStore.tokenKey, legacy);
      await prefs.remove(SharedPreferencesEntitlementLocalStore.tokenKey);
      return legacy;
    }
    return null;
  }

  @override
  Future<void> writeToken(String token) =>
      _store.write(SharedPreferencesEntitlementLocalStore.tokenKey, token);

  @override
  Future<void> clearToken() async {
    await _store.delete(SharedPreferencesEntitlementLocalStore.tokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(SharedPreferencesEntitlementLocalStore.tokenKey);
  }

  @override
  Future<DateTime?> readLastSeenUtc() async {
    final raw = await _store.read(SharedPreferencesEntitlementLocalStore.lastSeenKey);
    if (raw != null && raw.isNotEmpty) {
      return DateTime.tryParse(raw)?.toUtc();
    }
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(SharedPreferencesEntitlementLocalStore.lastSeenKey);
    if (legacy != null && legacy.isNotEmpty) {
      await _store.write(SharedPreferencesEntitlementLocalStore.lastSeenKey, legacy);
      await prefs.remove(SharedPreferencesEntitlementLocalStore.lastSeenKey);
      return DateTime.tryParse(legacy)?.toUtc();
    }
    return null;
  }

  @override
  Future<void> writeLastSeenUtc(DateTime value) => _store.write(
        SharedPreferencesEntitlementLocalStore.lastSeenKey,
        value.toUtc().toIso8601String(),
      );
}

/// Keystore/Keychain-backed account Plus cache with one-time SharedPreferences migration.
class SecureAccountPlusCacheStore implements AccountPlusCacheStore {
  const SecureAccountPlusCacheStore({
    SecretValueStore store = const FlutterSecureValueStore(),
  }) : _store = store;

  final SecretValueStore _store;

  @override
  Future<AccountPlusGrant?> read() async {
    var raw = await _store.read(SharedPreferencesAccountPlusCacheStore.key);
    if (raw == null || raw.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(SharedPreferencesAccountPlusCacheStore.key);
      if (legacy != null && legacy.isNotEmpty) {
        await _store.write(SharedPreferencesAccountPlusCacheStore.key, legacy);
        await prefs.remove(SharedPreferencesAccountPlusCacheStore.key);
        raw = legacy;
      }
    }
    if (raw == null || raw.isEmpty) return null;
    try {
      return AccountPlusGrant.tryParse(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(AccountPlusGrant grant) => _store.write(
        SharedPreferencesAccountPlusCacheStore.key,
        jsonEncode(grant.toJson()),
      );

  @override
  Future<void> clear() async {
    await _store.delete(SharedPreferencesAccountPlusCacheStore.key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(SharedPreferencesAccountPlusCacheStore.key);
  }
}
