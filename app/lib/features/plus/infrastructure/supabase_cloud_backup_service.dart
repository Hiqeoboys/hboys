import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../../../infrastructure/database/app_database.dart';
import '../../../infrastructure/database/database_connection.dart';
import '../../../infrastructure/database/repositories/drift_tracking_repository.dart';
import '../../../infrastructure/supabase/supabase_services.dart';
import '../../tracking/domain/tracking_repository.dart';
import '../../tracking/domain/tracking_session.dart';
import '../domain/cloud_backup.dart';
import '../domain/cloud_backup_bundle.dart';
import '../plus_dependencies.dart';
import 'plus_local_caches.dart';

/// Server cadangan cloud otomatis untuk pelanggan Hiqeo Plus.
///
/// Setiap sesi selesai dikemas menjadi 1 bundel JSON terkompresi gzip (~5–15 KB
/// dengan polyline tersederhanakan) pada tabel `cloud_session_backups`.
/// Saat pengguna berganti HP atau masuk ulang, riwayat & statistik dipulihkan
/// otomatis tanpa kode pemulihan manual.
class SupabaseCloudBackupService implements CloudBackupRepository {
  SupabaseCloudBackupService._();

  static final SupabaseCloudBackupService instance =
      SupabaseCloudBackupService._();

  static const String _table = 'cloud_session_backups';

  String? _cachedDeviceName;
  bool _syncing = false;

