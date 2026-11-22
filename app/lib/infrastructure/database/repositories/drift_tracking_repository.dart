import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../../features/tracking/domain/track_point.dart';
import '../../../features/tracking/domain/tracking_repository.dart';
import '../../../features/tracking/domain/tracking_session.dart';
import '../../auth/active_account_scope.dart';
import '../app_database.dart';
import '../daos/tracking_dao.dart';

class DriftTrackingRepository implements TrackingRepository {
  DriftTrackingRepository(
    AppDatabase db, {
    String? Function()? ownerUserIdProvider,
    bool enforceAccountScope = true,
  })  : _db = db,
        _dao = TrackingDao(db),
        _ownerUserIdProvider =
            ownerUserIdProvider ?? ActiveAccountScope.currentUserId,
        _enforceAccountScope = enforceAccountScope {
    _openDatabases.add(db);
  }

  final AppDatabase _db;
  final TrackingDao _dao;
  final String? Function() _ownerUserIdProvider;
  final bool _enforceAccountScope;

  static final Set<AppDatabase> _openDatabases = <AppDatabase>{};

  /// Notifier reaktif lintas instance database/halaman yang bertambah setiap
  /// kali sesi disimpan, diselesaikan, atau dihapus.
  static final ValueNotifier<int> historyRevision = ValueNotifier<int>(0);

  /// Dipanggil saat sesi selesai/diubah (termasuk dari isolate foreground
  /// service Android) agar seluruh halaman seperti Beranda dan Profil langsung
  /// memuat ulang data terbaru tanpa perlu menutup aplikasi.
  static void notifyExternalChange() {
    historyRevision.value++;
    final stale = <AppDatabase>[];
    for (final db in _openDatabases) {
      try {
        db.notifyUpdates(<TableUpdate>{
          TableUpdate.onTable(db.sessions),
          TableUpdate.onTable(db.trackPoints),
        });
      } catch (_) {
        stale.add(db);
      }
    }
    _openDatabases.removeAll(stale);
  }

  /// Melepaskan referensi database saat halaman ditutup.
  static void unregisterDatabase(AppDatabase db) {
    _openDatabases.remove(db);
  }

  @override
  Future<void> saveSession(TrackingSession session) async {
    await _dao.upsertSession(
      SessionsCompanion.insert(
        id: session.id,
        startedAtUtc: session.startedAtUtc.toUtc(),
        endedAtUtc: Value(session.endedAtUtc?.toUtc()),
        groupId: Value(session.groupId),
        trailId: Value(session.trailId),
        distanceM: Value(session.distanceM),
        movingSeconds: Value(session.movingSeconds),
        elevationGainM: Value(session.elevationGainM),
        elevationLossM: Value(session.elevationLossM),
        status: Value(session.status.name),
      ),
    );
    await _upsertMetadata(session);
    notifyExternalChange();
  }

