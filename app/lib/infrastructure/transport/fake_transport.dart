import 'dart:async';

import 'package:mesh_protocol/mesh_protocol.dart';

import 'transport.dart';

/// Transport tiruan di memori untuk menguji sinkronisasi, relay, dan SOS tanpa
/// Bluetooth. Paket di-serialisasi ke byte dan di-parse ulang untuk meniru kawat,
/// sehingga bug codec ikut tertangkap. Pengiriman berjalan sinkron.
class FakeTransport implements Transport {
  FakeTransport(this.nodeId, {this.available = true});

  final String nodeId;
  bool available;

  final StreamController<TransportEvent> _controller =
      StreamController<TransportEvent>.broadcast(sync: true);
  final Map<String, FakeTransport> _links = <String, FakeTransport>{};

  @override
  String get id => 'fake';

  @override
  bool get isAvailable => available;

  @override
  Stream<TransportEvent> get events => _controller.stream;

  Iterable<String> get peerIds => _links.keys;

  void linkTo(FakeTransport other) {
    _links[other.nodeId] = other;
    other._links[nodeId] = this;
    _controller.add(PeerConnected(other.nodeId));
    other._controller.add(PeerConnected(nodeId));
  }

  void unlink(FakeTransport other) {
    _links.remove(other.nodeId);
    other._links.remove(nodeId);
    _controller.add(PeerDisconnected(other.nodeId));
    other._controller.add(PeerDisconnected(nodeId));
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<SendResult> send(
    Packet packet, {
    String? peerId,
    String? exceptPeerId,
  }) async {
    if (!available) return SendResult.unavailable;
    final targets = _links.values
        .where((t) =>
            (peerId == null || t.nodeId == peerId) && t.nodeId != exceptPeerId)
        .toList();
    if (targets.isEmpty) return SendResult.noPeers;
    var delivered = false;
    for (final t in targets) {
      if (!t.available) continue;
      final onWire = Packet.fromBytes(packet.toBytes());
      t._controller.add(PacketReceived(onWire, fromPeerId: nodeId));
      delivered = true;
    }
    return delivered ? SendResult.sent : SendResult.noPeers;
  }
}
