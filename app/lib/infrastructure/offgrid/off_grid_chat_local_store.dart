import 'dart:async';

import 'package:drift/drift.dart';

import '../../features/chat/domain/group_chat_models.dart';
import '../database/app_database.dart';

/// Penyimpanan lokal-first tunggal (*single source of truth*) untuk pesan grup
/// (`local_group_messages`) dan lokasi terakhir anggota (`local_member_locations`).
///
/// Selalu memakai `client_msg_id` sebagai kunci utama deduplikasi agar paket yang
/// datang berganda dari BLE Mesh, Wi-Fi Direct, maupun Supabase Realtime tidak
/// pernah menghasilkan pesan duplikat di UI.
class OffGridChatLocalStore {
  OffGridChatLocalStore({AppDatabase? database}) : _db = database;

  final AppDatabase? _db;

  // Fallback & cache in-memory untuk reaktivitas stream seketika serta
  // lingkungan widget test tanpa SQLite disk.
  final Map<String, List<GroupMessageRecord>> _memMessages =
      <String, List<GroupMessageRecord>>{};
  final Map<String, List<MemberLastLocation>> _memLocations =
      <String, List<MemberLastLocation>>{};
  final Set<String> _memMeshDeliveredIds = <String>{};

  final Map<String, StreamController<List<GroupMessageRecord>>> _msgCtrls =
      <String, StreamController<List<GroupMessageRecord>>>{};
  final Map<String, StreamController<List<MemberLastLocation>>> _locCtrls =
      <String, StreamController<List<MemberLastLocation>>>{};

  bool _disposed = false;
  bool _migratedLegacyClientIds = false;

  Variable<Object> _nullableText(String? value) =>
      value == null ? const Variable<String>(null) : Variable<String>(value);

  Variable<Object> _nullableInt(int? value) =>
      value == null ? const Variable<int>(null) : Variable<int>(value);

  /// Mengamati daftar pesan satu grup terurut kronologis (`client_created_at ASC`).
  Stream<List<GroupMessageRecord>> watchGroupMessages(String groupId) async* {
    yield await messagesForGroup(groupId);
    yield* _msgController(groupId).stream;
  }

  /// Membaca satu rekaman pesan terakhir untuk tiap grup (untuk mengurutkan daftar grup).
  Future<Map<String, GroupMessageRecord>> latestMessagePerGroup() async {
    final db = _db;
    if (db == null) {
      final result = <String, GroupMessageRecord>{};
      for (final entry in _memMessages.entries) {
        if (entry.value.isEmpty) continue;
        var latest = entry.value.first;
        for (final m in entry.value) {
          if (m.clientCreatedAtUtc.isAfter(latest.clientCreatedAtUtc)) {
            latest = m;
          }
        }
        result[entry.key] = latest;
      }
      return result;
    }

    try {
      final rows = await db.customSelect(
        'SELECT * FROM local_group_messages '
        'ORDER BY client_created_at DESC, client_msg_id DESC',
      ).get();
      final result = <String, GroupMessageRecord>{};
      for (final r in rows) {
        final gid = r.data['group_id']?.toString() ?? '';
        if (gid.isEmpty || result.containsKey(gid)) continue;
        result[gid] = GroupMessageRecord.fromLocalSqliteMap(r.data);
      }
      return result;
    } catch (_) {
      return const <String, GroupMessageRecord>{};
    }
  }

  /// Membaca seluruh pesan tersimpan untuk [groupId] terurut `client_created_at ASC`.
  Future<List<GroupMessageRecord>> messagesForGroup(String groupId) async {
    final db = _db;
    if (db == null) {
      final list = _memMessages[groupId] ?? const <GroupMessageRecord>[];
      return List<GroupMessageRecord>.unmodifiable(<GroupMessageRecord>[
        for (final m in list)
          (m.syncStatus == ChatSyncStatus.pending &&
                  _memMeshDeliveredIds.contains(m.clientMsgId))
              ? m.copyWith(syncStatus: ChatSyncStatus.meshDelivered)
              : m,
      ]);
    }

    final rows = await db.customSelect(
      'SELECT * FROM local_group_messages WHERE group_id = ? '
      'ORDER BY client_created_at ASC, client_msg_id ASC',
      variables: <Variable<Object>>[Variable<String>(groupId)],
    ).get();

    final ackedIds = await _readAckedIds(db);

    return rows.map((r) {
      final rec = GroupMessageRecord.fromLocalSqliteMap(r.data);
      if (rec.syncStatus == ChatSyncStatus.pending &&
          (ackedIds.contains(rec.clientMsgId) ||
              _memMeshDeliveredIds.contains(rec.clientMsgId))) {
        return rec.copyWith(syncStatus: ChatSyncStatus.meshDelivered);
      }
      return rec;
    }).toList(growable: false);
  }

  Future<Set<String>> _readAckedIds(AppDatabase db) async {
    try {
      final rows =
          await db.customSelect('SELECT client_msg_id FROM local_mesh_acks').get();
      return <String>{
        for (final r in rows) r.data['client_msg_id'] as String,
      };
    } catch (_) {
      return const <String>{};
    }
  }

