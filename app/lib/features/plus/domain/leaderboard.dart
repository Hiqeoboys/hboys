import 'plus_format.dart';

/// Papan peringkat yang sedang dilihat. Papan nasional bisa dilihat semua
/// pengguna, tetapi hanya pengguna Plus yang ikut bersaing; papan grup gratis
/// untuk semua anggota.
enum LeaderboardScope {
  national('Nasional'),
  group('Grup');

  const LeaderboardScope(this.label);

  final String label;
}

/// Kategori yang dinilai. Tidak ada kategori kecepatan: keselamatan di atas
/// persaingan, jadi yang dihitung hanya jumlah gunung dan jarak.
enum LeaderboardMetric {
  totalMountains('Total gunung'),
  totalDistance('Total jarak');

  const LeaderboardMetric(this.label);

  final String label;
}

enum LeaderboardPeriod {
  weekly('Mingguan'),
  monthly('Bulanan'),
  yearly('Tahunan');

  const LeaderboardPeriod(this.label);

  final String label;
}

/// Label angka sesuai kategori, mis. "9 gunung" atau "128,4 km".
String leaderboardValueLabel(LeaderboardMetric metric, int value) {
  switch (metric) {
    case LeaderboardMetric.totalMountains:
      return '$value gunung';
    case LeaderboardMetric.totalDistance:
      return formatKm(value.toDouble());
  }
}

/// Satu baris papan. [value] memakai satuan kategori: jumlah gunung atau meter.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.displayName,
    required this.value,
    this.isCurrentUser = false,
  });

  final int rank;
  final String displayName;
  final int value;
  final bool isCurrentUser;

  String get initial {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, 1).toUpperCase();
  }
}

/// Hasil satu permintaan papan. Peringkat berasal dari server pada tahap
/// nyata; pada tahap ini implementasi dummy mengisi angka demo di build debug.
class LeaderboardBoard {
  const LeaderboardBoard({
    required this.scope,
    required this.metric,
    required this.period,
    required this.entries,
    this.groupName,
    this.groupMemberCount = 0,
    this.currentUser,
  });

  final LeaderboardScope scope;
  final LeaderboardMetric metric;
  final LeaderboardPeriod period;

  /// Nasional: 10 besar. Grup: seluruh anggota.
  final List<LeaderboardEntry> entries;

  final String? groupName;
  final int groupMemberCount;

  /// Baris pengguna sendiri. Di papan nasional bisa berada di luar 10 besar.
  final LeaderboardEntry? currentUser;

  int get topValue => entries.isEmpty ? 0 : entries.first.value;

  /// Bagian batang kemajuan 0..1 terhadap pemuncak papan.
  double progressFor(LeaderboardEntry entry) {
    final top = topValue;
    if (top <= 0) return 0;
    return (entry.value / top).clamp(0.0, 1.0);
  }
}

class LeaderboardUnavailable implements Exception {
  const LeaderboardUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Antarmuka papan peringkat. Server sungguhan yang menghitung ulang metrik
/// dari jejak mentah belum ada; implementasi dummy hanya untuk build debug.
abstract interface class LeaderboardRepository {
  Future<LeaderboardBoard> load({
    required LeaderboardScope scope,
    required LeaderboardMetric metric,
    required LeaderboardPeriod period,
  });

  /// Benar bila server peninjauan menerima laporan/blokir.
  Future<bool> report(String displayName);

  Future<bool> block(String displayName);
}

/// Pilihan tampil di papan nasional. Di luar `true`, nama pengguna tidak
/// ditampilkan meskipun ia sudah menyetujui ikut.
abstract interface class LeaderboardConsentStore {
  Future<bool?> readVisible();
  Future<void> writeVisible(bool visible);
}
