import 'packet.dart';
import 'seen_cache.dart';

class RelayDecision {
  const RelayDecision({required this.isNew, this.rebroadcast});

  /// Paket belum pernah terlihat: layak diserahkan ke aplikasi.
  final bool isNew;

  /// Paket yang harus disebar ulang (TTL sudah dikurangi), atau `null`.
  final Packet? rebroadcast;
}

/// Kebijakan relay: dedup, batas TTL, dan pengurangan TTL.
/// TTL paket dibatasi [maxTtl] agar paket berniat jahat tidak menyebar tanpa batas.
class RelayPolicy {
  RelayPolicy({this.maxTtl = 8, SeenCache? seen}) : seen = seen ?? SeenCache();

  final int maxTtl;
  final SeenCache seen;

  /// Tandai paket buatan sendiri agar tidak diproses lagi saat kembali.
  void markOwn(Packet packet) => seen.markSeen(packet.fragmentKey);

  RelayDecision onReceive(Packet packet) {
    if (!seen.markSeen(packet.fragmentKey)) {
      return const RelayDecision(isNew: false);
    }
    final effective = packet.ttl < maxTtl ? packet.ttl : maxTtl;
    final nextTtl = effective - 1;
    if (nextTtl < 1) return const RelayDecision(isNew: true);
    return RelayDecision(isNew: true, rebroadcast: packet.copyWith(ttl: nextTtl));
  }
}
