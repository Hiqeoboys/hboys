import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nama_app/features/chat/domain/group_chat_models.dart';
import 'package:nama_app/features/chat/domain/group_chat_remote_service.dart';
import 'package:nama_app/features/groups/domain/group_key_store.dart';
import 'package:nama_app/infrastructure/crypto/crypto_interfaces.dart';
import 'package:nama_app/infrastructure/database/app_database.dart';
import 'package:nama_app/infrastructure/offgrid/mesh_packet_codec.dart';
import 'package:nama_app/infrastructure/offgrid/mesh_router_service.dart';
import 'package:nama_app/infrastructure/offgrid/off_grid_chat_local_store.dart';
import 'package:nama_app/infrastructure/offgrid/off_grid_supabase_sync_service.dart';
import 'package:nama_app/infrastructure/offgrid/off_grid_transport_adapter.dart';

class _MemorySecretStore implements SecretValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

class _SpyGroupChatRemote implements GroupChatRemoteService {
  final List<GroupMessageRecord> upsertedMessages = <GroupMessageRecord>[];
  final List<MemberLastLocation> upsertedLocations = <MemberLastLocation>[];
  final Map<String, Uint8List> uploadedAudioBytes = <String, Uint8List>{};
  final StreamController<List<GroupMessageRecord>> msgStreamCtrl =
      StreamController<List<GroupMessageRecord>>.broadcast();
  final StreamController<List<MemberLastLocation>> locStreamCtrl =
      StreamController<List<MemberLastLocation>>.broadcast();

  @override
  Future<List<GroupMessageRecord>> fetchMessages(
    String groupId, {
    int limit = 50,
    DateTime? beforeCreatedAtUtc,
  }) async =>
      upsertedMessages;

  @override
  Stream<List<GroupMessageRecord>> watchMessages(String groupId) =>
      msgStreamCtrl.stream;

  @override
  Future<void> upsertMessage(GroupMessageRecord message) async {
    upsertedMessages.removeWhere((m) => m.clientMsgId == message.clientMsgId);
    upsertedMessages.add(message);
  }

  @override
  Future<int> syncOfflineMessages(List<GroupMessageRecord> messages) async {
    for (final m in messages) {
      await upsertMessage(m);
    }
    return messages.length;
  }

  @override
  Future<void> softDeleteMessage({
    required String groupId,
    required String clientMsgId,
  }) async {}

  @override
  Future<void> cancelHikeInviteMessage({
    required String groupId,
    required String clientMsgId,
  }) async {}

  @override
  Future<String> uploadVoiceNote({
    required String groupId,
    required String clientMsgId,
    required Uint8List audioBytes,
    int keyVersion = 1,
  }) async {
    final path = '$groupId/$clientMsgId.enc';
    uploadedAudioBytes[path] = audioBytes;
    return path;
  }

  @override
  Future<Uint8List?> downloadVoiceNote({
    required String groupId,
    required String clientMsgId,
    required String storagePath,
    int keyVersion = 1,
  }) async =>
      uploadedAudioBytes[storagePath];

  @override
  Future<String> resolveVoiceNotePlayUrl(String storagePathOrUrl) async =>
      'https://example.supabase.co/$storagePathOrUrl';

  @override
  Future<List<MemberLastLocation>> fetchMemberLocations(
    String groupId, {
    required String currentUserId,
  }) async =>
      upsertedLocations;

  @override
  Stream<List<MemberLastLocation>> watchMemberLocations(
    String groupId, {
    required String currentUserId,
  }) =>
      locStreamCtrl.stream;

  @override
  Future<void> upsertMemberLocation({
    required String groupId,
    required MemberLastLocation location,
    int keyVersion = 1,
  }) async {
    upsertedLocations.removeWhere((l) => l.userId == location.userId);
    upsertedLocations.add(location);
  }

  @override
  Future<int> syncOfflineMemberLocations({
    required String groupId,
    required List<MemberLastLocation> locations,
    int keyVersion = 1,
  }) async {
    for (final l in locations) {
      await upsertMemberLocation(groupId: groupId, location: l);
    }
    return locations.length;
  }
}

