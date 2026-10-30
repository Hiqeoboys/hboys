import 'group.dart';

abstract interface class GroupRepository {
  Future<void> saveGroup(Group group);
  Future<Group?> findGroup(String id);
  Stream<List<Group>> watchGroups();

  /// Menghapus grup beserta anggotanya (cascade di database).
  Future<void> deleteGroup(String id);

  Future<void> saveMember(GroupMember member);
  Future<List<GroupMember>> membersOf(String groupId);
  Stream<List<GroupMember>> watchMembers(String groupId);
  Future<void> removeMember(String groupId, String userId);
}
