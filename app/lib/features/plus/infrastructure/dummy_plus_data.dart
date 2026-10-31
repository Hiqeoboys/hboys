/// Data demo Plus yang HANYA boleh hidup di build debug.
///
/// Angka harga dan kuota di bawah adalah contoh untuk menguji tata letak;
/// bukan harga resmi. Build rilis tidak memakai berkas ini sama sekali dan
/// menampilkan keadaan "konfigurasi belum tersedia" sampai backend nyata
/// mengirim konfigurasi.
const Map<String, Object?> debugPlusRemoteConfigJson = <String, Object?>{
  'graceDays': 10,
  'flags': <String, Object?>{
    'leaderboard': true,
    'peakBadges': true,
  },
  'plans': <Object?>[
    <String, Object?>{
      'id': 'annual',
      'title': 'Tahunan',
      'priceLabel': 'Rp149.000',
      'periodLabel': 'per tahun',
      'note': 'Setara Rp12.417 per bulan.',
      'durationDays': 365,
      'badge': 'PALING PAS',
    },
    <String, Object?>{
      'id': 'student',
      'title': 'Pelajar/mahasiswa',
      'priceLabel': 'Rp79.000',
      'periodLabel': 'per tahun',
      'note': 'Dengan verifikasi status pelajar.',
      'durationDays': 365,
    },
    <String, Object?>{
      'id': 'trip7d',
      'title': 'Tiket 7 hari',
      'priceLabel': 'Rp29.900',
      'periodLabel': 'sekali bayar',
      'note': 'Cocok untuk satu perjalanan.',
      'durationDays': 7,
    },
    <String, Object?>{
      'id': 'founding',
      'title': 'Founding Member',
      'priceLabel': 'Rp349.000',
      'periodLabel': 'sekali bayar',
      'note': 'Berlaku selamanya selama kuota tersedia.',
      'badge': 'Seumur hidup',
      'quotaRemaining': 87,
      'quotaTotal': 500,
    },
  ],
};

/// Durasi paket di atas untuk penerbit token dummy. Null berarti seumur hidup.
const Map<String, int?> debugPlusPlanDurations = <String, int?>{
  'annual': 365,
  'student': 365,
  'trip7d': 7,
  'founding': null,
};
