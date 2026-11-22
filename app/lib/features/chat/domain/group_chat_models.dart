import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mesh_protocol/mesh_protocol.dart';

import '../../groups/domain/group.dart';
import '../../groups/domain/group_remote_service.dart';
import 'chat_message.dart';

/// Status pengiriman & sinkronisasi pesan/lokasi:
/// - [pending]: belum terkirim ke peer maupun server (Ikon Jam)
/// - [meshDelivered]: sudah terkirim/diterima peer via Offline Hiqeo Mesh (Titik Putih)
/// - [sent]: terkirim/tersinkronisasi via Online Supabase (Titik Biru)
enum ChatSyncStatus {
  pending('pending'),
  meshDelivered('mesh_delivered'),
  sent('sent');

  const ChatSyncStatus(this.dbValue);

  final String dbValue;

  static ChatSyncStatus fromDb(String? value) {
    if (value == 'sent') return ChatSyncStatus.sent;
    if (value == 'mesh_delivered') return ChatSyncStatus.meshDelivered;
    return ChatSyncStatus.pending;
  }
}

/// Menghasilkan UUID v4 acak secara kriptografis aman untuk `client_msg_id`.
String generateUuidV4([math.Random? rng]) {
  final random = rng ?? math.Random.secure();
  final bytes = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    bytes[i] = random.nextInt(256);
  }
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // Versi 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // Varian RFC 4122

  String hex2(int b) => b.toRadixString(16).padLeft(2, '0');
  final h = bytes.map(hex2).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
      '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20, 32)}';
}

/// Asal transport pesan/lokasi grup (sesuai kolom `origin_transport` &
/// `source_transport` di Supabase).
enum ChatTransportOrigin {
  online('online', 'Online'),
  bleMesh('ble_mesh', 'BLE Mesh'),
  wifiDirect('wifi_direct', 'Wi-Fi Direct');

  const ChatTransportOrigin(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static ChatTransportOrigin fromDb(String? value) {
    switch (value) {
      case 'ble_mesh':
        return ChatTransportOrigin.bleMesh;
      case 'wifi_direct':
        return ChatTransportOrigin.wifiDirect;
      case 'online':
      default:
        return ChatTransportOrigin.online;
    }
  }
}

/// Jenis pesan di tabel Supabase `public.group_messages`.
enum GroupMessageType {
  text('text'),
  audio('audio');

  const GroupMessageType(this.dbValue);

  final String dbValue;

