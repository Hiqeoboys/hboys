import 'dart:typed_data';

import 'packet.dart';

/// Memecah payload besar menjadi fragmen sesuai MTU, dan merakitnya kembali.
///
/// Batasan: paket bertanda tangan tidak boleh difragmentasi (SOS sengaja
/// dibuat kecil). Jika perlu, tanda tangan bisa dipindah ke tingkat pesan
/// utuh pada versi protokol berikutnya.
class Fragmenter {
  const Fragmenter._();

  static List<Packet> split(Packet whole, {required int maxPayload}) {
    if (maxPayload < 1) throw ArgumentError.value(maxPayload, 'maxPayload');
    if (whole.fragTotal != 1) {
      throw ArgumentError('Paket sudah berupa fragmen');
    }
    if (whole.payload.length <= maxPayload) return [whole];
    if (whole.signature != null) {
      throw ArgumentError('Paket bertanda tangan tidak boleh difragmentasi');
    }
    final count = (whole.payload.length + maxPayload - 1) ~/ maxPayload;
    if (count > 255) {
      throw ArgumentError('Payload terlalu besar: $count fragmen (maks 255)');
    }
    return List<Packet>.generate(count, (i) {
      final start = i * maxPayload;
      final end = start + maxPayload > whole.payload.length
          ? whole.payload.length
          : start + maxPayload;
      return whole.copyWith(
        fragIndex: i,
        fragTotal: count,
        payload: Uint8List.fromList(whole.payload.sublist(start, end)),
      );
    });
  }
}

class _Partial {
  _Partial(this.total) : parts = List<Uint8List?>.filled(total, null);
  final int total;
  final List<Uint8List?> parts;
  int received = 0;
}

/// Perakit fragmen. Fragmen boleh datang tidak berurutan dan boleh ganda.
class Reassembler {
  Reassembler({this.maxPartials = 64});

  /// Batas pesan setengah-jadi agar memori tidak membengkak.
  final int maxPartials;
  final Map<String, _Partial> _partials = <String, _Partial>{};

  int get pendingCount => _partials.length;

  /// Mengembalikan paket utuh jika sudah lengkap, selain itu `null`.
  Packet? add(Packet fragment) {
    if (fragment.fragTotal == 1) return fragment;

    final key = fragment.messageId;
    var partial = _partials[key];
    if (partial != null && partial.total != fragment.fragTotal) {
      _partials.remove(key); // inkonsisten: mulai ulang
      partial = null;
    }
    if (partial == null) {
      if (_partials.length >= maxPartials) {
        _partials.remove(_partials.keys.first);
      }
      partial = _Partial(fragment.fragTotal);
      _partials[key] = partial;
    }
    if (partial.parts[fragment.fragIndex] == null) {
      partial.parts[fragment.fragIndex] = fragment.payload;
      partial.received++;
    }
    if (partial.received < partial.total) return null;

    _partials.remove(key);
    final builder = BytesBuilder(copy: false);
    for (final p in partial.parts) {
      builder.add(p!);
    }
    return fragment.copyWith(
      fragIndex: 0,
      fragTotal: 1,
      payload: builder.takeBytes(),
    );
  }
}
