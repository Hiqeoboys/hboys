import 'dart:typed_data';

import 'package:mesh_protocol/mesh_protocol.dart';

/// Pesan yang tersimpan di perangkat. [payload] adalah byte opaque milik
/// lapisan transport; pesan teks lokal saat ini disimpan sebagai UTF-8 tanpa
/// enkripsi karena belum ada jalur pengiriman terenkripsi. Dekripsi bukan
/// tanggung jawab lapisan database.
class ChatMessage {
  const ChatMessage({
    required this.authorId,
    required this.seq,
    required this.groupId,
    required this.type,
    required this.sentAtUtc,
    required this.receivedAtUtc,
    required this.payload,
    this.signature,
    this.isOutgoing = false,
  });

  final String authorId;
  final int seq;
  final String groupId;
  final PacketType type;
  final DateTime sentAtUtc;
  final DateTime receivedAtUtc;
  final Uint8List payload;
  final Uint8List? signature;
  final bool isOutgoing;

  String get messageId => '$authorId:$seq';
}
