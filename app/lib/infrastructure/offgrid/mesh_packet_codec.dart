import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../features/chat/domain/group_chat_models.dart';
import '../../features/groups/domain/group_key_store.dart';
import '../crypto/crypto_interfaces.dart';
import '../crypto/cryptography_aead_cipher.dart';
import '../crypto/flutter_secure_value_store.dart';
import '../crypto/secure_group_key_store.dart';

/// Jenis muatan biner yang dikemas oleh [MeshPacketCodec].
enum MeshPayloadKind {
  chatMessage(1),
  memberLocation(2),
  sosSignal(3),
  deliveryAck(4);

  const MeshPayloadKind(this.code);

  final int code;

  static MeshPayloadKind? fromCode(int code) {
    for (final k in MeshPayloadKind.values) {
      if (k.code == code) return k;
    }
    return null;
  }
}

/// Payload SOS darurat yang dikirim melalui BLE Mesh multi-hop.
class MeshSosPayload {
  const MeshSosPayload({
    required this.clientMsgId,
    required this.groupId,
    required this.senderId,
    required this.senderName,
    required this.lat,
    required this.lon,
    this.altitudeMdpl,
    this.batteryPercent,
    this.category = 'darurat',
    required this.createdAtUtc,
  });

  final String clientMsgId;
  final String groupId;
  final String senderId;
  final String senderName;
  final double lat;
  final double lon;
  final int? altitudeMdpl;
  final int? batteryPercent;
  final String category;
  final DateTime createdAtUtc;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'client_msg_id': clientMsgId,
        'group_id': groupId,
        'sender_id': senderId,
        'sender_name': senderName,
        'lat': lat,
        'lon': lon,
        if (altitudeMdpl != null) 'altitude_mdpl': altitudeMdpl,
        if (batteryPercent != null) 'battery_percent': batteryPercent,
        'category': category,
        'created_at': createdAtUtc.toUtc().toIso8601String(),
      };

  static MeshSosPayload fromJson(Map<String, dynamic> map) => MeshSosPayload(
        clientMsgId: map['client_msg_id'] as String,
        groupId: map['group_id'] as String,
        senderId: map['sender_id'] as String,
        senderName: (map['sender_name'] as String?) ?? 'Pendaki',
        lat: (map['lat'] as num).toDouble(),
        lon: (map['lon'] as num).toDouble(),
        altitudeMdpl: (map['altitude_mdpl'] as num?)?.toInt(),
        batteryPercent: (map['battery_percent'] as num?)?.toInt(),
        category: (map['category'] as String?) ?? 'darurat',
        createdAtUtc:
            DateTime.parse(map['created_at'] as String).toUtc(),
      );
}

/// Amplop aplikasi terdekripsi hasil reassembly BLE Mesh.
class MeshEnvelope {
  const MeshEnvelope({
    required this.kind,
    required this.clientMsgId,
    required this.groupId,
    required this.keyVersion,
    required this.ttl,
    this.chatMessage,
    this.memberLocation,
    this.sosSignal,
    this.ackedClientMsgId,
  });

  final MeshPayloadKind kind;
  final String clientMsgId;
  final String groupId;
  final int keyVersion;
  final int ttl;
  final GroupMessageRecord? chatMessage;
  final MemberLastLocation? memberLocation;
  final MeshSosPayload? sosSignal;
  final String? ackedClientMsgId;
}

/// Header biner 12-byte di awal setiap paket potongan BLE Mesh (maks total 180 byte).
class MeshChunkHeader {
  const MeshChunkHeader({
    required this.kind,
    required this.ttl,
    required this.keyVersion,
    required this.msgHash32,
    required this.chunkIndex,
    required this.totalChunks,
  });

  final MeshPayloadKind kind;
  final int ttl;
  final int keyVersion;
  final int msgHash32;
  final int chunkIndex;
  final int totalChunks;
}

class MeshIngestResult {
  const MeshIngestResult({
    required this.header,
    required this.envelope,
    required this.completeChunks,
  });

  final MeshChunkHeader header;
  final MeshEnvelope envelope;
  final List<Uint8List> completeChunks;
}

/// Codec biner murni Dart untuk mengenkripsi pesan chat, lokasi/baterai, dan SOS
/// memakai AES-256-GCM dengan kunci grup dari `flutter_secure_storage`, lalu
/// memecahnya menjadi potongan <= 180 byte (12 byte header + 168 byte payload).
class MeshPacketCodec {
  MeshPacketCodec({
    GroupKeyStore? keyStore,
    AeadCipher? cipher,
  })  : _keyStore =
            keyStore ?? const SecureGroupKeyStore(store: FlutterSecureValueStore()),
        _cipher = cipher ?? CryptographyAeadCipher();

