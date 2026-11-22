import 'package:flutter/foundation.dart';

import '../../../core/utils/clock.dart';
import '../domain/plus_entitlement.dart';
import '../domain/plus_plan.dart';
import '../domain/plus_remote_config.dart';
import '../domain/plus_repositories.dart';

class PlusActionResult {
  const PlusActionResult.success()
      : success = true,
        message = null;

  const PlusActionResult.failure(this.message) : success = false;

  final bool success;
  final String? message;
}

/// Sumber status Plus tunggal untuk seluruh aplikasi.
///
/// Alur baca: token tersimpan diverifikasi sekali secara offline, lalu status
/// dihitung ulang dari waktu tanpa jaringan. Konfigurasi (harga, kuota,
/// tenggang, feature flag) diambil dari cache dan diperbarui paling sering
/// setiap [PlusRemoteConfig.refreshInterval], bukan setiap kali status
/// diperiksa.
class PlusController extends ChangeNotifier {
  PlusController({
    required PlusRemoteConfigRepository configRepository,
    required PlusConfigStore configStore,
    required EntitlementLocalStore entitlementStore,
    required EntitlementVerifier verifier,
    required PlusBillingRepository billing,
    AccountPlusCacheStore? accountPlusStore,
    Clock clock = const SystemClock(),
  })  : _configRepository = configRepository,
        _configStore = configStore,
        _entitlementStore = entitlementStore,
        _verifier = verifier,
        _billing = billing,
        _accountPlusStore = accountPlusStore,
        _clock = clock;

  final PlusRemoteConfigRepository _configRepository;
  final PlusConfigStore _configStore;
  final EntitlementLocalStore _entitlementStore;
  final EntitlementVerifier _verifier;
  final PlusBillingRepository _billing;
  final AccountPlusCacheStore? _accountPlusStore;
  final Clock _clock;

  PlusRemoteConfig? _config;
  EntitlementPayload? _payload;
  AccountPlusGrant? _accountGrant;
  PlusAccess _access = PlusAccess.free;
  DateTime? _lastSeenUtc;
  bool _loaded = false;
  bool _working = false;
  bool _configFetchFailed = false;

  PlusAccess get access => _access;
  bool get hasPlus => _access.hasPlus;
  bool get hasFullSocialAccess => _access.hasFullSocialAccess;
  bool get isWorking => _working;
  bool get isLoaded => _loaded;
  bool get configFetchFailed => _configFetchFailed;
  bool get hasConfig => _config != null;
  PlusRemoteConfig? get config => _config;
  List<PlusPlan> get plans => _config?.plans ?? const <PlusPlan>[];
  bool get leaderboardEnabled => _config?.flags.leaderboard ?? false;
  bool get peakBadgesEnabled => _config?.flags.peakBadges ?? false;

  PlusPlan? get currentPlan {
    final id = _access.planId;
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
    try {
      _lastSeenUtc = await _entitlementStore.readLastSeenUtc();
    } catch (_) {
      // Tanpa checkpoint, evaluasi tetap berjalan dari jam sekarang.
    }
    await _evaluateAndPersist();
    notifyListeners();
  }

  /// Menyinkronkan status Hiqeo Plus dari profil Supabase ke cache lokal agar
  /// seluruh fitur Hiqeo Plus tetap dapat dipakai secara offline.
  Future<void> syncAccountPlus({
    required String userId,
    required bool isPlus,
    String? planId,
    DateTime? expiresAtUtc,
  }) async {
    final grant = AccountPlusGrant(
      userId: userId,
      isPlus: isPlus,
      planId: isPlus ? (planId ?? 'lifetime') : null,
      expiresAtUtc: isPlus ? expiresAtUtc?.toUtc() : null,
      syncedAtUtc: _clock.nowUtc(),
    );
    _accountGrant = grant;
    try {
      await _accountPlusStore?.write(grant);
    } catch (_) {
      // Tetap aktif di sesi ini walaupun tulis cache gagal.
    }
    final changed = await _evaluateAndPersist();
    if (changed) notifyListeners();
  }

  /// Menghapus cache status Hiqeo Plus akun saat pengguna keluar/hapus akun.
  Future<void> clearAccountPlus() async {
    _accountGrant = null;
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

  Future<bool> _evaluateAndPersist() async {
    final now = _effectiveNow;
    final graceDays =
        _config?.effectiveGraceDays ?? PlusRemoteConfig.fallbackGraceDays;
    var next = evaluatePlusAccess(
      payload: _payload,
      nowUtc: now,
      graceDays: graceDays,
    );
    final grant = _accountGrant;
    if (!next.hasPlus && grant != null && grant.isPlus) {
      final accountPayload = EntitlementPayload(
        version: EntitlementPayload.currentVersion,
        subject: grant.userId,
        planId: grant.planId ?? 'lifetime',
        issuedAtUtc: grant.syncedAtUtc,
        expiresAtUtc: grant.expiresAtUtc,
      );
      final accountAccess = evaluatePlusAccess(
        payload: accountPayload,
        nowUtc: now,
        graceDays: graceDays,
      );
      if (accountAccess.hasPlus || next.state == PlusAccessState.free) {
        next = accountAccess;
      }
    }
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
