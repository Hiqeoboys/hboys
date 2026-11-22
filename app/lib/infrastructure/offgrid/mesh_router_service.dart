import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import '../../features/chat/domain/group_chat_models.dart';
import 'mesh_packet_codec.dart';
import 'off_grid_chat_local_store.dart';
import 'off_grid_transport_adapter.dart';

class _QueuedAudioTransfer {
  const _QueuedAudioTransfer({
    required this.clientMsgId,
    required this.audioFile,
    required this.meta,
  });

  final String clientMsgId;
  final File audioFile;
  final Map<String, dynamic> meta;
}

/// Router mesh murni Dart untuk relay multi-hop *store-and-forward* (`TTL = 5`),
/// deduplikasi `seen_msg_ids`, antrean kirim file audio offline Wi-Fi Direct,
/// dan *adaptive duty-cycling* (scan 2 detik / jeda 8 detik saat idle; mode cepat
/// saat ruang obrolan dibuka atau SOS aktif).
class MeshRouterService {
  MeshRouterService({
    required OffGridTransportAdapter adapter,
    required MeshPacketCodec codec,
    required OffGridChatLocalStore localStore,
    this.maxTtl = MeshPacketCodec.maxTtl,
    this.idleScanDuration = const Duration(seconds: 2),
    this.idlePauseDuration = const Duration(seconds: 8),
  })  : _adapter = adapter,
        _codec = codec,
        _localStore = localStore;

  final OffGridTransportAdapter _adapter;
  final MeshPacketCodec _codec;
  final OffGridChatLocalStore _localStore;
  final int maxTtl;
  final Duration idleScanDuration;
  final Duration idlePauseDuration;

  static const int _maxSeenIds = 2000;
  static const int _maxStoreAndForward = 64;

  final LinkedHashSet<String> _seenMsgIds = LinkedHashSet<String>();
  final List<List<Uint8List>> _storeAndForwardChunks = <List<Uint8List>>[];
  final List<String> _awaitingMeshDeliveryIds = <String>[];
  final List<_QueuedAudioTransfer> _pendingAudioQueue =
      <_QueuedAudioTransfer>[];

  final StreamController<MeshSosPayload> _sosCtrl =
      StreamController<MeshSosPayload>.broadcast();
  final StreamController<int> _peersCtrl = StreamController<int>.broadcast();
  final StreamController<GroupMessageRecord> _incomingMsgCtrl =
      StreamController<GroupMessageRecord>.broadcast();

  StreamSubscription<Uint8List>? _packetSub;
  StreamSubscription<OffGridAudioPacket>? _audioSub;
  StreamSubscription<int>? _peerSub;
  Timer? _dutyTimer;

  String? _activeGroupId;
  int _keyVersion = 1;
  bool _started = false;
  bool _chatRoomOpen = false;
  bool _sosActive = false;
  bool _idleDutyWindowActive = true;
  int _connectedPeers = 0;

  bool get isStarted => _started;
  bool get isHighDuty => _chatRoomOpen || _sosActive;
  bool get isIdleDutyScanActive => _idleDutyWindowActive;
  int get connectedPeersCount => _connectedPeers;
  String? get activeGroupId => _activeGroupId;
  Set<String> get seenMessageIds => UnmodifiableSetView<String>(_seenMsgIds);
  List<String> get pendingAudioClientIds =>
      _pendingAudioQueue.map((e) => e.clientMsgId).toList(growable: false);

  Stream<MeshSosPayload> get onSosReceived => _sosCtrl.stream;
  Stream<int> get onConnectedPeersChanged => _peersCtrl.stream;
  Stream<GroupMessageRecord> get onIncomingMessage => _incomingMsgCtrl.stream;