  static GroupMessageType fromDb(String? value) {
    return value == 'audio' ? GroupMessageType.audio : GroupMessageType.text;
  }
}

final RegExp _kUuidRegExp = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Memeriksa apakah string berbentuk UUID kanonik (`8-4-4-4-12`).
bool isValidUuid(String? value) =>
    value != null && _kUuidRegExp.hasMatch(value.trim());

/// Mengonversi string sembarang (termasuk ID lama berprefiks seperti `sos-...`
/// atau `invite_hike_...`) menjadi UUIDv5 kanonik lowercase. Bila [raw] sudah
/// berbentuk UUID valid, nilainya dinormalisasi ke lowercase dan dikembalikan apa
/// adanya agar selalu kompatibel dengan kolom bertipe `uuid` di PostgreSQL.
String normalizeToUuid(String raw) {
  final trimmed = raw.trim();
  if (isValidUuid(trimmed)) {
    return trimmed.toLowerCase();
  }
  const namespaceHex = '9f4b2c71a8e24d6f8c3a5e71d2904b12';
  final nsBytes = <int>[
    for (var i = 0; i < namespaceHex.length; i += 2)
      int.parse(namespaceHex.substring(i, i + 2), radix: 16),
  ];
  final digest = _sha1(<int>[...nsBytes, ...utf8.encode(trimmed)]);
  final uuidBytes = digest.sublist(0, 16);
  uuidBytes[6] = (uuidBytes[6] & 0x0f) | 0x50;
  uuidBytes[8] = (uuidBytes[8] & 0x3f) | 0x80;

  String hex2(int b) => b.toRadixString(16).padLeft(2, '0');
  final h = uuidBytes.map(hex2).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
      '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20, 32)}';
}

/// Menghasilkan `client_msg_id` berbentuk UUIDv5 deterministik dari identitas pesan
/// sehingga beberapa perangkat yang me-relay paket BLE Mesh / Wi-Fi Direct yang
/// sama selalu menghasilkan UUID identik untuk deduplikasi server (`onConflict: client_msg_id`).
String deterministicClientMsgId({
  required String groupId,
  required String authorId,
  required int seq,
  required DateTime sentAtUtc,
}) {
  // Namespace tetap Hiqeo (UUID v4 valid) + metadata pesan.
  const namespaceHex = '9f4b2c71a8e24d6f8c3a5e71d2904b12';
  final nsBytes = <int>[
    for (var i = 0; i < namespaceHex.length; i += 2)
      int.parse(namespaceHex.substring(i, i + 2), radix: 16),
  ];
  final payload = utf8.encode(
    '$groupId|$authorId|$seq|${sentAtUtc.toUtc().millisecondsSinceEpoch}',
  );
  final digest = _sha1(<int>[...nsBytes, ...payload]);
  final uuidBytes = digest.sublist(0, 16);
  uuidBytes[6] = (uuidBytes[6] & 0x0f) | 0x50; // Versi 5
  uuidBytes[8] = (uuidBytes[8] & 0x3f) | 0x80; // Varian RFC 4122

  String hex2(int b) => b.toRadixString(16).padLeft(2, '0');
  final h = uuidBytes.map(hex2).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
      '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20, 32)}';
}

Uint8List _sha1(List<int> input) {
  int rotl(int n, int bits) => ((n << bits) | (n >>> (32 - bits))) & 0xffffffff;

  final bitLen = input.length * 8;
  final bytes = <int>[...input, 0x80];
  while ((bytes.length % 64) != 56) {
    bytes.add(0);
  }
  for (var shift = 56; shift >= 0; shift -= 8) {
    bytes.add((bitLen >>> shift) & 0xff);
  }

  var h0 = 0x67452301;
  var h1 = 0xefcdab89;
  var h2 = 0x98badcfe;
  var h3 = 0x10325476;
  var h4 = 0xc3d2e1f0;

  final w = List<int>.filled(80, 0);
  for (var i = 0; i < bytes.length; i += 64) {
    for (var j = 0; j < 16; j++) {
      final base = i + j * 4;
      w[j] = ((bytes[base] << 24) |
              (bytes[base + 1] << 16) |
              (bytes[base + 2] << 8) |
              bytes[base + 3]) &
          0xffffffff;
    }
    for (var j = 16; j < 80; j++) {
      w[j] = rotl(w[j - 3] ^ w[j - 8] ^ w[j - 14] ^ w[j - 16], 1);
    }

    var a = h0;
    var b = h1;
    var c = h2;
    var d = h3;
    var e = h4;

    for (var j = 0; j < 80; j++) {
      final int f;
      final int k;
      if (j < 20) {
        f = (b & c) | ((~b & 0xffffffff) & d);
        k = 0x5a827999;
      } else if (j < 40) {
        f = b ^ c ^ d;
        k = 0x6ed9eba1;
      } else if (j < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8f1bbcdc;
      } else {
        f = b ^ c ^ d;
        k = 0xca62c1d6;
      }
      final temp = (rotl(a, 5) + f + e + k + w[j]) & 0xffffffff;
      e = d;
      d = c;
      c = rotl(b, 30);
      b = a;
      a = temp;
    }

    h0 = (h0 + a) & 0xffffffff;
    h1 = (h1 + b) & 0xffffffff;
    h2 = (h2 + c) & 0xffffffff;
    h3 = (h3 + d) & 0xffffffff;
    h4 = (h4 + e) & 0xffffffff;
  }

  final out = Uint8List(20);
  final bd = ByteData.view(out.buffer);
  bd.setUint32(0, h0);
  bd.setUint32(4, h1);
  bd.setUint32(8, h2);
  bd.setUint32(12, h3);
  bd.setUint32(16, h4);
  return out;
}

/// Representasi baris pada tabel Supabase `public.group_messages` serta
/// tabel lokal SQLite `local_group_messages` (single source of truth).
class GroupMessageRecord {
  const GroupMessageRecord({
    this.id,
    required this.clientMsgId,
    required this.groupId,
    required this.senderId,
    required this.senderName,
    required this.messageType,
    this.content,
    this.localAudioPath,
    this.audioUrl,
    this.audioDurationSec,
    this.keyVersion = 1,
    this.originTransport = ChatTransportOrigin.online,
    this.syncStatus = ChatSyncStatus.pending,
    required this.clientCreatedAtUtc,
    this.createdAtUtc,
    this.isDeleted = false,
    this.deletedAtUtc,
    this.isCancelled = false,
    this.cancelledAtUtc,
  });