void main() {
  const groupUuid = '11111111-2222-4333-8444-555555555555';
  const otherGroupUuid = '99999999-8888-4777-8666-555555555555';

  group('MeshPacketCodec AES-GCM & 180-byte chunking', () {
    test('enkripsi AES-256-GCM memecah paket besar <= 180 byte dan menyusun ulang', () async {
      final keyStore = _MemorySecretStore();
      final codecTx = MeshPacketCodec(
        keyStore: SecureGroupKeyStoreProxy.fromStore(keyStore),
      );
      final codecRx = MeshPacketCodec(
        keyStore: SecureGroupKeyStoreProxy.fromStore(keyStore),
      );

      final longText = List<String>.filled(
        20,
        'Posisi pos bayangan aman, lanjut mendaki pelan-pelan.',
      ).join(' ');
      final msgId = generateUuidV4();
      final record = GroupMessageRecord(
        clientMsgId: msgId,
        groupId: groupUuid,
        senderId: 'user-a',
        senderName: 'Raka',
        messageType: GroupMessageType.text,
        content: longText,
        keyVersion: 1,
        originTransport: ChatTransportOrigin.bleMesh,
        syncStatus: ChatSyncStatus.pending,
        clientCreatedAtUtc: DateTime.utc(2026, 11, 19, 5),
      );

      final chunks = await codecTx.encodeAndChunk(
        MeshEnvelope(
          kind: MeshPayloadKind.chatMessage,
          clientMsgId: msgId,
          groupId: groupUuid,
          keyVersion: 1,
          ttl: 5,
          chatMessage: record,
        ),
      );

      expect(chunks.length, greaterThan(2));
      for (final chunk in chunks) {
        expect(chunk.length, lessThanOrEqualTo(MeshPacketCodec.maxPacketBytes));
        expect(chunk[0], MeshPacketCodec.magicByte);
        final header = MeshPacketCodec.inspectHeader(chunk);
        expect(header, isNotNull);
        expect(header!.ttl, 5);
      }

      MeshIngestResult? decoded;
      for (final chunk in chunks) {
        decoded = await codecRx.ingestChunk(chunk, groupId: groupUuid);
      }
      expect(decoded, isNotNull);
      expect(decoded!.envelope.chatMessage?.content, longText);
      expect(decoded.envelope.chatMessage?.clientMsgId, msgId);

      // Dekripsi dengan groupId salah harus ditolak AES-GCM AEAD
      final codecWrongGroup = MeshPacketCodec(
        keyStore: SecureGroupKeyStoreProxy.fromStore(keyStore),
      );
      Future<void> tryWrongDecrypt() async {
        for (final chunk in chunks) {
          await codecWrongGroup.ingestChunk(chunk, groupId: otherGroupUuid);
        }
      }

      await expectLater(
        tryWrongDecrypt(),
        throwsA(isA<AeadAuthenticationException>()),
      );
    });
  });

  group('MeshRouterService multi-hop, deduplikasi, Wi-Fi Direct audio & duty-cycle', () {
    test('multi-hop store-and-forward berhenti tepat di TTL = 5 hop', () async {
      final bus = LoopbackOffGridMeshBus();
      final routers = <MeshRouterService>[];
      final stores = <OffGridChatLocalStore>[];

      for (var i = 0; i < 7; i++) {
        final store = OffGridChatLocalStore();
        final adapter = InMemoryOffGridTransportAdapter(
          nodeId: 'n$i',
          bus: bus,
        );
        final router = MeshRouterService(
          adapter: adapter,
          codec: MeshPacketCodec(
            keyStore: SecureGroupKeyStoreProxy.fromStore(_MemorySecretStore()),
          ),
          localStore: store,
        );
        await router.start(groupId: groupUuid, highDuty: true);
        stores.add(store);
        routers.add(router);
      }

      // Topologi rantai: n0 <-> n1 <-> n2 <-> n3 <-> n4 <-> n5 <-> n6
      for (var i = 0; i < 6; i++) {
        bus.connect('n$i', 'n${i + 1}');
      }

      final msgId = generateUuidV4();
      await routers[0].sendTextMessage(
        GroupMessageRecord(
          clientMsgId: msgId,
          groupId: groupUuid,
          senderId: 'user-0',
          senderName: 'Dimas',
          messageType: GroupMessageType.text,
          content: 'Cek sinyal multi-hop!',
          originTransport: ChatTransportOrigin.bleMesh,
          syncStatus: ChatSyncStatus.pending,
          clientCreatedAtUtc: DateTime.utc(2026, 11, 19, 6),
        ),
      );

      // Biarkan event mikrotask relay berjalan
      await Future<void>.delayed(const Duration(milliseconds: 120));

      // n0..n5 (jarak 0..5 hop) menerima tepat 1 pesan (tidak duplikat),
      // sementara n6 (hop ke-6) tidak menerima karena TTL habis.
      for (var i = 0; i <= 5; i++) {
        final msgs = await stores[i].messagesForGroup(groupUuid);
        expect(msgs, hasLength(1), reason: 'Node n$i harus menerima tepat 1 pesan');
      }
      expect(await stores[6].messagesForGroup(groupUuid), isEmpty);

      for (final r in routers) {
        await r.dispose();
      }
      for (final s in stores) {
        await s.dispose();
      }
    });

    test('antrean offline Wi-Fi Direct mengirim file .m4a begitu peer tersambung', () async {
      final tempDir = await Directory.systemTemp.createTemp('hiqeo_mesh_audio_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final bus = LoopbackOffGridMeshBus();
      final storeTx = OffGridChatLocalStore();
      final storeRx = OffGridChatLocalStore();
      final adapterTx = InMemoryOffGridTransportAdapter(
        nodeId: 'tx',
        bus: bus,
        receivedAudioDirectory: tempDir,
      );
      final adapterRx = InMemoryOffGridTransportAdapter(
        nodeId: 'rx',
        bus: bus,
        receivedAudioDirectory: tempDir,
      );
      final routerTx = MeshRouterService(
        adapter: adapterTx,
        codec: MeshPacketCodec(
          keyStore: SecureGroupKeyStoreProxy.fromStore(_MemorySecretStore()),
        ),
        localStore: storeTx,
      );
      final routerRx = MeshRouterService(
        adapter: adapterRx,
        codec: MeshPacketCodec(
          keyStore: SecureGroupKeyStoreProxy.fromStore(_MemorySecretStore()),
        ),
        localStore: storeRx,
      );

      await routerTx.start(groupId: groupUuid, highDuty: true);
      await routerRx.start(groupId: groupUuid, highDuty: true);

      final srcFile = File('${tempDir.path}${Platform.pathSeparator}voice_src.m4a');
      await srcFile.writeAsBytes(utf8.encode('FAKE-M4A-AUDIO-BYTES'));

      final clientMsgId = generateUuidV4();
      await routerTx.sendVoiceNoteMessage(
        record: GroupMessageRecord(
          clientMsgId: clientMsgId,
          groupId: groupUuid,
          senderId: 'user-tx',
          senderName: 'Sari',
          messageType: GroupMessageType.audio,
          audioDurationSec: 9,
          originTransport: ChatTransportOrigin.wifiDirect,
          syncStatus: ChatSyncStatus.pending,
          clientCreatedAtUtc: DateTime.utc(2026, 11, 19, 7),
        ),
        audioFile: srcFile,
      );

      // Saat belum ada peer, masuk antrean offline
      expect(routerTx.pendingAudioClientIds, contains(clientMsgId));

      // Peer mendekat -> Wi-Fi Direct otomatis mengirim file .m4a
      bus.connect('tx', 'rx');
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(routerTx.pendingAudioClientIds, isEmpty);
      final rxMsgs = await storeRx.messagesForGroup(groupUuid);
      expect(rxMsgs, hasLength(1));
      expect(rxMsgs.first.localAudioPath, isNotNull);
      expect(File(rxMsgs.first.localAudioPath!).existsSync(), isTrue);
      expect(rxMsgs.first.originTransport, ChatTransportOrigin.wifiDirect);

      await routerTx.dispose();
      await routerRx.dispose();
      await storeTx.dispose();
      await storeRx.dispose();
    });

    test('adaptive duty-cycling berganti 2dt/8dt saat idle dan mode cepat saat chat dibuka', () async {
      final adapter = InMemoryOffGridTransportAdapter();
      final store = OffGridChatLocalStore();
      final router = MeshRouterService(
        adapter: adapter,
        codec: MeshPacketCodec(
          keyStore: SecureGroupKeyStoreProxy.fromStore(_MemorySecretStore()),
        ),
        localStore: store,
        idleScanDuration: const Duration(milliseconds: 30),
        idlePauseDuration: const Duration(milliseconds: 60),
      );

      await router.start(groupId: groupUuid, highDuty: false);
      await Future<void>.delayed(const Duration(milliseconds: 130));
      expect(adapter.dutyModeHistory, containsAllInOrder(<bool>[false, false, true]));

      await router.setChatRoomOpen(true);
      expect(router.isHighDuty, isTrue);
      expect(adapter.dutyModeHistory.last, isTrue);

      await router.dispose();
      await store.dispose();
    });
  });

  group('SQLite OffGridChatLocalStore & OffGridSupabaseSyncService', () {
    test('SQLite menolak duplikasi client_msg_id dan sync pending ke sent', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final store = OffGridChatLocalStore(database: db);
      final remote = _SpyGroupChatRemote();
      final sync = OffGridSupabaseSyncService(
        localStore: store,
        remoteService: remote,
      );

      final tempDir = await Directory.systemTemp.createTemp('hiqeo_sqlite_sync_');
      addTearDown(() async {
        await sync.dispose();
        await store.dispose();
        await db.close();
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final audioFile = File('${tempDir.path}${Platform.pathSeparator}msg.m4a');
      await audioFile.writeAsBytes(utf8.encode('AAC-VOICE-DATA'));

      final msgId = generateUuidV4();
      final record = GroupMessageRecord(
        clientMsgId: msgId,
        groupId: groupUuid,
        senderId: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
        senderName: 'Bayu',
        messageType: GroupMessageType.audio,
        localAudioPath: audioFile.path,
        audioDurationSec: 15,
        originTransport: ChatTransportOrigin.wifiDirect,
        syncStatus: ChatSyncStatus.pending,
        clientCreatedAtUtc: DateTime.utc(2026, 11, 19, 8),
      );

      // Sisipan pertama berhasil; sisipan kedua dengan client_msg_id sama diabaikan
      expect(await store.insertMessageIfAbsent(record), isTrue);
      expect(await store.insertMessageIfAbsent(record), isFalse);
      expect(await store.messagesForGroup(groupUuid), hasLength(1));

      // Simpan lokasi pending + tolak lokasi usang
      final newerLoc = MemberLastLocation(
        groupId: groupUuid,
        userId: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
        displayName: 'Bayu',
        initial: 'B',
        hasSignal: true,
        lat: -6.8901,
        lon: 108.4092,
        altitudeMdpl: 3010,
        batteryPercent: 78,
        sourceTransport: ChatTransportOrigin.bleMesh,
        syncStatus: ChatSyncStatus.pending,
        recordedAtUtc: DateTime.utc(2026, 11, 19, 8, 5),
        updatedAtUtc: DateTime.utc(2026, 11, 19, 8, 5),
      );
      final staleLoc = newerLoc.copyWith(
        altitudeMdpl: 2500,
        recordedAtUtc: DateTime.utc(2026, 11, 19, 7, 50),
        updatedAtUtc: DateTime.utc(2026, 11, 19, 7, 50),
      );
      expect(await store.upsertMemberLocation(groupUuid, newerLoc), isTrue);
      expect(await store.upsertMemberLocation(groupUuid, staleLoc), isFalse);

      // Jalankan background sync ke Supabase
      final synced = await sync.syncPending(groupId: groupUuid);
      expect(synced, 2); // 1 message + 1 location
      expect(remote.uploadedAudioBytes.containsKey('$groupUuid/$msgId.enc'), isTrue);
      expect(remote.upsertedMessages.single.audioUrl, '$groupUuid/$msgId.enc');
      expect(remote.upsertedLocations.single.altitudeMdpl, 3010);

      // Status lokal berubah menjadi 'sent'
      expect(await store.pendingMessages(groupId: groupUuid), isEmpty);
      expect(await store.pendingMemberLocations(groupId: groupUuid), isEmpty);
      final saved = (await store.messagesForGroup(groupUuid)).single;
      expect(saved.syncStatus, ChatSyncStatus.sent);
      expect(saved.audioUrl, '$groupUuid/$msgId.enc');
    });
  });
}

/// Wrapper ringan [GroupKeyStore] untuk unit test.
class SecureGroupKeyStoreProxy extends _BaseKeyStore {
  SecureGroupKeyStoreProxy.fromStore(super.store);
}

class _BaseKeyStore implements GroupKeyStore {
  _BaseKeyStore(this._store);
  final SecretValueStore _store;

  @override
  Future<Uint8List?> readGroupKey(String groupId, int keyVersion) async {
    final v = await _store.read('$groupId:v$keyVersion');
    return v == null ? null : Uint8List.fromList(base64Decode(v));
  }

  @override
  Future<void> writeGroupKey(String groupId, int keyVersion, Uint8List groupKey) =>
      _store.write('$groupId:v$keyVersion', base64Encode(groupKey));

  @override
  Future<void> deleteGroupKey(String groupId, int keyVersion) =>
      _store.delete('$groupId:v$keyVersion');

  @override
  Future<String?> readDistributionSignature(String groupId, int keyVersion) async =>
      null;

  @override
  Future<void> writeDistributionSignature(
    String groupId,
    int keyVersion,
    String signature,
  ) async {}

  @override
  Future<void> deleteDistributionSignature(String groupId, int keyVersion) async {}
}