  /// Mengaktifkan router untuk grup tertentu dan mulai memantau paket masuk.
  ///
  /// [useForegroundService] hanya diaktifkan saat perangkat benar-benar offline
  /// agar notifikasi `Hiqeo Mesh Aktif` tidak muncul ketika aplikasi online/idle.
  Future<void> start({
    required String groupId,
    int keyVersion = 1,
    bool highDuty = false,
    bool useForegroundService = false,
  }) async {
    _activeGroupId = groupId;
    _keyVersion = keyVersion;
    if (highDuty) {
      _chatRoomOpen = true;
    }

    await _packetSub?.cancel();
    await _audioSub?.cancel();
    await _peerSub?.cancel();

    _packetSub = _adapter.onPacketReceived.listen(
      (chunk) => unawaited(_handleIncomingChunk(chunk)),
    );
    _audioSub = _adapter.onAudioFileReceived.listen(
      (packet) => unawaited(_handleIncomingAudioFile(packet)),
    );
    _peerSub = _adapter.onConnectedPeersChanged.listen(_handlePeersChanged);

    final groupHash = await MeshPacketCodec.groupHashHexFor(groupId);
    try {
      await _adapter.start(
        groupHashHex: groupHash,
        highDuty: isHighDuty,
        useForegroundService: useForegroundService,
      );
    } catch (_) {
      // Radio hardware/izin parsial tidak boleh menggagalkan antrean offline lokal.
    }
    _started = true;
    _scheduleDutyCycle();
  }

  /// Menghapus cache kunci codec agar kunci baru hasil sinkronisasi online
  /// segera dipakai untuk enkripsi/dekripsi paket BLE Mesh.
  void invalidateGroupKeyCache([String? groupId]) {
    _codec.invalidateKeyCache(groupId);
  }

  /// Menghentikan radio dan timer duty cycle.
  Future<void> stop() async {
    _started = false;
    _dutyTimer?.cancel();
    _dutyTimer = null;
    await _packetSub?.cancel();
    await _audioSub?.cancel();
    await _peerSub?.cancel();
    _packetSub = null;
    _audioSub = null;
    _peerSub = null;
    await _adapter.stop();
  }

  /// Mengatur mode cepat saat ruang obrolan sedang terbuka vs mode hemat baterai saat idle.
  Future<void> setChatRoomOpen(bool isOpen) async {
    _chatRoomOpen = isOpen;
    await _syncDutyMode();
  }

  /// Mengaktifkan mode radio penuh saat sinyal SOS darurat aktif.
  Future<void> setSosActive(bool isActive) async {
    _sosActive = isActive;
    await _syncDutyMode();
  }

  Future<void> _syncDutyMode() async {
    if (!_started) return;
    _dutyTimer?.cancel();
    _dutyTimer = null;
    await _adapter.setDutyMode(highDuty: isHighDuty);
    if (!isHighDuty) {
      _idleDutyWindowActive = true;
      _scheduleDutyCycle();
    }
  }

  void _scheduleDutyCycle() {
    _dutyTimer?.cancel();
    _dutyTimer = null;
    if (!_started || isHighDuty) return;

    // Mode hemat baterai: scan aktif 2 detik -> jeda 8 detik saat idle.
    final delay = _idleDutyWindowActive ? idleScanDuration : idlePauseDuration;
    _dutyTimer = Timer(delay, () async {
      if (!_started || isHighDuty) return;
      _idleDutyWindowActive = !_idleDutyWindowActive;
      await _adapter.setDutyMode(highDuty: _idleDutyWindowActive);
      _scheduleDutyCycle();
    });
  }

  void _handlePeersChanged(int peers) {
    _connectedPeers = peers;
    if (!_peersCtrl.isClosed) {
      _peersCtrl.add(peers);
    }
    if (peers > 0) {
      unawaited(_flushStoreAndForwardAndAudio());
    }
  }

  /// Mencatat `client_msg_id` agar paket yang sama dari jalur lain (mis. Supabase)
  /// langsung diabaikan dan dimasukkan ke database lokal tanpa duplikasi.
  Future<bool> ingestExternalMessage(GroupMessageRecord record) async {
    _rememberMsgId(record.clientMsgId);
    return _localStore.insertMessageIfAbsent(record);
  }