  /// Menandai pesan offline telah terkirim/diterima peer via Hiqeo Mesh
  /// (menjadi Titik Putih, tetap disinkronkan ke Supabase saat online kembali).
  Future<void> markMessageMeshDelivered({
    required String clientMsgId,
    String? groupId,
  }) async {
    _memMeshDeliveredIds.add(clientMsgId);
    final db = _db;
    if (db == null) {
      String? resolvedGroup = groupId;
      for (final entry in _memMessages.entries) {
        final idx =
            entry.value.indexWhere((m) => m.clientMsgId == clientMsgId);
        if (idx >= 0) {
          final current = entry.value[idx];
          if (current.syncStatus == ChatSyncStatus.pending) {
            entry.value[idx] =
                current.copyWith(syncStatus: ChatSyncStatus.meshDelivered);
          }
          resolvedGroup = entry.key;
          break;
        }
      }
      if (resolvedGroup != null) {
        await _emitMessages(resolvedGroup);
      }
      return;
    }

    try {
      await db.customInsert(
        'INSERT OR IGNORE INTO local_mesh_acks (client_msg_id, acked_at) VALUES (?, ?)',
        variables: <Variable<Object>>[
          Variable<String>(clientMsgId),
          Variable<int>(DateTime.now().toUtc().millisecondsSinceEpoch),
        ],
      );
    } catch (_) {}

    String? resolvedGroup = groupId;
    if (resolvedGroup == null) {
      final hit = await db.customSelect(
        'SELECT group_id FROM local_group_messages WHERE client_msg_id = ? LIMIT 1',
        variables: <Variable<Object>>[Variable<String>(clientMsgId)],
      ).getSingleOrNull();
      resolvedGroup = hit?.data['group_id'] as String?;
    }
    if (resolvedGroup != null) {
      await _emitMessages(resolvedGroup);
    }
  }

  /// Menghapus seluruh data lokal (pesan, lokasi, ack) untuk [groupId] secara permanen.
  Future<void> deleteGroupData(String groupId) async {
    _memMessages.remove(groupId);
    _memLocations.remove(groupId);
    final db = _db;
    if (db != null) {
      await db.customUpdate(
        'DELETE FROM local_group_messages WHERE group_id = ?',
        variables: <Variable<Object>>[Variable<String>(groupId)],
      );
      await db.customUpdate(
        'DELETE FROM local_member_locations WHERE group_id = ?',
        variables: <Variable<Object>>[Variable<String>(groupId)],
      );
    }
    await _emitMessages(groupId);
    await _emitLocations(groupId);
  }

  /// Memeriksa apakah [clientMsgId] sudah ada di database lokal.
  Future<bool> hasMessage(String clientMsgId) async {
    final db = _db;
    if (db == null) {
      for (final list in _memMessages.values) {
        if (list.any((m) => m.clientMsgId == clientMsgId)) return true;
      }
      return false;
    }

    final rows = await db.customSelect(
      'SELECT 1 AS hit FROM local_group_messages WHERE client_msg_id = ? LIMIT 1',
      variables: <Variable<Object>>[Variable<String>(clientMsgId)],
    ).get();
    return rows.isNotEmpty;
  }

  /// Menyisipkan pesan atau memperbarui baris yang sudah ada berdasarkan
  /// `client_msg_id` (PRIMARY KEY / UNIQUE).
  ///
  /// Pantulan Supabase Realtime *echo* maupun paket ulang BLE Mesh / Wi-Fi
  /// Direct dengan `client_msg_id` sama SELALU menimpa/memperbarui baris lokal
  /// secara atomik dan tidak pernah membuat baris ganda.
  /// Mengembalikan `true` bila pesan baru disisipkan, atau `false` bila baris
  /// dengan `client_msg_id` tersebut sudah ada dan diperbarui.
  Future<bool> insertMessageIfAbsent(GroupMessageRecord message) async {
    final existed = await hasMessage(message.clientMsgId);
    final db = _db;
    if (db == null) {
      final list = _memMessages.putIfAbsent(
        message.groupId,
        () => <GroupMessageRecord>[],
      );
      final idx = list.indexWhere((m) => m.clientMsgId == message.clientMsgId);
      if (idx >= 0) {
        final current = list[idx];
        final nextDeleted = current.isDeleted || message.isDeleted;
        final nextCancelled = current.isCancelled || message.isCancelled;
        final isPlaceholder = current.content ==
            'Pesan terenkripsi (menunggu kunci grup)';
        final incomingReal = message.content != null &&
            message.content != 'Pesan terenkripsi (menunggu kunci grup)';
        list[idx] = current.copyWith(
          content: nextDeleted
              ? null
              : ((isPlaceholder && incomingReal)
                  ? message.content
                  : (current.content ?? message.content)),
          localAudioPath:
              nextDeleted ? null : (message.localAudioPath ?? current.localAudioPath),
          audioUrl: nextDeleted ? null : (message.audioUrl ?? current.audioUrl),
          originTransport:
              message.originTransport == ChatTransportOrigin.wifiDirect
                  ? ChatTransportOrigin.wifiDirect
                  : current.originTransport,
          syncStatus: message.syncStatus == ChatSyncStatus.sent
              ? ChatSyncStatus.sent
              : current.syncStatus,
          isDeleted: nextDeleted,
          deletedAtUtc: current.deletedAtUtc ?? message.deletedAtUtc,
          isCancelled: nextCancelled,
          cancelledAtUtc: current.cancelledAtUtc ?? message.cancelledAtUtc,
        );
        await _emitMessages(message.groupId);
        return false;
      }
      list.add(message);
      list.sort(
        (a, b) => a.clientCreatedAtUtc.compareTo(b.clientCreatedAtUtc),
      );
      await _emitMessages(message.groupId);
      return true;
    }

    await db.transaction(() async {
      await _upsertMessageDb(db, message);
    });
    await _emitMessages(message.groupId);
    return !existed;
  }

