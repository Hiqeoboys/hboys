# SOS

Dokumen ini menjelaskan apa yang benar-benar dikerjakan layar SOS, apa yang
sudah dijalankan, dan apa yang belum diuji.

## 1. Lingkup yang sudah ada

- Layar SOS selalu memakai palet terbalik biru gelap, tidak mengikuti tema
  aplikasi. Tidak ada efek gooey di layar ini.
- Pemicu memakai tekan-tahan 3 detik, lalu hitung mundur 3 detik. Melepas jari
  setelah hitung mundur dimulai tidak membatalkan; pengguna harus menekan
  **Batal, saya aman**. Pembatalan berlaku selama hitung mundur maupun setelah
  status aktif.
- SOS hanya disimpan ke database perangkat, dan hanya bila ada perbaikan
  lokasi nyata. Urutan sumber lokasi:
  1. titik terakhir dari pelacakan yang sedang berjalan;
  2. `Geolocator.getLastKnownPosition()`;
  3. `Geolocator.getCurrentPosition()` dengan batas waktu 10 detik.
  Bila semuanya gagal, tidak ada baris yang ditulis dan layar menyatakan
  `Lokasi GPS belum tersedia. SOS tidak tersimpan di HP.`
- Baris `SosEvent` memakai:
  - `authorId` = `perangkat-lokal` (penanda perangkat, bukan akun);
  - `groupId` = null;
  - `id` = `sos-<microsecondsSinceEpoch>`;
  - `createdAtUtc` = waktu mulai hitung mundur, `receivedAtUtc` = waktu simpan;
  - status awal `active`, lalu `cancelled` bila dibatalkan.
- Tangga status ditampilkan apa adanya. Hanya `Tersimpan di HP` yang bisa
  menyala. Baris `Diterima 0 anggota`, `Diteruskan ke server`, dan `Pesan
  sampai ke kontak darurat` tetap kosong, disertai catatan bahwa hanya
  penyimpanan lokal yang terjadi.
- Kategori CEDERA / TERSESAT / CUACA tidak dipilih otomatis. Tanpa pilihan
  pengguna, event tersimpan sebagai `SosCategory.other`. Perubahan kategori
  setelah event tersimpan ikut ditulis ke baris database yang sama.
- Tombol **Basarnas 115** dan **Darurat 112** membuka aplikasi telepon lewat
  `Intent.ACTION_DIAL` dengan nomor terisi. Aplikasi tidak meminta izin
  `CALL_PHONE` dan tidak pernah menelpon sendiri. Bila aplikasi telepon tidak
  dapat dibuka, nomor ditampilkan untuk diketik manual.
- Layar menegaskan `SOS tidak menjamin pertolongan datang. Altracq tidak
  mengklaim telah menghubungi Basarnas.`
- Tombol kembali sistem mengembalikan pengguna ke Beranda.

## 2. Yang sengaja tidak dilakukan

- Tidak ada pengiriman ke anggota, server, atau kontak darurat. Ketiga tahap
  itu belum punya transport, jadi tidak boleh dan tidak pernah diklaim.
- Tidak ada klaim bahwa pertolongan akan datang atau bahwa Basarnas sudah
  dihubungi.
- Tidak ada data contoh: tidak ada lokasi, anggota, atau kontak darurat
  buatan. Bila GPS tidak tersedia, SOS tidak disimpan.
- Tidak ada enkripsi end-to-end untuk data SOS. Baris disimpan apa adanya di
  database perangkat.
- Tidak ada penjadwalan pengingat, riwayat SOS, atau pengiriman ulang otomatis.
  Membuka kembali layar memulai alur baru.

## 3. Berkas utama

- `app/lib/features/safety/presentation/sos_page.dart` — layar SOS.
- `app/lib/features/safety/domain/sos_trigger_controller.dart` — mesin
  tekan-tahan, hitung mundur, dan batal.
- `app/lib/features/safety/domain/sos_status_tracker.dart` — tangga status.
- `app/lib/features/safety/domain/sos_category.dart` dan `sos_event.dart` —
  model kategori dan event.
- `app/lib/features/safety/application/sos_location.dart` — sumber lokasi.
- `app/lib/core/platform/phone_dialer.dart` — jembatan `MethodChannel` ke
  pemanggil nomor.
- `app/android/app/src/main/kotlin/id/nama/nama_app/MainActivity.kt` —
  penangan `ACTION_DIAL`.
- `app/lib/app/router.dart` — rute `/sos` memakai `SosPage`.
- `app/test/widget/sos_page_test.dart` — tes widget layar SOS.

## 4. Sudah dijalankan

- `flutter analyze lib test` bersih.
- Seluruh suite aplikasi lulus: **276 tes**.
- Tes widget SOS (10 tes) mencakup:
  - layar diam jujur dan palet terbalik;
  - tekan-tahan 3 detik menyimpan SOS lokal dengan lokasi nyata dan hitung
    mundur 3 → 2 → 1;
  - melepas sebelum 3 detik tidak menyimpan apa pun;
  - batal saat hitung mundur menandai event lokal sebagai batal;
  - batal setelah hitung mundur selesai juga menandai event lokal sebagai
    batal;
  - tanpa perbaikan GPS tidak ada SOS yang disimpan dan tangga status tetap
    kosong;
  - kategori yang dipilih ikut tersimpan;
  - tombol telepon mengirim nomor yang benar;
  - kegagalan membuka aplikasi telepon menampilkan nomor manual;
  - kegagalan penyimpanan lokal tidak diklaim berhasil.
- Di emulator Android (mode terang aplikasi):
  - layar diam, hitung mundur, status aktif, dan status batal terlihat benar
    dengan palet terbalik;
  - chip kategori tampil satu baris dan catatan jujur tidak terpotong;
  - baris database berisi `author_id = perangkat-lokal`, `group_id = null`,
    lat/lon dan akurasi nyata dari perangkat, serta status `active`;
  - memilih CEDERA mengubah `category_code` menjadi 1;
  - menekan **Batal, saya aman** menulis status `cancelled` beserta
    `cancelled_at_utc`;
  - tombol 115 dan 112 membuka aplikasi telepon Android dengan nomor terisi,
    tanpa menelpon;
  - tombol kembali sistem mengembalikan ke Beranda.

## 5. Ditulis tetapi belum diuji di perangkat

- Seluruh sisi iOS, termasuk `ACTION_DIAL` yang tidak ada di iOS; jembatan
  akan mengembalikan `false` dan nomor ditampilkan untuk diketik manual.
- Perilaku aplikasi telepon pada merek Android lain (layar panggilan darurat
  khusus, dual-SIM, atau perangkat tanpa aplikasi telepon bawaan).
- Uji lapangan: perilaku GPS di dalam hutan, waktu perbaikan lokasi lebih dari
  10 detik, dan penyimpanan saat aplikasi di latar belakang atau proses
  dimatikan.
- Pembacaan layar pembaca (TalkBack) untuk seluruh elemen, meskipun label
  semantik sudah diuji lewat tes widget.
- Pengiriman SOS ke anggota, server, atau kontak darurat, karena belum ada
  transportnya.

## 6. Cara memeriksa

```sh
cd app
flutter analyze lib test
flutter test test/widget/sos_page_test.dart
```

Untuk mencoba di perangkat, buka Beranda, gulir ke kartu SOS, lalu tekan-tahan
lingkaran selama 3 detik. Pastikan GPS perangkat mendapat perbaikan lokasi
sebelum mencoba, karena tanpa lokasi SOS memang tidak disimpan.
