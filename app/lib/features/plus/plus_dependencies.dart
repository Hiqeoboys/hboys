import 'package:flutter/foundation.dart';

import '../../core/utils/clock.dart';
import 'application/plus_controller.dart';
import 'domain/plus_repositories.dart';
import 'infrastructure/dev_entitlement_issuer.dart';
import 'infrastructure/dummy_plus_repositories.dart';
import 'infrastructure/entitlement_token.dart';
import 'infrastructure/local_plus_stores.dart';

/// Titik rakit Plus untuk aplikasi.
///
/// Kunci publik produksi diisi lewat
/// `--dart-define=PLUS_PUBLIC_KEY=<base64url>`. Tanpa itu, build rilis
/// menolak semua token, sedangkan build debug memakai kunci pengembangan yang
/// cocok dengan toko pembelian dummy.
abstract final class PlusDependencies {
  static final PlusController controller = createDefaultPlusController();
}

PlusController createDefaultPlusController({
  Clock clock = const SystemClock(),
}) {
  return PlusController(
    configRepository: kDebugMode
        ? const DebugPlusConfigRepository()
        : const UnavailablePlusConfigRepository(),
    configStore: const SharedPreferencesPlusConfigStore(),
    entitlementStore: const SharedPreferencesEntitlementLocalStore(),
    verifier: _buildEntitlementVerifier(),
    billing: kDebugMode
        ? DebugPlusBillingRepository(clock: clock)
        : const UnavailablePlusBillingRepository(),
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
