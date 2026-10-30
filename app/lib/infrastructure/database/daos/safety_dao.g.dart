// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'safety_dao.dart';

// ignore_for_file: type=lint
mixin _$SafetyDaoMixin on DatabaseAccessor<AppDatabase> {
  $GroupsTable get groups => attachedDatabase.groups;
  $SosEventsTable get sosEvents => attachedDatabase.sosEvents;
  $EmergencyContactsTable get emergencyContacts =>
      attachedDatabase.emergencyContacts;
  SafetyDaoManager get managers => SafetyDaoManager(this);
}

class SafetyDaoManager {
  final _$SafetyDaoMixin _db;
  SafetyDaoManager(this._db);
  $$GroupsTableTableManager get groups =>
      $$GroupsTableTableManager(_db.attachedDatabase, _db.groups);
  $$SosEventsTableTableManager get sosEvents =>
      $$SosEventsTableTableManager(_db.attachedDatabase, _db.sosEvents);
  $$EmergencyContactsTableTableManager get emergencyContacts =>
      $$EmergencyContactsTableTableManager(
          _db.attachedDatabase, _db.emergencyContacts);
}