  /// Menyisipkan atau memperbarui banyak pesan sekaligus dalam satu transaksi
  /// SQLite dan memancarkan pembaruan stream maksimal satu kali per grup.
  Future<int> upsertMessagesBatch(List<GroupMessageRecord> messages) async {
    if (messages.isEmpty) return 0;
    final touchedGroups = <String>{};
    final db = _db;
    if (db == null) {
      for (final message in messages) {
        touchedGroups.add(message.groupId);
        final list = _memMessages.putIfAbsent(
          message.groupId,
          () => <GroupMessageRecord>[],
        );
        final idx =
            list.indexWhere((m) => m.clientMsgId == message.clientMsgId);
        if (idx >= 0) {
          final current = list[idx];
          final nextDeleted = current.isDeleted || message.isDeleted;
          final nextCancelled = current.isCancelled || message.isCancelled;
          final isPlaceholder = current.content ==
              'Pesan terenkripsi (menunggu kunci grup)';
          final incomingReal = message.content != null &&
              message.content != 'Pesan terenkripsi (menunggu kunci grup)';
          list[idx] = current.copyWith(
            content: nextDeleted
                ? null
                : ((isPlaceholder && incomingReal)
                    ? message.content
                    : (current.content ?? message.content)),
            localAudioPath: nextDeleted
                ? null
                : (message.localAudioPath ?? current.localAudioPath),
            audioUrl:
                nextDeleted ? null : (message.audioUrl ?? current.audioUrl),
            originTransport:
                message.originTransport == ChatTransportOrigin.wifiDirect
                    ? ChatTransportOrigin.wifiDirect
                    : current.originTransport,
            syncStatus: message.syncStatus == ChatSyncStatus.sent
                ? ChatSyncStatus.sent
                : current.syncStatus,
            isDeleted: nextDeleted,
            deletedAtUtc: current.deletedAtUtc ?? message.deletedAtUtc,
            isCancelled: nextCancelled,
            cancelledAtUtc: current.cancelledAtUtc ?? message.cancelledAtUtc,
          );
        } else {
          list.add(message);
        }
      }
      for (final gid in touchedGroups) {
        _memMessages[gid]?.sort(
          (a, b) => a.clientCreatedAtUtc.compareTo(b.clientCreatedAtUtc),
        );
        await _emitMessages(gid);
      }
      return messages.length;
    }

    await db.transaction(() async {
      for (final message in messages) {
        touchedGroups.add(message.groupId);
        await _upsertMessageDb(db, message);
      }
    });
    for (final gid in touchedGroups) {
      await _emitMessages(gid);
    }
    return messages.length;
  }

