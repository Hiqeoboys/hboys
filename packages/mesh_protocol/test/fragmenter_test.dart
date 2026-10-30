import 'dart:typed_data';

import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:test/test.dart';

Packet big(int length, {Uint8List? signature}) => Packet(
      type: PacketType.voiceFragment,
      ttl: 5,
      authorId: '0011223344556677',
      groupId: 'aabbccddeeff0011',
      seq: 7,
      sentAtUtc: DateTime.utc(2027, 6, 1),
      payload: Uint8List.fromList(List<int>.generate(length, (i) => i % 251)),
      signature: signature,
    );

void main() {
  test('payload kecil tidak dipecah', () {
    final p = big(20);
    expect(Fragmenter.split(p, maxPayload: 30), [p]);
  });

  test('memecah dan merakit ulang walau urutan acak dan ada duplikat', () {
    final whole = big(100);
    final parts = Fragmenter.split(whole, maxPayload: 30);
    expect(parts.length, 4);
    expect(parts.every((p) => p.fragTotal == 4), isTrue);

    final r = Reassembler();
    final order = [2, 0, 2, 3, 1];
    Packet? result;
    for (final i in order) {
      result = r.add(parts[i]) ?? result;
    }
    expect(result, isNotNull);
    expect(result!.payload, whole.payload);
    expect(result.fragTotal, 1);
    expect(r.pendingCount, 0);
  });

  test('paket bertanda tangan tidak boleh difragmentasi', () {
    final sig = Uint8List(64);
    expect(
      () => Fragmenter.split(big(100, signature: sig), maxPayload: 30),
      throwsArgumentError,
    );
  });

  test('batas pesan setengah-jadi menjaga memori', () {
    final r = Reassembler(maxPartials: 2);
    for (var seq = 1; seq <= 5; seq++) {
      final whole = Packet(
        type: PacketType.voiceFragment,
        ttl: 5,
        authorId: '0011223344556677',
        groupId: 'aabbccddeeff0011',
        seq: seq,
        sentAtUtc: DateTime.utc(2027),
        payload: Uint8List(60),
      );
      r.add(Fragmenter.split(whole, maxPayload: 30).first);
    }
    expect(r.pendingCount, 2);
  });
}
