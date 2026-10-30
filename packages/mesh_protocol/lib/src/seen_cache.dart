import 'dart:collection';

/// Cache kunci yang sudah pernah dilihat (dedup relay), dengan batas kapasitas.
class SeenCache {
  SeenCache({this.capacity = 2048}) : assert(capacity > 0);

  final int capacity;
  final LinkedHashSet<String> _keys = LinkedHashSet<String>();

  int get length => _keys.length;

  bool contains(String key) => _keys.contains(key);

  /// Mengembalikan `true` jika [key] baru (belum pernah terlihat).
  bool markSeen(String key) {
    if (_keys.contains(key)) return false;
    _keys.add(key);
    if (_keys.length > capacity) _keys.remove(_keys.first);
    return true;
  }
}
