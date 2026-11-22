import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/chat/application/group_chat_crypto.dart';
import '../../features/chat/domain/group_chat_models.dart';
import '../../features/chat/domain/group_chat_remote_service.dart';

/// Implementasi E2EE [GroupChatRemoteService] berbasis Supabase PostgreSQL,
/// Supabase Realtime, dan bucket privat Supabase Storage (`group-voice`).
///
/// Server hanya menerima `ciphertext` + `nonce` (AES-256-GCM dengan kunci grup)
/// untuk seluruh pesan teks, metadata & biner pesan suara, dan koordinat lokasi.
class SupabaseGroupChatRemoteService
    implements GroupChatRemoteService, GroupChatSinceFilterRemoteService {
  SupabaseGroupChatRemoteService(
    this._client, {
    required GroupChatCrypto crypto,
  }) : _crypto = crypto;

  final SupabaseClient _client;
  final GroupChatCrypto _crypto;

  static const String _messagesTable = 'group_messages';
  static const String _locationsTable = 'member_locations';
  static const Duration _timeout = Duration(seconds: 9);

  @override
  Future<List<GroupMessageRecord>> fetchMessages(
    String groupId, {
    int limit = 40,
    DateTime? beforeCreatedAtUtc,
  }) =>
      fetchMessagesSince(
        groupId,
        limit: limit,
        beforeCreatedAtUtc: beforeCreatedAtUtc,
      );

  @override
  Future<List<GroupMessageRecord>> fetchMessagesSince(
    String groupId, {
    int limit = 40,
    DateTime? beforeCreatedAtUtc,
    DateTime? minCreatedAtUtc,
  }) async {
    var query = _client.from(_messagesTable).select().eq('group_id', groupId);
    if (minCreatedAtUtc != null) {
      query = query.gte(
        'created_at',
        minCreatedAtUtc.toUtc().toIso8601String(),
      );
    }
    if (beforeCreatedAtUtc != null) {
      query = query.lt(
        'created_at',
        beforeCreatedAtUtc.toUtc().toIso8601String(),
      );
    }
    final rows = await query
        .order('created_at', ascending: false)
        .limit(limit)
        .timeout(_timeout);
    final rawList = _mapRows(rows).reversed.toList(growable: false);
    return _decryptMessageRowsBatch(rawList);
  }

  @override
  Stream<List<GroupMessageRecord>> watchMessages(String groupId) =>
      watchMessagesSince(groupId);

  @override
  Stream<List<GroupMessageRecord>> watchMessagesSince(
    String groupId, {
    DateTime? minCreatedAtUtc,
  }) {
    final controller = StreamController<List<GroupMessageRecord>>();
    RealtimeChannel? channel;
    var closed = false;

    Future<void> emitInitial() async {
      try {
        final initial = await fetchMessagesSince(
          groupId,
          limit: 40,
          minCreatedAtUtc: minCreatedAtUtc,
        );
        if (!closed && !controller.isClosed && initial.isNotEmpty) {
          controller.add(initial);
        }
      } catch (_) {}
    }

    controller.onListen = () {
      unawaited(emitInitial());
      try {
        final ch = _client.channel(
          'hiqeo-chat-msg-$groupId-${identityHashCode(controller)}',
        );
        channel = ch;
        ch.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _messagesTable,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: groupId,
          ),
          callback: (payload) async {
            if (closed || controller.isClosed) return;
            if (payload.eventType == PostgresChangeEvent.delete ||
                payload.newRecord.isEmpty) {
              return;
            }
            try {
              var decoded = await _decryptMessageRowsBatch(
                <Map<String, dynamic>>[
                  Map<String, dynamic>.from(payload.newRecord),
                ],
              );
              if (minCreatedAtUtc != null) {
                decoded = decoded
                    .where(
                      (m) => !(m.createdAtUtc ?? m.clientCreatedAtUtc)
                          .isBefore(minCreatedAtUtc),
                    )
                    .toList(growable: false);
              }
              if (!closed && !controller.isClosed && decoded.isNotEmpty) {
                controller.add(decoded);
              }
            } catch (_) {}
          },
        );
        ch.subscribe();
      } catch (_) {}
    };

    controller.onCancel = () async {
      closed = true;
      final ch = channel;
      channel = null;
      if (ch != null) {
        try {
          await _client.removeChannel(ch);
        } catch (_) {}
      }
      if (!controller.isClosed) {
        await controller.close();
      }
    };

    return controller.stream;
  }

  @override
  Future<void> upsertMessage(GroupMessageRecord message) async {
    final row = await _encryptMessageRow(message);
    await _client
        .from(_messagesTable)
        .upsert(row, onConflict: 'id', ignoreDuplicates: true)
        .timeout(_timeout);
  }

  @override
  Future<int> syncOfflineMessages(List<GroupMessageRecord> messages) async {
    if (messages.isEmpty) return 0;
    final byGroup = <String, List<GroupMessageRecord>>{};
    for (final m in messages) {
      byGroup.putIfAbsent(m.groupId, () => <GroupMessageRecord>[]).add(m);
    }
    var synced = 0;
    for (final entry in byGroup.entries) {
      final payloads = <Map<String, dynamic>>[];
      for (final m in entry.value) {
        payloads.add(await _encryptMessageRow(m));
      }
      await _client
          .from(_messagesTable)
          .upsert(payloads, onConflict: 'id', ignoreDuplicates: true)
          .timeout(_timeout);
      synced += payloads.length;
    }
    return synced;
  }

  @override
  Future<void> softDeleteMessage({
    required String groupId,
    required String clientMsgId,
  }) async {
    final normalizedClientId = normalizeToUuid(clientMsgId);
    try {
      await _client.rpc(
        'soft_delete_group_message',
        params: <String, dynamic>{
          'p_group_id': groupId,
          'p_client_id': normalizedClientId,
        },
      ).timeout(_timeout);
    } on PostgrestException catch (error) {
      final msg = '${error.message} ${error.details ?? ''}';
      if (error.code == 'PGRST202' ||
          error.code == '42883' ||
          msg.contains('soft_delete_group_message')) {
        final uid = _client.auth.currentUser?.id;
        if (uid == null) return;
        await _client
            .from(_messagesTable)
            .update(<String, dynamic>{
              'is_deleted': true,
              'deleted_at': DateTime.now().toUtc().toIso8601String(),
              'ciphertext': '',
              'nonce': '',
              'voice_path': null,
            })
            .eq('group_id', groupId)
            .eq('client_id', normalizedClientId)
            .eq('sender_id', uid)
            .timeout(_timeout);
      } else {
        rethrow;
      }
    }
  }

  @override
  Future<void> cancelHikeInviteMessage({
    required String groupId,
    required String clientMsgId,
  }) async {
    final normalizedClientId = normalizeToUuid(clientMsgId);
    try {
      await _client
          .from(_messagesTable)
          .update(<String, dynamic>{
            'is_cancelled': true,
            'cancelled_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('group_id', groupId)
          .eq('client_id', normalizedClientId)
          .timeout(_timeout);
    } catch (_) {}
  }

  @override
  Future<String> uploadVoiceNote({
    required String groupId,
    required String clientMsgId,
    required Uint8List audioBytes,
    int keyVersion = 1,
  }) async {
    final normalizedClientId = normalizeToUuid(clientMsgId);
    // Enkripsi biner audio dengan kunci grup sebelum menyentuh Supabase Storage.
    final encrypted = await _crypto.encryptVoiceBytes(
      groupId: groupId,
      clientId: normalizedClientId,
      keyVersion: keyVersion,
      plainAudioBytes: audioBytes,
    );
    final objectPath = '$groupId/$normalizedClientId.enc';
    await _client.storage
        .from(GroupChatRemoteService.voiceNotesBucket)
        .uploadBinary(
          objectPath,
          encrypted,
          fileOptions: const FileOptions(
            contentType: 'application/octet-stream',
            upsert: true,
          ),
        )
        .timeout(_timeout);
    return objectPath;
  }

  @override
  Future<Uint8List?> downloadVoiceNote({
    required String groupId,
    required String clientMsgId,
    required String storagePath,
    int keyVersion = 1,
  }) async {
    final normalizedClientId = normalizeToUuid(clientMsgId);
    final encrypted = await _client.storage
        .from(GroupChatRemoteService.voiceNotesBucket)
        .download(storagePath)
        .timeout(_timeout);
    return _crypto.decryptVoiceBytes(
      groupId: groupId,
      clientId: normalizedClientId,
      keyVersion: keyVersion,
      encryptedAudioBytes: encrypted,
    );
  }

  @override
  Future<String> resolveVoiceNotePlayUrl(String storagePathOrUrl) async {
    final trimmed = storagePathOrUrl.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return _client.storage
        .from(GroupChatRemoteService.voiceNotesBucket)
        .createSignedUrl(trimmed, 3600)
        .timeout(_timeout);
  }

  @override
  Future<List<MemberLastLocation>> fetchMemberLocations(
    String groupId, {
    required String currentUserId,
  }) async {
    final rows = await _client
        .from(_locationsTable)
        .select()
        .eq('group_id', groupId)
        .order('updated_at', ascending: false)
        .timeout(_timeout);
    final rawList = _mapRows(rows);
    return _decryptLocationRowsBatch(
      rawList,
      currentUserId: currentUserId,
    );
  }

  @override
  Stream<List<MemberLastLocation>> watchMemberLocations(
    String groupId, {
    required String currentUserId,
  }) {
    final controller = StreamController<List<MemberLastLocation>>();
    RealtimeChannel? channel;
    var closed = false;

    Future<void> emitInitial() async {
      try {
        final initial = await fetchMemberLocations(
          groupId,
          currentUserId: currentUserId,
        );
        if (!closed && !controller.isClosed && initial.isNotEmpty) {
          controller.add(initial);
        }
      } catch (_) {}
    }

    controller.onListen = () {
      unawaited(emitInitial());
      try {
        final ch = _client.channel(
          'hiqeo-chat-loc-$groupId-${identityHashCode(controller)}',
        );
        channel = ch;
        ch.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _locationsTable,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: groupId,
          ),
          callback: (payload) async {
            if (closed || controller.isClosed) return;
            if (payload.eventType == PostgresChangeEvent.delete ||
                payload.newRecord.isEmpty) {
              return;
            }
            try {
              final decoded = await _decryptLocationRowsBatch(
                <Map<String, dynamic>>[
                  Map<String, dynamic>.from(payload.newRecord),
                ],
                currentUserId: currentUserId,
              );
              if (!closed && !controller.isClosed && decoded.isNotEmpty) {
                controller.add(decoded);
              }
            } catch (_) {}
          },
        );
        ch.subscribe();
      } catch (_) {}
    };

    controller.onCancel = () async {
      closed = true;
      final ch = channel;
      channel = null;
      if (ch != null) {
        try {
          await _client.removeChannel(ch);
        } catch (_) {}
      }
      if (!controller.isClosed) {
        await controller.close();
      }
    };

    return controller.stream;
  }

  @override
  Future<void> upsertMemberLocation({
    required String groupId,
    required MemberLastLocation location,
    int keyVersion = 1,
  }) async {
    final row = await _encryptLocationRow(
      groupId: groupId,
      location: location,
      keyVersion: keyVersion,
    );
    await _client
        .from(_locationsTable)
        .upsert(row, onConflict: 'group_id,user_id')
        .timeout(_timeout);
  }

  @override
  Future<int> syncOfflineMemberLocations({
    required String groupId,
    required List<MemberLastLocation> locations,
    int keyVersion = 1,
  }) async {
    if (locations.isEmpty) return 0;
    final payloads = <Map<String, dynamic>>[];
    for (final loc in locations) {
      payloads.add(
        await _encryptLocationRow(
          groupId: groupId,
          location: loc,
          keyVersion: keyVersion,
        ),
      );
    }
    await _client
        .from(_locationsTable)
        .upsert(payloads, onConflict: 'group_id,user_id')
        .timeout(_timeout);
    return payloads.length;
  }

  Future<Map<String, dynamic>> _encryptMessageRow(
    GroupMessageRecord message,
  ) async {
    final normalizedClientId = normalizeToUuid(message.clientMsgId);
    final kind = message.messageType == GroupMessageType.audio ? 'voice' : 'text';
    final plainPayload = <String, dynamic>{
      'sender_name': message.senderName,
      if (message.content != null) 'text': message.content,
      if (message.audioDurationSec != null)
        'audio_duration_sec': message.audioDurationSec,
      'client_created_at': message.clientCreatedAtUtc.toUtc().toIso8601String(),
      'origin_transport': message.originTransport.dbValue,
    };
    final sealed = await _crypto.encryptJson(
      kind: kind,
      groupId: message.groupId,
      recordId: normalizedClientId,
      keyVersion: message.keyVersion,
      payload: plainPayload,
    );
    return <String, dynamic>{
      // Kirim UUID `client_msg_id` yang persis sama sebagai `id` & `client_id`
      // agar pantulan Realtime echo selalu memetakan ke baris lokal yang sama.
      'id': normalizedClientId,
      'group_id': message.groupId,
      'sender_id': message.senderId,
      'client_id': normalizedClientId,
      'kind': kind,
      'ciphertext': sealed.ciphertextBase64,
      'nonce': sealed.nonceBase64,
      'voice_path': message.audioUrl,
      'key_version': sealed.keyVersion,
    };
  }

  Future<List<GroupMessageRecord>> _decryptMessageRowsBatch(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return const <GroupMessageRecord>[];

    final slots = List<GroupMessageRecord?>.filled(rows.length, null);
    final batchItems = <GroupChatDecryptBatchItem>[];
    final pendingMeta = <({
      int slotIndex,
      Map<String, dynamic> row,
      String groupId,
      String senderId,
      String clientId,
      bool isVoice,
      int keyVersion,
      DateTime createdAt,
      bool isCancelled,
      DateTime? cancelledAt,
    })>[];

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final groupId = row['group_id'] as String?;
      final senderId = row['sender_id'] as String?;
      final clientId =
          (row['client_id'] ?? row['client_msg_id'] ?? row['id']) as String?;
      if (groupId == null || senderId == null || clientId == null) continue;

      final kindRaw = (row['kind'] ?? row['message_type'] ?? 'text').toString();
      final isVoice = kindRaw == 'voice' || kindRaw == 'audio';
      final keyVersion = (row['key_version'] as num?)?.toInt() ?? 1;
      final rawCreated = row['created_at'] as String?;
      final createdAt = rawCreated != null
          ? (DateTime.tryParse(rawCreated)?.toUtc() ?? DateTime.now().toUtc())
          : DateTime.now().toUtc();
      final rawDeleted = row['deleted_at'] as String?;
      final deletedAt =
          rawDeleted != null ? DateTime.tryParse(rawDeleted)?.toUtc() : null;
      final isDeleted = row['is_deleted'] == true || deletedAt != null;
      final rawCancelled = row['cancelled_at'] as String?;
      final cancelledAt = rawCancelled != null
          ? DateTime.tryParse(rawCancelled)?.toUtc()
          : null;
      final isCancelled = row['is_cancelled'] == true || cancelledAt != null;

      if (isDeleted) {
        slots[i] = GroupMessageRecord(
          id: row['id'] as String?,
          clientMsgId: clientId,
          groupId: groupId,
          senderId: senderId,
          senderName: 'Anggota',
          messageType:
              isVoice ? GroupMessageType.audio : GroupMessageType.text,
          content: null,
          audioUrl: null,
          keyVersion: keyVersion,
          syncStatus: ChatSyncStatus.sent,
          clientCreatedAtUtc: createdAt,
          createdAtUtc: createdAt,
          isDeleted: true,
          deletedAtUtc: deletedAt ?? createdAt,
          isCancelled: isCancelled,
          cancelledAtUtc: cancelledAt,
        );
        continue;
      }

      final ciphertext = row['ciphertext'] as String?;
      if (ciphertext == null || ciphertext.isEmpty) {
        continue;
      }

      pendingMeta.add((
        slotIndex: i,
        row: row,
        groupId: groupId,
        senderId: senderId,
        clientId: clientId,
        isVoice: isVoice,
        keyVersion: keyVersion,
        createdAt: createdAt,
        isCancelled: isCancelled,
        cancelledAt: cancelledAt,
      ));
      batchItems.add(
        GroupChatDecryptBatchItem(
          kind: isVoice ? 'voice' : 'text',
          groupId: groupId,
          recordId: clientId,
          keyVersion: keyVersion,
          ciphertextBase64: ciphertext,
        ),
      );
    }

    if (batchItems.isNotEmpty) {
      final decodedList = await _crypto.decryptJsonBatch(batchItems);
      for (var j = 0; j < pendingMeta.length; j++) {
        final meta = pendingMeta[j];
        final clear = decodedList[j];
        if (clear != null) {
          final rawClientCreated = clear['client_created_at'] as String?;
          final parsedClientCreated = rawClientCreated != null
              ? DateTime.tryParse(rawClientCreated)?.toUtc()
              : null;
          slots[meta.slotIndex] = GroupMessageRecord(
            id: meta.row['id'] as String?,
            clientMsgId: meta.clientId,
            groupId: meta.groupId,
            senderId: meta.senderId,
            senderName: (clear['sender_name'] as String?) ?? 'Anggota',
            messageType:
                meta.isVoice ? GroupMessageType.audio : GroupMessageType.text,
            content: clear['text'] as String?,
            audioUrl: meta.row['voice_path'] as String?,
            audioDurationSec: (clear['audio_duration_sec'] as num?)?.toInt(),
            keyVersion: meta.keyVersion,
            originTransport:
                ChatTransportOrigin.fromDb(clear['origin_transport'] as String?),
            syncStatus: ChatSyncStatus.sent,
            clientCreatedAtUtc: parsedClientCreated ?? meta.createdAt,
            createdAtUtc: meta.createdAt,
            isDeleted: false,
            isCancelled: meta.isCancelled,
            cancelledAtUtc: meta.cancelledAt,
          );
        } else {
          // Kunci grup belum dimuat atau ciphertext tidak terautentikasi; tampilkan
          // placeholder jujur tanpa membocorkan data mentah.
          slots[meta.slotIndex] = GroupMessageRecord(
            id: meta.row['id'] as String?,
            clientMsgId: meta.clientId,
            groupId: meta.groupId,
            senderId: meta.senderId,
            senderName: 'Anggota',
            messageType: GroupMessageType.text,
            content: 'Pesan terenkripsi (menunggu kunci grup)',
            keyVersion: meta.keyVersion,
            syncStatus: ChatSyncStatus.sent,
            clientCreatedAtUtc: meta.createdAt,
            createdAtUtc: meta.createdAt,
            isCancelled: meta.isCancelled,
            cancelledAtUtc: meta.cancelledAt,
          );
        }
      }
    }

    return <GroupMessageRecord>[
      for (final s in slots)
        if (s != null) s,
    ];
  }

  Future<Map<String, dynamic>> _encryptLocationRow({
    required String groupId,
    required MemberLastLocation location,
    required int keyVersion,
  }) async {
    final plainPayload = <String, dynamic>{
      'display_name': location.displayName,
      'lat': location.lat,
      'lon': location.lon,
      'accuracy_m': location.accuracyM,
      'altitude_mdpl': location.altitudeMdpl,
      'battery_percent': location.batteryPercent,
      'source_transport': location.sourceTransport.dbValue,
      'recorded_at': location.effectiveRecordedAtUtc.toUtc().toIso8601String(),
    };
    final sealed = await _crypto.encryptJson(
      kind: 'location',
      groupId: groupId,
      recordId: location.userId,
      keyVersion: keyVersion,
      payload: plainPayload,
    );
    return <String, dynamic>{
      'group_id': groupId,
      'user_id': location.userId,
      'ciphertext': sealed.ciphertextBase64,
      'nonce': sealed.nonceBase64,
      'key_version': sealed.keyVersion,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<List<MemberLastLocation>> _decryptLocationRowsBatch(
    List<Map<String, dynamic>> rows, {
    required String currentUserId,
  }) async {
    if (rows.isEmpty) return const <MemberLastLocation>[];

    final pendingMeta = <({
      int index,
      String groupId,
      String userId,
      DateTime updatedAt,
    })>[];
    final batchItems = <GroupChatDecryptBatchItem>[];

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final groupId = row['group_id'] as String?;
      final userId = row['user_id'] as String?;
      final ciphertext = row['ciphertext'] as String?;
      if (groupId == null || userId == null || ciphertext == null) continue;

      final keyVersion = (row['key_version'] as num?)?.toInt() ?? 1;
      final rawUpdated = row['updated_at'] as String?;
      final updatedAt = rawUpdated != null
          ? (DateTime.tryParse(rawUpdated)?.toUtc() ?? DateTime.now().toUtc())
          : DateTime.now().toUtc();

      pendingMeta.add((
        index: i,
        groupId: groupId,
        userId: userId,
        updatedAt: updatedAt,
      ));
      batchItems.add(
        GroupChatDecryptBatchItem(
          kind: 'location',
          groupId: groupId,
          recordId: userId,
          keyVersion: keyVersion,
          ciphertextBase64: ciphertext,
        ),
      );
    }

    if (batchItems.isEmpty) return const <MemberLastLocation>[];
    final decodedList = await _crypto.decryptJsonBatch(batchItems);

    const spots = <List<double>>[
      <double>[0.48, 0.56],
      <double>[0.38, 0.54],
      <double>[0.56, 0.44],
      <double>[0.64, 0.36],
    ];

    final decoded = <MemberLastLocation>[];
    for (var j = 0; j < pendingMeta.length; j++) {
      final meta = pendingMeta[j];
      final clear = decodedList[j];
      if (clear == null) continue;

      final rawName = (clear['display_name'] as String?)?.trim() ?? 'Anggota';
      final displayName = meta.userId == currentUserId ? 'Kamu' : rawName;
      final initial =
          displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
      final rawRecorded = clear['recorded_at'] as String?;
      final recordedAt = rawRecorded != null
          ? (DateTime.tryParse(rawRecorded)?.toUtc() ?? meta.updatedAt)
          : meta.updatedAt;
      final spot = spots[meta.index % spots.length];

      decoded.add(
        MemberLastLocation(
          groupId: meta.groupId,
          userId: meta.userId,
          displayName: displayName,
          initial: initial,
          hasSignal: true,
          lat: (clear['lat'] as num?)?.toDouble(),
          lon: (clear['lon'] as num?)?.toDouble(),
          accuracyM: (clear['accuracy_m'] as num?)?.toInt(),
          altitudeMdpl: (clear['altitude_mdpl'] as num?)?.toInt(),
          batteryPercent: (clear['battery_percent'] as num?)?.toInt(),
          sourceTransport:
              ChatTransportOrigin.fromDb(clear['source_transport'] as String?),
          syncStatus: ChatSyncStatus.sent,
          recordedAtUtc: recordedAt,
          updatedAtUtc: meta.updatedAt,
          mapX: spot[0],
          mapY: spot[1],
        ),
      );
    }
    return decoded;
  }

  List<Map<String, dynamic>> _mapRows(dynamic data) {
    if (data is! List) return const <Map<String, dynamic>>[];
    return data
        .whereType<Map>()
        .map((row) => row.map((k, v) => MapEntry(k.toString(), v)))
        .toList(growable: false);
  }
}
