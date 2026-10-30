import 'dart:typed_data';

import 'ids.dart';
import 'packet_type.dart';

/// Paket di kawat (big-endian). Tata letak header 32 byte:
///
/// | offset | ukuran | isi                                   |
/// |--------|--------|---------------------------------------|
/// | 0      | 1      | versi                                 |
/// | 1      | 1      | tipe                                  |
/// | 2      | 1      | TTL                                   |
/// | 3      | 1      | flags (bit0 = ada tanda tangan)       |
/// | 4      | 8      | authorId                              |
/// | 12     | 8      | groupId                               |
/// | 20     | 4      | seq (uint32)                          |
/// | 24     | 4      | sentAt (detik sejak epoch, UTC)       |
/// | 28     | 1      | fragIndex                             |
/// | 29     | 1      | fragTotal                             |
/// | 30     | 2      | panjang payload                       |
/// | 32     | N      | payload (terenkripsi)                 |
/// | 32+N   | 64     | tanda tangan (opsional, jika flag)    |
class Packet {
  Packet({
    this.version = currentVersion,
    required this.type,
    required this.ttl,
    required this.authorId,
    required this.groupId,
    required this.seq,
    required this.sentAtUtc,
    this.fragIndex = 0,
    this.fragTotal = 1,
    required this.payload,
    this.signature,
  }) {
    if (!isValidId(authorId)) {
      throw ArgumentError.value(authorId, 'authorId', 'harus 16 hex huruf kecil');
    }
    if (!isValidId(groupId)) {
      throw ArgumentError.value(groupId, 'groupId', 'harus 16 hex huruf kecil');
    }
    if (ttl < 0 || ttl > 255) {
      throw ArgumentError.value(ttl, 'ttl', 'harus 0..255');
    }
    if (seq < 0 || seq > 0xFFFFFFFF) {
      throw ArgumentError.value(seq, 'seq', 'harus uint32');
    }
    if (fragTotal < 1 || fragTotal > 255 || fragIndex < 0 || fragIndex >= fragTotal) {
      throw ArgumentError('fragIndex/fragTotal tidak valid: $fragIndex/$fragTotal');
    }
    if (payload.length > maxPayloadLength) {
      throw ArgumentError.value(payload.length, 'payload', 'terlalu besar');
    }
    final sig = signature;
    if (sig != null && sig.length != signatureLength) {
      throw ArgumentError.value(sig.length, 'signature', 'harus $signatureLength byte');
    }
  }

  static const int currentVersion = 1;
  static const int headerLength = 32;
  static const int signatureLength = 64;
  static const int maxPayloadLength = 0xFFFF;
  static const int _flagSigned = 0x01;

  final int version;
  final PacketType type;
  final int ttl;
  final String authorId;
  final String groupId;
  final int seq;
  final DateTime sentAtUtc;
  final int fragIndex;
  final int fragTotal;
  final Uint8List payload;
  final Uint8List? signature;

  /// Identitas pesan utuh (semua fragmen berbagi ID yang sama).
  String get messageId => '$authorId:$seq';

  /// Identitas satu fragmen (untuk deduplikasi relay).
  String get fragmentKey => '$authorId:$seq:$fragIndex';

  Packet copyWith({
    PacketType? type,
    int? ttl,
    int? fragIndex,
    int? fragTotal,
    Uint8List? payload,
    Uint8List? signature,
    bool clearSignature = false,
  }) {
    return Packet(
      version: version,
      type: type ?? this.type,
      ttl: ttl ?? this.ttl,
      authorId: authorId,
      groupId: groupId,
      seq: seq,
      sentAtUtc: sentAtUtc,
      fragIndex: fragIndex ?? this.fragIndex,
      fragTotal: fragTotal ?? this.fragTotal,
      payload: payload ?? this.payload,
      signature: clearSignature ? null : (signature ?? this.signature),
    );
  }

  Uint8List toBytes() {
    final sig = signature;
    final total = headerLength + payload.length + (sig != null ? signatureLength : 0);
    final out = Uint8List(total);
    final bd = ByteData.sublistView(out);
    bd.setUint8(0, version);
    bd.setUint8(1, type.code);
    bd.setUint8(2, ttl);
    bd.setUint8(3, sig != null ? _flagSigned : 0);
    out.setRange(4, 12, hexToBytes(authorId));
    out.setRange(12, 20, hexToBytes(groupId));
    bd.setUint32(20, seq);
    bd.setUint32(24, sentAtUtc.millisecondsSinceEpoch ~/ 1000);
    bd.setUint8(28, fragIndex);
    bd.setUint8(29, fragTotal);
    bd.setUint16(30, payload.length);
    out.setRange(headerLength, headerLength + payload.length, payload);
    if (sig != null) {
      out.setRange(headerLength + payload.length, total, sig);
    }
    return out;
  }

  /// Mem-parse paket. Selalu melempar [FormatException] untuk masukan rusak,
  /// karena data dari radio tidak boleh dipercaya.
  factory Packet.fromBytes(Uint8List bytes) {
    if (bytes.length < headerLength) {
      throw FormatException('Paket terlalu pendek (${bytes.length} byte)');
    }
    final bd = ByteData.sublistView(bytes);
    final version = bd.getUint8(0);
    if (version != currentVersion) {
      throw FormatException('Versi paket tidak didukung', version);
    }
    final type = PacketType.fromCode(bd.getUint8(1));
    final ttl = bd.getUint8(2);
    final signed = bd.getUint8(3) & _flagSigned != 0;
    final payloadLength = bd.getUint16(30);
    final expected = headerLength + payloadLength + (signed ? signatureLength : 0);
    if (bytes.length != expected) {
      throw FormatException('Panjang paket ${bytes.length} != $expected');
    }
    try {
      return Packet(
        version: version,
        type: type,
        ttl: ttl,
        authorId: bytesToHex(bytes.sublist(4, 12)),
        groupId: bytesToHex(bytes.sublist(12, 20)),
        seq: bd.getUint32(20),
        sentAtUtc: DateTime.fromMillisecondsSinceEpoch(bd.getUint32(24) * 1000, isUtc: true),
        fragIndex: bd.getUint8(28),
        fragTotal: bd.getUint8(29),
        payload: Uint8List.fromList(
          bytes.sublist(headerLength, headerLength + payloadLength),
        ),
        signature: signed
            ? Uint8List.fromList(bytes.sublist(headerLength + payloadLength, expected))
            : null,
      );
    } on ArgumentError catch (e) {
      throw FormatException('Paket tidak valid: ${e.message}');
    }
  }
}
