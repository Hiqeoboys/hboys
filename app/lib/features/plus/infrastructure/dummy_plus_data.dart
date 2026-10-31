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
      'title': 'Hiqeo Plus Tahunan',
      'priceLabel': 'Rp 249.000',
      'periodLabel': 'per tahun',
      'note': 'Setara Rp 20.750 per bulan.',
      'durationDays': 365,
      'badge': 'Paling hemat',
    },
    <String, Object?>{
      'id': 'student',
      'title': 'Hiqeo Plus Pelajar',
      'priceLabel': 'Rp 149.000',
      'periodLabel': 'per tahun',
      'note': 'Dengan verifikasi status pelajar.',
      'durationDays': 365,
      'badge': 'Pelajar',
    },
    <String, Object?>{
      'id': 'trip7d',
      'title': 'Hiqeo Plus 7 Hari',
      'priceLabel': 'Rp 29.000',
      'periodLabel': 'sekali bayar',
      'note': 'Cocok untuk satu perjalanan.',
      'durationDays': 7,
    },
    <String, Object?>{
      'id': 'founding',
      'title': 'Founding Member',
      'priceLabel': 'Rp 499.000',
      'periodLabel': 'sekali bayar',
      'note': 'Berlaku seumur hidup selama kuota tersedia.',
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
