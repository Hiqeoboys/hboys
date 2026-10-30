import 'package:mesh_protocol/mesh_protocol.dart';

import 'transport.dart';

/// Memilih transport untuk mengirim paket.
/// - SOS: dikirim lewat SEMUA transport yang tersedia (peluang terbesar sampai).
/// - Lainnya: transport tersedia pertama yang berhasil, sesuai urutan preferensi.
class TransportManager {
  TransportManager(this.transports);

  /// Urutan = preferensi (mis. internet lebih dulu, lalu BLE, lalu hotspot).
  final List<Transport> transports;

  Future<void> startAll() async {
    for (final t in transports) {
      await t.start();
    }
  }

  Future<void> stopAll() async {
    for (final t in transports) {
      await t.stop();
    }
  }

  Future<SendResult> send(Packet packet) async {
    final available = transports.where((t) => t.isAvailable).toList();
    if (available.isEmpty) return SendResult.unavailable;

    var last = SendResult.noPeers;
    var anySent = false;
    for (final t in available) {
      final result = await t.send(packet);
      if (result == SendResult.sent) {
        anySent = true;
        if (packet.type != PacketType.sos) return SendResult.sent;
      } else {
        last = result;
      }
    }
    return anySent ? SendResult.sent : last;
  }
}