  final String? id;
  final String clientMsgId;
  final String groupId;
  final String senderId;
  final String senderName;
  final GroupMessageType messageType;
  final String? content;
  final String? localAudioPath;
  final String? audioUrl;
  final int? audioDurationSec;
  final int keyVersion;
  final ChatTransportOrigin originTransport;
  final ChatSyncStatus syncStatus;
  final DateTime clientCreatedAtUtc;
  final DateTime? createdAtUtc;
  final bool isDeleted;
  final DateTime? deletedAtUtc;
  final bool isCancelled;
  final DateTime? cancelledAtUtc;

  GroupMessageRecord copyWith({
    String? id,
    String? clientMsgId,
    String? groupId,
    String? senderId,
    String? senderName,
    GroupMessageType? messageType,
    String? content,
    String? localAudioPath,
    String? audioUrl,
    int? audioDurationSec,
    int? keyVersion,
    ChatTransportOrigin? originTransport,
    ChatSyncStatus? syncStatus,
    DateTime? clientCreatedAtUtc,
    DateTime? createdAtUtc,
    bool? isDeleted,
    DateTime? deletedAtUtc,
    bool? isCancelled,
    DateTime? cancelledAtUtc,
  }) {
    return GroupMessageRecord(
      id: id ?? this.id,
      clientMsgId: clientMsgId ?? this.clientMsgId,
      groupId: groupId ?? this.groupId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      messageType: messageType ?? this.messageType,
      content: content ?? this.content,
      localAudioPath: localAudioPath ?? this.localAudioPath,
      audioUrl: audioUrl ?? this.audioUrl,
      audioDurationSec: audioDurationSec ?? this.audioDurationSec,
      keyVersion: keyVersion ?? this.keyVersion,
      originTransport: originTransport ?? this.originTransport,
      syncStatus: syncStatus ?? this.syncStatus,
      clientCreatedAtUtc: clientCreatedAtUtc ?? this.clientCreatedAtUtc,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAtUtc: deletedAtUtc ?? this.deletedAtUtc,
      isCancelled: isCancelled ?? this.isCancelled,
      cancelledAtUtc: cancelledAtUtc ?? this.cancelledAtUtc,
    );
  }

  Map<String, dynamic> toLocalSqliteMap() {
    return <String, dynamic>{
      'client_msg_id': clientMsgId,
      'group_id': groupId,
      'sender_id': senderId,
      'sender_name': senderName,
      'message_type': messageType.dbValue,
      'content': isDeleted ? null : content,
      'local_audio_path': isDeleted ? null : localAudioPath,
      'audio_url': isDeleted ? null : audioUrl,
      'audio_duration_sec': isDeleted ? null : audioDurationSec,
      'key_version': keyVersion,
      'origin_transport': originTransport.dbValue,
      'sync_status': syncStatus.dbValue,
      'client_created_at': clientCreatedAtUtc.toUtc().millisecondsSinceEpoch,
      'is_deleted': isDeleted ? 1 : 0,
      'deleted_at': deletedAtUtc?.toUtc().millisecondsSinceEpoch,
      'is_cancelled': isCancelled ? 1 : 0,
      'cancelled_at': cancelledAtUtc?.toUtc().millisecondsSinceEpoch,
    };
  }

