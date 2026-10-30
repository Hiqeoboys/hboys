/// Jenis paket. [priority] makin kecil makin diutamakan saat antrean sempit:
/// SOS > lokasi > teks > suara > gambar.
enum PacketType {
  sos(3, 0),
  ack(4, 0),
  location(2, 1),
  text(1, 2),
  hello(0, 3),
  voiceFragment(5, 4),
  thumbnailFragment(6, 5);

  const PacketType(this.code, this.priority);

  /// Kode 1 byte di kawat. Jangan diubah setelah rilis; tambahkan kode baru.
  final int code;
  final int priority;

  static PacketType fromCode(int code) {
    for (final t in PacketType.values) {
      if (t.code == code) return t;
    }
    throw FormatException('Tipe paket tidak dikenal', code);
  }
}
