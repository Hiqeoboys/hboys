import 'dart:math' as math;

import 'package:mesh_protocol/mesh_protocol.dart';

import '../database/daos/outbox_dao.dart';
import '../transport/transport.dart';
import '../transport/transport_manager.dart';

class BackoffPolicy {
  const BackoffPolicy({
    this.base = const Duration(seconds: 5),
    this.factor = 2.0,
    this.max = const Duration(minutes: 5),
  });

  /// SOS dicoba lebih sering dan tidak pernah menunggu lama.
  static const BackoffPolicy sos = BackoffPolicy(
    base: Duration(seconds: 2),
    factor: 1.5,
    max: Duration(seconds: 30),
  );

  final Duration base;
  final double factor;
  final Duration max;

  Duration delayFor(int attempts) {
    final ms = base.inMilliseconds * math.pow(factor, attempts);
    final capped = math.min(ms, max.inMilliseconds.toDouble());
    return Duration(milliseconds: capped.round());
  }
}

/// Antrean kirim berprioritas dengan backoff, disimpan di tabel `outbox`
/// sehingga tetap ada setelah aplikasi ditutup. Paket disimpan sebagai byte
/// hasil serialisasi; fragmentasi tetap dilakukan di tingkat transport.
class OutboxService {
  OutboxService({
    required this.dao,
    required this.manager,
    this.normalBackoff = const BackoffPolicy(),
    this.sosBackoff = BackoffPolicy.sos,
  });

  final OutboxDao dao;
  final TransportManager manager;
  final BackoffPolicy normalBackoff;
  final BackoffPolicy sosBackoff;

  Future<int> get pendingCount => dao.pendingCount();

  Future<bool> contains(String messageId) => dao.contains(messageId);

  Future<void> enqueue(Packet packet, DateTime nowUtc) {
    final now = nowUtc.toUtc();
    return dao.enqueue(
      messageId: packet.messageId,
      packet: packet.toBytes(),
      priority: packet.type.priority,
      enqueuedAtUtc: now,
      nextAttemptAtUtc: now,
      repeatUntilAck: packet.type == PacketType.sos,
    );
  }

  /// ACK diterima atau SOS dibatalkan: hentikan pengiriman ulang.
  Future<bool> acknowledge(String messageId) async =>
      await dao.deleteById(messageId) > 0;

  /// Mengirim item yang jatuh tempo, berurutan menurut prioritas lalu usia.
  /// Mengembalikan ID pesan yang berhasil dikirim pada putaran ini.
  Future<List<String>> flush(DateTime nowUtc, {int limit = 20}) async {
    final now = nowUtc.toUtc();
    final due = await dao.due(now, limit: limit);

    final sent = <String>[];
    for (final entry in due) {
      final packet = Packet.fromBytes(entry.packet);
      final result = await manager.send(packet);
      final nextAttempt = entry.attempts + 1;
      final backoff = entry.repeatUntilAck ? sosBackoff : normalBackoff;

      if (result == SendResult.sent) {
        sent.add(entry.messageId);
        if (entry.repeatUntilAck) {
          await dao.recordAttempt(
            entry.messageId,
            now.add(backoff.delayFor(nextAttempt)),
          );
        } else {
          await dao.deleteById(entry.messageId);
        }
      } else {
        await dao.recordAttempt(
          entry.messageId,
          now.add(backoff.delayFor(nextAttempt)),
        );
      }
    }
    return sent;
  }
}
