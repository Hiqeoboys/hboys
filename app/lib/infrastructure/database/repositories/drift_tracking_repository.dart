import 'dart:async';

import 'package:drift/drift.dart';

import '../../../features/tracking/domain/track_point.dart';
import '../../../features/tracking/domain/tracking_repository.dart';
import '../../../features/tracking/domain/tracking_session.dart';
import '../app_database.dart';
import '../daos/tracking_dao.dart';

class DriftTrackingRepository implements TrackingRepository {
  DriftTrackingRepository(AppDatabase db) : _dao = TrackingDao(db);

  final TrackingDao _dao;

  @override
  Future<void> saveSession(TrackingSession session) => _dao.upsertSession(
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

  @override
  Future<TrackingSession?> findSession(String id) async {
    final row = await _dao.sessionById(id);
    return row == null ? null : _toSession(row);
  }

  @override
  Future<TrackingSession?> findActiveSession() async {
    final row = await _dao.activeSession();
    return row == null ? null : _toSession(row);
  }

  @override
  Stream<List<TrackingSession>> watchSessions() =>
      _dao.watchSessions().map((rows) => rows.map(_toSession).toList());

  @override
  Future<void> deleteSession(String id) async {
    await _dao.deleteSession(id);
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
  Future<List<TrackPoint>> points(String sessionId) async {
    final rows = await _dao.points(sessionId);
    return rows.map(_toPoint).toList(growable: false);
  }

  @override
  Future<TrackPoint?> latestPoint(String sessionId) async {
    final row = await _dao.latestPoint(sessionId);
    return row == null ? null : _toPoint(row);
  }

  TrackingSession _toSession(SessionRow row) => TrackingSession(
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
