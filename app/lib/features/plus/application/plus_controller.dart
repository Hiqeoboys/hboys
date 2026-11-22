import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/clock.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../domain/plus_entitlement.dart';
import '../domain/plus_plan.dart';
import '../domain/plus_remote_config.dart';
import '../domain/plus_repositories.dart';
import '../domain/plus_subscription_history.dart';

class PlusActionResult {
  const PlusActionResult.success()
      : success = true,
        message = null;

  const PlusActionResult.failure(this.message) : success = false;

  final bool success;
  final String? message;
}

typedef PlusSubscriptionHistoryFetcher = Future<List<PlusSubscriptionHistoryEntry>>
    Function(String userId);

/// Sumber status Plus tunggal untuk seluruh aplikasi.
///
/// Alur baca: token tersimpan diverifikasi sekali secara offline, lalu status
/// dihitung ulang dari waktu tanpa jaringan. Konfigurasi (harga, kuota,
/// tenggang 3 hari, feature flag) diambil dari cache dan diperbarui paling
/// sering setiap [PlusRemoteConfig.refreshInterval].
class PlusController extends ChangeNotifier {
  PlusController({
    required PlusRemoteConfigRepository configRepository,
    required PlusConfigStore configStore,
    required EntitlementLocalStore entitlementStore,
    required EntitlementVerifier verifier,
    required PlusBillingRepository billing,
    AccountPlusCacheStore? accountPlusStore,
    PlusSubscriptionHistoryFetcher? historyFetcher,
    Clock clock = const SystemClock(),
  })  : _configRepository = configRepository,
        _configStore = configStore,
        _entitlementStore = entitlementStore,
        _verifier = verifier,
        _billing = billing,
        _accountPlusStore = accountPlusStore,
        _historyFetcher = historyFetcher,
        _clock = clock;

  static const String _historyCachePrefix = 'hiqeo_plus_history_v1_';

  final PlusRemoteConfigRepository _configRepository;
  final PlusConfigStore _configStore;
  final EntitlementLocalStore _entitlementStore;
  final EntitlementVerifier _verifier;
  final PlusBillingRepository _billing;
  final AccountPlusCacheStore? _accountPlusStore;
  final PlusSubscriptionHistoryFetcher? _historyFetcher;
  final Clock _clock;

  PlusRemoteConfig? _config;
  EntitlementPayload? _payload;
  AccountPlusGrant? _accountGrant;
  PlusAccess _access = PlusAccess.free;
  List<PlusSubscriptionHistoryEntry> _subscriptionHistory =
      const <PlusSubscriptionHistoryEntry>[];
  DateTime? _lastSeenUtc;
  bool _loaded = false;
  bool _working = false;
  bool _configFetchFailed = false;

  PlusAccess get access => _access;
  bool get hasPlus => _access.hasPlus;
  bool get hasFullSocialAccess => _access.hasFullSocialAccess;
  bool get hasFullPlanIncludingGrace => _access.hasFullPlanIncludingGrace;
  bool get isUltima => _access.isUltima;
  bool get isWorking => _working;
  bool get isLoaded => _loaded;
  bool get configFetchFailed => _configFetchFailed;
  bool get hasConfig => _config != null;
  PlusRemoteConfig? get config => _config;
  List<PlusPlan> get plans => _config?.plans ?? const <PlusPlan>[];
  bool get leaderboardEnabled => _config?.flags.leaderboard ?? false;
  bool get peakBadgesEnabled => _config?.flags.peakBadges ?? false;

  bool get hasEverSubscribed =>
      hasPlus ||
      _access.isExpired ||
      _access.planId != null ||
      _accountGrant?.planId != null ||
      _accountGrant?.expiresAtUtc != null ||
      _subscriptionHistory.isNotEmpty;

  /// Riwayat langganan pengguna. Jika daftar dari server belum tersedia saat
  /// offline, menyintesis 1 entri dari status grant lokal bila user pernah
  /// atau sedang berlangganan. Kosong mutlak bila user belum pernah berlangganan.
  List<PlusSubscriptionHistoryEntry> get subscriptionHistory {
    if (_subscriptionHistory.isNotEmpty) {
      return List<PlusSubscriptionHistoryEntry>.unmodifiable(_subscriptionHistory);
    }
    final synthesized = _synthesizeHistoryEntry();
    if (synthesized == null) return const <PlusSubscriptionHistoryEntry>[];
    return List<PlusSubscriptionHistoryEntry>.unmodifiable(
      <PlusSubscriptionHistoryEntry>[synthesized],
    );
  }