  Future<void> _upsertMessageDb(
    AppDatabase db,
    GroupMessageRecord message,
  ) async {
    await db.customInsert(
      '''
      INSERT INTO local_group_messages (
        client_msg_id, group_id, sender_id, sender_name, message_type,
        content, local_audio_path, audio_url, audio_duration_sec,
        key_version, origin_transport, sync_status, client_created_at,
        is_deleted, deleted_at, is_cancelled, cancelled_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(client_msg_id) DO UPDATE SET
        sender_name = CASE
          WHEN local_group_messages.sender_name = 'Anggota'
               AND excluded.sender_name <> 'Anggota'
            THEN excluded.sender_name
          ELSE local_group_messages.sender_name
        END,
        is_deleted = CASE
          WHEN local_group_messages.is_deleted = 1 OR excluded.is_deleted = 1
            THEN 1
          ELSE 0
        END,
        deleted_at = COALESCE(local_group_messages.deleted_at, excluded.deleted_at),
        content = CASE
          WHEN local_group_messages.is_deleted = 1 OR excluded.is_deleted = 1
            THEN NULL
          WHEN (local_group_messages.content IS NULL
                OR local_group_messages.content = 'Pesan terenkripsi (menunggu kunci grup)')
               AND excluded.content IS NOT NULL
               AND excluded.content <> 'Pesan terenkripsi (menunggu kunci grup)'
            THEN excluded.content
          ELSE local_group_messages.content
        END,
        local_audio_path = CASE
          WHEN local_group_messages.is_deleted = 1 OR excluded.is_deleted = 1
            THEN NULL
          ELSE COALESCE(excluded.local_audio_path, local_group_messages.local_audio_path)
        END,
        audio_url = CASE
          WHEN local_group_messages.is_deleted = 1 OR excluded.is_deleted = 1
            THEN NULL
          ELSE COALESCE(excluded.audio_url, local_group_messages.audio_url)
        END,
        audio_duration_sec = CASE
          WHEN local_group_messages.is_deleted = 1 OR excluded.is_deleted = 1
            THEN NULL
          ELSE COALESCE(local_group_messages.audio_duration_sec, excluded.audio_duration_sec)
        END,
        is_cancelled = CASE
          WHEN local_group_messages.is_cancelled = 1 OR excluded.is_cancelled = 1
            THEN 1
          ELSE 0
        END,
        cancelled_at = COALESCE(local_group_messages.cancelled_at, excluded.cancelled_at),
        origin_transport = CASE
          WHEN excluded.origin_transport = 'wifi_direct' THEN 'wifi_direct'
          ELSE local_group_messages.origin_transport
        END,
        sync_status = CASE
          WHEN excluded.sync_status = 'sent' THEN 'sent'
          ELSE local_group_messages.sync_status
        END
      ''',
      variables: <Variable<Object>>[
        Variable<String>(message.clientMsgId),
        Variable<String>(message.groupId),
        Variable<String>(message.senderId),
        Variable<String>(message.senderName),
        Variable<String>(message.messageType.dbValue),
        _nullableText(message.isDeleted ? null : message.content),
        _nullableText(message.isDeleted ? null : message.localAudioPath),
        _nullableText(message.isDeleted ? null : message.audioUrl),
        _nullableInt(message.isDeleted ? null : message.audioDurationSec),
        Variable<int>(message.keyVersion),
        Variable<String>(message.originTransport.dbValue),
        Variable<String>(
          message.syncStatus == ChatSyncStatus.sent ? 'sent' : 'pending',
        ),
        Variable<int>(message.clientCreatedAtUtc.toUtc().millisecondsSinceEpoch),
        Variable<int>(message.isDeleted ? 1 : 0),
        _nullableInt(message.deletedAtUtc?.toUtc().millisecondsSinceEpoch),
        Variable<int>(message.isCancelled ? 1 : 0),
        _nullableInt(message.cancelledAtUtc?.toUtc().millisecondsSinceEpoch),
      ],
    );
    if (message.syncStatus == ChatSyncStatus.meshDelivered) {
      _memMeshDeliveredIds.add(message.clientMsgId);
      try {
        await db.customInsert(
          'INSERT OR IGNORE INTO local_mesh_acks (client_msg_id, acked_at) VALUES (?, ?)',
          variables: <Variable<Object>>[
            Variable<String>(message.clientMsgId),
            Variable<int>(DateTime.now().toUtc().millisecondsSinceEpoch),
          ],
        );
      } catch (_) {}
    }
  }

  /// Membersihkan baris duplikat historis di database lokal (mis. sisa migrasi
  /// dari jalur penyimpanan ganda lama di mana pesan yang sama tersimpan 2x
  /// dengan UUID berbeda dalam rentang waktu berdekatan).
  ///
  /// Mengembalikan jumlah baris duplikat yang dihapus.
  Future<int> cleanupDuplicateMessages({String? groupId}) async {
    final db = _db;
    if (db == null) {
      var removed = 0;
      final targetGroups = groupId != null
          ? <String>[groupId]
          : _memMessages.keys.toList(growable: false);
      for (final gid in targetGroups) {
        final list = _memMessages[gid];
        if (list == null || list.length <= 1) continue;
        final deduped = _dedupeRecords(list);
        removed += list.length - deduped.length;
        if (deduped.length != list.length) {
          _memMessages[gid] = deduped;
          await _emitMessages(gid);
        }
      }
      return removed;
    }

    final rows = groupId == null
        ? await db.customSelect(
            'SELECT * FROM local_group_messages '
            'ORDER BY group_id ASC, client_created_at ASC, client_msg_id ASC',
          ).get()
        : await db.customSelect(
            'SELECT * FROM local_group_messages WHERE group_id = ? '
            'ORDER BY client_created_at ASC, client_msg_id ASC',
            variables: <Variable<Object>>[Variable<String>(groupId)],
          ).get();

    if (rows.length <= 1) return 0;

    final records = rows
        .map((r) => GroupMessageRecord.fromLocalSqliteMap(r.data))
        .toList(growable: false);
    final byGroup = <String, List<GroupMessageRecord>>{};
    for (final r in records) {
      byGroup.putIfAbsent(r.groupId, () => <GroupMessageRecord>[]).add(r);
    }

    final toDelete = <String>[];
    final affectedGroups = <String>{};
    for (final entry in byGroup.entries) {
      final kept = _dedupeRecords(entry.value);
      final keptIds = kept.map((e) => e.clientMsgId).toSet();
      for (final r in entry.value) {
        if (!keptIds.contains(r.clientMsgId)) {
          toDelete.add(r.clientMsgId);
          affectedGroups.add(entry.key);
        }
      }
    }

    if (toDelete.isEmpty) return 0;

    await db.transaction(() async {
      for (final id in toDelete) {
        await db.customUpdate(
          'DELETE FROM local_group_messages WHERE client_msg_id = ?',
          variables: <Variable<Object>>[Variable<String>(id)],
        );
      }
    });

    for (final gid in affectedGroups) {
      await _emitMessages(gid);
    }
    return toDelete.length;
  }

