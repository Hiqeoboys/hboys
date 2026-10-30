/// Kategori SOS disimpan sebagai kode, bukan teks, agar ringkas di kawat dan
/// bisa ditampilkan dalam bahasa penerima.
enum SosCategory {
  injury(1),
  lost(2),
  weather(3),
  medical(4),
  other(9);

  const SosCategory(this.code);
  final int code;

  static SosCategory fromCode(int code) {
    for (final c in SosCategory.values) {
      if (c.code == code) return c;
    }
    return SosCategory.other;
  }
}