  static const int maxPacketBytes = 180;
  static const int headerBytes = 12;
  static const int maxChunkPayloadBytes = 168;
  static const int maxTtl = 5;
  static const int magicByte = 0x48; // 'H'

  final GroupKeyStore _keyStore;
  final AeadCipher _cipher;

  final Map<String, Uint8List> _keyCache = <String, Uint8List>{};
  final Map<int, _ReassemblyBuffer> _buffers = <int, _ReassemblyBuffer>{};

  /// Menghitung 12-hex karakter hash grup untuk filter BLE / topik grup.
  static Future<String> groupHashHexFor(String groupId) async {
    final hash = await Sha256().hash(utf8.encode('hiqeo-group:$groupId'));
    return hash.bytes
        .take(6)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Kunci fallback deterministik lama (hanya untuk grup lokal murni yang
  /// belum pernah sinkron dengan server, atau mendeteksi & membersihkan
  /// cache lama yang pernah tertulis sebelum perbaikan sinkronisasi kunci).
  static Future<Uint8List> deriveFallbackGroupKey(
    String groupId,
    int keyVersion,
  ) async {
    final derived = await Sha256().hash(
      utf8.encode('hiqeo-mesh-key:$groupId:v$keyVersion'),
    );
    return Uint8List.fromList(derived.bytes);
  }

  /// Menghapus cache kunci di memori agar perubahan kunci dari Keystore/Keychain
  /// (misalnya setelah pemilik membagikan kunci grup) langsung dipakai.
  void invalidateKeyCache([String? groupId]) {
    if (groupId == null) {
      _keyCache.clear();
    } else {
      _keyCache.removeWhere((k, _) => k.startsWith('$groupId:'));
    }
  }

  /// Membaca kunci grup 32-byte yang identik antar-anggota dari Keystore/Keychain
  /// (`flutter_secure_storage` / [GroupKeyStore]).
  ///
  /// PENTING: Jangan pernah menimpa [GroupKeyStore] dengan kunci fallback lokal
  /// karena hal itu akan mencegah [GroupKeyManager] membuka kunci asli milik
  /// pemilik dari `group_key_blobs` dan membuat dekripsi AES-GCM BLE Mesh gagal
  /// diam-diam antar-HP.
  Future<Uint8List> resolveGroupKey(String groupId, int keyVersion) async {
    final cacheKey = '$groupId:v$keyVersion';
    final cached = _keyCache[cacheKey];
    if (cached != null) return cached;

    try {
      final stored = await _keyStore.readGroupKey(groupId, keyVersion);
      if (stored != null && stored.length == 32) {
        _keyCache[cacheKey] = stored;
        return stored;
      }
    } catch (_) {
      // Fallback bila FlutterSecureStorage belum tersedia (mis. unit test).
    }

    // Fallback sementara di memori saja (TIDAK disimpan ke secure storage dan
    // TIDAK di-cache permanen) sehingga begitu kunci asli grup masuk ke
    // flutter_secure_storage, pemanggilan berikutnya langsung memakai kunci asli.
    return deriveFallbackGroupKey(groupId, keyVersion);
  }

  /// Mengenkripsi [envelope] memakai AES-256-GCM dan memecahnya menjadi chunk <= 180 byte.
  Future<List<Uint8List>> encodeAndChunk(MeshEnvelope envelope) async {
    final ttl = envelope.ttl.clamp(1, maxTtl);
    final key = await resolveGroupKey(envelope.groupId, envelope.keyVersion);
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(_toJson(envelope))));
    final aad = Uint8List.fromList(
      utf8.encode('${envelope.groupId}:v${envelope.keyVersion}:${envelope.kind.code}'),
    );

    final encrypted = await _cipher.encrypt(
      groupKey: key,
      plaintext: plaintext,
      associatedData: aad,
    );

    final msgHash32 = fnv1a32(envelope.clientMsgId);
    final totalChunks =
        ((encrypted.length + maxChunkPayloadBytes - 1) ~/ maxChunkPayloadBytes)
            .clamp(1, 65535);

    final chunks = <Uint8List>[];
    for (var i = 0; i < totalChunks; i++) {
      final start = i * maxChunkPayloadBytes;
      final end = (start + maxChunkPayloadBytes) > encrypted.length
          ? encrypted.length
          : (start + maxChunkPayloadBytes);
      final slice = encrypted.sublist(start, end);

      final packet = Uint8List(headerBytes + slice.length);
      final bd = ByteData.view(packet.buffer);
      bd.setUint8(0, magicByte);
      bd.setUint8(1, ((envelope.kind.code & 0x0f) << 4) | (ttl & 0x0f));
      bd.setUint16(2, envelope.keyVersion & 0xffff);
      bd.setUint32(4, msgHash32);
      bd.setUint16(8, i & 0xffff);
      bd.setUint16(10, totalChunks & 0xffff);
      packet.setRange(headerBytes, packet.length, slice);
      chunks.add(packet);
    }
    return chunks;
  }