  List<GroupMessageRecord> _dedupeRecords(List<GroupMessageRecord> input) {
    final sorted = List<GroupMessageRecord>.of(input)
      ..sort(
        (a, b) => a.clientCreatedAtUtc.compareTo(b.clientCreatedAtUtc),
      );
    final kept = <GroupMessageRecord>[];
    for (final candidate in sorted) {
      final dupIdx = kept.indexWhere((existing) {
        if (existing.clientMsgId == candidate.clientMsgId) return true;
        if (existing.groupId != candidate.groupId ||
            existing.senderId != candidate.senderId ||
            existing.messageType != candidate.messageType) {
          return false;
        }
        final deltaMs = existing.clientCreatedAtUtc
            .difference(candidate.clientCreatedAtUtc)
            .inMilliseconds
            .abs();
        if (deltaMs > 2500) return false;
        if (existing.messageType == GroupMessageType.text) {
          return (existing.content ?? '') == (candidate.content ?? '');
        }
        return (existing.audioDurationSec ?? -1) ==
            (candidate.audioDurationSec ?? -1);
      });
      if (dupIdx < 0) {
        kept.add(candidate);
      } else {
        // Pertahankan baris yang sudah berstatus 'sent' atau punya path audio.
        final existing = kept[dupIdx];
        final preferCandidate =
            (candidate.syncStatus == ChatSyncStatus.sent &&
                existing.syncStatus != ChatSyncStatus.sent) ||
            (candidate.audioUrl != null && existing.audioUrl == null);
        if (preferCandidate) {
          kept[dupIdx] = candidate.copyWith(
            localAudioPath: candidate.localAudioPath ?? existing.localAudioPath,
            audioUrl: candidate.audioUrl ?? existing.audioUrl,
          );
        }
      }
    }
    return kept;
  }

  /// Menyimpan/memperbarui path audio lokal (`local_audio_path`), URL Supabase
  /// (`audio_url`), asal transport, dan status sinkronisasi (`sync_status`).
  Future<void> updateMessageAudioAndSync({
    required String clientMsgId,
    String? groupId,
    String? localAudioPath,
    String? audioUrl,
    ChatTransportOrigin? originTransport,
    ChatSyncStatus? syncStatus,
  }) async {
    final db = _db;
    if (db == null) {
      String? resolvedGroup = groupId;
      for (final entry in _memMessages.entries) {
        final idx =
            entry.value.indexWhere((m) => m.clientMsgId == clientMsgId);
        if (idx >= 0) {
          final current = entry.value[idx];
          entry.value[idx] = current.copyWith(
            localAudioPath: localAudioPath ?? current.localAudioPath,
            audioUrl: audioUrl ?? current.audioUrl,
            originTransport: originTransport ?? current.originTransport,
            syncStatus: syncStatus ?? current.syncStatus,
          );
          resolvedGroup = entry.key;
          break;
        }
      }
      if (resolvedGroup != null) {
        await _emitMessages(resolvedGroup);
      }
      return;
    }

    String? resolvedGroup = groupId;
    if (resolvedGroup == null) {
      final hit = await db.customSelect(
        'SELECT group_id FROM local_group_messages WHERE client_msg_id = ? LIMIT 1',
        variables: <Variable<Object>>[Variable<String>(clientMsgId)],
      ).getSingleOrNull();
      resolvedGroup = hit?.data['group_id'] as String?;
    }

    final normalizedSyncDb = syncStatus == null
        ? null
        : (syncStatus == ChatSyncStatus.sent ? 'sent' : 'pending');
    if (syncStatus == ChatSyncStatus.meshDelivered) {
      await markMessageMeshDelivered(
        clientMsgId: clientMsgId,
        groupId: resolvedGroup,
      );
    }
    await db.customUpdate(
      '''
      UPDATE local_group_messages
      SET local_audio_path = COALESCE(?, local_audio_path),
          audio_url = COALESCE(?, audio_url),
          origin_transport = COALESCE(?, origin_transport),
          sync_status = COALESCE(?, sync_status)
      WHERE client_msg_id = ?
      ''',
      variables: <Variable<Object>>[
        _nullableText(localAudioPath),
        _nullableText(audioUrl),
        _nullableText(originTransport?.dbValue),
        _nullableText(normalizedSyncDb),
        Variable<String>(clientMsgId),
      ],
    );

    if (resolvedGroup != null) {
      await _emitMessages(resolvedGroup);
    }
  }

