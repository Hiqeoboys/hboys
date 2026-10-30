import 'dart:async';

import 'package:drift/drift.dart';
import 'package:mesh_protocol/mesh_protocol.dart';

import '../../../features/chat/domain/chat_message.dart';
import '../../../features/chat/domain/chat_repository.dart';
import '../../../features/chat/domain/media_attachment.dart';
import '../app_database.dart';
import '../daos/chat_dao.dart';

class DriftChatRepository implements ChatRepository {
  DriftChatRepository(AppDatabase db) : _dao = ChatDao(db);

  final ChatDao _dao;

  @override
  Future<void> saveMessage(ChatMessage message) => _dao.upsertMessage(
        MessagesCompanion.insert(
          id: message.messageId,
          authorId: message.authorId,
          seq: message.seq,
          groupId: message.groupId,
          typeCode: message.type.code,
          sentAtUtc: message.sentAtUtc.toUtc(),
          receivedAtUtc: message.receivedAtUtc.toUtc(),
          payload: message.payload,
          signature: Value(message.signature),
          isOutgoing: Value(message.isOutgoing),
        ),
      );

  @override
  Future<ChatMessage?> findMessage(String messageId) async {
    final row = await _dao.messageById(messageId);
    return row == null ? null : _toMessage(row);
  }

  @override
  Future<List<ChatMessage>> recentMessages(
    String groupId, {
    int limit = 50,
    DateTime? beforeUtc,
  }) async {
    final rows = await _dao.recentMessages(
      groupId,
      limit: limit,
      beforeUtc: beforeUtc?.toUtc(),
    );
    return rows.map(_toMessage).toList(growable: false);
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String groupId, {int limit = 50}) =>
      _dao
          .watchMessages(groupId, limit: limit)
          .map((rows) => rows.map(_toMessage).toList(growable: false));

  @override
  Future<int> nextSeq({required String groupId, required String authorId}) =>
      _dao.nextSeq(groupId: groupId, authorId: authorId);

  @override
  Future<void> saveMedia(MediaAttachment media) => _dao.upsertMedia(
        MediaCompanion.insert(
          id: media.id,
          messageId: Value(media.messageId),
          groupId: Value(media.groupId),
          kind: media.kind.name,
          relativePath: media.relativePath,
          mimeType: media.mimeType,
          byteSize: media.byteSize,
          createdAtUtc: media.createdAtUtc.toUtc(),
        ),
      );

  @override
  Future<List<MediaAttachment>> mediaForMessage(String messageId) async {
    final rows = await _dao.mediaForMessage(messageId);
    return rows.map(_toMedia).toList(growable: false);
  }

  ChatMessage _toMessage(MessageRow row) => ChatMessage(
        authorId: row.authorId,
        seq: row.seq,
        groupId: row.groupId,
        type: PacketType.fromCode(row.typeCode),
        sentAtUtc: row.sentAtUtc,
        receivedAtUtc: row.receivedAtUtc,
        payload: row.payload,
        signature: row.signature,
        isOutgoing: row.isOutgoing,
      );

  MediaAttachment _toMedia(MediaRow row) => MediaAttachment(
        id: row.id,
        messageId: row.messageId,
        groupId: row.groupId,
        kind: _kindFromDb(row.kind),
        relativePath: row.relativePath,
        mimeType: row.mimeType,
        byteSize: row.byteSize,
        createdAtUtc: row.createdAtUtc,
      );

  MediaKind _kindFromDb(String value) => switch (value) {
        'image' => MediaKind.image,
        'audio' => MediaKind.audio,
        'video' => MediaKind.video,
        'file' => MediaKind.file,
        _ => throw StateError('Jenis media tidak dikenal: $value'),
      };
}