  static GroupMessageRecord fromLocalSqliteMap(Map<String, Object?> map) {
    final createdMs = (map['client_created_at'] as num?)?.toInt() ??
        DateTime.now().toUtc().millisecondsSinceEpoch;
    final deletedMs = (map['deleted_at'] as num?)?.toInt();
    final cancelledMs = (map['cancelled_at'] as num?)?.toInt();
    final isDeleted = ((map['is_deleted'] as num?)?.toInt() ?? 0) == 1 ||
        deletedMs != null;
    final isCancelled = ((map['is_cancelled'] as num?)?.toInt() ?? 0) == 1 ||
        cancelledMs != null;
    return GroupMessageRecord(
      clientMsgId: map['client_msg_id'] as String,
      groupId: map['group_id'] as String,
      senderId: map['sender_id'] as String,
      senderName: (map['sender_name'] as String?) ?? 'Anggota',
      messageType: GroupMessageType.fromDb(map['message_type'] as String?),
      content: isDeleted ? null : map['content'] as String?,
      localAudioPath: isDeleted ? null : map['local_audio_path'] as String?,
      audioUrl: isDeleted ? null : map['audio_url'] as String?,
      audioDurationSec:
          isDeleted ? null : (map['audio_duration_sec'] as num?)?.toInt(),
      keyVersion: (map['key_version'] as num?)?.toInt() ?? 1,
      originTransport:
          ChatTransportOrigin.fromDb(map['origin_transport'] as String?),
      syncStatus: ChatSyncStatus.fromDb(map['sync_status'] as String?),
      clientCreatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        createdMs,
        isUtc: true,
      ),
      isDeleted: isDeleted,
      deletedAtUtc: deletedMs != null
          ? DateTime.fromMillisecondsSinceEpoch(deletedMs, isUtc: true)
          : null,
      isCancelled: isCancelled,
      cancelledAtUtc: cancelledMs != null
          ? DateTime.fromMillisecondsSinceEpoch(cancelledMs, isUtc: true)
          : null,
    );
  }

  Map<String, dynamic> toSupabaseInsertMap() {
    return <String, dynamic>{
      'client_msg_id': clientMsgId,
      'group_id': groupId,
      'sender_id': senderId,
      'sender_name': senderName,
      'message_type': messageType.dbValue,
      'content': isDeleted ? null : content,
      'audio_url': isDeleted ? null : audioUrl,
      'audio_duration_sec': isDeleted ? null : audioDurationSec,
      'key_version': keyVersion,
      'origin_transport': originTransport.dbValue,
      'client_created_at': clientCreatedAtUtc.toUtc().toIso8601String(),
      'is_deleted': isDeleted,
      if (deletedAtUtc != null)
        'deleted_at': deletedAtUtc!.toUtc().toIso8601String(),
      'is_cancelled': isCancelled,
      if (cancelledAtUtc != null)
        'cancelled_at': cancelledAtUtc!.toUtc().toIso8601String(),
    };
  }

  static GroupMessageRecord fromSupabaseMap(Map<String, dynamic> map) {
    final rawClientCreated = map['client_created_at'] as String?;
    final rawCreated = map['created_at'] as String?;
    final rawDeleted = map['deleted_at'] as String?;
    final rawCancelled = map['cancelled_at'] as String?;
    final isDeleted = map['is_deleted'] == true || rawDeleted != null;
    final isCancelled = map['is_cancelled'] == true || rawCancelled != null;
    return GroupMessageRecord(
      id: map['id'] as String?,
      clientMsgId: map['client_msg_id'] as String,
      groupId: map['group_id'] as String,
      senderId: map['sender_id'] as String,
      senderName: (map['sender_name'] as String?) ?? 'Anggota',
      messageType: GroupMessageType.fromDb(map['message_type'] as String?),
      content: isDeleted ? null : map['content'] as String?,
      localAudioPath: isDeleted ? null : map['local_audio_path'] as String?,
      audioUrl: isDeleted ? null : map['audio_url'] as String?,
      audioDurationSec:
          isDeleted ? null : (map['audio_duration_sec'] as num?)?.toInt(),
      keyVersion: (map['key_version'] as num?)?.toInt() ?? 1,
      originTransport:
          ChatTransportOrigin.fromDb(map['origin_transport'] as String?),
      syncStatus: ChatSyncStatus.sent,
      clientCreatedAtUtc: rawClientCreated != null
          ? DateTime.parse(rawClientCreated).toUtc()
          : DateTime.now().toUtc(),
      createdAtUtc:
          rawCreated != null ? DateTime.parse(rawCreated).toUtc() : null,
      isDeleted: isDeleted,
      deletedAtUtc:
          rawDeleted != null ? DateTime.tryParse(rawDeleted)?.toUtc() : null,
      isCancelled: isCancelled,
      cancelledAtUtc:
          rawCancelled != null ? DateTime.tryParse(rawCancelled)?.toUtc() : null,
    );
  }

