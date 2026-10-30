import 'package:drift/drift.dart';

import '../app_database.dart';

part 'group_dao.g.dart';

@DriftAccessor(tables: [Groups, Members])
class GroupDao extends DatabaseAccessor<AppDatabase> with _$GroupDaoMixin {
  GroupDao(super.db);

  Future<void> upsertGroup(GroupsCompanion group) =>
      into(groups).insertOnConflictUpdate(group);

  Future<GroupRow?> groupById(String id) =>
      (select(groups)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<List<GroupRow>> watchAllGroups() => select(groups).watch();

  Future<int> deleteGroup(String id) =>
      (delete(groups)..where((t) => t.id.equals(id))).go();

  Future<void> upsertMember(MembersCompanion member) =>
      into(members).insertOnConflictUpdate(member);

  Future<List<MemberRow>> membersOf(String groupId) => (select(members)
        ..where((t) => t.groupId.equals(groupId))
        ..orderBy([
          (t) => OrderingTerm(expression: t.joinedAtUtc),
          (t) => OrderingTerm(expression: t.userId),
        ]))
      .get();

  Stream<List<MemberRow>> watchMembers(String groupId) => (select(members)
        ..where((t) => t.groupId.equals(groupId))
        ..orderBy([
          (t) => OrderingTerm(expression: t.joinedAtUtc),
          (t) => OrderingTerm(expression: t.userId),
        ]))
      .watch();

  Future<int> deleteMember(String groupId, String userId) => (delete(members)
        ..where(
          (t) => t.groupId.equals(groupId) & t.userId.equals(userId),
        ))
      .go();
}