  PlusPlan? get currentPlan {
    final id = _access.planId ?? _accountGrant?.planId;
    if (id == null) return null;
    for (final plan in plans) {
      if (plan.id == id) return plan;
    }
    return null;
  }

  /// Jam efektif tidak pernah mundur dari pemeriksaan terakhir, sehingga
  /// memundurkan jam perangkat tidak memperpanjang token yang sudah lewat.
  DateTime get _effectiveNow {
    final now = _clock.nowUtc();
    final lastSeen = _lastSeenUtc;
    if (lastSeen != null && lastSeen.isAfter(now)) return lastSeen;
    return now;
  }

  /// Membaca cache konfigurasi dan token lokal tanpa jaringan. Dipanggil
  /// sebelum `runApp` agar status Plus langsung benar saat layar pertama
  /// dibuka.
  Future<void> loadCached() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final cached = await _configStore.read();
      if (cached != null) _config = cached;
    } catch (_) {
      // Penyimpanan lokal bermasalah tidak boleh menggagalkan start.
    }
    try {
      final token = await _entitlementStore.readToken();
      if (token != null) {
        final payload = await _verifier.verify(token);
        if (payload == null) {
          await _entitlementStore.clearToken();
        } else {
          _payload = payload;
        }
      }
    } catch (_) {
      // Token rusak atau plugin gagal: diperlakukan seperti pengguna gratis.
    }
    try {
      _accountGrant = await _accountPlusStore?.read();
    } catch (_) {
      // Cache akun rusak diabaikan.
    }
    final uid = _accountGrant?.userId;
    if (uid != null && uid.isNotEmpty) {
      await _loadCachedHistory(uid);
    }
    try {
      _lastSeenUtc = await _entitlementStore.readLastSeenUtc();
    } catch (_) {
      // Tanpa checkpoint, evaluasi tetap berjalan dari jam sekarang.
    }
    await _evaluateAndPersist();
    notifyListeners();
  }

  /// Menyinkronkan status Hiqeo Plus dari profil Supabase ke cache lokal agar
  /// seluruh fitur Hiqeo Plus (termasuk masa tenggang 3 hari dan riwayat
  /// berakhir) tetap akurat secara offline.
  Future<void> syncAccountPlus({
    required String userId,
    required bool isPlus,
    String? planId,
    DateTime? startedAtUtc,
    DateTime? expiresAtUtc,
  }) async {
    final normalizedPlan = planId?.trim().isNotEmpty == true
        ? planId!.trim()
        : (isPlus ? 'lifetime' : null);
    final grant = AccountPlusGrant(
      userId: userId,
      isPlus: isPlus,
      planId: normalizedPlan,
      startedAtUtc: startedAtUtc?.toUtc() ?? _accountGrant?.startedAtUtc,
      expiresAtUtc: expiresAtUtc?.toUtc(),
      syncedAtUtc: _clock.nowUtc(),
    );
    _accountGrant = grant;
    try {
      await _accountPlusStore?.write(grant);
    } catch (_) {
      // Tetap aktif di sesi ini walaupun tulis cache gagal.
    }
    await _loadCachedHistory(userId);
    final changed = await _evaluateAndPersist();
    if (changed) notifyListeners();
  }

  /// Mengambil riwayat berlangganan akun dari server (atau cache per-akun bila
  /// offline). Hanya berisi data bila akun sedang/pernah berlangganan.
  Future<void> refreshSubscriptionHistory({String? userId}) async {
    final uid = userId ??
        _accountGrant?.userId ??
        SupabaseServices.clientOrNull?.auth.currentUser?.id;
    if (uid == null || uid.trim().isEmpty) return;

    await _loadCachedHistory(uid);

    try {
      final fetched = _historyFetcher != null
          ? await _historyFetcher(uid)
          : await _defaultFetchHistory();
      if (fetched != null) {
        _subscriptionHistory = fetched;
        await _persistCachedHistory(uid, fetched);
        notifyListeners();
      }
    } catch (_) {
      // Offline: pertahankan cache riwayat lokal / hasil sintesis.
    }
  }

  Future<List<PlusSubscriptionHistoryEntry>?> _defaultFetchHistory() async {
    final client = SupabaseServices.clientOrNull;
    if (client == null || client.auth.currentUser == null) return null;
    final raw = await client.rpc('my_subscription_history');
    if (raw is! List) return const <PlusSubscriptionHistoryEntry>[];
    return raw
        .map(PlusSubscriptionHistoryEntry.tryParse)
        .whereType<PlusSubscriptionHistoryEntry>()
        .toList(growable: false);
  }

  Future<void> _loadCachedHistory(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_historyCachePrefix$userId');
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final parsed = decoded
          .map(PlusSubscriptionHistoryEntry.tryParse)
          .whereType<PlusSubscriptionHistoryEntry>()
          .toList(growable: false);
      if (!listEquals(parsed, _subscriptionHistory)) {
        _subscriptionHistory = parsed;
      }
    } catch (_) {}
  }

  Future<void> _persistCachedHistory(
    String userId,
    List<PlusSubscriptionHistoryEntry> entries,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_historyCachePrefix$userId',
        jsonEncode(
          entries.map((e) => e.toJson()).toList(growable: false),
        ),
      );
    } catch (_) {}
  }

  /// Menghapus cache status Hiqeo Plus akun saat pengguna keluar/ganti/hapus akun.
  Future<void> clearAccountPlus() async {
    _accountGrant = null;
    _subscriptionHistory = const <PlusSubscriptionHistoryEntry>[];
    try {
      await _accountPlusStore?.clear();
    } catch (_) {}
    final changed = await _evaluateAndPersist();
    if (changed) notifyListeners();
  }

  /// Mengambil konfigurasi dari server bila cache belum ada atau sudah lewat
  /// [PlusRemoteConfig.refreshInterval]. Gagal jaringan tidak mengubah akses
  /// Plus yang sudah ada.
  Future<void> refreshRemote({bool force = false}) async {
    final now = _effectiveNow;
    final current = _config;
    if (!force &&
        current != null &&
        now.difference(current.fetchedAtUtc) <
            PlusRemoteConfig.refreshInterval) {
      return;
    }
    try {
      final fetched = await _configRepository.fetch(fetchedAtUtc: now);
      _config = fetched;
      _configFetchFailed = false;
      try {
        await _configStore.write(fetched);
      } catch (_) {
        // Cache gagal ditulis; konfigurasi tetap dipakai untuk sesi ini.
      }
    } catch (_) {
      _configFetchFailed = true;
    }
    await _evaluateAndPersist();
    notifyListeners();
  }

  Future<PlusActionResult> purchase(String planId) =>
      _runBilling(() => _billing.purchase(planId));

  Future<PlusActionResult> restore() => _runBilling(_billing.restore);

  Future<PlusActionResult> _runBilling(
    Future<PlusBillingResult> Function() action,
  ) async {
    if (_working) {
      return const PlusActionResult.failure(
        'Transaksi lain sedang diproses.',
      );
    }
    _working = true;
    notifyListeners();
    try {
      final result = await action();
      return await _applyBillingResult(result);
    } catch (_) {
      return const PlusActionResult.failure(
        'Transaksi gagal. Coba lagi.',
      );
    } finally {
      _working = false;
      notifyListeners();
    }
  }

  Future<PlusActionResult> _applyBillingResult(
    PlusBillingResult result,
  ) async {
    switch (result.status) {
      case PlusBillingStatus.purchased:
        final token = result.token;
        if (token == null || token.isEmpty) {
          return const PlusActionResult.failure(
            'Bukti pembelian tidak valid.',
          );
        }
        final payload = await _verifier.verify(token);
        if (payload == null) {
          return const PlusActionResult.failure(
            'Bukti pembelian tidak valid.',
          );
        }
        try {
          await _entitlementStore.writeToken(token);
        } catch (_) {
          // Hak akses tetap berlaku untuk sesi ini meskipun penyimpanan gagal.
        }
        _payload = payload;
        await _evaluateAndPersist();
        return const PlusActionResult.success();
      case PlusBillingStatus.cancelled:
        return const PlusActionResult.failure('Pembelian dibatalkan.');
      case PlusBillingStatus.nothingToRestore:
        return PlusActionResult.failure(
          result.message ?? 'Tidak ada pembelian untuk dipulihkan.',
        );
      case PlusBillingStatus.unavailable:
        return PlusActionResult.failure(
          result.message ?? 'Pembelian belum tersedia.',
        );
    }
  }

  /// Menghitung ulang status dari waktu sekarang, misalnya saat aplikasi
  /// kembali ke depan. Tidak memanggil jaringan.
  Future<void> refreshAccess() async {
    if (!_loaded) return;
    final changed = await _evaluateAndPersist();
    if (changed) notifyListeners();
  }

  PlusSubscriptionHistoryEntry? _synthesizeHistoryEntry() {
    final acc = _access;
    final grant = _accountGrant;
    final planId = acc.planId ?? grant?.planId;
    final expiresAt = acc.expiresAtUtc ?? grant?.expiresAtUtc;
    final isLifetime = acc.isUltima ||
        (grant != null &&
            grant.isPlus &&
            (expiresAt == null || PlusAccess.isLifetimePlanId(planId)));

    if (!acc.hasPlus && !acc.isExpired && planId == null && expiresAt == null) {
      return null;
    }

    final effectivePlanId = planId ?? 'annual';
    final status = isLifetime
        ? PlusSubscriptionHistoryStatus.lifetime
        : switch (acc.state) {
            PlusAccessState.active => PlusSubscriptionHistoryStatus.active,
            PlusAccessState.grace => PlusSubscriptionHistoryStatus.grace,
            PlusAccessState.expired => PlusSubscriptionHistoryStatus.expired,
            PlusAccessState.free => PlusSubscriptionHistoryStatus.expired,
          };
    final startedAt = acc.issuedAtUtc ??
        grant?.startedAtUtc ??
        expiresAt?.subtract(const Duration(days: 30)) ??
        grant?.syncedAtUtc ??
        _effectiveNow;

    return PlusSubscriptionHistoryEntry(
      id: 'local-$effectivePlanId-${startedAt.millisecondsSinceEpoch}',
      planId: effectivePlanId,
      planTitle: currentPlan?.title ?? plusPlanTitleForId(effectivePlanId),
      status: status,
      startedAtUtc: startedAt,
      expiresAtUtc: isLifetime ? null : expiresAt,
    );
  }

  int _priorityOf(PlusAccessState state) => switch (state) {
        PlusAccessState.active => 3,
        PlusAccessState.grace => 2,
        PlusAccessState.expired => 1,
        PlusAccessState.free => 0,
      };

  Future<bool> _evaluateAndPersist() async {
    final now = _effectiveNow;
    final graceDays =
        _config?.effectiveGraceDays ?? PlusRemoteConfig.fallbackGraceDays;
    final tokenAccess = evaluatePlusAccess(
      payload: _payload,
      nowUtc: now,
      graceDays: graceDays,
    );

    PlusAccess accountAccess = PlusAccess.free;
    final grant = _accountGrant;
    if (grant != null) {
      final hasHistoricalGrant = grant.isPlus ||
          grant.planId != null ||
          grant.expiresAtUtc != null;
      if (grant.isPlus &&
          (grant.expiresAtUtc == null ||
              PlusAccess.isLifetimePlanId(grant.planId))) {
        accountAccess = PlusAccess(
          state: PlusAccessState.active,
          planId: grant.planId ?? 'lifetime',
          issuedAtUtc: grant.startedAtUtc ?? grant.syncedAtUtc,
          lifetime: true,
        );
      } else if (grant.expiresAtUtc != null) {
        final exp = grant.expiresAtUtc!;
        final issued = grant.startedAtUtc ??
            (grant.syncedAtUtc.isAfter(exp)
                ? exp.subtract(const Duration(days: 30))
                : grant.syncedAtUtc);
        final accountPayload = EntitlementPayload(
          version: EntitlementPayload.currentVersion,
          subject: grant.userId,
          planId: grant.planId ?? 'annual',
          issuedAtUtc: issued,
          expiresAtUtc: exp,
        );
        accountAccess = evaluatePlusAccess(
          payload: accountPayload,
          nowUtc: now,
          graceDays: graceDays,
        );
      } else if (hasHistoricalGrant && grant.isPlus) {
        accountAccess = PlusAccess(
          state: PlusAccessState.active,
          planId: grant.planId ?? 'annual',
          issuedAtUtc: grant.startedAtUtc ?? grant.syncedAtUtc,
        );
      } else if (hasHistoricalGrant) {
        accountAccess = PlusAccess(
          state: PlusAccessState.expired,
          planId: grant.planId,
          issuedAtUtc: grant.startedAtUtc ?? grant.syncedAtUtc,
        );
      }
    }

    final next = _priorityOf(accountAccess.state) > _priorityOf(tokenAccess.state)
        ? accountAccess
        : tokenAccess;

    final changed = next != _access;
    _access = next;
    if (_lastSeenUtc == null || now.isAfter(_lastSeenUtc!)) {
      _lastSeenUtc = now;
      try {
        await _entitlementStore.writeLastSeenUtc(now);
      } catch (_) {
        // Checkpoint hanya pertahanan tambahan; kegagalan menulis diabaikan.
      }
    }
    return changed;
  }
}
