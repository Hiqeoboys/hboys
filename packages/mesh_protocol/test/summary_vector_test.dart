import 'dart:typed_data';

import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:test/test.dart';

const a = '00000000000000aa';
const b = '00000000000000bb';

void main() {
  test('nomor berurutan menaikkan batas tanpa celah', () {
    final sv = SummaryVector()
      ..record(a, 1)
      ..record(a, 2)
      ..record(a, 3);
    expect(sv.highest(a), 3);
  });

  test('celah ditahan sampai terisi', () {
    final sv = SummaryVector()
      ..record(a, 1)
      ..record(a, 3)
      ..record(a, 4);
    expect(sv.highest(a), 1);
    expect(sv.has(a, 3), isTrue);
    sv.record(a, 2);
    expect(sv.highest(a), 4);
  });

  test('missingFrom menghitung rentang yang kurang', () {
    final mine = SummaryVector();
    for (var i = 1; i <= 10; i++) {
      mine.record(a, i);
    }
    mine.record(b, 1);
    final theirs = SummaryVector()
      ..record(a, 1)
      ..record(a, 2)
      ..record(a, 3)
      ..record(b, 1);
    final missing = mine.missingFrom(theirs);
    expect(missing.length, 1);
    expect(missing.single.authorId, a);
    expect(missing.single.from, 4);
    expect(missing.single.to, 10);
    expect(theirs.missingFrom(mine), isEmpty);
  });

  test('encode/decode round trip', () {
    final sv = SummaryVector()
      ..record(a, 1)
      ..record(a, 2)
      ..record(b, 1);
    final decoded = SummaryVector.decode(sv.encode());
    expect(decoded.highest(a), 2);
    expect(decoded.highest(b), 1);
  });

  test('decode menolak data rusak', () {
    expect(() => SummaryVector.decode(Uint8List.fromList([0, 5])), throwsFormatException);
  });
}
