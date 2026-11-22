import 'plus_entitlement.dart';
import 'plus_remote_config.dart';

/// Konfigurasi jarak jauh tidak tersedia (belum ada backend, offline pertama
/// kali, atau build tanpa kredensial). Bukan kesalahan fatal: cache dipakai.
class PlusConfigUnavailable implements Exception {
  const PlusConfigUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class PlusRemoteConfigRepository {
  Future<PlusRemoteConfig> fetch({required DateTime fetchedAtUtc});
}

abstract interface class PlusConfigStore {
  Future<PlusRemoteConfig?> read();
  Future<void> write(PlusRemoteConfig config);
}

abstract interface class EntitlementLocalStore {
  Future<String?> readToken();
  Future<void> writeToken(String token);
  Future<void> clearToken();

  /// Waktu pemeriksaan tertinggi yang pernah tercatat. Dipakai agar jam
  /// perangkat yang dimundurkan tidak memperpanjang masa berlaku token.
  Future<DateTime?> readLastSeenUtc();
  Future<void> writeLastSeenUtc(DateTime value);
}

/// Hak akses Hiqeo Plus yang disinkronkan dari akun Supabase dan disimpan di
/// cache lokal agar seluruh fitur Plus tetap aktif ketika perangkat offline.
class AccountPlusGrant {
  const AccountPlusGrant({
    required this.userId,
    required this.isPlus,
    this.planId,
    this.expiresAtUtc,
    required this.syncedAtUtc,
  });

  final String userId;
  final bool isPlus;
  final String? planId;
  final DateTime? expiresAtUtc;
  final DateTime syncedAtUtc;

  Map<String, Object?> toJson() => <String, Object?>{
        'user_id': userId,
        'is_plus': isPlus,
        'plan_id': planId,
        'expires_at': expiresAtUtc?.toUtc().toIso8601String(),
        'synced_at': syncedAtUtc.toUtc().toIso8601String(),
      };

  static AccountPlusGrant? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final userId = raw['user_id'];
    final isPlus = raw['is_plus'];
    if (userId is! String || userId.trim().isEmpty || isPlus is! bool) {
      return null;
    }
    final rawExp = raw['expires_at'];
    final expiresAt =
        rawExp is String ? DateTime.tryParse(rawExp)?.toUtc() : null;
    final rawSynced = raw['synced_at'];
    final syncedAt = (rawSynced is String
            ? DateTime.tryParse(rawSynced)?.toUtc()
            : null) ??
        DateTime.now().toUtc();
    return AccountPlusGrant(
      userId: userId,
      isPlus: isPlus,
      planId: raw['plan_id'] as String?,
      expiresAtUtc: expiresAt,
      syncedAtUtc: syncedAt,
    );
  }
}

/// Cache lokal status Hiqeo Plus hasil sinkronisasi akun (offline-first).
abstract interface class AccountPlusCacheStore {
  Future<AccountPlusGrant?> read();
  Future<void> write(AccountPlusGrant grant);
  Future<void> clear();
}

abstract interface class EntitlementVerifier {
  /// Mengembalikan null bila tanda tangan, format, atau isi token tidak sah.
  Future<EntitlementPayload?> verify(String token);
}

enum PlusBillingStatus { purchased, cancelled, nothingToRestore, unavailable }

class PlusBillingResult {
  const PlusBillingResult.purchased(String this.token)
      : status = PlusBillingStatus.purchased,
        message = null;

  const PlusBillingResult.cancelled()
      : status = PlusBillingStatus.cancelled,
        token = null,
        message = null;

  const PlusBillingResult.nothingToRestore([this.message])
      : status = PlusBillingStatus.nothingToRestore,
        token = null;

  const PlusBillingResult.unavailable(this.message)
      : status = PlusBillingStatus.unavailable,
        token = null;

  final PlusBillingStatus status;
  final String? token;
  final String? message;
}

/// Antarmuka toko pembelian. Implementasi nyata (Play Billing/StoreKit) belum
/// ada pada tahap ini; dummy debug menerbitkan token bertanda tangan lokal.
abstract interface class PlusBillingRepository {
  Future<PlusBillingResult> purchase(String planId);
  Future<PlusBillingResult> restore();
}