  /// Menandai pesan sebagai terhapus (soft-delete) pada cache lokal agar UI langsung sinkron.
  Future<void> markMessageDeleted({
    required String groupId,
    required String clientMsgId,
    DateTime? deletedAtUtc,
  }) async {
    final stamp = (deletedAtUtc ?? DateTime.now()).toUtc();
    final db = _db;
    if (db == null) {
      final list = _memMessages[groupId];
      if (list != null) {
        final idx = list.indexWhere((m) => m.clientMsgId == clientMsgId);
        if (idx >= 0) {
          final current = list[idx];
          list[idx] = GroupMessageRecord(
            id: current.id,
            clientMsgId: current.clientMsgId,
            groupId: current.groupId,
            senderId: current.senderId,
            senderName: current.senderName,
            messageType: current.messageType,
            content: null,
            localAudioPath: null,
            audioUrl: null,
            audioDurationSec: null,
            keyVersion: current.keyVersion,
            originTransport: current.originTransport,
            syncStatus: current.syncStatus,
            clientCreatedAtUtc: current.clientCreatedAtUtc,
            createdAtUtc: current.createdAtUtc,
            isDeleted: true,
            deletedAtUtc: current.deletedAtUtc ?? stamp,
            isCancelled: current.isCancelled,
            cancelledAtUtc: current.cancelledAtUtc,
          );
          await _emitMessages(groupId);
        }
      }
      return;
    }

    await db.customUpdate(
      'UPDATE local_group_messages '
      'SET is_deleted = 1, deleted_at = COALESCE(deleted_at, ?), '
      'content = NULL, local_audio_path = NULL, audio_url = NULL, audio_duration_sec = NULL '
      'WHERE group_id = ? AND client_msg_id = ?',
      variables: <Variable<Object>>[
        Variable<int>(stamp.millisecondsSinceEpoch),
        Variable<String>(groupId),
        Variable<String>(clientMsgId),
      ],
    );
    await _emitMessages(groupId);
  }

  /// Menandai pesan kartu ajakan pendakian grup sebagai dibatalkan secara lokal.
  Future<void> markMessageCancelled({
    required String groupId,
    required String clientMsgId,
    DateTime? cancelledAtUtc,
  }) async {
    final stamp = (cancelledAtUtc ?? DateTime.now()).toUtc();
    final db = _db;
    if (db == null) {
      final list = _memMessages[groupId];
      if (list != null) {
        final idx = list.indexWhere((m) => m.clientMsgId == clientMsgId);
        if (idx >= 0) {
          list[idx] = list[idx].copyWith(
            isCancelled: true,
            cancelledAtUtc: list[idx].cancelledAtUtc ?? stamp,
          );
          await _emitMessages(groupId);
        }
      }
      return;
    }

    await db.customUpdate(
      'UPDATE local_group_messages '
      'SET is_cancelled = 1, cancelled_at = COALESCE(cancelled_at, ?) '
      'WHERE group_id = ? AND client_msg_id = ?',
      variables: <Variable<Object>>[
        Variable<int>(stamp.millisecondsSinceEpoch),
        Variable<String>(groupId),
        Variable<String>(clientMsgId),
      ],
    );
    await _emitMessages(groupId);
  }

  /// Mengambil semua pesan berstatus `pending` yang perlu disinkronkan ke Supabase.
  Future<List<GroupMessageRecord>> pendingMessages({String? groupId}) async {
    final db = _db;
    if (db == null) {
      final all = groupId == null
          ? _memMessages.values.expand((e) => e)
          : (_memMessages[groupId] ?? const <GroupMessageRecord>[]);
      return all
          .where((m) => m.syncStatus != ChatSyncStatus.sent)
          .toList(growable: false);
    }

    await migrateLegacyNonUuidClientIds();

    final rows = groupId == null
        ? await db.customSelect(
            "SELECT * FROM local_group_messages WHERE sync_status = 'pending' "
            'ORDER BY client_created_at ASC',
          ).get()
        : await db.customSelect(
            "SELECT * FROM local_group_messages WHERE group_id = ? AND sync_status = 'pending' "
            'ORDER BY client_created_at ASC',
            variables: <Variable<Object>>[Variable<String>(groupId)],
          ).get();

    return rows
        .map((r) => GroupMessageRecord.fromLocalSqliteMap(r.data))
        .toList(growable: false);
  }

  /// Mengonversi `client_msg_id` lama non-UUID pada antrean pending lokal
  /// (mis. `sos-...` atau `invite_hike_...`) menjadi UUID kanonik agar tidak
  /// pernah ditolak Postgres dengan `22P02` saat sinkronisasi.
  Future<void> migrateLegacyNonUuidClientIds() async {
    if (_migratedLegacyClientIds) return;
    final db = _db;
    if (db == null) {
      _migratedLegacyClientIds = true;
      return;
    }
    try {
      final rows = await db.customSelect(
        "SELECT client_msg_id FROM local_group_messages WHERE sync_status = 'pending'",
      ).get();
      final legacyIds = <String>[
        for (final row in rows)
          if (row.data['client_msg_id'] is String &&
              !isValidUuid(row.data['client_msg_id'] as String))
            row.data['client_msg_id'] as String,
      ];
      if (legacyIds.isNotEmpty) {
        await db.transaction(() async {
          for (final oldId in legacyIds) {
            final nextId = normalizeToUuid(oldId);
            final conflict = await db.customSelect(
              'SELECT 1 FROM local_group_messages WHERE client_msg_id = ? LIMIT 1',
              variables: <Variable<Object>>[Variable<String>(nextId)],
            ).getSingleOrNull();
            if (conflict != null) {
              await db.customUpdate(
                'DELETE FROM local_group_messages WHERE client_msg_id = ?',
                variables: <Variable<Object>>[Variable<String>(oldId)],
              );
            } else {
              await db.customUpdate(
                'UPDATE local_group_messages SET client_msg_id = ? WHERE client_msg_id = ?',
                variables: <Variable<Object>>[
                  Variable<String>(nextId),
                  Variable<String>(oldId),
                ],
              );
            }
          }
        });
      }
      _migratedLegacyClientIds = true;
    } catch (_) {}
  }