  Future<String> _deviceName() async {
    if (_cachedDeviceName != null) return _cachedDeviceName!;
    if (kIsWeb) return _cachedDeviceName = 'Web';
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        final model = '${android.brand} ${android.model}'.trim();
        return _cachedDeviceName = model.isEmpty ? 'Android' : model;
      }
      if (Platform.isIOS) {
        final ios = await info.iosInfo;
        return _cachedDeviceName = ios.utsname.machine;
      }
    } catch (_) {}
    return _cachedDeviceName = 'Perangkat ini';
  }

  Future<SharedPreferencesCloudBackupRepository> _localStore() async =>
      SharedPreferencesCloudBackupRepository(deviceName: await _deviceName());

  Future<bool> _isNetworkAllowed({required bool wifiOnly}) async {
    try {
      final results = await Connectivity()
          .checkConnectivity()
          .timeout(const Duration(seconds: 2));
      final hasNet = results.any((r) => r != ConnectivityResult.none);
      if (!hasNet) return false;
      if (wifiOnly) return results.contains(ConnectivityResult.wifi);
      return true;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<CloudBackupState> load() async {
    final store = await _localStore();
    final state = await store.load();
    final client = SupabaseServices.clientOrNull;
    if (client == null || client.auth.currentUser == null) return state;
    return state.copyWith(connected: true);
  }

  @override
  Future<CloudBackupState> setAutoBackup(bool enabled) async {
    final store = await _localStore();
    final next = await store.setAutoBackup(enabled);
    if (enabled) {
      unawaited(syncAndRestore());
    }
    return next.copyWith(
      connected: SupabaseServices.clientOrNull?.auth.currentUser != null,
    );
  }

  @override
  Future<CloudBackupState> setWifiOnly(bool wifiOnly) async {
    final store = await _localStore();
    final next = await store.setWifiOnly(wifiOnly);
    return next.copyWith(
      connected: SupabaseServices.clientOrNull?.auth.currentUser != null,
    );
  }

  @override
  Future<CloudBackupState> syncNow({bool ignoreWifiOnly = true}) =>
      syncAndRestore(ignoreWifiOnly: ignoreWifiOnly);

  /// Memulihkan sesi yang hilang dari server secara otomatis, lalu mengunggah
  /// sesi lokal yang belum ada di server (jika `autoBackup` aktif).
  Future<CloudBackupState> syncAndRestore({
    TrackingRepository? trackingRepository,
    bool ignoreWifiOnly = false,
    bool hasPlusOverride = false,
  }) async {
    final store = await _localStore();
    var state = await store.load();
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return state;

    final isPlus = hasPlusOverride || PlusDependencies.controller.hasPlus;
    if (!isPlus || _syncing) {
      return state.copyWith(connected: true);
    }

    _syncing = true;
    AppDatabase? ownedDb;
    try {
      var repo = trackingRepository;
      if (repo == null) {
        ownedDb = openAppDatabase(await defaultAppDatabaseFile());
        repo = DriftTrackingRepository(
          ownedDb,
          ownerUserIdProvider: () => user.id,
        );
      }

      final remoteRows = await client
          .from(_table)
          .select('session_id, bundle_gzip_b64, device_name, updated_at')
          .eq('user_id', user.id)
          .timeout(const Duration(seconds: 10));

      final localSessions = await repo.watchSessions().first;
      final localIds = <String>{for (final s in localSessions) s.id};
      final remoteIds = <String>{};
      final devicesByName = <String, BackupDevice>{};
      final currentDeviceName = await _deviceName();

      var restored = 0;
      for (final raw in remoteRows) {
        final sid = raw['session_id']?.toString() ?? '';
        if (sid.isEmpty) continue;
        remoteIds.add(sid);

        final devName = raw['device_name']?.toString().trim();
        final updatedAt =
            DateTime.tryParse(raw['updated_at']?.toString() ?? '')?.toUtc() ??
                DateTime.now().toUtc();
        if (devName != null && devName.isNotEmpty) {
          final existingDev = devicesByName[devName];
          if (existingDev == null ||
              updatedAt.isAfter(existingDev.lastActiveUtc)) {
            devicesByName[devName] = BackupDevice(
              name: devName,
              lastActiveUtc: updatedAt,
              current: devName == currentDeviceName,
            );
          }
        }

        if (!localIds.contains(sid)) {
          final b64 = raw['bundle_gzip_b64']?.toString() ?? '';
          final decoded = await Isolate.run(() => decodeSessionBundle(b64));
          if (decoded != null) {
            await repo.saveSession(
              decoded.session.copyWith(ownerUserId: user.id),
            );
            for (final pt in decoded.points) {
              await repo.addPoint(decoded.session.id, pt);
            }
            restored++;
          }
        }
      }

      if (restored > 0) {
        DriftTrackingRepository.notifyExternalChange();
      }

      // Unggah sesi lokal yang selesai & belum ada di cloud.
      if (state.autoBackup || ignoreWifiOnly) {
        final allowed = await _isNetworkAllowed(
          wifiOnly: ignoreWifiOnly ? false : state.wifiOnly,
        );
        if (allowed) {
          final completedLocal = localSessions.where(
            (s) =>
                s.status == TrackingSessionStatus.completed &&
                !remoteIds.contains(s.id),
          );
          for (final session in completedLocal) {
            final points = await repo.points(session.id);
            final encoded =
                await Isolate.run(() => encodeSessionBundle(session, points));
            await client
                .from(_table)
                .upsert(
                  <String, dynamic>{
                    'user_id': user.id,
                    'session_id': session.id,
                    'activity_type': session.activityType,
                    'started_at': session.startedAtUtc.toUtc().toIso8601String(),
                    'ended_at': session.endedAtUtc?.toUtc().toIso8601String(),
                    'bundle_gzip_b64': encoded.gzipBase64,
                    'bundle_bytes': encoded.byteLength,
                    'device_name': currentDeviceName,
                    'updated_at': DateTime.now().toUtc().toIso8601String(),
                  },
                  onConflict: 'user_id,session_id',
                )
                .timeout(const Duration(seconds: 10));
          }
        }
      }

      final nowUtc = DateTime.now().toUtc();
      devicesByName.putIfAbsent(
        currentDeviceName,
        () => BackupDevice(
          name: currentDeviceName,
          lastActiveUtc: nowUtc,
          current: true,
        ),
      );
      final devices = devicesByName.values.toList()
        ..sort((a, b) => a.current == b.current
            ? b.lastActiveUtc.compareTo(a.lastActiveUtc)
            : (a.current ? -1 : 1));
      state = await store.recordSyncSuccess(nowUtc, devices: devices);
    } catch (_) {
      // Tetap aman secara offline tanpa membuang data lokal.
    } finally {
      _syncing = false;
      if (ownedDb != null) {
        DriftTrackingRepository.unregisterDatabase(ownedDb);
        unawaited(ownedDb.close());
      }
    }
    return state.copyWith(connected: true);
  }

  /// Mencadangkan 1 sesi yang baru selesai secara otomatis jika pengguna
  /// berlangganan Plus dan aturan Wi-Fi terpenuhi.
  Future<void> backupSingleSessionIfAllowed(
    TrackingSession session,
    TrackingRepository repo,
  ) async {
    if (session.status != TrackingSessionStatus.completed) return;
    final client = SupabaseServices.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    if (!PlusDependencies.controller.hasPlus) return;

    try {
      final store = await _localStore();
      final state = await store.load();
      if (!state.autoBackup) return;
      if (!await _isNetworkAllowed(wifiOnly: state.wifiOnly)) return;

      final points = await repo.points(session.id);
      final encoded = encodeSessionBundle(session, points);
      final deviceName = await _deviceName();
      final nowUtc = DateTime.now().toUtc();

      await client.from(_table).upsert(
        <String, dynamic>{
          'user_id': user.id,
          'session_id': session.id,
          'activity_type': session.activityType,
          'started_at': session.startedAtUtc.toUtc().toIso8601String(),
          'ended_at': session.endedAtUtc?.toUtc().toIso8601String(),
          'bundle_gzip_b64': encoded.gzipBase64,
          'bundle_bytes': encoded.byteLength,
          'device_name': deviceName,
          'updated_at': nowUtc.toIso8601String(),
        },
        onConflict: 'user_id,session_id',
      );
      await store.recordSyncSuccess(nowUtc);
    } catch (_) {}
  }
}