  /// Konversi dari pesan lokal [ChatMessage] ke rekaman Supabase / SQLite.
  static GroupMessageRecord fromChatMessage(
    ChatMessage msg, {
    String? clientMsgId,
    required String senderName,
    int keyVersion = 1,
    ChatTransportOrigin originTransport = ChatTransportOrigin.online,
    ChatSyncStatus? syncStatus,
    String? localAudioPath,
    String? audioUrl,
  }) {
    final resolvedSync = syncStatus ??
        (originTransport == ChatTransportOrigin.online
            ? ChatSyncStatus.sent
            : ChatSyncStatus.pending);
    if (msg.type == PacketType.voiceFragment) {
      final vn = VoiceNoteData.fromBytes(msg.payload);
      final resolvedClientMsgId = clientMsgId ??
          vn.clientMsgId ??
          deterministicClientMsgId(
            groupId: msg.groupId,
            authorId: msg.authorId,
            seq: msg.seq,
            sentAtUtc: msg.sentAtUtc,
          );
      return GroupMessageRecord(
        clientMsgId: resolvedClientMsgId,
        groupId: msg.groupId,
        senderId: msg.authorId,
        senderName: senderName,
        messageType: GroupMessageType.audio,
        localAudioPath: localAudioPath ?? vn.localAudioPath,
        audioUrl: audioUrl ?? vn.audioUrl,
        audioDurationSec: vn.durationSeconds,
        keyVersion: keyVersion,
        originTransport: originTransport,
        syncStatus: resolvedSync,
        clientCreatedAtUtc: msg.sentAtUtc.toUtc(),
      );
    }

    final text = utf8.decode(msg.payload, allowMalformed: true);
    return GroupMessageRecord(
      clientMsgId: clientMsgId ??
          deterministicClientMsgId(
            groupId: msg.groupId,
            authorId: msg.authorId,
            seq: msg.seq,
            sentAtUtc: msg.sentAtUtc,
          ),
      groupId: msg.groupId,
      senderId: msg.authorId,
      senderName: senderName,
      messageType: GroupMessageType.text,
      content: text,
      keyVersion: keyVersion,
      originTransport: originTransport,
      syncStatus: resolvedSync,
      clientCreatedAtUtc: msg.sentAtUtc.toUtc(),
    );
  }

  /// Konversi rekaman ke model [ChatMessage] untuk UI gelembung chat.
  ChatMessage toChatMessage({
    required String currentUserId,
    int? seq,
  }) {
    final resolvedSeq = seq ?? _stableSeqFromClientMsgId(clientMsgId);
    final PacketType packetType;
    final Uint8List payloadBytes;

    if (messageType == GroupMessageType.audio) {
      packetType = PacketType.voiceFragment;
      payloadBytes = VoiceNoteData(
        durationSeconds: audioDurationSec ?? 12,
        peaks: VoiceNoteData.defaultPeaks,
        localAudioPath: localAudioPath,
        audioUrl: audioUrl,
        clientMsgId: clientMsgId,
        syncStatus: syncStatus.dbValue,
      ).toBytes();
    } else {
      packetType = PacketType.text;
      payloadBytes = Uint8List.fromList(utf8.encode(content ?? ''));
    }

    return ChatMessage(
      authorId: senderId,
      seq: resolvedSeq,
      groupId: groupId,
      type: packetType,
      sentAtUtc: clientCreatedAtUtc,
      receivedAtUtc: createdAtUtc ?? clientCreatedAtUtc,
      payload: payloadBytes,
      isOutgoing: senderId == currentUserId,
    );
  }

