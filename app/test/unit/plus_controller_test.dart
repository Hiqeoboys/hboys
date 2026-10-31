import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/core/utils/clock.dart';
import 'package:nama_app/features/plus/application/plus_controller.dart';
import 'package:nama_app/features/plus/domain/plus_entitlement.dart';
import 'package:nama_app/features/plus/domain/plus_plan.dart';
import 'package:nama_app/features/plus/domain/plus_remote_config.dart';
import 'package:nama_app/features/plus/domain/plus_repositories.dart';
import 'package:nama_app/features/plus/infrastructure/dev_entitlement_issuer.dart';
import 'package:nama_app/features/plus/infrastructure/dummy_plus_repositories.dart';
import 'package:nama_app/features/plus/infrastructure/entitlement_token.dart';
import 'package:nama_app/features/plus/infrastructure/local_plus_stores.dart';

class _FakeConfigRepository implements PlusRemoteConfigRepository {
  _FakeConfigRepository(this.config);

  PlusRemoteConfig? config;
  bool fail = false;
  int fetches = 0;

  @override
  Future<PlusRemoteConfig> fetch({required DateTime fetchedAtUtc}) async {
    fetches++;
    final current = config;
    if (fail || current == null) {
      throw const PlusConfigUnavailable('offline');
    }
    return PlusRemoteConfig(
      plans: current.plans,
      graceDays: current.graceDays,
      flags: current.flags,
      fetchedAtUtc: fetchedAtUtc,
    );
  }
}

class _FakeVerifier implements EntitlementVerifier {
  _FakeVerifier([Map<String, EntitlementPayload>? tokens])
      : tokens = tokens ?? <String, EntitlementPayload>{};

  final Map<String, EntitlementPayload> tokens;
  int verifications = 0;

  @override
  Future<EntitlementPayload?> verify(String token) async {
    verifications++;
    return tokens[token];
  }
}

class _FakeBilling implements PlusBillingRepository {
  PlusBillingResult purchaseResult =
      const PlusBillingResult.unavailable('belum diatur');
  PlusBillingResult restoreResult = const PlusBillingResult.nothingToRestore();
  String? lastPlanId;
  int purchaseCalls = 0;
  int restoreCalls = 0;

  @override
  Future<PlusBillingResult> purchase(String planId) async {
    purchaseCalls++;
    lastPlanId = planId;
    return purchaseResult;
  }

  @override
  Future<PlusBillingResult> restore() async {
    restoreCalls++;
    return restoreResult;
  }
}

EntitlementPayload _payload({
  String planId = 'annual',
  DateTime? expiresAtUtc,
}) =>
    EntitlementPayload(
      version: EntitlementPayload.currentVersion,
      subject: 'local-device',
      planId: planId,
      issuedAtUtc: DateTime.utc(2026, 1, 1),
      expiresAtUtc: expiresAtUtc,
    );

PlusRemoteConfig _config({
  required DateTime fetchedAtUtc,
  int graceDays = 10,
  bool leaderboard = true,
  bool peakBadges = true,
}) =>
    PlusRemoteConfig(
      plans: const <PlusPlan>[
        PlusPlan(
          id: 'annual',
          title: 'Hiqeo Plus Tahunan',
          priceLabel: 'Rp 249.000',
          periodLabel: 'per tahun',
          durationDays: 365,
        ),
      ],
      graceDays: graceDays,
      flags: PlusFeatureFlags(
        leaderboard: leaderboard,
        peakBadges: peakBadges,
      ),
      fetchedAtUtc: fetchedAtUtc,
    );