  static String? _normalizeOwner(String? owner) {
    final trimmed = owner?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  String? _activeOwner() => _normalizeOwner(_ownerUserIdProvider());

  bool _matchesActiveOwner(String? rowOwner) {
    if (!_enforceAccountScope) return true;
    final active = _activeOwner();
    final normalizedRowOwner = _normalizeOwner(rowOwner);
    if (active != null) {
      return normalizedRowOwner == active;
    }
    return normalizedRowOwner == null || normalizedRowOwner == 'guest';
  }

  Future<void> _upsertMetadata(TrackingSession session) async {
    final activityType = TrackingSession.normalizeActivityType(session.activityType);
    final owner = _normalizeOwner(session.ownerUserId) ?? _activeOwner();
    try {
      await _db.customStatement(
        '''
        INSERT INTO session_metadata (session_id, reached_summit, mountain_name, trail_name, activity_type, owner_user_id)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(session_id) DO UPDATE SET
          reached_summit = CASE WHEN excluded.activity_type = 'jogging' THEN 0 WHEN excluded.reached_summit = 1 THEN 1 ELSE session_metadata.reached_summit END,
          mountain_name = CASE WHEN excluded.activity_type = 'jogging' THEN NULL ELSE COALESCE(excluded.mountain_name, session_metadata.mountain_name) END,
          trail_name = CASE WHEN excluded.activity_type = 'jogging' THEN NULL ELSE COALESCE(excluded.trail_name, session_metadata.trail_name) END,
          activity_type = CASE WHEN excluded.activity_type = 'jogging' THEN 'jogging' ELSE session_metadata.activity_type END,
          owner_user_id = COALESCE(excluded.owner_user_id, session_metadata.owner_user_id)
        ''',
        <Object?>[
          session.id,
          session.isJogging ? 0 : (session.reachedSummit ? 1 : 0),
          session.isJogging ? null : session.mountainName,
          session.isJogging ? null : session.trailName,
          activityType,
          owner,
        ],
      );
    } catch (_) {
      // Tabel metadata mungkin belum tersedia di skema uji khusus.
    }
  }

  Future<Map<String, _SessionMeta>> _loadAllMetadata() async {
    try {
      final rows = await _db
          .customSelect(
            'SELECT session_id, reached_summit, mountain_name, trail_name, activity_type, owner_user_id FROM session_metadata',
          )
          .get();
      return <String, _SessionMeta>{
        for (final row in rows)
          row.read<String>('session_id'): _SessionMeta(
            reachedSummit: row.read<int>('reached_summit') == 1,
            mountainName: row.readNullable<String>('mountain_name'),
            trailName: row.readNullable<String>('trail_name'),
            activityType: TrackingSession.normalizeActivityType(
              row.readNullable<String>('activity_type'),
            ),
            ownerUserId: _normalizeOwner(row.readNullable<String>('owner_user_id')),
          ),
      };
    } catch (_) {
      return const <String, _SessionMeta>{};
    }
  }

  Future<_SessionMeta?> _loadMetadata(String sessionId) async {
    try {
      final row = await _db
          .customSelect(
            'SELECT reached_summit, mountain_name, trail_name, activity_type, owner_user_id FROM session_metadata WHERE session_id = ?',
            variables: <Variable<Object>>[Variable.withString(sessionId)],
          )
          .getSingleOrNull();
      if (row == null) return null;
      return _SessionMeta(
        reachedSummit: row.read<int>('reached_summit') == 1,
        mountainName: row.readNullable<String>('mountain_name'),
        trailName: row.readNullable<String>('trail_name'),
        activityType: TrackingSession.normalizeActivityType(
          row.readNullable<String>('activity_type'),
        ),
        ownerUserId: _normalizeOwner(row.readNullable<String>('owner_user_id')),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<TrackingSession?> findSession(String id) async {
    final row = await _dao.sessionById(id);
    if (row == null) return null;
    final meta = await _loadMetadata(id);
    if (!_matchesActiveOwner(meta?.ownerUserId)) return null;
    return _toSession(row, meta);
  }

  @override
  Future<TrackingSession?> findActiveSession() async {
    final row = await _dao.activeSession();
    if (row == null) return null;
    final meta = await _loadMetadata(row.id);
    if (_matchesActiveOwner(meta?.ownerUserId)) {
      return _toSession(row, meta);
    }
    // Cek bila ada sesi aktif lain yang memang milik akun aktif.
    final all = await watchSessions().first;
    for (final s in all) {
      if (s.status == TrackingSessionStatus.active) return s;
    }
    return null;
  }

  @override
  Stream<List<TrackingSession>> watchSessions() =>
      _dao.watchSessions().asyncMap((rows) async {
        final metas = await _loadAllMetadata();
        return rows
            .where((row) => _matchesActiveOwner(metas[row.id]?.ownerUserId))
            .map((row) => _toSession(row, metas[row.id]))
            .toList(growable: false);
      });

  @override
  Future<void> deleteSession(String id) async {
    await _dao.deleteSession(id);
    try {
      await _db.customStatement(
        'DELETE FROM session_metadata WHERE session_id = ?',
        <Object?>[id],
      );
    } catch (_) {}
    notifyExternalChange();
  }

  void disposeDatabaseRegistration() {
    unregisterDatabase(_db);
  }

  @override
  Future<void> addPoint(String sessionId, TrackPoint point) => _dao.insertPoint(
        TrackPointsCompanion.insert(
          sessionId: sessionId,
          lat: point.lat,
          lon: point.lon,
          altitudeM: Value(point.altitudeM),
          accuracyM: point.accuracyM,
          speedMps: Value(point.speedMps),
          recordedAtUtc: point.timestampUtc.toUtc(),
        ),
      );

  @override
  Future<void> clearPoints(String sessionId) async {
    await _dao.deletePoints(sessionId);
    notifyExternalChange();
  }

  @override
  Future<List<TrackPoint>> points(String sessionId) async {
    final rows = await _dao.points(sessionId);
    return rows.map(_toPoint).toList(growable: false);
  }

  @override
  Future<TrackPoint?> latestPoint(String sessionId) async {
    final row = await _dao.latestPoint(sessionId);
    return row == null ? null : _toPoint(row);
  }

  TrackingSession _toSession(SessionRow row, [_SessionMeta? meta]) =>
      TrackingSession(
        id: row.id,
        startedAtUtc: row.startedAtUtc,
        endedAtUtc: row.endedAtUtc,
        groupId: row.groupId,
        trailId: row.trailId,
        distanceM: row.distanceM,
        movingSeconds: row.movingSeconds,
        elevationGainM: row.elevationGainM,
        elevationLossM: row.elevationLossM,
        status: _statusFromDb(row.status),
        reachedSummit: meta?.reachedSummit ?? false,
        mountainName: meta?.mountainName,
        trailName: meta?.trailName,
        activityType: meta?.activityType ?? TrackingSession.activityHiking,
        ownerUserId: meta?.ownerUserId,
      );

  TrackPoint _toPoint(TrackPointRow row) => TrackPoint(
        lat: row.lat,
        lon: row.lon,
        timestampUtc: row.recordedAtUtc,
        accuracyM: row.accuracyM,
        altitudeM: row.altitudeM,
        speedMps: row.speedMps,
      );

  TrackingSessionStatus _statusFromDb(String value) => switch (value) {
        'active' => TrackingSessionStatus.active,
        'completed' => TrackingSessionStatus.completed,
        _ => throw StateError('Status sesi tidak dikenal: $value'),
      };
}

class _SessionMeta {
  const _SessionMeta({
    required this.reachedSummit,
    this.mountainName,
    this.trailName,
    this.activityType = TrackingSession.activityHiking,
    this.ownerUserId,
  });

  final bool reachedSummit;
  final String? mountainName;
  final String? trailName;
  final String activityType;
  final String? ownerUserId;
}