  /// Mengirim pesan teks melalui penyimpanan lokal + siaran chunk BLE Mesh terenkripsi.
  Future<void> sendTextMessage(GroupMessageRecord record) async {
    _rememberMsgId(record.clientMsgId);
    await _localStore.insertMessageIfAbsent(record);

    final envelope = MeshEnvelope(
      kind: MeshPayloadKind.chatMessage,
      clientMsgId: record.clientMsgId,
      groupId: record.groupId,
      keyVersion: record.keyVersion,
      ttl: maxTtl,
      chatMessage: record,
    );
    await _broadcastEnvelope(envelope);
    if (_connectedPeers > 0) {
      await _localStore.markMessageMeshDelivered(
        clientMsgId: record.clientMsgId,
        groupId: record.groupId,
      );
    } else if (!_awaitingMeshDeliveryIds.contains(record.clientMsgId)) {
      _awaitingMeshDeliveryIds.add(record.clientMsgId);
    }
  }

  /// Mengirim pesan suara `.m4a`: simpan lokal -> siarkan metadata via BLE Mesh
  /// -> kirim file `.m4a` via Wi-Fi Direct (atau antrekan sampai peer tersedia).
  Future<void> sendVoiceNoteMessage({
    required GroupMessageRecord record,
    required File audioFile,
  }) async {
    final normalized = record.copyWith(localAudioPath: audioFile.path);
    _rememberMsgId(normalized.clientMsgId);
    await _localStore.insertMessageIfAbsent(normalized);

    // 1. Metadata voice note di-broadcast lewat BLE Mesh (multi-hop ringan).
    await _broadcastEnvelope(
      MeshEnvelope(
        kind: MeshPayloadKind.chatMessage,
        clientMsgId: normalized.clientMsgId,
        groupId: normalized.groupId,
        keyVersion: normalized.keyVersion,
        ttl: maxTtl,
        chatMessage: normalized,
      ),
    );

    // 2. File `.m4a` dikirim via Wi-Fi Direct atau disimpan di antrean offline.
    final meta = <String, dynamic>{
      'client_msg_id': normalized.clientMsgId,
      'group_id': normalized.groupId,
      'sender_id': normalized.senderId,
      'sender_name': normalized.senderName,
      'audio_duration_sec': normalized.audioDurationSec ?? 12,
      'key_version': normalized.keyVersion,
      'client_created_at':
          normalized.clientCreatedAtUtc.toUtc().toIso8601String(),
    };
    final delivered =
        await _adapter.sendAudioFile('broadcast', audioFile, meta);
    if (!delivered) {
      _pendingAudioQueue.removeWhere(
        (q) => q.clientMsgId == normalized.clientMsgId,
      );
      _pendingAudioQueue.add(
        _QueuedAudioTransfer(
          clientMsgId: normalized.clientMsgId,
          audioFile: audioFile,
          meta: meta,
        ),
      );
    }
  }

  /// Mengirim pembaruan lokasi/elevasi/baterai ke database lokal dan BLE Mesh.
  Future<void> sendLocationUpdate(
    MemberLastLocation location, {
    required String groupId,
    int? keyVersion,
  }) async {
    final normalized = location.copyWith(
      groupId: groupId,
      sourceTransport: ChatTransportOrigin.bleMesh,
      syncStatus: ChatSyncStatus.pending,
    );
    await _localStore.upsertMemberLocation(groupId, normalized);
    await broadcastLocationEnvelope(
      normalized,
      groupId: groupId,
      keyVersion: keyVersion,
    );
  }

  /// Menyiarkan pembaruan lokasi/elevasi/baterai lewat BLE Mesh tanpa menimpa
  /// status sinkronisasi yang sudah tersimpan di database lokal.
  Future<void> broadcastLocationEnvelope(
    MemberLastLocation location, {
    required String groupId,
    int? keyVersion,
  }) async {
    final msgId = generateUuidV4();
    _rememberMsgId(msgId);
    await _broadcastEnvelope(
      MeshEnvelope(
        kind: MeshPayloadKind.memberLocation,
        clientMsgId: msgId,
        groupId: groupId,
        keyVersion: keyVersion ?? _keyVersion,
        ttl: maxTtl,
        memberLocation: location,
      ),
    );
  }