void main() {
  group('PlusController tanpa jaringan', () {
    test('memakai cache konfigurasi dan token yang tersimpan', () async {
      final now = DateTime.utc(2026, 6, 1, 8);
      final clock = FakeClock(now);
      final configRepository =
          _FakeConfigRepository(_config(fetchedAtUtc: now));
      final configStore = InMemoryPlusConfigStore(
        _config(fetchedAtUtc: now, leaderboard: false),
      );
      final entitlementStore = InMemoryEntitlementLocalStore(
        token: 'token-aktif',
      );
      final verifier = _FakeVerifier(<String, EntitlementPayload>{
        'token-aktif': _payload(expiresAtUtc: DateTime.utc(2027, 6, 1)),
      });
      final controller = PlusController(
        configRepository: configRepository,
        configStore: configStore,
        entitlementStore: entitlementStore,
        verifier: verifier,
        billing: _FakeBilling(),
        clock: clock,
      );

      await controller.loadCached();

      expect(controller.isLoaded, isTrue);
      expect(controller.hasPlus, isTrue);
      expect(controller.access.state, PlusAccessState.active);
      expect(controller.plans.single.id, 'annual');
      expect(controller.leaderboardEnabled, isFalse);
      expect(configRepository.fetches, 0);
      expect(verifier.verifications, 1);
    });

    test('token tidak sah dihapus dan pengguna tetap gratis', () async {
      final now = DateTime.utc(2026, 6, 1, 8);
      final clock = FakeClock(now);
      final entitlementStore = InMemoryEntitlementLocalStore(
        token: 'token-palsu',
      );
      final controller = PlusController(
        configRepository: _FakeConfigRepository(_config(fetchedAtUtc: now)),
        configStore: InMemoryPlusConfigStore(),
        entitlementStore: entitlementStore,
        verifier: _FakeVerifier(),
        billing: _FakeBilling(),
        clock: clock,
      );

      await controller.loadCached();

      expect(controller.hasPlus, isFalse);
      expect(controller.access, PlusAccess.free);
      expect(entitlementStore.token, isNull);
    });

    test('tanpa konfigurasi, tenggang memakai batas bawah 7 hari', () async {
      final expiresAt = DateTime.utc(2026, 1, 10);
      final clock = FakeClock(DateTime.utc(2026, 1, 16));
      final controller = PlusController(
        configRepository: _FakeConfigRepository(null),
        configStore: InMemoryPlusConfigStore(),
        entitlementStore: InMemoryEntitlementLocalStore(token: 'token'),
        verifier: _FakeVerifier(<String, EntitlementPayload>{
          'token': _payload(expiresAtUtc: expiresAt),
        }),
        billing: _FakeBilling(),
        clock: clock,
      );

      await controller.loadCached();

      expect(controller.access.state, PlusAccessState.grace);
      expect(controller.access.graceEndsAtUtc, DateTime.utc(2026, 1, 17));
      expect(controller.leaderboardEnabled, isFalse);
      expect(controller.peakBadgesEnabled, isFalse);
    });

    test('status berubah dari aktif ke tenggang lalu kedaluwarsa', () async {
      final expiresAt = DateTime.utc(2026, 1, 10);
      final clock = FakeClock(DateTime.utc(2026, 1, 1));
      final controller = PlusController(
        configRepository: _FakeConfigRepository(
          _config(fetchedAtUtc: DateTime.utc(2026, 1, 1)),
        ),
        configStore: InMemoryPlusConfigStore(),
        entitlementStore: InMemoryEntitlementLocalStore(token: 'token'),
        verifier: _FakeVerifier(<String, EntitlementPayload>{
          'token': _payload(expiresAtUtc: expiresAt),
        }),
        billing: _FakeBilling(),
        clock: clock,
      );
      await controller.loadCached();
      expect(controller.access.state, PlusAccessState.active);

      clock.advance(const Duration(days: 12));
      await controller.refreshAccess();
      expect(controller.access.state, PlusAccessState.grace);
      expect(controller.hasPlus, isTrue);

      clock.advance(const Duration(days: 9));
      await controller.refreshAccess();
      expect(controller.access.state, PlusAccessState.expired);
      expect(controller.hasPlus, isFalse);
    });

    test('jam perangkat yang dimundurkan tidak menghidupkan token', () async {
      final expiresAt = DateTime.utc(2026, 1, 10);
      final clock = FakeClock(DateTime.utc(2026, 1, 25));
      final controller = PlusController(
        configRepository: _FakeConfigRepository(
          _config(fetchedAtUtc: DateTime.utc(2026, 1, 25)),
        ),
        configStore: InMemoryPlusConfigStore(),
        entitlementStore: InMemoryEntitlementLocalStore(token: 'token'),
        verifier: _FakeVerifier(<String, EntitlementPayload>{
          'token': _payload(expiresAtUtc: expiresAt),
        }),
        billing: _FakeBilling(),
        clock: clock,
      );
      await controller.loadCached();
      expect(controller.access.state, PlusAccessState.expired);

      clock.advance(const Duration(days: -20));
      await controller.refreshAccess();

      expect(controller.access.state, PlusAccessState.expired);
      expect(controller.hasPlus, isFalse);
    });
  });

  group('PlusController konfigurasi jarak jauh', () {
    test('mengambil, menyimpan cache, dan menyalakan feature flag', () async {
      final now = DateTime.utc(2026, 6, 1, 8);
      final clock = FakeClock(now);
      final configStore = InMemoryPlusConfigStore();
      final configRepository = _FakeConfigRepository(
        _config(fetchedAtUtc: now, leaderboard: true),
      );
      final controller = PlusController(
        configRepository: configRepository,
        configStore: configStore,
        entitlementStore: InMemoryEntitlementLocalStore(),
        verifier: _FakeVerifier(),
        billing: _FakeBilling(),
        clock: clock,
      );
      await controller.loadCached();
      expect(controller.hasConfig, isFalse);
      expect(controller.leaderboardEnabled, isFalse);

      await controller.refreshRemote();

      expect(configRepository.fetches, 1);
      expect(controller.hasConfig, isTrue);
      expect(controller.leaderboardEnabled, isTrue);
      expect(controller.peakBadgesEnabled, isTrue);
      expect(configStore.writes, 1);
      expect(configStore.config?.fetchedAtUtc, now);
      expect(controller.configFetchFailed, isFalse);
    });

    test('cache yang masih segar tidak diambil ulang', () async {
      final now = DateTime.utc(2026, 6, 1, 8);
      final clock = FakeClock(now);
      final configRepository = _FakeConfigRepository(
        _config(fetchedAtUtc: now),
      );
      final controller = PlusController(
        configRepository: configRepository,
        configStore: InMemoryPlusConfigStore(_config(fetchedAtUtc: now)),
        entitlementStore: InMemoryEntitlementLocalStore(),
        verifier: _FakeVerifier(),
        billing: _FakeBilling(),
        clock: clock,
      );
      await controller.loadCached();

      await controller.refreshRemote();
      expect(configRepository.fetches, 0);

      await controller.refreshRemote(force: true);
      expect(configRepository.fetches, 1);
    });

    test('gagal jaringan mempertahankan cache dan menandai kegagalan',
        () async {
      final now = DateTime.utc(2026, 6, 1, 8);
      final clock = FakeClock(now);
      final cached = _config(
        fetchedAtUtc: now.subtract(const Duration(days: 1)),
      );
      final configRepository = _FakeConfigRepository(cached)..fail = true;
      final controller = PlusController(
        configRepository: configRepository,
        configStore: InMemoryPlusConfigStore(cached),
        entitlementStore: InMemoryEntitlementLocalStore(),
        verifier: _FakeVerifier(),
        billing: _FakeBilling(),
        clock: clock,
      );
      await controller.loadCached();

      await controller.refreshRemote(force: true);

      expect(controller.configFetchFailed, isTrue);
      expect(controller.plans.single.id, 'annual');
      expect(controller.leaderboardEnabled, isTrue);
    });
  });

  group('PlusController pembelian', () {
    late _FakeBilling billing;
    late _FakeVerifier verifier;
    late InMemoryEntitlementLocalStore entitlementStore;
    late PlusController controller;
    late FakeClock clock;

    setUp(() async {
      final now = DateTime.utc(2026, 6, 1, 8);
      clock = FakeClock(now);
      billing = _FakeBilling();
      verifier = _FakeVerifier(<String, EntitlementPayload>{
        'token-baru': _payload(expiresAtUtc: DateTime.utc(2027, 6, 1)),
      });
      entitlementStore = InMemoryEntitlementLocalStore();
      controller = PlusController(
        configRepository: _FakeConfigRepository(_config(fetchedAtUtc: now)),
        configStore: InMemoryPlusConfigStore(_config(fetchedAtUtc: now)),
        entitlementStore: entitlementStore,
        verifier: verifier,
        billing: billing,
        clock: clock,
      );
      await controller.loadCached();
    });

    test('pembelian berhasil menyimpan token dan mengaktifkan Plus', () async {
      billing.purchaseResult = const PlusBillingResult.purchased('token-baru');

      final result = await controller.purchase('annual');

      expect(result.success, isTrue);
      expect(billing.lastPlanId, 'annual');
      expect(entitlementStore.token, 'token-baru');
      expect(controller.hasPlus, isTrue);
      expect(controller.access.planId, 'annual');
      expect(controller.currentPlan?.title, 'Hiqeo Plus Tahunan');
    });

    test('bukti pembelian tidak sah tidak disimpan', () async {
      billing.purchaseResult = const PlusBillingResult.purchased('token-palsu');

      final result = await controller.purchase('annual');

      expect(result.success, isFalse);
      expect(result.message, 'Bukti pembelian tidak valid.');
      expect(entitlementStore.token, isNull);
      expect(controller.hasPlus, isFalse);
    });

    test('pembelian dibatalkan tidak mengubah status', () async {
      billing.purchaseResult = const PlusBillingResult.cancelled();

      final result = await controller.purchase('annual');

      expect(result.success, isFalse);
      expect(result.message, 'Pembelian dibatalkan.');
      expect(controller.hasPlus, isFalse);
    });

    test('pemulihan tanpa pembelian memberi pesan jujur', () async {
      billing.restoreResult = const PlusBillingResult.nothingToRestore(
        'Tidak ada pembelian untuk dipulihkan.',
      );

      final result = await controller.restore();

      expect(result.success, isFalse);
      expect(result.message, 'Tidak ada pembelian untuk dipulihkan.');
      expect(billing.restoreCalls, 1);
      expect(controller.hasPlus, isFalse);
    });
  });

  group('implementasi demo', () {
    test('konfigurasi demo mati jika tidak diaktifkan', () async {
      final repository = const DebugPlusConfigRepository(enabled: false);

      await expectLater(
        repository.fetch(fetchedAtUtc: DateTime.utc(2026, 10, 31)),
        throwsA(isA<PlusConfigUnavailable>()),
      );
    });

    test('toko demo menerbitkan token yang lolos verifikasi offline', () async {
      final clock = FakeClock(DateTime.utc(2026, 6, 1));
      final billing = DebugPlusBillingRepository(
        clock: clock,
        enabled: true,
      );

      final result = await billing.purchase('annual');

      expect(result.status, PlusBillingStatus.purchased);
      final payload = await const Ed25519EntitlementVerifier(
        publicKeyBase64Url: DevelopmentPlusKeys.publicKeyBase64Url,
      ).verify(result.token!);
      expect(payload, isNotNull);
      expect(payload!.planId, 'annual');
      expect(payload.expiresAtUtc, DateTime.utc(2027, 6, 1));
    });

    test('paket tak dikenal dan pemulihan kosong tidak mengarang hasil',
        () async {
      final billing = DebugPlusBillingRepository(
        clock: FakeClock(DateTime.utc(2026, 6, 1)),
        enabled: true,
      );

      final unknown = await billing.purchase('tidak-ada');
      final restored = await billing.restore();

      expect(unknown.status, PlusBillingStatus.unavailable);
      expect(restored.status, PlusBillingStatus.nothingToRestore);
      expect(restored.token, isNull);
    });

    test('alur lengkap demo: konfigurasi, beli, lalu aktif offline', () async {
      final clock = FakeClock(DateTime.utc(2026, 10, 31, 9));
      final configStore = InMemoryPlusConfigStore();
      final entitlementStore = InMemoryEntitlementLocalStore();
      final controller = PlusController(
        configRepository: const DebugPlusConfigRepository(enabled: true),
        configStore: configStore,
        entitlementStore: entitlementStore,
        verifier: const Ed25519EntitlementVerifier(
          publicKeyBase64Url: DevelopmentPlusKeys.publicKeyBase64Url,
        ),
        billing: DebugPlusBillingRepository(clock: clock, enabled: true),
        clock: clock,
      );
      await controller.loadCached();

      await controller.refreshRemote();
      final result = await controller.purchase('founding');

      expect(result.success, isTrue);
      expect(controller.hasPlus, isTrue);
      expect(controller.access.lifetime, isTrue);
      expect(controller.currentPlan?.isLifetime, isTrue);
      expect(controller.leaderboardEnabled, isTrue);
      expect(controller.plans, hasLength(4));
      expect(configStore.config, isNotNull);
    });
  });
}