  static int _stableSeqFromClientMsgId(String uuid) {
    final clean = uuid.replaceAll('-', '');
    if (clean.length >= 8) {
      return (int.tryParse(clean.substring(0, 8), radix: 16) ?? 1) & 0x7fffffff;
    }
    return uuid.hashCode & 0x7fffffff;
  }
}

/// Ringkasan tampilan satu grup pada halaman daftar grup.
class GroupCardData {
  const GroupCardData({
    required this.remote,
    required this.memberCount,
    this.unreadCount = 0,
    this.readyCount = 0,
    this.hasActiveHikeInvite = false,
    this.locationShared = false,
    this.pendingSync = false,
    this.scheduledDate,
    this.lastMessageSnippet,
    this.lastMessageAtUtc,
    this.hasUnread = false,
  });

  final RemoteGroup remote;
  final int memberCount;
  final int unreadCount;
  final int readyCount;
  final bool hasActiveHikeInvite;
  final bool locationShared;
  final bool pendingSync;
  final DateTime? scheduledDate;
  final String? lastMessageSnippet;
  final DateTime? lastMessageAtUtc;
  final bool hasUnread;

  Group get group => remote.group;

  GroupCardData copyWith({
    RemoteGroup? remote,
    int? memberCount,
    int? unreadCount,
    int? readyCount,
    bool? hasActiveHikeInvite,
    bool? locationShared,
    bool? pendingSync,
    DateTime? scheduledDate,
    String? lastMessageSnippet,
    DateTime? lastMessageAtUtc,
    bool? hasUnread,
  }) {
    return GroupCardData(
      remote: remote ?? this.remote,
      memberCount: memberCount ?? this.memberCount,
      unreadCount: unreadCount ?? this.unreadCount,
      readyCount: readyCount ?? this.readyCount,
      hasActiveHikeInvite: hasActiveHikeInvite ?? this.hasActiveHikeInvite,
      locationShared: locationShared ?? this.locationShared,
      pendingSync: pendingSync ?? this.pendingSync,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      lastMessageSnippet: lastMessageSnippet ?? this.lastMessageSnippet,
      lastMessageAtUtc: lastMessageAtUtc ?? this.lastMessageAtUtc,
      hasUnread: hasUnread ?? this.hasUnread,
    );
  }
}

/// Posisi terakhir anggota rombongan untuk layar Lokasi Terakhir.
/// Selaras dengan tabel Supabase `public.member_locations`.
class MemberLastLocation {
  const MemberLastLocation({
    required this.userId,
    required this.displayName,
    required this.initial,
    required this.hasSignal,
    required this.updatedAtUtc,
    this.groupId,
    this.accuracyM,
    this.lat,
    this.lon,
    this.altitudeMdpl,
    this.batteryPercent,
    this.sourceTransport = ChatTransportOrigin.online,
    this.syncStatus = ChatSyncStatus.pending,
    this.recordedAtUtc,
    this.mapX = 0.5,
    this.mapY = 0.5,
  });

  final String userId;
  final String displayName;
  final String initial;
  final bool hasSignal;
  final DateTime updatedAtUtc;
  final String? groupId;
  final int? accuracyM;
  final double? lat;
  final double? lon;
  final int? altitudeMdpl;
  final int? batteryPercent;
  final ChatTransportOrigin sourceTransport;
  final ChatSyncStatus syncStatus;
  final DateTime? recordedAtUtc;

  /// Koordinat relatif pada kanvas topografi (0..1) bila belum memetakan proyeksi peta penuh.
  final double mapX;
  final double mapY;

  DateTime get effectiveRecordedAtUtc => recordedAtUtc ?? updatedAtUtc;

