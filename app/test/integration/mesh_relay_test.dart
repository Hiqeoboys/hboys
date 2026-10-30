import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:nama_app/infrastructure/database/app_database.dart';
import 'package:nama_app/infrastructure/database/daos/outbox_dao.dart';
import 'package:nama_app/infrastructure/database/database_connection.dart';
import 'package:nama_app/infrastructure/sync/outbox_service.dart';
import 'package:nama_app/infrastructure/sync/relay_service.dart';
import 'package:nama_app/infrastructure/transport/fake_transport.dart';
import 'package:nama_app/infrastructure/transport/transport.dart';
import 'package:nama_app/infrastructure/transport/transport_manager.dart';

const idA = 'aaaaaaaaaaaaaaaa';
const idB = 'bbbbbbbbbbbbbbbb';
const idC = 'cccccccccccccccc';
const groupHex = '1111111111111111';

Packet msg({
  PacketType type = PacketType.text,
  int ttl = 3,
  int seq = 1,
  String author = idA,
}) =>
    Packet(
      type: type,
      ttl: ttl,
      authorId: author,
      groupId: groupHex,
      seq: seq,
      sentAtUtc: DateTime.utc(2027, 6, 1),
      payload: Uint8List.fromList([1, 2, 3]),
    );

class Node {
  Node(String id)
      : transport = FakeTransport(id),
        received = [] {
    relay = RelayService(
      transport: transport,
      selfId: id,
      onDeliver: received.add,
    );
  }
  final FakeTransport transport;
  final List<Packet> received;
  late final RelayService relay;
}

void main() {
  test('pesan menyeberang A -> B -> C lewat relay', () {
    final a = Node(idA), b = Node(idB), c = Node(idC);
    a.transport.linkTo(b.transport);
    b.transport.linkTo(c.transport);

    a.relay.send(msg(ttl: 3));

    expect(b.received.length, 1);
    expect(c.received.length, 1);
    expect(a.received, isEmpty, reason: 'pengirim tidak menerima pantulan');
  });

  test('TTL 1 tidak diteruskan', () {
    final a = Node(idA), b = Node(idB), c = Node(idC);
    a.transport.linkTo(b.transport);
    b.transport.linkTo(c.transport);

    a.relay.send(msg(ttl: 1));

    expect(b.received.length, 1);
    expect(c.received, isEmpty);
  });

  test('topologi segitiga: tiap node menerima tepat satu kali', () {
    final a = Node(idA), b = Node(idB), c = Node(idC);
    a.transport.linkTo(b.transport);
    b.transport.linkTo(c.transport);
    c.transport.linkTo(a.transport);

    a.relay.send(msg(ttl: 5));

    expect(b.received.length, 1);
    expect(c.received.length, 1);
    expect(a.received, isEmpty);
  });

  group('OutboxService', () {
    final t0 = DateTime.utc(2027, 6, 1, 8);
    late AppDatabase db;

    setUp(() => db = openInMemoryAppDatabase());
    tearDown(() => db.close());

    OutboxService outboxFor(FakeTransport transport) => OutboxService(
          dao: OutboxDao(db),
          manager: TransportManager([transport]),
        );

    test('SOS dikirim lebih dulu daripada teks', () async {
      final a = FakeTransport(idA);
      final b = FakeTransport(idB);
      a.linkTo(b);
      final got = <PacketType>[];
      b.events.listen((e) {
        if (e is PacketReceived) got.add(e.packet.type);
      });

      final outbox = outboxFor(a);
      await outbox.enqueue(msg(type: PacketType.text, seq: 1), t0);
      await outbox.enqueue(msg(type: PacketType.sos, seq: 2), t0);
      await outbox.flush(t0);

      expect(got, [PacketType.sos, PacketType.text]);
    });

    test('pesan biasa dihapus setelah terkirim, SOS tetap sampai di-ACK', () async {
      final a = FakeTransport(idA);
      final b = FakeTransport(idB);
      a.linkTo(b);
      final outbox = outboxFor(a);
      await outbox.enqueue(msg(type: PacketType.text, seq: 1), t0);
      await outbox.enqueue(msg(type: PacketType.sos, seq: 2), t0);
      await outbox.flush(t0);

      expect(await outbox.contains('$idA:1'), isFalse);
      expect(await outbox.contains('$idA:2'), isTrue);
      expect(await outbox.acknowledge('$idA:2'), isTrue);
      expect(await outbox.pendingCount, 0);
    });

    test('SOS dikirim ulang setelah jeda', () async {
      final a = FakeTransport(idA);
      final b = FakeTransport(idB);
      a.linkTo(b);
      var count = 0;
      b.events.listen((e) {
        if (e is PacketReceived) count++;
      });
      final outbox = outboxFor(a);
      await outbox.enqueue(msg(type: PacketType.sos, seq: 1), t0);

      await outbox.flush(t0);
      await outbox.flush(t0.add(const Duration(seconds: 1))); // belum jatuh tempo
      expect(count, 1);
      await outbox.flush(t0.add(const Duration(minutes: 1)));
      expect(count, 2);
    });

    test('gagal kirim dicoba lagi dengan backoff', () async {
      final a = FakeTransport(idA, available: false);
      final outbox = outboxFor(a);
      await outbox.enqueue(msg(seq: 1), t0);

      expect(await outbox.flush(t0), isEmpty);
      expect(await outbox.contains('$idA:1'), isTrue);

      a.available = true;
      final b = FakeTransport(idB);
      a.linkTo(b);
      expect(await outbox.flush(t0.add(const Duration(seconds: 1))), isEmpty);
      expect(await outbox.flush(t0.add(const Duration(minutes: 1))), ['$idA:1']);
      expect(await outbox.contains('$idA:1'), isFalse);
    });

    test('antrean selamat setelah database ditutup dan dibuka ulang', () async {
      final dir = await Directory.systemTemp.createTemp('nama_outbox_');
      final file = File('${dir.path}/outbox.sqlite');
      final a = FakeTransport(idA);
      final b = FakeTransport(idB);
      a.linkTo(b);
      final received = <Packet>[];
      b.events.listen((e) {
        if (e is PacketReceived) received.add(e.packet);
      });

      var fileDb = openAppDatabase(file);
      try {
        await OutboxService(
          dao: OutboxDao(fileDb),
          manager: TransportManager([a]),
        ).enqueue(msg(type: PacketType.sos, seq: 7), t0);
        await fileDb.close();

        fileDb = openAppDatabase(file);
        final outbox = OutboxService(
          dao: OutboxDao(fileDb),
          manager: TransportManager([a]),
        );
        expect(await outbox.contains('$idA:7'), isTrue);
        expect(await outbox.flush(t0), ['$idA:7']);
        expect(received.single.messageId, '$idA:7');
        expect(received.single.type, PacketType.sos);
        expect(received.single.payload, [1, 2, 3]);
        expect(await outbox.contains('$idA:7'), isTrue);
      } finally {
        await fileDb.close();
        await dir.delete(recursive: true);
      }
    });
  });
}
