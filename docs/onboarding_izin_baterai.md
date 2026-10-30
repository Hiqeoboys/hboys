# Panduan onboarding izin dan baterai

Status verifikasi: **SEMUA LANGKAH PER MEREK DI BAWAH BELUM DIUJI DI PERANGKAT
NYATA.** Isi halaman dalam aplikasi memakai teks yang sama dengan dokumen ini.

## Tujuan

Agar pengguna memberi izin minimum yang diperlukan untuk merekam GPS saat layar
mati, lalu memahami bahwa pengaturan baterai/autostart pada banyak ROM Android
dapat mematikan rekaman meskipun izin sudah benar.

## Urutan izin di aplikasi

1. **Layanan lokasi perangkat.** Harus aktif. Jika mati, pengguna diarahkan ke
   setelan lokasi.
2. **Lokasi saat digunakan.** Diminta lebih dulu.
3. **Lokasi selalu.** Diminta terpisah. Di Android 11+ sistem dapat menolak
   dialog langsung dan membuka halaman setelan aplikasi; hasilnya selalu
   diperiksa ulang.
4. **Lokasi presisi.** Diperiksa melalui status akurasi lokasi. Bila masih
   perkiraan, pengguna diarahkan ke setelan izin aplikasi untuk mengaktifkan
   "Gunakan lokasi presisi".
5. **Notifikasi (Android 13+).** Diperlukan agar notifikasi layanan latar
   terlihat; tanpa ini layanan tidak boleh dimulai.
6. **Optimasi baterai (Android).** Aplikasi meminta pengecualian optimasi
   baterai bila dialog sistem tersedia. Bila tidak, pengguna memakai setelan
   baterai dan panduan merek.

Aplikasi baru menandai "Izin siap" bila layanan lokasi aktif, izin "Selalu"
diberikan, lokasi presisi, dan (Android) notifikasi diizinkan. Pengecualian
optimasi baterai bersifat sangat disarankan, bukan syarat teknis yang diperiksa
oleh sistem.

## Batasan yang harus disampaikan ke pengguna

- Izin "Saat digunakan" saja tidak cukup untuk rekaman saat layar mati.
- Mengubah izin menjadi "Saat digunakan" di tengah sesi dapat menghentikan
  pembaruan lokasi; ini belum diuji dan belum ditangani secara khusus.
- Beberapa merek menonaktifkan dialog permintaan pengecualian baterai. Pengguna
  harus mengikuti setelan merek secara manual.
- Menghentikan paksa aplikasi (force stop) juga menghentikan layanan latar.
  Sesi yang sudah tersimpan akan dipulihkan ketika aplikasi dibuka lagi.
- iOS: pengguna harus memilih "Always" dan "Precise Location". Jika pengguna
  memaksa keluar aplikasi, iOS dapat menghentikan lokasi latar; ini batasan OS.
- Panduan ini tidak menjamin rekaman berjalan. Hasil wajib diverifikasi lewat
  `docs/field_tests/tracking_gps.md`.

## Langkah umum Android

1. Buka aplikasi, lalu menu **Izin & Baterai**.
2. Tekan **Aktifkan izin dasar** dan setujui lokasi saat digunakan.
3. Tekan **Izinkan lokasi "Selalu"**. Bila berpindah ke setelan, pilih
   **Selalu** (bukan "Hanya saat aplikasi digunakan").
4. Aktifkan **Lokasi presisi** pada halaman izin aplikasi.
5. Izinkan notifikasi.
6. Minta pengecualian optimasi baterai. Bila dialog tidak muncul, buka setelan
   baterai dan pilih **Tidak dibatasi** / **Tidak dioptimalkan** sesuai merek.
7. Kembali ke menu izin dan pastikan daftar berstatus **Siap**.

## Panduan awal per merek (BELUM DIUJI)

Nama menu berubah antar versi OS/ROM. Verifikasi satu per satu di perangkat
target sebelum dipakai sebagai instruksi rilis.

### Xiaomi / Redmi / POCO (MIUI/HyperOS)

- [ ] BELUM DIUJI: Setelan > Aplikasi > Kelola aplikasi > aplikasi ini > Hemat
      baterai: **Tanpa batasan**.
- [ ] BELUM DIUJI: Setelan > Aplikasi > Kelola aplikasi > aplikasi ini >
      Autostart: aktifkan.
- [ ] BELUM DIUJI: Kunci aplikasi di layar Recents agar tidak dibersihkan.
- [ ] BELUM DIUJI: Setelan > Lokasi > Izin lokasi aplikasi: **Selalu**.

### Samsung (One UI)

- [ ] BELUM DIUJI: Setelan > Baterai > Batas penggunaan latar belakang:
      pastikan aplikasi tidak dibatasi.
- [ ] BELUM DIUJI: Setelan > Baterai > Aplikasi tidur: keluarkan aplikasi dari
      daftar atau masukkan ke aplikasi yang tidak pernah tidur.
- [ ] BELUM DIUJI: Setelan > Aplikasi > aplikasi ini > Baterai: **Tidak
      dibatasi**.
