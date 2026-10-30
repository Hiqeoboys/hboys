import 'dart:async';

import 'package:mesh_protocol/mesh_protocol.dart';

import '../transport/transport.dart';

/// Menghubungkan satu [Transport] dengan [RelayPolicy]: paket baru diserahkan
/// ke aplikasi ([onDeliver]) lalu disebar ulang ke tetangga lain.
class RelayService {
  RelayService({
    required this.transport,
    required this.selfId,
    required this.onDeliver,
    RelayPolicy? policy,
  }) : policy = policy ?? RelayPolicy() {
    _sub = transport.events.listen(_onEvent);
  }

  final Transport transport;

  /// authorId milik perangkat ini (paket sendiri tidak diserahkan lagi).
  final String selfId;
  final void Function(Packet packet) onDeliver;
  final RelayPolicy policy;
  late final StreamSubscription<TransportEvent> _sub;

  void _onEvent(TransportEvent event) {
    if (event is! PacketReceived) return;
    final packet = event.packet;
    if (packet.authorId == selfId) return;

    final decision = policy.onReceive(packet);
    if (!decision.isNew) return;
    onDeliver(packet);

    final next = decision.rebroadcast;
    if (next != null) {
      unawaited(transport.send(next, exceptPeerId: event.fromPeerId));
    }
  }

  /// Kirim paket buatan sendiri (ditandai agar tidak diproses saat kembali).
  Future<SendResult> send(Packet packet) {
    policy.markOwn(packet);
    return transport.send(packet);
  }

  Future<void> dispose() => _sub.cancel();
}
