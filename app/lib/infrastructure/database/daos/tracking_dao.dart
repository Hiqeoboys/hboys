import 'package:drift/drift.dart';

import '../app_database.dart';

part 'tracking_dao.g.dart';

@DriftAccessor(tables: [Sessions, TrackPoints])
class TrackingDao extends DatabaseAccessor<AppDatabase>
    with _$TrackingDaoMixin {
  TrackingDao(super.db);

  Future<void> upsertSession(SessionsCompanion session) =>
      into(sessions).insertOnConflictUpdate(session);

  Future<SessionRow?> sessionById(String id) =>
      (select(sessions)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<SessionRow?> activeSession() => (select(sessions)
        ..where((t) => t.status.equals('active'))
        ..orderBy([
          (t) =>
              OrderingTerm(expression: t.startedAtUtc, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.id),
        ])
        ..limit(1))
      .getSingleOrNull();

  Stream<List<SessionRow>> watchSessions() => (select(sessions)
        ..orderBy([
          (t) =>
              OrderingTerm(expression: t.startedAtUtc, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.id),
        ]))
      .watch();

  Future<int> deleteSession(String id) =>
      (delete(sessions)..where((t) => t.id.equals(id))).go();

  Future<void> insertPoint(TrackPointsCompanion point) async {
    await into(trackPoints).insert(point);
  }

  Future<List<TrackPointRow>> points(String sessionId) => (select(trackPoints)
        ..where((t) => t.sessionId.equals(sessionId))
        ..orderBy([
          (t) => OrderingTerm(expression: t.recordedAtUtc),
          (t) => OrderingTerm(expression: t.id),
        ]))
      .get();

  Future<TrackPointRow?> latestPoint(String sessionId) => (select(trackPoints)
        ..where((t) => t.sessionId.equals(sessionId))
        ..orderBy([
          (t) =>
              OrderingTerm(expression: t.recordedAtUtc, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
        ])
        ..limit(1))
      .getSingleOrNull();
}