  /// Memperbarui lokasi terakhir anggota pada grup jika `recorded_at` sama atau lebih baru.
  Future<bool> upsertMemberLocation(
    String groupId,
    MemberLastLocation location,
  ) async {
    final normalized = location.copyWith(groupId: groupId);
    final incomingMs =
        normalized.effectiveRecordedAtUtc.toUtc().millisecondsSinceEpoch;

    final db = _db;
    if (db == null) {
      final list = _memLocations.putIfAbsent(
        groupId,
        () => <MemberLastLocation>[],
      );
      final idx = list.indexWhere((e) => e.userId == normalized.userId);
      if (idx >= 0) {
        final existingMs = list[idx]
            .effectiveRecordedAtUtc
            .toUtc()
            .millisecondsSinceEpoch;
        if (incomingMs < existingMs) return false;
        list[idx] = normalized;
      } else {
        list.add(normalized);
      }
      await _emitLocations(groupId);
      return true;
    }

    final updated = await db.transaction(
      () => _upsertLocationDb(db, groupId, normalized, incomingMs),
    );
    if (updated) {
      await _emitLocations(groupId);
    }
    return updated;
  }

  /// Memperbarui sekumpulan lokasi anggota grup dalam satu transaksi SQLite
  /// dengan paling banyak satu kali pemancaran stream UI.
  Future<int> upsertMemberLocationsBatch(
    String groupId,
    List<MemberLastLocation> locations,
  ) async {
    if (locations.isEmpty) return 0;
    final db = _db;
    var count = 0;
    if (db == null) {
      final list = _memLocations.putIfAbsent(
        groupId,
        () => <MemberLastLocation>[],
      );
      for (final loc in locations) {
        final normalized = loc.copyWith(groupId: groupId);
        final incomingMs =
            normalized.effectiveRecordedAtUtc.toUtc().millisecondsSinceEpoch;
        final idx = list.indexWhere((e) => e.userId == normalized.userId);
        if (idx >= 0) {
          final existingMs = list[idx]
              .effectiveRecordedAtUtc
              .toUtc()
              .millisecondsSinceEpoch;
          if (incomingMs < existingMs) continue;
          list[idx] = normalized;
        } else {
          list.add(normalized);
        }
        count++;
      }
      if (count > 0) {
        await _emitLocations(groupId);
      }
      return count;
    }

    await db.transaction(() async {
      for (final loc in locations) {
        final normalized = loc.copyWith(groupId: groupId);
        final incomingMs =
            normalized.effectiveRecordedAtUtc.toUtc().millisecondsSinceEpoch;
        final ok = await _upsertLocationDb(db, groupId, normalized, incomingMs);
        if (ok) count++;
      }
    });
    if (count > 0) {
      await _emitLocations(groupId);
    }
    return count;
  }

  Future<bool> _upsertLocationDb(
    AppDatabase db,
    String groupId,
    MemberLastLocation normalized,
    int incomingMs,
  ) async {
    final existing = await db.customSelect(
      'SELECT recorded_at FROM local_member_locations '
      'WHERE group_id = ? AND user_id = ? LIMIT 1',
      variables: <Variable<Object>>[
        Variable<String>(groupId),
        Variable<String>(normalized.userId),
      ],
    ).getSingleOrNull();
    if (existing != null) {
      final existingMs = (existing.data['recorded_at'] as num?)?.toInt() ?? 0;
      if (incomingMs < existingMs) {
        return false;
      }
    }

    await db.customInsert(
      '''
      INSERT INTO local_member_locations (
        group_id, user_id, display_name, latitude, longitude,
        altitude_mdpl, battery_percent, accuracy_m,
        source_transport, sync_status, recorded_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(group_id, user_id) DO UPDATE SET
        display_name = excluded.display_name,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        altitude_mdpl = excluded.altitude_mdpl,
        battery_percent = excluded.battery_percent,
        accuracy_m = COALESCE(excluded.accuracy_m, local_member_locations.accuracy_m),
        source_transport = excluded.source_transport,
        sync_status = excluded.sync_status,
        recorded_at = excluded.recorded_at,
        updated_at = excluded.updated_at
      ''',
      variables: <Variable<Object>>[
        Variable<String>(groupId),
        Variable<String>(normalized.userId),
        Variable<String>(normalized.displayName),
        Variable<double>(normalized.lat ?? 0.0),
        Variable<double>(normalized.lon ?? 0.0),
        _nullableInt(normalized.altitudeMdpl),
        _nullableInt(normalized.batteryPercent),
        _nullableInt(normalized.accuracyM),
        Variable<String>(normalized.sourceTransport.dbValue),
        Variable<String>(normalized.syncStatus.dbValue),
        Variable<int>(incomingMs),
        Variable<int>(normalized.updatedAtUtc.toUtc().millisecondsSinceEpoch),
      ],
    );
    return true;
  }

