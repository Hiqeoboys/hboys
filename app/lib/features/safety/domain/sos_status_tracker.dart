/// Tahap pengiriman SOS, berurutan dari yang paling lemah.
enum SosDeliveryStage {
  savedLocally,
  sentToPeers,
  acknowledgedByMember,
  forwardedToServer,
  deliveredToEmergencyContact,
}

/// Melacak tahap yang BENAR-BENAR tercapai. UI hanya boleh menampilkan klaim
/// yang didukung tahap ini (aturan produk: status SOS harus jujur).
class SosStatusTracker {
  final Set<SosDeliveryStage> _reached = <SosDeliveryStage>{};
  int _peerCount = 0;

  int get peerCount => _peerCount;

  void mark(SosDeliveryStage stage, {int? peers}) {
    _reached.add(stage);
    if (peers != null && peers > _peerCount) _peerCount = peers;
  }

  bool reached(SosDeliveryStage stage) => _reached.contains(stage);

  SosDeliveryStage? get highest {
    SosDeliveryStage? best;
    for (final s in _reached) {
      if (best == null || s.index > best.index) best = s;
    }
    return best;
  }

  /// SOS sudah keluar dari rombongan (server atau kontak darurat).
  bool get leftTheGroup =>
      reached(SosDeliveryStage.forwardedToServer) ||
      reached(SosDeliveryStage.deliveredToEmergencyContact);

  /// Hanya `true` jika kontak darurat benar-benar menerima. Hanya saat inilah
  /// UI boleh menampilkan kalimat "sampai ke kontak darurat".
  bool get mayClaimDeliveredToContact =>
      reached(SosDeliveryStage.deliveredToEmergencyContact);
}
