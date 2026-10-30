# Kartu Pendakian

Dokumen ini menjelaskan apa yang benar-benar dikerjakan layar Kartu Pendakian,
apa yang sudah dijalankan, dan apa yang belum diuji.

## 1. Lingkup yang sudah ada

- Layar memakai sesi **selesai** terbaru dari database perangkat. Sesi yang
  masih berjalan diabaikan. Tanpa sesi selesai, kartu menampilkan keadaan kosong
  yang jujur dan tombol **Simpan PNG**, **Bagikan**, serta **Ganti foto**
  dinonaktifkan. Tidak ada data contoh.
- Tiga gaya kartu, bisa dipilih lewat pil di panel bawah:
  - **Profil** — metrik di atas, kurva elevasi dari titik tersimpan, merek di
    bawah;
  - **Tengah** — metrik di tengah, merek di bawah;
  - **Peta** — metrik di atas, rute ternormalisasi di dalam bingkai peta
    bergaris, merek di bawah.
- Metrik yang ditampilkan: jarak, tanjakan, dan waktu bergerak. Label jarak
  memakai koma desimal (`12,8 km`), tanjakan memakai titik ribuan dan tanda
  minus (`+1.140 m`, `−420 m`), waktu memakai `HH:MM`. Tanggal di merek
  berformat `30 OKT 2026` dan selalu waktu lokal.
- Kurva profil dihitung dari fraksi jarak geodesik kumulatif, bukan indeks
  titik, sehingga sumbu X mengikuti jarak sebenarnya. Puncak ditandai di
  fraksi tertinggi. Kurva baru muncul bila ada minimal dua titik dengan
  ketinggian; tanpa itu label `Profil elevasi belum tersedia` tampil.
- Rute dinormalisasi dengan satu skala untuk kedua sumbu (memakai kosinus
  lintang) supaya bentuk rute tidak gepeng. Titik yang semuanya berimpit
  menghasilkan rute kosong dan label `Rute belum tersedia`.
- Sakelar `Sembunyikan titik awal dan akhir` menghapus penanda awal/akhir dari
  kartu. Sakelar tidak muncul sebagai pengganti informasi privasi lokasi; hanya
  penanda di kartu yang disembunyikan.
- `Ganti foto` membuka pemilih foto sistem (galeri) lewat `image_picker`,
  maksimal 1600 px dan kualitas 85. Foto ditaruh di balik lapisan gelap agar
  teks tetap terbaca. Foto yang gagal didekode ditolak dan kartu tetap memakai
  gradasi. Kartu tidak pernah menyimpan foto ke database.
- `Simpan PNG` menangkap kartu lewat `RepaintBoundary` pada lebar 1080 px
  (4:5, jadi 1080×1350), lalu menyimpannya ke `Pictures/Altracq` lewat
  MediaStore Android. Sudut kartu transparan karena `RepaintBoundary` berada di
  luar `ClipRRect`. Pesan sukses: `PNG tersimpan di Pictures/Altracq.`
- `Bagikan` menangkap PNG yang sama, menulis berkas sementara, lalu membuka
  lembar berbagi Android. Lembar berbagi tidak melaporkan apakah pengguna
  benar-benar mengirim, jadi aplikasi tidak pernah menampilkan klaim
  "terkirim" atau "dibagikan". Bila lembar berbagi tidak tersedia, pesan
  `Berbagi tidak tersedia di perangkat ini.` tampil.
- Penyimpanan MediaStore hanya tersedia di Android 10 (API 29) ke atas. Di
  perangkat lebih lama, `Simpan PNG` gagal dengan pesan jujur dan pengguna
  diarahkan memakai **Bagikan**.
- Nama berkas: `altracq-kartu-yyyyMMdd-HHmm.png` memakai waktu lokal mulai
  sesi.

## 2. Yang sengaja tidak dilakukan

- Tidak ada pengambilan foto dari kamera dan tidak ada penyimpanan foto ke
  database.
- Tidak ada unggahan kartu ke server, grup, atau media sosial. Bagikan hanya
  membuka lembar berbagi sistem.
- Tidak ada metrik karangan: langkah dan kalori tidak ditampilkan di kartu.
- Tidak ada sesi contoh. Bila belum ada sesi selesai, tidak ada kartu.
- Tidak ada penyesuaian warna kartu per tema aplikasi: kartu selalu memakai
  gradasi biru gelap `#3F4765 → #5C6684 → #8B94AE` sesuai rancangan.

## 3. Berkas utama

- `app/lib/features/kartu/presentation/kartu_page.dart` — layar, pemilihan
  sesi, panel gaya, sakelar, dan aksi simpan/bagikan.
- `app/lib/features/kartu/presentation/kartu_card.dart` — tiga tata letak
  kartu, pelukis profil dan rute, penanda awal/akhir.
- `app/lib/features/kartu/domain/kartu_data.dart` — model dari sesi dan titik,
  profil berbasis jarak, normalisasi rute, format label.
