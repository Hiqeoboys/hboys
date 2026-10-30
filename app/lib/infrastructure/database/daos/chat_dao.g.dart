// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_dao.dart';

// ignore_for_file: type=lint
mixin _$ChatDaoMixin on DatabaseAccessor<AppDatabase> {
  $MessagesTable get messages => attachedDatabase.messages;
  $MediaTable get media => attachedDatabase.media;
  ChatDaoManager get managers => ChatDaoManager(this);
}

class ChatDaoManager {
  final _$ChatDaoMixin _db;
  ChatDaoManager(this._db);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db.attachedDatabase, _db.messages);
  $$MediaTableTableManager get media =>
      $$MediaTableTableManager(_db.attachedDatabase, _db.media);
}
