class AndroidBrandGuide {
  const AndroidBrandGuide({
    required this.brand,
    required this.steps,
  });

  final String brand;
  final List<String> steps;
}

/// Panduan awal. Nama menu berubah antar versi OS dan ROM; setiap langkah
/// wajib diverifikasi di perangkat sebelum dipakai sebagai instruksi rilis.
const androidBrandGuides = [
  AndroidBrandGuide(
    brand: 'Xiaomi / Redmi / POCO (MIUI/HyperOS)',
    steps: [
      'Setelan > Aplikasi > Kelola aplikasi > aplikasi ini > Hemat baterai: pilih Tanpa batasan.',
      'Setelan > Aplikasi > Kelola aplikasi > aplikasi ini > Autostart: aktifkan.',
      'Di layar Recents, kunci aplikasi (ikon gembok) agar tidak dibersihkan.',
      'Setelan > Lokasi > Izin lokasi aplikasi: pilih Selalu untuk aplikasi ini.',
    ],
  ),
  AndroidBrandGuide(
    brand: 'Samsung (One UI)',
    steps: [
      'Setelan > Baterai > Batas penggunaan latar belakang: pastikan aplikasi ini tidak dibatasi.',
      'Setelan > Baterai > Aplikasi tidur: hapus aplikasi ini dari daftar, atau masukkan ke Aplikasi yang tidak pernah tidur.',
      'Setelan > Aplikasi > aplikasi ini > Baterai: pilih Tidak dibatasi.',
      'Setelan > Lokasi > Izin aplikasi: pilih Selalu.',
    ],
  ),
  AndroidBrandGuide(
    brand: 'OPPO / OnePlus (ColorOS/OxygenOS)',
    steps: [
      'Setelan > Baterai > Optimasi baterai > aplikasi ini: pilih Jangan optimalkan.',
      'Setelan > Aplikasi > Peluncuran otomatis: aktifkan untuk aplikasi ini.',
      'Setelan > Aplikasi > aplikasi ini > Penggunaan daya latar belakang: izinkan aktivitas latar belakang.',
      'Setelan > Lokasi > Izin aplikasi: pilih Selalu.',
    ],
  ),
  AndroidBrandGuide(
    brand: 'Vivo / iQOO (FuntouchOS/OriginOS)',
    steps: [
      'Setelan > Baterai > Konsumsi daya tinggi latar belakang: izinkan aplikasi ini.',
      'Setelan > Aplikasi > Peluncuran otomatis: aktifkan untuk aplikasi ini.',
      'Setelan > Baterai > Optimasi baterai: pilih Tidak dioptimalkan.',
      'Setelan > Lokasi > Izin aplikasi: pilih Selalu.',
    ],
  ),
  AndroidBrandGuide(
    brand: 'Realme (realme UI)',
    steps: [
      'Setelan > Baterai > Optimasi baterai > aplikasi ini: pilih Jangan optimalkan.',
      'Setelan > Aplikasi > Peluncuran otomatis: aktifkan untuk aplikasi ini.',
      'Setelan > Aplikasi > aplikasi ini > Penggunaan daya latar belakang: izinkan.',
      'Setelan > Lokasi > Izin aplikasi: pilih Selalu.',
    ],
  ),
  AndroidBrandGuide(
    brand: 'Huawei / Honor (EMUI/MagicOS)',
    steps: [
      'Setelan > Baterai > Peluncuran aplikasi: kelola secara manual dan aktifkan peluncuran otomatis.',
      'Setelan > Baterai > Aplikasi konsumsi daya tinggi: pilih izinkan aktivitas latar belakang.',
      'Setelan > Aplikasi > aplikasi ini > Baterai: pilih Tidak dibatasi.',
      'Setelan > Lokasi > Izin aplikasi: pilih Selalu.',
    ],
  ),
  AndroidBrandGuide(
    brand: 'Transsion (Tecno/Infinix/itel)',
    steps: [
      'Setelan > Baterai > Optimasi daya aplikasi: matikan untuk aplikasi ini.',
      'Setelan > Aplikasi > Manajemen aplikasi > Autostart: aktifkan.',
      'Setelan > Aplikasi > aplikasi ini > Aktivitas latar belakang: izinkan.',
      'Setelan > Lokasi > Izin aplikasi: pilih Selalu.',
    ],
  ),
  AndroidBrandGuide(
    brand: 'Asus / Zenfone (ZenUI)',
    steps: [
      'Setelan > Baterai > Pengelolaan daya > aplikasi ini: izinkan aktivitas latar belakang.',
      'Setelan > Aplikasi > Autostart: aktifkan untuk aplikasi ini.',
      'Setelan > Baterai > Optimasi baterai: pilih Tidak dioptimalkan.',
      'Setelan > Lokasi > Izin aplikasi: pilih Selalu.',
    ],
  ),
];
