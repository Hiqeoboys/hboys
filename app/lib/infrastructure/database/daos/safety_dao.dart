import 'package:drift/drift.dart';

import '../app_database.dart';

part 'safety_dao.g.dart';

@DriftAccessor(tables: [SosEvents, EmergencyContacts])
class SafetyDao extends DatabaseAccessor<AppDatabase> with _$SafetyDaoMixin {
  SafetyDao(super.db);

  Future<void> upsertSosEvent(SosEventsCompanion event) =>
      into(sosEvents).insertOnConflictUpdate(event);

  Future<SosEventRow?> sosEventById(String id) =>
      (select(sosEvents)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<SosEventRow>> activeSosEvents() => (select(sosEvents)
        ..where((t) => t.status.equals('active'))
        ..orderBy([
          (t) => OrderingTerm(
                expression: t.createdAtUtc,
                mode: OrderingMode.desc,
              ),
        ]))
      .get();

  Stream<List<SosEventRow>> watchSosEvents() => (select(sosEvents)
        ..orderBy([
          (t) => OrderingTerm(
                expression: t.createdAtUtc,
                mode: OrderingMode.desc,
              ),
          (t) => OrderingTerm(expression: t.id),
        ]))
      .watch();

  Future<bool> cancelSosEvent(String id, DateTime nowUtc) async {
    final changed = await (update(sosEvents)
          ..where((t) => t.id.equals(id) & t.status.equals('active')))
        .write(
      SosEventsCompanion(
        status: const Value('cancelled'),
        cancelledAtUtc: Value(nowUtc),
      ),
    );
    return changed > 0;
  }

  Future<void> upsertContact(EmergencyContactsCompanion contact) =>
      into(emergencyContacts).insertOnConflictUpdate(contact);

  Future<List<ContactRow>> contactsOf(String userId) =>
      (select(emergencyContacts)
            ..where((t) => t.userId.equals(userId))
            ..orderBy([
              (t) => OrderingTerm(expression: t.createdAtUtc),
              (t) => OrderingTerm(expression: t.id),
            ]))
          .get();

  Stream<List<ContactRow>> watchContacts(String userId) =>
      (select(emergencyContacts)
            ..where((t) => t.userId.equals(userId))
            ..orderBy([
              (t) => OrderingTerm(expression: t.createdAtUtc),
              (t) => OrderingTerm(expression: t.id),
            ]))
          .watch();

  Future<int> deleteContact(String id) =>
      (delete(emergencyContacts)..where((t) => t.id.equals(id))).go();
}
