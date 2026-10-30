# SOS

Dokumen ini menjelaskan apa yang benar-benar dikerjakan layar SOS, apa yang
sudah dijalankan, dan apa yang belum diuji.

## 1. Lingkup yang sudah ada

- Layar SOS selalu memakai palet terbalik biru gelap, tidak mengikuti tema
  aplikasi. Tidak ada efek gooey di layar ini.
- Sudut kiri atas berisi tombol tutup bulat 44 px (`HeaderIconButton`, sama
  dengan Kartu Pendakian), bukan judul "SOS". Judul "SOS" hanya ada di tengah
  lingkaran. Bila SOS sedang berjalan, tombol itu meminta konfirmasi
  **Batalkan SOS?** lebih dulu, membatalkan lewat jalur yang sama dengan
  **Batal, saya aman**, lalu menutup layar. Bila status batal gagal ditulis,
  layar tetap terbuka supaya catatannya terbaca.
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
- **Basarnas 115** dan **Darurat 112** berupa dua trek geser kaca bertumpuk
  (`SlideToCall`): trek 64 px, knob 56 px, ambang 85% perjalanan, knob membal
  dengan overshoot kecil bila tidak sampai, dan haptic sedang saat memicu.
  Ketukan biasa tidak melakukan apa pun supaya nomor darurat tidak terbuka
  tanpa sengaja. Setelah memicu, knob tetap di ujung dan baru pulang saat
  aplikasi kembali dari pemanggil telepon. Hanya satu trek yang menerima
  geseran pada satu waktu. Trek membuka aplikasi telepon lewat
  `Intent.ACTION_DIAL` dengan nomor terisi. Aplikasi tidak meminta izin
  `CALL_PHONE` dan tidak pernah menelpon sendiri. Bila aplikasi telepon tidak
  dapat dibuka, nomor ditampilkan untuk diketik manual.
- Pembaca layar mendapat jalur tanpa geser: aksi semantik pada trek membuka
  dialog konfirmasi **Buka telepon** sebelum nomor dibuka.
- "Kurangi animasi" mematikan lensa label di dalam knob dan mengganti spring
  dengan perpindahan biasa. Profil daya Hemat/Kritis mengganti blur knob
  dengan isi kaca padat. Fungsi geser tidak berubah pada kedua kondisi itu.
- Layar menegaskan `SOS tidak menjamin pertolongan datang. Altracq tidak
  mengklaim telah menghubungi Basarnas.`
- Tombol kembali sistem mengikuti aturan tombol tutup: langsung kembali bila
  SOS diam, meminta konfirmasi bila SOS berjalan.

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
- Tidak ada warna baru dan tidak ada warna merah pada trek geser. Seluruh isian,
  garis tepi, dan kilau diambil dari token kaca `AltracqColors` yang sudah ada.

## 3. Berkas utama

- `app/lib/features/safety/presentation/sos_page.dart` — layar SOS.
- `app/lib/features/safety/presentation/slide_to_call.dart` — trek geser kaca
  untuk nomor darurat.
- `app/lib/design/widgets/header_icon_button.dart` — tombol tutup bulat 44 px,
  dipakai bersama oleh SOS dan Kartu Pendakian.
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
- `app/test/widget/slide_to_call_test.dart` — tes widget trek geser.

## 4. Sudah dijalankan

- `flutter analyze lib test` bersih.
- Seluruh suite aplikasi lulus: **341 tes**.
- Tes widget SOS (18 tes) mencakup:
  - layar diam jujur dan palet terbalik, termasuk tombol tutup 44 px dan dua
    trek geser;
  - tekan-tahan 3 detik menyimpan SOS lokal dengan lokasi nyata dan hitung
    mundur 3 → 2 → 1;
  - melepas sebelum 3 detik tidak menyimpan apa pun;
  - batal saat hitung mundur menandai event lokal sebagai batal;
  - batal setelah hitung mundur selesai juga menandai event lokal sebagai
    batal;
  - tanpa perbaikan GPS tidak ada SOS yang disimpan dan tangga status tetap
    kosong;
  - kategori yang dipilih ikut tersimpan;
  - geser melewati ambang membuka nomor yang benar, geser di bawah ambang dan
    ketukan biasa tidak membuka nomor apa pun;
  - hanya satu trek yang dapat digeser pada satu waktu;
  - aksi semantik trek membuka dialog konfirmasi lebih dulu;
  - kegagalan membuka aplikasi telepon menampilkan nomor manual;
  - tombol tutup menutup layar saat SOS diam, meminta konfirmasi lalu
    membatalkan saat SOS aktif, dan tombol kembali Android mengikuti aturan
    yang sama;
  - kegagalan penyimpanan lokal tidak diklaim berhasil.
- Tes widget trek geser (9 tes) mencakup: geometri diam 64/56/4 px, knob
  mengikuti jari, balikan di bawah ambang, pemicuan sekali pada 85% beserta
  haptic sedang, knob tetap di ujung sampai aplikasi kembali dari pemanggil,
  lensa mati saat kurangi animasi, blur knob diganti isi padat pada profil
  hemat, trek terkunci saat `interactive: false`, dan jalur aksi semantik.
- Di emulator Android (mode terang aplikasi, **build sebelum revisi UI ini**):
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

- Revisi UI layar ini (tombol tutup, trek geser, lensa knob, spring, dan haptic)
  baru lulus tes widget; belum dilihat di emulator maupun perangkat nyata.
- Rasa geser di jari: ambang 85%, overshoot saat knob membal, dan kekuatan
  haptic sedang perlu dicoba langsung.
- Seluruh sisi iOS, termasuk `ACTION_DIAL` yang tidak ada di iOS; jembatan
  akan mengembalikan `false` dan nomor ditampilkan untuk diketik manual.
- Perilaku aplikasi telepon pada merek Android lain (layar panggilan darurat
  khusus, dual-SIM, atau perangkat tanpa aplikasi telepon bawaan), termasuk
  apakah `AppLifecycleState.resumed` selalu dikirim saat kembali dari pemanggil
  telepon sehingga knob pulang.
- Uji lapangan: perilaku GPS di dalam hutan, waktu perbaikan lokasi lebih dari
  10 detik, dan penyimpanan saat aplikasi di latar belakang atau proses
  dimatikan.
- Pembacaan layar pembaca (TalkBack) untuk seluruh elemen, termasuk aksi
  semantik kustom pada trek geser, meskipun label semantik sudah diuji lewat
  tes widget.
- Pengiriman SOS ke anggota, server, atau kontak darurat, karena belum ada
  transportnya.

## 6. Cara memeriksa

```sh
cd app
flutter analyze lib test
flutter test test/widget/sos_page_test.dart test/widget/slide_to_call_test.dart
```

Untuk mencoba di perangkat, buka Beranda, gulir ke kartu SOS, lalu tekan-tahan
lingkaran selama 3 detik. Pastikan GPS perangkat mendapat perbaikan lokasi
sebelum mencoba, karena tanpa lokasi SOS memang tidak disimpan.