  /// Memeriksa header 12-byte dari satu chunk mentah.
  static MeshChunkHeader? inspectHeader(Uint8List chunk) {
    if (chunk.length <= headerBytes || chunk.length > maxPacketBytes) {
      return null;
    }
    if (chunk[0] != magicByte) return null;
    final kind = MeshPayloadKind.fromCode((chunk[1] >> 4) & 0x0f);
    if (kind == null) return null;
    final ttl = chunk[1] & 0x0f;
    if (ttl <= 0 || ttl > maxTtl) return null;

    final bd = ByteData.sublistView(chunk);
    final keyVersion = bd.getUint16(2);
    final msgHash32 = bd.getUint32(4);
    final chunkIndex = bd.getUint16(8);
    final totalChunks = bd.getUint16(10);
    if (totalChunks == 0 || chunkIndex >= totalChunks) return null;

    return MeshChunkHeader(
      kind: kind,
      ttl: ttl,
      keyVersion: keyVersion,
      msgHash32: msgHash32,
      chunkIndex: chunkIndex,
      totalChunks: totalChunks,
    );
  }

  /// Mengembalikan salinan chunk dengan `TTL` dikurangi 1, atau `null` bila habis (`ttl <= 1`).
  static Uint8List? decrementChunkTtl(Uint8List chunk) {
    final header = inspectHeader(chunk);
    if (header == null || header.ttl <= 1) return null;
    final copy = Uint8List.fromList(chunk);
    copy[1] = ((header.kind.code & 0x0f) << 4) | ((header.ttl - 1) & 0x0f);
    return copy;
  }