  /// Mengirim sinyal SOS darurat dengan TTL maksimum dan mode radio cepat.
  Future<void> sendSosSignal(MeshSosPayload sos) async {
    await setSosActive(true);
    _rememberMsgId(sos.clientMsgId);
    await _broadcastEnvelope(
      MeshEnvelope(
        kind: MeshPayloadKind.sosSignal,
        clientMsgId: sos.clientMsgId,
        groupId: sos.groupId,
        keyVersion: _keyVersion,
        ttl: maxTtl,
        sosSignal: sos,
      ),
    );
  }

  Future<void> _broadcastEnvelope(
    MeshEnvelope envelope, {
    bool storeForForward = true,
  }) async {
    final chunks = await _codec.encodeAndChunk(envelope);
    if (storeForForward) {
      _enqueueStoreAndForward(chunks);
    }
    for (final chunk in chunks) {
      try {
        await _adapter.sendPacket(chunk);
      } catch (_) {}
    }
  }

  Future<void> _handleIncomingChunk(Uint8List rawChunk) async {
    final groupId = _activeGroupId;
    if (groupId == null) return;

    MeshIngestResult? result;
    try {
      result = await _codec.ingestChunk(rawChunk, groupId: groupId);
    } catch (_) {
      // Abaikan paket dari grup berbeda atau korupsi kriptografi AES-GCM.
      return;
    }
    if (result == null) return;

    final envelope = result.envelope;
    if (_seenMsgIds.contains(envelope.clientMsgId)) {
      return; // Deduplikasi hop / pengulangan pesan yang sudah pernah diproses.
    }
    _rememberMsgId(envelope.clientMsgId);

    switch (envelope.kind) {
      case MeshPayloadKind.chatMessage:
        final record = envelope.chatMessage;
        if (record != null) {
          final incomingRecord = record.copyWith(
            syncStatus: ChatSyncStatus.meshDelivered,
          );
          final inserted =
              await _localStore.insertMessageIfAbsent(incomingRecord);
          if (inserted && !_incomingMsgCtrl.isClosed) {
            _incomingMsgCtrl.add(incomingRecord);
          }
          // Kirim ACK ringan agar pengirim langsung beralih ke Titik Putih.
          unawaited(
            _broadcastEnvelope(
              MeshEnvelope(
                kind: MeshPayloadKind.deliveryAck,
                clientMsgId: generateUuidV4(),
                groupId: record.groupId,
                keyVersion: envelope.keyVersion,
                ttl: 2,
                ackedClientMsgId: record.clientMsgId,
              ),
              storeForForward: false,
            ),
          );
        }
      case MeshPayloadKind.deliveryAck:
        final ackedId = envelope.ackedClientMsgId;
        if (ackedId != null && ackedId.isNotEmpty) {
          _awaitingMeshDeliveryIds.remove(ackedId);
          await _localStore.markMessageMeshDelivered(
            clientMsgId: ackedId,
            groupId: envelope.groupId,
          );
        }
        return;
      case MeshPayloadKind.memberLocation:
        final loc = envelope.memberLocation;
        if (loc != null) {
          await _localStore.upsertMemberLocation(envelope.groupId, loc);
        }
      case MeshPayloadKind.sosSignal:
        final sos = envelope.sosSignal;
        if (sos != null) {
          if (!_sosCtrl.isClosed) _sosCtrl.add(sos);
          final locText = sos.altitudeMdpl != null
              ? '(${sos.lat.toStringAsFixed(4)}, ${sos.lon.toStringAsFixed(4)}, ${sos.altitudeMdpl} mdpl)'
              : '(${sos.lat.toStringAsFixed(4)}, ${sos.lon.toStringAsFixed(4)})';
          final sosRecord = GroupMessageRecord(
            clientMsgId: sos.clientMsgId,
            groupId: sos.groupId,
            senderId: sos.senderId,
            senderName: sos.senderName,
            messageType: GroupMessageType.text,
            content: 'DARURAT SOS (${sos.category}): $locText',
            keyVersion: envelope.keyVersion,
            originTransport: ChatTransportOrigin.bleMesh,
            syncStatus: ChatSyncStatus.pending,
            clientCreatedAtUtc: sos.createdAtUtc,
          );
          final inserted = await _localStore.insertMessageIfAbsent(sosRecord);
          if (inserted && !_incomingMsgCtrl.isClosed) {
            _incomingMsgCtrl.add(sosRecord);
          }
        }
    }

    // Store-and-forward multi-hop relay: teruskan jika TTL > 1 (maks 5 hop).
    if (result.header.ttl > 1) {
      final relayChunks = <Uint8List>[];
      for (final chunk in result.completeChunks) {
        final decremented = MeshPacketCodec.decrementChunkTtl(chunk);
        if (decremented != null) {
          relayChunks.add(decremented);
        }
      }
      if (relayChunks.isNotEmpty) {
        _enqueueStoreAndForward(relayChunks);
        for (final relayChunk in relayChunks) {
          await _adapter.sendPacket(relayChunk);
        }
      }
    }
  }

