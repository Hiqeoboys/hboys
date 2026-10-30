// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invitation_dao.dart';

// ignore_for_file: type=lint
mixin _$InvitationDaoMixin on DatabaseAccessor<AppDatabase> {
  $InvitationsTable get invitations => attachedDatabase.invitations;
  InvitationDaoManager get managers => InvitationDaoManager(this);
}

class InvitationDaoManager {
  final _$InvitationDaoMixin _db;
  InvitationDaoManager(this._db);
  $$InvitationsTableTableManager get invitations =>
      $$InvitationsTableTableManager(_db.attachedDatabase, _db.invitations);
}