  /// Memasukkan satu potongan chunk 180-byte; jika seluruh potongan telah lengkap,
  /// mengembalikan amplop yang sudah didekripsi dan disusun ulang.
  Future<MeshIngestResult?> ingestChunk(
    Uint8List chunk, {
    required String groupId,
  }) async {
    final header = inspectHeader(chunk);
    if (header == null) return null;

    _evictStaleBuffers();

    final buffer = _buffers.putIfAbsent(
      header.msgHash32,
      () => _ReassemblyBuffer(
        totalChunks: header.totalChunks,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    if (buffer.totalChunks != header.totalChunks) {
      _buffers[header.msgHash32] = _ReassemblyBuffer(
        totalChunks: header.totalChunks,
        createdAt: DateTime.now().toUtc(),
      );
    }

    final activeBuffer = _buffers[header.msgHash32]!;
    activeBuffer.chunks[header.chunkIndex] =
        Uint8List.fromList(chunk.sublist(headerBytes));
    activeBuffer.rawPackets[header.chunkIndex] = Uint8List.fromList(chunk);

    if (!activeBuffer.isComplete) return null;

    final completePackets = <Uint8List>[
      for (var i = 0; i < header.totalChunks; i++) activeBuffer.rawPackets[i]!,
    ];
    final combinedLen = activeBuffer.chunks.values.fold<int>(
      0,
      (sum, slice) => sum + slice.length,
    );
    final ciphertext = Uint8List(combinedLen);
    var offset = 0;
    for (var i = 0; i < header.totalChunks; i++) {
      final slice = activeBuffer.chunks[i]!;
      ciphertext.setRange(offset, offset + slice.length, slice);
      offset += slice.length;
    }

    _buffers.remove(header.msgHash32);

    final key = await resolveGroupKey(groupId, header.keyVersion);
    final aad = Uint8List.fromList(
      utf8.encode('$groupId:v${header.keyVersion}:${header.kind.code}'),
    );
    final plaintext = await _cipher.decrypt(
      groupKey: key,
      ciphertext: ciphertext,
      associatedData: aad,
    );
    final jsonMap = jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
    final envelope = _fromJson(
      jsonMap,
      kind: header.kind,
      keyVersion: header.keyVersion,
      ttl: header.ttl,
    );

    return MeshIngestResult(
      header: header,
      envelope: envelope,
      completeChunks: completePackets,
    );
  }

  void _evictStaleBuffers() {
    if (_buffers.length < 32) return;
    final cutoff = DateTime.now().toUtc().subtract(const Duration(seconds: 45));
    _buffers.removeWhere((_, buf) => buf.createdAt.isBefore(cutoff));
  }

  static int fnv1a32(String input) {
    var hash = 0x811c9dc5;
    for (final b in utf8.encode(input)) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  Map<String, dynamic> _toJson(MeshEnvelope e) {
    switch (e.kind) {
      case MeshPayloadKind.chatMessage:
        final m = e.chatMessage!;
        return <String, dynamic>{
          'client_msg_id': m.clientMsgId,
          'group_id': m.groupId,
          'sender_id': m.senderId,
          'sender_name': m.senderName,
          'message_type': m.messageType.dbValue,
          if (m.content != null) 'content': m.content,
          if (m.audioDurationSec != null)
            'audio_duration_sec': m.audioDurationSec,
          'client_created_at': m.clientCreatedAtUtc.toUtc().toIso8601String(),
        };
      case MeshPayloadKind.memberLocation:
        final l = e.memberLocation!;
        return <String, dynamic>{
          'client_msg_id': e.clientMsgId,
          'group_id': e.groupId,
          'user_id': l.userId,
          'display_name': l.displayName,
          'latitude': l.lat ?? 0.0,
          'longitude': l.lon ?? 0.0,
          if (l.altitudeMdpl != null) 'altitude_mdpl': l.altitudeMdpl,
          if (l.batteryPercent != null) 'battery_percent': l.batteryPercent,
          if (l.accuracyM != null) 'accuracy_m': l.accuracyM,
          'recorded_at': l.effectiveRecordedAtUtc.toUtc().toIso8601String(),
        };
      case MeshPayloadKind.sosSignal:
        return e.sosSignal!.toJson();
      case MeshPayloadKind.deliveryAck:
        return <String, dynamic>{
          'client_msg_id': e.clientMsgId,
          'group_id': e.groupId,
          'acked_client_msg_id': e.ackedClientMsgId ?? '',
        };
    }
  }

  MeshEnvelope _fromJson(
    Map<String, dynamic> map, {
    required MeshPayloadKind kind,
    required int keyVersion,
    required int ttl,
  }) {
    final clientMsgId = map['client_msg_id'] as String;
    final groupId = map['group_id'] as String;

    switch (kind) {
      case MeshPayloadKind.chatMessage:
        final record = GroupMessageRecord(
          clientMsgId: clientMsgId,
          groupId: groupId,
          senderId: map['sender_id'] as String,
          senderName: (map['sender_name'] as String?) ?? 'Anggota',
          messageType: GroupMessageType.fromDb(map['message_type'] as String?),
          content: map['content'] as String?,
          audioDurationSec: (map['audio_duration_sec'] as num?)?.toInt(),
          keyVersion: keyVersion,
          originTransport: ChatTransportOrigin.bleMesh,
          syncStatus: ChatSyncStatus.pending,
          clientCreatedAtUtc:
              DateTime.parse(map['client_created_at'] as String).toUtc(),
        );
        return MeshEnvelope(
          kind: kind,
          clientMsgId: clientMsgId,
          groupId: groupId,
          keyVersion: keyVersion,
          ttl: ttl,
          chatMessage: record,
        );
      case MeshPayloadKind.memberLocation:
        final userId = map['user_id'] as String;
        final displayName = (map['display_name'] as String?) ?? 'Anggota';
        final recordedAt =
            DateTime.parse(map['recorded_at'] as String).toUtc();
        final loc = MemberLastLocation(
          groupId: groupId,
          userId: userId,
          displayName: displayName,
          initial:
              displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
          hasSignal: true,
          lat: (map['latitude'] as num?)?.toDouble(),
          lon: (map['longitude'] as num?)?.toDouble(),
          altitudeMdpl: (map['altitude_mdpl'] as num?)?.toInt(),
          batteryPercent: (map['battery_percent'] as num?)?.toInt(),
          accuracyM: (map['accuracy_m'] as num?)?.toInt(),
          sourceTransport: ChatTransportOrigin.bleMesh,
          syncStatus: ChatSyncStatus.pending,
          recordedAtUtc: recordedAt,
          updatedAtUtc: recordedAt,
        );
        return MeshEnvelope(
          kind: kind,
          clientMsgId: clientMsgId,
          groupId: groupId,
          keyVersion: keyVersion,
          ttl: ttl,
          memberLocation: loc,
        );
      case MeshPayloadKind.sosSignal:
        return MeshEnvelope(
          kind: kind,
          clientMsgId: clientMsgId,
          groupId: groupId,
          keyVersion: keyVersion,
          ttl: ttl,
          sosSignal: MeshSosPayload.fromJson(map),
        );
      case MeshPayloadKind.deliveryAck:
        return MeshEnvelope(
          kind: kind,
          clientMsgId: clientMsgId,
          groupId: groupId,
          keyVersion: keyVersion,
          ttl: ttl,
          ackedClientMsgId: map['acked_client_msg_id'] as String?,
        );
    }
  }
}

class _ReassemblyBuffer {
  _ReassemblyBuffer({required this.totalChunks, required this.createdAt});

  final int totalChunks;
  final DateTime createdAt;
  final Map<int, Uint8List> chunks = <int, Uint8List>{};
  final Map<int, Uint8List> rawPackets = <int, Uint8List>{};

  bool get isComplete => chunks.length == totalChunks;
}
