import 'dart:typed_data';

import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:test/test.dart';

Packet sample({
  PacketType type = PacketType.text,
  Uint8List? payload,
  Uint8List? signature,
  int ttl = 6,
}) =>
    Packet(
      type: type,
      ttl: ttl,
      authorId: '0011223344556677',
      groupId: 'aabbccddeeff0011',
      seq: 42,
      sentAtUtc: DateTime.utc(2027, 6, 1, 8, 30, 15),
      payload: payload ?? Uint8List.fromList([1, 2, 3, 4, 5]),
      signature: signature,
    );

void main() {
  group('Packet', () {
    test('round trip tanpa tanda tangan', () {
      final original = sample();
      final bytes = original.toBytes();
      expect(bytes.length, Packet.headerLength + 5);
      final decoded = Packet.fromBytes(bytes);
      expect(decoded.type, PacketType.text);
      expect(decoded.ttl, 6);
      expect(decoded.authorId, '0011223344556677');
      expect(decoded.groupId, 'aabbccddeeff0011');
      expect(decoded.seq, 42);
      expect(decoded.sentAtUtc, DateTime.utc(2027, 6, 1, 8, 30, 15));
      expect(decoded.payload, [1, 2, 3, 4, 5]);
      expect(decoded.signature, isNull);
      expect(decoded.toBytes(), bytes);
    });

    test('round trip dengan tanda tangan', () {
      final sig = Uint8List.fromList(List<int>.generate(64, (i) => i));
      final decoded = Packet.fromBytes(
        sample(type: PacketType.sos, signature: sig).toBytes(),
      );
      expect(decoded.type, PacketType.sos);
      expect(decoded.signature, sig);
    });

    test('menolak paket terlalu pendek', () {
      expect(() => Packet.fromBytes(Uint8List(10)), throwsFormatException);
    });

    test('menolak versi tidak dikenal', () {
      final bytes = sample().toBytes()..[0] = 9;
      expect(() => Packet.fromBytes(bytes), throwsFormatException);
    });

    test('menolak tipe tidak dikenal', () {
      final bytes = sample().toBytes()..[1] = 200;
      expect(() => Packet.fromBytes(bytes), throwsFormatException);
    });

    test('menolak panjang tidak sesuai header', () {
      final bytes = sample().toBytes();
      final truncated = Uint8List.sublistView(bytes, 0, bytes.length - 1);
      expect(() => Packet.fromBytes(truncated), throwsFormatException);
    });

    test('konstruktor menolak ID tidak valid', () {
      expect(
        () => Packet(
          type: PacketType.text,
          ttl: 1,
          authorId: 'XYZ',
          groupId: 'aabbccddeeff0011',
          seq: 1,
          sentAtUtc: DateTime.utc(2027),
          payload: Uint8List(0),
        ),
        throwsArgumentError,
      );
    });

    test('prioritas: SOS lebih tinggi dari lokasi, teks, suara, gambar', () {
      final order = [
        PacketType.sos,
        PacketType.location,
        PacketType.text,
        PacketType.voiceFragment,
        PacketType.thumbnailFragment,
      ];
      for (var i = 0; i < order.length - 1; i++) {
        expect(order[i].priority, lessThan(order[i + 1].priority));
      }
    });
  });
}
