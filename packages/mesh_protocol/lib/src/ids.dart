import 'dart:typed_data';

/// Panjang ID penulis/grup di kawat: 8 byte (16 karakter hex huruf kecil).
const int idLength = 8;

final RegExp _hexId = RegExp(r'^[0-9a-f]{16}$');

bool isValidId(String id) => _hexId.hasMatch(id);

Uint8List hexToBytes(String hex) {
  if (hex.length.isOdd) {
    throw FormatException('Panjang hex harus genap', hex);
  }
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final byte = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    if (byte == null) {
      throw FormatException('Karakter hex tidak valid', hex);
    }
    out[i] = byte;
  }
  return out;
}

String bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