  MemberLastLocation copyWith({
    String? userId,
    String? displayName,
    String? initial,
    bool? hasSignal,
    DateTime? updatedAtUtc,
    String? groupId,
    int? accuracyM,
    double? lat,
    double? lon,
    int? altitudeMdpl,
    int? batteryPercent,
    ChatTransportOrigin? sourceTransport,
    ChatSyncStatus? syncStatus,
    DateTime? recordedAtUtc,
    double? mapX,
    double? mapY,
  }) {
    return MemberLastLocation(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      initial: initial ?? this.initial,
      hasSignal: hasSignal ?? this.hasSignal,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      groupId: groupId ?? this.groupId,
      accuracyM: accuracyM ?? this.accuracyM,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      altitudeMdpl: altitudeMdpl ?? this.altitudeMdpl,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      sourceTransport: sourceTransport ?? this.sourceTransport,
      syncStatus: syncStatus ?? this.syncStatus,
      recordedAtUtc: recordedAtUtc ?? this.recordedAtUtc,
      mapX: mapX ?? this.mapX,
      mapY: mapY ?? this.mapY,
    );
  }

  Map<String, dynamic> toLocalSqliteMap({required String groupId}) {
    return <String, dynamic>{
      'group_id': groupId,
      'user_id': userId,
      'display_name': displayName,
      'latitude': lat ?? 0.0,
      'longitude': lon ?? 0.0,
      'altitude_mdpl': altitudeMdpl,
      'battery_percent': batteryPercent,
      'accuracy_m': accuracyM,
      'source_transport': sourceTransport.dbValue,
      'sync_status': syncStatus.dbValue,
      'recorded_at': effectiveRecordedAtUtc.toUtc().millisecondsSinceEpoch,
      'updated_at': updatedAtUtc.toUtc().millisecondsSinceEpoch,
    };
  }

  static MemberLastLocation fromLocalSqliteMap(
    Map<String, Object?> map, {
    required String currentUserId,
    int index = 0,
  }) {
    final userId = map['user_id'] as String;
    final rawName = (map['display_name'] as String?)?.trim() ?? 'Anggota';
    final displayName = userId == currentUserId ? 'Kamu' : rawName;
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    final recordedMs = (map['recorded_at'] as num?)?.toInt() ??
        DateTime.now().toUtc().millisecondsSinceEpoch;
    final updatedMs = (map['updated_at'] as num?)?.toInt() ?? recordedMs;
    const spots = <List<double>>[
      <double>[0.48, 0.56],
      <double>[0.38, 0.54],
      <double>[0.56, 0.44],
      <double>[0.64, 0.36],
    ];
    final spot = spots[index % spots.length];

    return MemberLastLocation(
      groupId: map['group_id'] as String?,
      userId: userId,
      displayName: displayName,
      initial: initial,
      hasSignal: true,
      accuracyM: (map['accuracy_m'] as num?)?.toInt(),
      lat: (map['latitude'] as num?)?.toDouble(),
      lon: (map['longitude'] as num?)?.toDouble(),
      altitudeMdpl: (map['altitude_mdpl'] as num?)?.toInt(),
      batteryPercent: (map['battery_percent'] as num?)?.toInt(),
      sourceTransport:
          ChatTransportOrigin.fromDb(map['source_transport'] as String?),
      syncStatus: ChatSyncStatus.fromDb(map['sync_status'] as String?),
      recordedAtUtc: DateTime.fromMillisecondsSinceEpoch(recordedMs, isUtc: true),
      updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(updatedMs, isUtc: true),
      mapX: spot[0],
      mapY: spot[1],
    );
  }

  Map<String, dynamic> toSupabaseUpsertMap({required String groupId}) {
    return <String, dynamic>{
      'group_id': groupId,
      'user_id': userId,
      'display_name': displayName,
      'latitude': lat ?? 0.0,
      'longitude': lon ?? 0.0,
      'altitude_mdpl': altitudeMdpl,
      'battery_percent': batteryPercent,
      'source_transport': sourceTransport.dbValue,
      'recorded_at': effectiveRecordedAtUtc.toUtc().toIso8601String(),
    };
  }

