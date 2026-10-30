import 'dart:typed_data';

import 'ids.dart';

/// Rentang nomor urut yang belum dimiliki pihak lain (inklusif).
class SeqRange {
  const SeqRange(this.authorId, this.from, this.to);
  final String authorId;
  final int from;
  final int to;
  int get length => to - from + 1;

  @override
  String toString() => '$authorId[$from..$to]';
}

/// Ringkasan "aku punya pesan penulis X sampai nomor N tanpa celah".
/// Dua perangkat bertukar ringkasan ini, lalu saling mengirim yang kurang.
/// Mekanisme yang sama dipakai di BLE, hotspot, maupun internet.
class SummaryVector {
  SummaryVector();

  final Map<String, int> _have = <String, int>{};
  final Map<String, Set<int>> _pending = <String, Set<int>>{};

  int highest(String authorId) => _have[authorId] ?? 0;

  Iterable<String> get authors => _have.keys;

  bool has(String authorId, int seq) =>
      seq <= highest(authorId) || (_pending[authorId]?.contains(seq) ?? false);

  /// Mencatat bahwa pesan (authorId, seq) sudah dimiliki. seq dimulai dari 1.
  void record(String authorId, int seq) {
    if (seq < 1) throw ArgumentError.value(seq, 'seq', 'harus >= 1');
    final current = highest(authorId);
    if (seq <= current) return;
    if (seq == current + 1) {
      var next = seq;
      final pending = _pending[authorId];
      while (pending != null && pending.remove(next + 1)) {
        next++;
      }
      _have[authorId] = next;
      if (pending != null && pending.isEmpty) _pending.remove(authorId);
    } else {
      (_pending[authorId] ??= <int>{}).add(seq);
    }
  }

  /// Rentang yang kita punya tetapi [remote] belum.
  List<SeqRange> missingFrom(SummaryVector remote) {
    final out = <SeqRange>[];
    final ids = _have.keys.toList()..sort();
    for (final author in ids) {
      final mine = _have[author]!;
      final theirs = remote.highest(author);
      if (mine > theirs) out.add(SeqRange(author, theirs + 1, mine));
    }
    return out;
  }

  static const int _entryLength = idLength + 4;

  Uint8List encode() {
    final entries = _have.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    if (entries.length > 0xFFFF) {
      throw StateError('Terlalu banyak penulis untuk satu ringkasan');
    }
    final out = Uint8List(2 + entries.length * _entryLength);
    final bd = ByteData.sublistView(out);
    bd.setUint16(0, entries.length);
    for (var i = 0; i < entries.length; i++) {
      final offset = 2 + i * _entryLength;
      out.setRange(offset, offset + idLength, hexToBytes(entries[i].key));
      bd.setUint32(offset + idLength, entries[i].value);
    }
    return out;
  }

  factory SummaryVector.decode(Uint8List bytes) {
    if (bytes.length < 2) throw const FormatException('Ringkasan terlalu pendek');
    final bd = ByteData.sublistView(bytes);
    final count = bd.getUint16(0);
    if (bytes.length != 2 + count * _entryLength) {
      throw const FormatException('Panjang ringkasan tidak sesuai');
    }
    final sv = SummaryVector();
    for (var i = 0; i < count; i++) {
      final offset = 2 + i * _entryLength;
      final author = bytesToHex(bytes.sublist(offset, offset + idLength));
      sv._have[author] = bd.getUint32(offset + idLength);
    }
    return sv;
  }
}