  Future<List<MemberLastLocation>> memberLocationsForGroup(
    String groupId, {
    required String currentUserId,
  }) async {
    final db = _db;
    if (db == null) {
      final raw = _memLocations[groupId] ?? const <MemberLastLocation>[];
      final sorted = List<MemberLastLocation>.of(raw)
        ..sort(
          (a, b) => b.effectiveRecordedAtUtc.compareTo(a.effectiveRecordedAtUtc),
        );
      return List<MemberLastLocation>.unmodifiable(<MemberLastLocation>[
        for (var i = 0; i < sorted.length; i++)
          (() {
            final item = sorted[i];
            if (item.userId == currentUserId && item.displayName != 'Kamu') {
              return item.copyWith(displayName: 'Kamu', initial: 'K');
            }
            return item;
          })(),
      ]);
    }

    final rows = await db.customSelect(
      'SELECT * FROM local_member_locations WHERE group_id = ? '
      'ORDER BY recorded_at DESC',
      variables: <Variable<Object>>[Variable<String>(groupId)],
    ).get();

    return <MemberLastLocation>[
      for (var i = 0; i < rows.length; i++)
        MemberLastLocation.fromLocalSqliteMap(
          rows[i].data,
          currentUserId: currentUserId,
          index: i,
        ),
    ];
  }

  Stream<List<MemberLastLocation>> watchMemberLocations(
    String groupId, {
    required String currentUserId,
  }) async* {
    yield await memberLocationsForGroup(groupId, currentUserId: currentUserId);
    yield* _locController(groupId).stream.map((list) {
      return <MemberLastLocation>[
        for (final item in list)
          if (item.userId == currentUserId && item.displayName != 'Kamu')
            item.copyWith(displayName: 'Kamu', initial: 'K')
          else
            item,
      ];
    });
  }

  Future<List<MemberLastLocation>> pendingMemberLocations({
    String? groupId,
    String currentUserId = '',
  }) async {
    final db = _db;
    if (db == null) {
      final source = groupId == null
          ? _memLocations.values.expand((e) => e)
          : (_memLocations[groupId] ?? const <MemberLastLocation>[]);
      return source
          .where((l) => l.syncStatus == ChatSyncStatus.pending)
          .toList(growable: false);
    }

    final rows = groupId == null
        ? await db.customSelect(
            "SELECT * FROM local_member_locations WHERE sync_status = 'pending' "
            'ORDER BY recorded_at DESC',
          ).get()
        : await db.customSelect(
            "SELECT * FROM local_member_locations WHERE group_id = ? AND sync_status = 'pending' "
            'ORDER BY recorded_at DESC',
            variables: <Variable<Object>>[Variable<String>(groupId)],
          ).get();

    return <MemberLastLocation>[
      for (var i = 0; i < rows.length; i++)
        MemberLastLocation.fromLocalSqliteMap(
          rows[i].data,
          currentUserId: currentUserId,
          index: i,
        ),
    ];
  }

  Future<void> markMemberLocationSent({
    required String groupId,
    required String userId,
  }) async {
    final db = _db;
    if (db == null) {
      final list = _memLocations[groupId];
      if (list != null) {
        final idx = list.indexWhere((e) => e.userId == userId);
        if (idx >= 0) {
          list[idx] = list[idx].copyWith(syncStatus: ChatSyncStatus.sent);
          await _emitLocations(groupId);
        }
      }
      return;
    }

    await db.customUpdate(
      "UPDATE local_member_locations SET sync_status = 'sent' "
      'WHERE group_id = ? AND user_id = ?',
      variables: <Variable<Object>>[
        Variable<String>(groupId),
        Variable<String>(userId),
      ],
    );
    await _emitLocations(groupId);
  }

  StreamController<List<GroupMessageRecord>> _msgController(String groupId) =>
      _msgCtrls.putIfAbsent(
        groupId,
        () => StreamController<List<GroupMessageRecord>>.broadcast(),
      );

  StreamController<List<MemberLastLocation>> _locController(String groupId) =>
      _locCtrls.putIfAbsent(
        groupId,
        () => StreamController<List<MemberLastLocation>>.broadcast(),
      );

  Future<void> _emitMessages(String groupId) async {
    if (_disposed) return;
    final ctrl = _msgCtrls[groupId];
    if (ctrl == null || ctrl.isClosed) return;
    ctrl.add(await messagesForGroup(groupId));
  }

  Future<void> _emitLocations(String groupId) async {
    if (_disposed) return;
    final ctrl = _locCtrls[groupId];
    if (ctrl == null || ctrl.isClosed) return;
    ctrl.add(await memberLocationsForGroup(groupId, currentUserId: ''));
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final c in _msgCtrls.values) {
      await c.close();
    }
    for (final c in _locCtrls.values) {
      await c.close();
    }
    _msgCtrls.clear();
    _locCtrls.clear();
  }
}