  static MemberLastLocation fromSupabaseMap(
    Map<String, dynamic> map, {
    required String currentUserId,
    int index = 0,
  }) {
    final userId = map['user_id'] as String;
    final rawName = (map['display_name'] as String?)?.trim() ?? 'Anggota';
    final displayName = userId == currentUserId ? 'Kamu' : rawName;
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    final recordedRaw = map['recorded_at'] as String?;
    final updatedRaw = map['updated_at'] as String?;
    final recordedAt = recordedRaw != null
        ? DateTime.parse(recordedRaw).toUtc()
        : DateTime.now().toUtc();
    final updatedAt = updatedRaw != null
        ? DateTime.parse(updatedRaw).toUtc()
        : recordedAt;

    const spots = <List<double>>[
      <double>[0.48, 0.56],
      <double>[0.38, 0.54],
      <double>[0.56, 0.44],
      <double>[0.64, 0.36],
    ];
    final spot = spots[index % spots.length];

    return MemberLastLocation(
      groupId: map['group_id'] as String?,
      userId: userId,
      displayName: displayName,
      initial: initial,
      hasSignal: true,
      lat: (map['latitude'] as num?)?.toDouble(),
      lon: (map['longitude'] as num?)?.toDouble(),
      altitudeMdpl: (map['altitude_mdpl'] as num?)?.toInt(),
      batteryPercent: (map['battery_percent'] as num?)?.toInt(),
      sourceTransport:
          ChatTransportOrigin.fromDb(map['source_transport'] as String?),
      syncStatus: ChatSyncStatus.sent,
      recordedAtUtc: recordedAt,
      updatedAtUtc: updatedAt,
      mapX: spot[0],
      mapY: spot[1],
    );
  }

  String relativeTimeLabel(DateTime nowUtc) {
    final ref = effectiveRecordedAtUtc;
    final diff = nowUtc.difference(ref);
    final mins = diff.inMinutes < 0 ? 0 : diff.inMinutes;
    if (!hasSignal) {
      if (mins < 60) return 'Terakhir $mins menit lalu';
      final hours = diff.inHours;
      return 'Terakhir $hours jam lalu';
    }
    if (mins <= 0) return 'Baru saja';
    if (mins < 60) return '$mins menit lalu';
    return '${diff.inHours} jam lalu';
  }
}

/// Payload pesan suara (*voice note*) yang disimpan di `ChatMessage.payload`.
class VoiceNoteData {
  const VoiceNoteData({
    required this.durationSeconds,
    required this.peaks,
    this.localAudioPath,
    this.audioUrl,
    this.clientMsgId,
    this.syncStatus,
  });

  final int durationSeconds;
  final List<double> peaks;
  final String? localAudioPath;
  final String? audioUrl;
  final String? clientMsgId;
  final String? syncStatus;

  static const List<double> defaultPeaks = <double>[
    0.35, 0.72, 0.48, 0.90, 0.62, 0.40, 0.85, 0.95,
    0.55, 0.78, 0.42, 0.68, 0.88, 0.50, 0.35, 0.60,
  ];

  Uint8List toBytes() {
    final jsonMap = <String, dynamic>{
      'kind': 'voice_note',
      'durationSec': durationSeconds,
      'peaks': peaks,
      if (localAudioPath != null) 'localAudioPath': localAudioPath,
      if (audioUrl != null) 'audioUrl': audioUrl,
      if (clientMsgId != null) 'clientMsgId': clientMsgId,
      if (syncStatus != null) 'syncStatus': syncStatus,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(jsonMap)));
  }

  static VoiceNoteData fromBytes(Uint8List bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic> && decoded['kind'] == 'voice_note') {
        final duration = (decoded['durationSec'] as num?)?.toInt() ?? 12;
        final rawPeaks = decoded['peaks'];
        final peaks = rawPeaks is List
            ? rawPeaks
                .whereType<num>()
                .map((n) => n.toDouble().clamp(0.15, 1.0))
                .toList(growable: false)
            : defaultPeaks;
        return VoiceNoteData(
          durationSeconds: duration.clamp(1, 300),
          peaks: peaks.isEmpty ? defaultPeaks : peaks,
          localAudioPath: decoded['localAudioPath'] as String?,
          audioUrl: decoded['audioUrl'] as String?,
          clientMsgId: decoded['clientMsgId'] as String?,
          syncStatus: decoded['syncStatus'] as String?,
        );
      }
    } catch (_) {
      // Abaikan error dekode untuk payload lama.
    }
    return const VoiceNoteData(durationSeconds: 12, peaks: defaultPeaks);
  }

  String get formattedDuration {
    final mins = durationSeconds ~/ 60;
    final secs = durationSeconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
}
