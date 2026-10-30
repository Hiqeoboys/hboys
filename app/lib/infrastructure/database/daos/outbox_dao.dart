import 'package:drift/drift.dart';

import '../app_database.dart';

part 'outbox_dao.g.dart';

@DriftAccessor(tables: [Outbox])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(super.db);

  /// Idempoten: entri dengan [messageId] yang sama tidak diduplikasi.
  Future<void> enqueue({
    required String messageId,
    required Uint8List packet,
    required int priority,
    required DateTime enqueuedAtUtc,
    required DateTime nextAttemptAtUtc,
    required bool repeatUntilAck,
  }) async {
    await into(outbox).insert(
      OutboxCompanion.insert(
        messageId: messageId,
        packet: packet,
        priority: priority,
        enqueuedAtUtc: enqueuedAtUtc,
        nextAttemptAtUtc: nextAttemptAtUtc,
        repeatUntilAck: Value(repeatUntilAck),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<bool> contains(String messageId) async {
    final row = await (select(outbox)
          ..where((t) => t.messageId.equals(messageId)))
        .getSingleOrNull();
    return row != null;
  }

  Future<int> pendingCount() async {
    final count = outbox.messageId.count();
    final query = selectOnly(outbox)..addColumns([count]);
    return (await query.getSingle()).read(count) ?? 0;
  }

  Future<List<OutboxRow>> due(DateTime nowUtc, {int limit = 20}) =>
      (select(outbox)
            ..where((t) => t.nextAttemptAtUtc.isSmallerOrEqualValue(nowUtc))
            ..orderBy([
              (t) => OrderingTerm(expression: t.priority),
              (t) => OrderingTerm(expression: t.enqueuedAtUtc),
              (t) => OrderingTerm(expression: t.messageId),
            ])
            ..limit(limit))
          .get();

  Future<void> recordAttempt(String messageId, DateTime nextAttemptAtUtc) {
    return transaction(() async {
      final row = await (select(outbox)
            ..where((t) => t.messageId.equals(messageId)))
          .getSingleOrNull();
      if (row == null) return;

      await (update(outbox)..where((t) => t.messageId.equals(messageId))).write(
        OutboxCompanion(
          attempts: Value(row.attempts + 1),
          nextAttemptAtUtc: Value(nextAttemptAtUtc),
        ),
      );
    });
  }

  Future<int> deleteById(String messageId) =>
      (delete(outbox)..where((t) => t.messageId.equals(messageId))).go();
}
