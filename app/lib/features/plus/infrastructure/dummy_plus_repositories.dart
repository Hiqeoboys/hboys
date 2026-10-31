import 'package:flutter/foundation.dart';

import '../../../core/utils/clock.dart';
import '../domain/plus_remote_config.dart';
import '../domain/plus_repositories.dart';
import 'dev_entitlement_issuer.dart';
import 'dummy_plus_data.dart';

/// Konfigurasi demo mode debug. Build rilis memakai
/// [UnavailablePlusConfigRepository] sampai backend nyata tersedia.
class DebugPlusConfigRepository implements PlusRemoteConfigRepository {
  const DebugPlusConfigRepository({this.enabled = kDebugMode});

  final bool enabled;

  @override
  Future<PlusRemoteConfig> fetch({required DateTime fetchedAtUtc}) async {
    if (!enabled) {
      throw const PlusConfigUnavailable(
        'Konfigurasi Plus demo tidak aktif di build ini.',
      );
    }
    return PlusRemoteConfig.fromJson(
      debugPlusRemoteConfigJson,
      fetchedAtUtc: fetchedAtUtc,
    );
  }
}

class UnavailablePlusConfigRepository implements PlusRemoteConfigRepository {
  const UnavailablePlusConfigRepository();

  @override
  Future<PlusRemoteConfig> fetch({required DateTime fetchedAtUtc}) async {
    throw const PlusConfigUnavailable(
      'Konfigurasi Plus belum tersedia. Coba lagi beberapa saat lagi.',
    );
  }
}

/// Toko pembelian dummy yang menandatangani token dengan kunci pengembangan.
/// Hanya untuk alur UI di mode debug; tidak menghubungi Play/App Store.
class DebugPlusBillingRepository implements PlusBillingRepository {
  const DebugPlusBillingRepository({
    required this.clock,
    this.durations = debugPlusPlanDurations,
    this.enabled = kDebugMode,
  });

  final Clock clock;
  final Map<String, int?> durations;
  final bool enabled;

  @override
  Future<PlusBillingResult> purchase(String planId) async {
    if (!enabled) {
      return const PlusBillingResult.unavailable(
        'Pembelian Plus belum tersedia di build ini.',
      );
    }
    if (!durations.containsKey(planId)) {
      return const PlusBillingResult.unavailable('Paket tidak dikenal.');
    }
    final days = durations[planId];
    final token = await DevEntitlementIssuer(clock: clock).issue(
      planId: planId,
      duration: days == null ? null : Duration(days: days),
    );
    return PlusBillingResult.purchased(token);
  }

  /// Dummy tidak punya riwayat toko sungguhan, jadi tidak mengarang pembelian.
  @override
  Future<PlusBillingResult> restore() async {
    if (!enabled) {
      return const PlusBillingResult.unavailable(
        'Pemulihan pembelian belum tersedia di build ini.',
      );
    }
    return const PlusBillingResult.nothingToRestore(
      'Belum ada pembelian yang bisa dipulihkan di mode debug.',
    );
  }
}

class UnavailablePlusBillingRepository implements PlusBillingRepository {
  const UnavailablePlusBillingRepository();

  @override
  Future<PlusBillingResult> purchase(String planId) async =>
      const PlusBillingResult.unavailable(
        'Pembelian Plus belum tersedia di versi ini.',
      );

  @override
  Future<PlusBillingResult> restore() async =>
      const PlusBillingResult.unavailable(
        'Pemulihan pembelian belum tersedia di versi ini.',
      );
}
