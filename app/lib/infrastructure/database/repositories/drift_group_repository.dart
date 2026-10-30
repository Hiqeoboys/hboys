import 'dart:async';

import 'package:drift/drift.dart';

import '../../../features/groups/domain/group.dart';
import '../../../features/groups/domain/group_repository.dart';
import '../app_database.dart';
import '../daos/group_dao.dart';

class DriftGroupRepository implements GroupRepository {
  DriftGroupRepository(AppDatabase db) : _dao = GroupDao(db);

  final GroupDao _dao;

  @override
  Future<void> saveGroup(Group group) => _dao.upsertGroup(
        GroupsCompanion.insert(
          id: group.id,
          name: group.name,
          ownerId: group.ownerId,
          mountain: Value(group.mountain),
          keyVersion: Value(group.keyVersion),
          createdAtUtc: group.createdAtUtc.toUtc(),
        ),
      );

  @override
  Future<Group?> findGroup(String id) async {
    final row = await _dao.groupById(id);
    return row == null ? null : _toGroup(row);
  }

  @override
  Stream<List<Group>> watchGroups() =>
      _dao.watchAllGroups().map((rows) => rows.map(_toGroup).toList());

  @override
  Future<void> deleteGroup(String id) async {
    await _dao.deleteGroup(id);
  }

  @override
  Future<void> saveMember(GroupMember member) => _dao.upsertMember(
        MembersCompanion.insert(
          groupId: member.groupId,
          userId: member.userId,
          username: member.username,
          role: Value(member.role.name),
          joinedAtUtc: member.joinedAtUtc.toUtc(),
        ),
      );

  @override
  Future<List<GroupMember>> membersOf(String groupId) async {
    final rows = await _dao.membersOf(groupId);
    return rows.map(_toMember).toList(growable: false);
  }

  @override
  Stream<List<GroupMember>> watchMembers(String groupId) =>
      _dao.watchMembers(groupId).map(
            (rows) => rows.map(_toMember).toList(growable: false),
          );

  @override
  Future<void> removeMember(String groupId, String userId) async {
    await _dao.deleteMember(groupId, userId);
  }

  Group _toGroup(GroupRow row) => Group(
        id: row.id,
        name: row.name,
        ownerId: row.ownerId,
        mountain: row.mountain,
        keyVersion: row.keyVersion,
        createdAtUtc: row.createdAtUtc,
      );

  GroupMember _toMember(MemberRow row) => GroupMember(
        groupId: row.groupId,
        userId: row.userId,
        username: row.username,
        role: _roleFromDb(row.role),
        joinedAtUtc: row.joinedAtUtc,
      );

  GroupRole _roleFromDb(String value) => switch (value) {
        'owner' => GroupRole.owner,
        'member' => GroupRole.member,
        _ => throw StateError('Role anggota tidak dikenal: $value'),
      };
}
