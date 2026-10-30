import 'package:mesh_protocol/mesh_protocol.dart';

enum SendResult {
  /// Dikirim ke minimal satu tujuan.
  sent,

  /// Transport aktif tetapi tidak ada tetangga/tujuan.
  noPeers,

  /// Transport tidak tersedia (mis. tidak ada internet, Bluetooth mati).
  unavailable,

  failed,
}

sealed class TransportEvent {
  const TransportEvent();
}

class PeerConnected extends TransportEvent {
  const PeerConnected(this.peerId);
  final String peerId;
}

class PeerDisconnected extends TransportEvent {
  const PeerDisconnected(this.peerId);
  final String peerId;
}

class PacketReceived extends TransportEvent {
  const PacketReceived(this.packet, {this.fromPeerId});
  final Packet packet;
  final String? fromPeerId;
}

/// Kontrak seragam untuk semua jalur pengiriman (internet, BLE, hotspot).
/// Lapisan di atasnya tidak boleh tahu transport apa yang dipakai.
abstract interface class Transport {
  /// 'internet' | 'ble' | 'hotspot' | 'fake'
  String get id;

  bool get isAvailable;

  Stream<TransportEvent> get events;

  Future<void> start();
  Future<void> stop();

  /// Kirim ke [peerId] (jika diberikan) atau ke semua tetangga, kecuali
  /// [exceptPeerId] (dipakai relay agar tidak memantulkan ke pengirim).
  Future<SendResult> send(
    Packet packet, {
    String? peerId,
    String? exceptPeerId,
  });
}