- [ ] BELUM DIUJI: Setelan > Lokasi > Izin aplikasi: **Selalu**.

### OPPO / OnePlus (ColorOS/OxygenOS)

- [ ] BELUM DIUJI: Setelan > Baterai > Optimasi baterai > aplikasi ini:
      **Jangan optimalkan**.
- [ ] BELUM DIUJI: Setelan > Aplikasi > Peluncuran otomatis: aktifkan.
- [ ] BELUM DIUJI: Setelan > Aplikasi > aplikasi ini > Penggunaan daya latar
      belakang: izinkan aktivitas latar belakang.
- [ ] BELUM DIUJI: Setelan > Lokasi > Izin aplikasi: **Selalu**.

### Vivo / iQOO (FuntouchOS/OriginOS)

- [ ] BELUM DIUJI: Setelan > Baterai > Konsumsi daya tinggi latar belakang:
      izinkan aplikasi.
- [ ] BELUM DIUJI: Setelan > Aplikasi > Peluncuran otomatis: aktifkan.
- [ ] BELUM DIUJI: Setelan > Baterai > Optimasi baterai: **Tidak
      dioptimalkan**.
- [ ] BELUM DIUJI: Setelan > Lokasi > Izin aplikasi: **Selalu**.

### Realme (realme UI)

- [ ] BELUM DIUJI: Setelan > Baterai > Optimasi baterai > aplikasi ini:
      **Jangan optimalkan**.
- [ ] BELUM DIUJI: Setelan > Aplikasi > Peluncuran otomatis: aktifkan.
- [ ] BELUM DIUJI: Setelan > Aplikasi > aplikasi ini > Penggunaan daya latar
      belakang: izinkan.
- [ ] BELUM DIUJI: Setelan > Lokasi > Izin aplikasi: **Selalu**.

### Huawei / Honor (EMUI/MagicOS)

- [ ] BELUM DIUJI: Setelan > Baterai > Peluncuran aplikasi: kelola manual dan
      aktifkan peluncuran otomatis.
- [ ] BELUM DIUJI: Setelan > Baterai > Aplikasi konsumsi daya tinggi: izinkan
      aktivitas latar belakang.
- [ ] BELUM DIUJI: Setelan > Aplikasi > aplikasi ini > Baterai: **Tidak
      dibatasi**.
- [ ] BELUM DIUJI: Setelan > Lokasi > Izin aplikasi: **Selalu**.

### Transsion (Tecno/Infinix/itel)

- [ ] BELUM DIUJI: Setelan > Baterai > Optimasi daya aplikasi: matikan untuk
      aplikasi ini.
- [ ] BELUM DIUJI: Setelan > Aplikasi > Manajemen aplikasi > Autostart:
      aktifkan.
- [ ] BELUM DIUJI: Setelan > Aplikasi > aplikasi ini > Aktivitas latar
      belakang: izinkan.
- [ ] BELUM DIUJI: Setelan > Lokasi > Izin aplikasi: **Selalu**.

### Asus / Zenfone (ZenUI)

- [ ] BELUM DIUJI: Setelan > Baterai > Pengelolaan daya > aplikasi ini: izinkan
      aktivitas latar belakang.
- [ ] BELUM DIUJI: Setelan > Aplikasi > Autostart: aktifkan.
- [ ] BELUM DIUJI: Setelan > Baterai > Optimasi baterai: **Tidak
      dioptimalkan**.
- [ ] BELUM DIUJI: Setelan > Lokasi > Izin aplikasi: **Selalu**.

## Langkah umum iOS

1. Buka **Izin & Baterai**.
2. Berikan izin lokasi saat digunakan.
3. Berikan izin **Always**; bila perlu melalui Setelan > Privasi & Keamanan >
   Layanan Lokasi > aplikasi ini.
4. Aktifkan **Precise Location**.
5. Pastikan indikator lokasi latar muncul saat merekam dengan layar mati.
6. Uji ulang setelah Low Power Mode dan setelah aplikasi disapu dari app
   switcher.

## Catatan rilis

- Permintaan pengecualian optimasi baterai dan izin lokasi latar harus sesuai
  kebijakan Google Play dan alasan penggunaan yang ditampilkan ke pengguna.
  Tinjau kebijakan toko sebelum rilis; ini belum ditinjau dalam tugas ini.
- Jangan menyembunyikan notifikasi layanan latar atau memakai trik yang membuat
  pengguna mengira aplikasi tidak merekam.
- Untuk iOS, alasan penggunaan lokasi latar harus jelas untuk peninjauan App
  Store; konfigurasi saat ini belum diuji dan belum ditinjau App Store.

## Kriteria panduan dianggap terverifikasi

- Setiap langkah per merek dicoba pada perangkat fisik dan hasilnya dicatat
  (menu ditemukan, teks menu sesuai, efek terlihat).
- Perbedaan versi OS/ROM dicatat sebagai varian, bukan dihapus tanpa bukti.
- Langkah yang tidak dapat direproduksi ditandai dan diperbaiki.
- Panduan tidak menjanjikan rekaman berjalan sebelum uji lapangan lulus.
