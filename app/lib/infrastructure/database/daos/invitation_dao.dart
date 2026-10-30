import 'package:drift/drift.dart';

import '../app_database.dart';

part 'invitation_dao.g.dart';

@DriftAccessor(tables: [Invitations])
class InvitationDao extends DatabaseAccessor<AppDatabase>
    with _$InvitationDaoMixin {
  InvitationDao(super.db);

  Future<void> upsert(InvitationsCompanion invitation) =>
      into(invitations).insertOnConflictUpdate(invitation);

  Future<InvitationRow?> byId(String id) =>
      (select(invitations)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<InvitationRow>> pendingFor(
    String inviteeUsername,
    DateTime nowUtc,
  ) =>
      (select(invitations)
            ..where(
              (t) =>
                  t.inviteeUsername.equals(inviteeUsername) &
                  t.status.equals('pending') &
                  t.expiresAtUtc.isBiggerThanValue(nowUtc),
            )
            ..orderBy([(t) => OrderingTerm(expression: t.createdAtUtc)]))
          .get();

  Stream<List<InvitationRow>> watchAll() => (select(invitations)
        ..orderBy([
          (t) => OrderingTerm(expression: t.createdAtUtc, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.id),
        ]))
      .watch();
}