- `app/lib/features/kartu/application/kartu_exporter.dart` — antarmuka ekspor,
  tangkapan `RepaintBoundary`, simpan MediaStore, lembar berbagi.
- `app/lib/features/kartu/application/kartu_photo_picker.dart` — pemilih foto
  galeri.
- `app/android/app/src/main/kotlin/id/nama/nama_app/MainActivity.kt` — kanal
  `id.nama.nama_app/media` dengan metode `saveImage` (MediaStore, API 29+).
- `app/lib/app/router.dart` — rute `/kartu` memakai `KartuPage`.
- `app/test/unit/kartu_data_test.dart` — 10 tes unit.
- `app/test/widget/kartu_page_test.dart` — 12 tes widget dengan repositori,
  eksportir, dan pemilih foto palsu.

## 4. Sudah dijalankan

- `flutter analyze lib test` bersih.
- Seluruh suite aplikasi lulus: **324 tes**.
- Tes unit (10) mencakup: penolakan sesi aktif, format label jarak/tanjakan/
  waktu/tanggal, tanjakan nol dan negatif, fraksi profil dan puncak, profil
  kosong bila ketinggian kurang dari dua, normalisasi rute (batas dan rasio
  aspek), satu titik tanpa rute, titik berimpit, dan tipe titik profil.
- Tes widget (12) mencakup:
  - keadaan kosong menonaktifkan simpan, bagikan, dan ganti foto;
  - metrik, profil, dan tanggal dari data nyata;
  - sesi selesai terbaru dipilih dan sesi aktif diabaikan;
  - ketiga gaya dapat dipilih;
  - sakelar menyembunyikan penanda awal/akhir di gaya Profil dan Peta;
  - simpan sukses memakai nama berkas tepat
    `altracq-kartu-20261030-0712.png`;
  - kegagalan simpan, kegagalan tangkap, dan berbagi tidak tersedia memberi
    pesan jujur;
  - berbagi sukses tidak menampilkan SnackBar dan tidak pernah memuat kata
    "terkirim" atau "dibagikan";
  - pemilih foto terhubung ke tombol ganti foto;
  - galat muat dan tombol coba lagi.
- Di emulator Android, memakai sesi nyata yang sudah ada di database perangkat
  (tanpa menambah data contoh):
  - Beranda → Kartu membuka layar dengan kartu sesi terakhir;
  - gaya Profil, Tengah, dan Peta tampil sesuai tata letak;
  - sakelar menyembunyikan titik awal dan akhir benar-benar menghapus penanda;
  - **Simpan PNG** menampilkan `PNG tersimpan di Pictures/Altracq.` dan baris
    MediaStore mencatat `relative_path = Pictures/Altracq/`, lebar 1080,
    tinggi 1350;
  - berkas yang ditarik dari perangkat terdekode sebagai PNG 8-bit RGBA
    (color type 6) dengan sudut alfa 0 dan tengah `(89, 99, 129, 255)`, jadi
    latar kartu memang transparan di luar sudut membulat;
  - **Bagikan** membuka lembar berbagi Android (`ChooserActivity`) berisi
    pratinjau kartu dan target bagikan, tanpa pesan klaim apa pun;
  - **Ganti foto** membuka pemilih foto sistem Android;
  - tombol tutup (X) kembali ke Beranda.
- Data pada emulator kebetulan datar (ketinggian hampir sama) dan rutenya
  hampir vertikal. Itu hasil data GPS nyata, bukan data contoh.

## 5. Ditulis tetapi belum diuji di perangkat

- Foto galeri yang benar-benar terdekode dan tampil di kartu. Galeri emulator
  kosong, jadi yang terverifikasi baru pemilih foto terbuka dan jalur
  `precacheImage` berjalan lewat tes widget.
- Penyimpanan MediaStore di perangkat Android 10 ke atas yang sesungguhnya;
  emulator memakai API 37 dan berhasil. Perangkat di bawah Android 10 hanya
  diuji lewat logika (kanal mengembalikan `null`).
- Seluruh sisi iOS, termasuk lembar berbagi iOS dan izin akses galeri.
- Pembacaan layar pembaca (TalkBack) untuk seluruh elemen kartu.
- Keadaan kosong di perangkat, karena database emulator sudah berisi sesi
  selesai. Keadaan itu baru diuji lewat tes widget.
- Kartu dengan jarak/tanjakan besar (ribuan meter) di perangkat; format label
  diuji unit, bukan dilihat langsung.

## 6. Cara memeriksa

```sh
cd app
flutter analyze lib test
flutter test test/unit/kartu_data_test.dart
flutter test test/widget/kartu_page_test.dart
```

Untuk mencoba di perangkat, selesaikan satu pendakian di layar Lacak, buka
Beranda → Kartu, pilih gaya, coba sakelar, lalu **Simpan PNG**. Berkas muncul
di `Pictures/Altracq` pada galeri.
