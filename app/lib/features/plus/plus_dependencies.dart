import 'package:flutter/foundation.dart';

import '../../config/plans.dart';
import '../../core/utils/clock.dart';
import 'application/plus_controller.dart';
import 'domain/plus_repositories.dart';
import 'infrastructure/dev_entitlement_issuer.dart';
import 'infrastructure/entitlement_token.dart';
import 'infrastructure/local_plus_stores.dart';

/// Titik rakit Plus untuk aplikasi.
///
/// Kunci publik produksi diisi lewat
/// `--dart-define=PLUS_PUBLIC_KEY=<base64url>`. Sebelum payment gateway
/// disambungkan, aplikasi memakai [MockSubscriptionRepository] sehingga tombol
/// "Berlangganan" menampilkan "Pembayaran belum tersedia" dan tidak
/// mengaktifkan status Plus secara palsu.
abstract final class PlusDependencies {
  static final PlusController controller = createDefaultPlusController();
}

PlusController createDefaultPlusController({
  Clock clock = const SystemClock(),
  SubscriptionRepository subscriptionRepository =
      const MockSubscriptionRepository(),
}) {
  return PlusController(
    configRepository: subscriptionRepository,
    configStore: const SharedPreferencesPlusConfigStore(),
    entitlementStore: const SecureEntitlementLocalStore(),
    verifier: _buildEntitlementVerifier(),
    billing: subscriptionRepository,
    accountPlusStore: const SecureAccountPlusCacheStore(),
    clock: clock,
  );
}

EntitlementVerifier _buildEntitlementVerifier() {
  const configuredPublicKey = String.fromEnvironment('PLUS_PUBLIC_KEY');
  if (configuredPublicKey.isNotEmpty) {
    return const Ed25519EntitlementVerifier(
      publicKeyBase64Url: configuredPublicKey,
    );
  }
  if (kDebugMode) {
    return const Ed25519EntitlementVerifier(
      publicKeyBase64Url: DevelopmentPlusKeys.publicKeyBase64Url,
    );
  }
  return const RejectingEntitlementVerifier();
}
