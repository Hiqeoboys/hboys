// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tracking_dao.dart';

// ignore_for_file: type=lint
mixin _$TrackingDaoMixin on DatabaseAccessor<AppDatabase> {
  $SessionsTable get sessions => attachedDatabase.sessions;
  $TrackPointsTable get trackPoints => attachedDatabase.trackPoints;
  TrackingDaoManager get managers => TrackingDaoManager(this);
}

class TrackingDaoManager {
  final _$TrackingDaoMixin _db;
  TrackingDaoManager(this._db);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db.attachedDatabase, _db.sessions);
  $$TrackPointsTableTableManager get trackPoints =>
      $$TrackPointsTableTableManager(_db.attachedDatabase, _db.trackPoints);
}