  Future<void> _handleIncomingAudioFile(OffGridAudioPacket packet) async {
    final meta = packet.meta;
    final clientMsgId = (meta['client_msg_id'] as String?) ?? generateUuidV4();
    final groupId = (meta['group_id'] as String?) ?? _activeGroupId;
    if (groupId == null) return;

    _rememberMsgId(clientMsgId);

    final record = GroupMessageRecord(
      clientMsgId: clientMsgId,
      groupId: groupId,
      senderId: (meta['sender_id'] as String?) ?? (packet.fromPeerId ?? 'peer'),
      senderName: (meta['sender_name'] as String?) ?? 'Anggota',
      messageType: GroupMessageType.audio,
      localAudioPath: packet.audioFile.path,
      audioDurationSec: (meta['audio_duration_sec'] as num?)?.toInt() ?? 12,
      keyVersion: (meta['key_version'] as num?)?.toInt() ?? _keyVersion,
      originTransport: ChatTransportOrigin.wifiDirect,
      syncStatus: ChatSyncStatus.pending,
      clientCreatedAtUtc: meta['client_created_at'] is String
          ? DateTime.parse(meta['client_created_at'] as String).toUtc()
          : DateTime.now().toUtc(),
    );
    final inserted = await _localStore.insertMessageIfAbsent(record);
    if (inserted && !_incomingMsgCtrl.isClosed) {
      _incomingMsgCtrl.add(record);
    }
  }

  Future<void> _flushStoreAndForwardAndAudio() async {
    if (!_started) return;

    if (_storeAndForwardChunks.isNotEmpty) {
      final batches = List<List<Uint8List>>.of(_storeAndForwardChunks);
      for (final batch in batches) {
        for (final chunk in batch) {
          await _adapter.sendPacket(chunk);
        }
      }
    }

    if (_connectedPeers > 0 && _awaitingMeshDeliveryIds.isNotEmpty) {
      final delivered = List<String>.of(_awaitingMeshDeliveryIds);
      _awaitingMeshDeliveryIds.clear();
      for (final msgId in delivered) {
        await _localStore.markMessageMeshDelivered(
          clientMsgId: msgId,
          groupId: _activeGroupId,
        );
      }
    }

    if (_pendingAudioQueue.isNotEmpty) {
      final remaining = <_QueuedAudioTransfer>[];
      for (final item in List<_QueuedAudioTransfer>.of(_pendingAudioQueue)) {
        final sent = await _adapter.sendAudioFile(
          'broadcast',
          item.audioFile,
          item.meta,
        );
        if (!sent) remaining.add(item);
      }
      _pendingAudioQueue
        ..clear()
        ..addAll(remaining);
    }
  }

  void _enqueueStoreAndForward(List<Uint8List> chunks) {
    if (_storeAndForwardChunks.length >= _maxStoreAndForward) {
      _storeAndForwardChunks.removeAt(0);
    }
    _storeAndForwardChunks.add(chunks);
  }

  void _rememberMsgId(String id) {
    if (_seenMsgIds.contains(id)) return;
    if (_seenMsgIds.length >= _maxSeenIds) {
      _seenMsgIds.remove(_seenMsgIds.first);
    }
    _seenMsgIds.add(id);
  }

  Future<void> dispose() async {
    await stop();
    await _sosCtrl.close();
    await _peersCtrl.close();
    await _incomingMsgCtrl.close();
  }
}
