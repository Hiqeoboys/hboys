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
