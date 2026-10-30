import 'dart:typed_data';

import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:test/test.dart';

Packet pkt({int ttl = 5, int seq = 1}) => Packet(
      type: PacketType.text,
      ttl: ttl,
      authorId: '0011223344556677',
      groupId: 'aabbccddeeff0011',
      seq: seq,
      sentAtUtc: DateTime.utc(2027),
      payload: Uint8List(3),
    );

void main() {
  test('paket baru disebar ulang dengan TTL berkurang', () {
    final d = RelayPolicy().onReceive(pkt(ttl: 5));
    expect(d.isNew, isTrue);
    expect(d.rebroadcast?.ttl, 4);
  });

  test('duplikat diabaikan', () {
    final policy = RelayPolicy();
    expect(policy.onReceive(pkt()).isNew, isTrue);
    final second = policy.onReceive(pkt());
    expect(second.isNew, isFalse);
    expect(second.rebroadcast, isNull);
  });

  test('TTL 1 dikirim ke aplikasi tetapi tidak disebar', () {
    final d = RelayPolicy().onReceive(pkt(ttl: 1));
    expect(d.isNew, isTrue);
    expect(d.rebroadcast, isNull);
  });

  test('TTL berlebihan dibatasi maxTtl', () {
    final d = RelayPolicy(maxTtl: 4).onReceive(pkt(ttl: 200));
    expect(d.rebroadcast?.ttl, 3);
  });

  test('paket buatan sendiri yang kembali diabaikan', () {
    final policy = RelayPolicy();
    final own = pkt();
    policy.markOwn(own);
    expect(policy.onReceive(own).isNew, isFalse);
  });

  test('SeenCache membuang entri tertua saat penuh', () {
    final c = SeenCache(capacity: 2);
    c.markSeen('x');
    c.markSeen('y');
    c.markSeen('z');
    expect(c.contains('x'), isFalse);
    expect(c.contains('z'), isTrue);
  });
}
