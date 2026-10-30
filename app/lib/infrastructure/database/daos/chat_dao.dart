import 'package:drift/drift.dart';

import '../app_database.dart';

part 'chat_dao.g.dart';

@DriftAccessor(tables: [Messages, Media])
class ChatDao extends DatabaseAccessor<AppDatabase> with _$ChatDaoMixin {
  ChatDao(super.db);

  Future<void> upsertMessage(MessagesCompanion message) =>
      into(messages).insertOnConflictUpdate(message);

  Future<MessageRow?> messageById(String id) =>
      (select(messages)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<MessageRow>> recentMessages(
    String groupId, {
    int limit = 50,
    DateTime? beforeUtc,
  }) async {
    final query = select(messages)
      ..where((t) => t.groupId.equals(groupId))
      ..orderBy([
        (t) => OrderingTerm(expression: t.sentAtUtc, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    if (beforeUtc != null) {
      query.where((t) => t.sentAtUtc.isSmallerThanValue(beforeUtc));
    }
    final rows = await query.get();
    return rows.reversed.toList(growable: false);
  }

  Stream<List<MessageRow>> watchMessages(String groupId, {int limit = 50}) {
    final query = select(messages)
      ..where((t) => t.groupId.equals(groupId))
      ..orderBy([
        (t) => OrderingTerm(expression: t.sentAtUtc, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return query
        .watch()
        .map((rows) => rows.reversed.toList(growable: false));
  }

  Future<void> upsertMedia(MediaCompanion attachment) =>
      into(media).insertOnConflictUpdate(attachment);

  Future<List<MediaRow>> mediaForMessage(String messageId) => (select(media)
        ..where((t) => t.messageId.equals(messageId))
        ..orderBy([
          (t) => OrderingTerm(expression: t.createdAtUtc),
          (t) => OrderingTerm(expression: t.id),
        ]))
      .get();
}
