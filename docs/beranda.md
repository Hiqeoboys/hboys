# Beranda

Dokumen ini menjelaskan susunan Beranda setelah revisi UI gelombang ini, setiap
keputusan desain yang tidak disebutkan di spesifikasi, dan apa yang sudah
dijalankan versus yang baru ditulis.

## 1. Susunan layar

1. Sapaan menurut jam lokal dan pil baterai.
2. Kartu "Pendakian berikutnya" (`_HeroCard`), tidak berubah pada revisi ini.
3. **Ringkasan perjalanan terakhir** (`LastTripSummaryCard`).
4. **Semua fitur** (`ExpandableFeaturesCard`) yang mulai tertutup.

Warna, tipografi, kaca, dan mode terang/malam tidak berubah; tidak ada warna
baru. Semua latar memakai `colors.surface` lewat `GlassSurface`, teks memakai
`textPrimary`/`textSecondary`, dan sorotan memakai `primary`/`onPrimary`.

## 2. Ringkasan perjalanan terakhir

- Sumber data: sesi **selesai** terbaru dari database perangkat, dibaca lewat
  `TrackingRepository.watchSessions()` supaya ringkasan terisi setelah
  pendakian selesai tanpa memuat ulang layar. Titik sesi itu diambil lewat
  `points(session.id)` lalu dihitung dengan `KartuData.fromSession`, model yang
  sama dengan layar Kartu.
- Nama gunung diambil dari grup sesi (`groupId`) bila grup itu dikenal akun.
  Bila tidak, judul memakai tanggal terformat, misalnya
  `Pendakian 30 Okt 2026` — keputusan yang diminta pemilik proyek. Tanggalnya
  waktu lokal perangkat, sama dengan layar Kartu.
- Baris kecil di bawah judul: `30 Okt 2026 · 07:12` (tanggal · waktu mulai).
- Tiga angka besar: **Jarak**, **Tanjakan**, **Waktu** dengan label 9 px tebal,
  huruf renggang 1,4. Angkanya 20 px, bobot 800, tinggi baris 1,1, renggang
  −0,8. Format label memakai `KartuData`: koma desimal (`12,8 km`), titik
  ribuan dan tanda minus (`+1.140 m`), `HH:MM` untuk waktu.
- Jejak rute mini 44 px di kanan angka: hanya garis, tanpa ubin peta, dan
  **titik awal/akhir tidak pernah digambar**. Alasannya: sakelar privasi
  "sembunyikan titik awal dan akhir" hanya ada di layar Kartu dan tidak
  disimpan; Beranda memilih sisi aman. Rute dinormalisasi dengan
  `KartuData.fitRoute` (satu skala kedua sumbu) dengan tepi 2 px.
- Sparkline elevasi selebar kartu, tinggi 38 px, sumbu X mengikuti fraksi jarak
  sebenarnya. Puncak diberi titik kecil dan label `PUNCAK` yang baru muncul
  setelah garis gambar menyentuh puncak. Isian memakai gradasi `textPrimary`
  dari alfa 0,18 ke 0, tanpa warna baru. Bila profil kurang dari dua titik,
  kartu menulis `Profil elevasi belum tersedia`, bukan menggambar garis palsu.
- Tombol **Lihat kartu** berupa pil kaca kecil; pil yang terlihat 36 px tetapi
  area sentuhnya tetap 44 px (`HiqeoMetrics.minTouchTarget`). Tombol membuka
  `/kartu?sesi=<id>` sehingga layar Kartu menampilkan sesi yang sama, bukan
  sesi terbaru yang kebetulan lain.
- Keadaan kosong: overline `PENDAKIAN TERAKHIR`, judul
  `Belum ada riwayat pendakian`, dan pendukung
  `Ringkasan pendakian terakhirmu akan muncul di sini.` Bila database gagal
  dibaca, judulnya `Riwayat belum dapat dibaca` dengan alasan jujur dari
  halaman, dan tombol **Lihat kartu** nonaktif.
- Animasi masuk satu kali: hitung-naik selesai pada 600 ms dengan `easeOut`,
  sedangkan garis rute dan sparkline tergambar sampai 700 ms. Bila data baru
  tiba setelah kartu tampil, animasi tetap hanya diputar sekali. Saat
  kebijakan meminta kurangi animasi, semua nilai langsung final dan tidak ada
  animasi yang berjalan.
- Tinggi kartu: sasaran 190–210 px. Dengan ukuran jejak 44 px (bukan 48 px),
  kartu terukur 203 px di Beranda dan 207 px saat diuji sendiri, memakai huruf
  Plus Jakarta Sans asli.

## 3. Semua fitur (kartu lipat)

- Tertutup: satu baris kaca setinggi 64 px berisi judul dan **satu** tombol
  bulat 44 px bergambar grid. Grid fitur tidak dibangun saat tertutup penuh,
  jadi tidak ada blur atau opacity yang bekerja diam-diam.
- Terbuka: persegi panjang radius 28 (`HiqeoRadius.hero`), tinggi
  4 baris × 140 px + 3 celah × 12 px + tepi bawah 16 px = 676 px untuk 8 fitur.
- Morph buka/tutup 550 ms. Tiap kartu mulai dengan jeda 35 ms (di dalam
  rentang 30–40 ms yang diminta), skala 0,6 → 1, isi kabur 8 → 0, opacity
  0 → 1. Latar kartu dan latar tiap fitur digambar lewat `GooeyLayer` selama
  morph, lalu disilangkan ke kaca tajam pada 88% animasi; setelah selesai
  lapisan gooey dibuang, jadi tidak ada filter ambang alfa yang tertinggal
  aktif di pohon widget.
- Ikon tombol berubah dari grid menjadi X saat terbuka. Kartu mulai tertutup
  dan tidak menyimpan pilihan ke penyimpanan.
- Semantik: satu tombol dengan label `Tampilkan semua fitur` /
  `Sembunyikan semua fitur` dan keadaan *expanded*; isi visual header
  dikecualikan supaya judul dan ikon tidak dibacakan dua kali. Saat tertutup,
  kartu fitur di dalamnya juga dikecualikan dan tidak bisa disentuh.
- Setelah terbuka, kartu digulir sampai terlihat penuh lewat
  `Scrollable.ensureVisible` dengan durasi `HiqeoMotion.spring`. Gulir
  dijalankan satu bingkai setelah animasi selesai, karena status selesai tiba
  sebelum bingkai dengan tinggi akhir terpasang; tanpa itu gulir berhenti
  kurang dari tinggi sebenarnya.
- Saat kurangi animasi aktif (atau perangkat lemah / profil Hemat), morph
  diganti tinggi + fade biasa selama 260 ms
  (`HiqeoMotion.screenFade`), tanpa gooey dan tanpa blur isi. Gooey hanya
  menyala bila `VisualEffectPolicy.gooey` benar; glass blur mengikuti
  `glassBlur`.

## 4. Keputusan di tempat yang tidak dispesifikasikan

- Jejak rute 44 px, bukan 48 px, agar tinggi kartu masuk 190–210 px.
- Titik awal/akhir rute tidak digambar dan tidak diberi label pembaca layar per
  titik; hanya ada satu label `Jejak rute pendakian` bila rute punya ≥ 2 titik.
- Judul kartu memakai nama gunung bila diketahui; jika tidak, tanggal
  terformat `Pendakian 30 Okt 2026` (jawaban pemilik proyek).
- Salinan keadaan kosong ditulis pendek satu baris pendukung supaya kartu tetap
  ringkas dan jujur.
- Angka besar memakai `FittedBox` agar `+1.140 m` tidak terpotong di lebar
  sempit; angka tetap satu baris.
- Sparkline memakai `textPrimary` dengan alfa untuk isian; tidak menambah warna
  baru dan tetap terbaca di kedua tema.
- Label `PUNCAK` muncul bertahap setelah garis melewati puncak, bukan sejak
  awal, supaya tidak menunjuk tempat yang belum tergambar.
- Kartu ringkasan tidak dibuat dapat diketuk seluruhnya; hanya tombol
  **Lihat kartu** yang menjadi aksi, supaya tidak ada aksi tersembunyi.
- Grid "Semua fitur" memakai tinggi sel tetap 140 px (dua kolom), sama seperti
  rancangan sebelumnya, supaya tiga baris teks tidak terpotong.
- Kartu lipat tidak menutup sendiri setelah sebuah fitur diketuk; pengguna
  kembali ke Beranda dengan kartu tetap terbuka pada kunjungan itu.
- `Lihat kartu` mengirim id sesi lewat query, bukan mengandalkan "sesi terbaru",
  karena ringkasan boleh jadi bukan sesi terbaru setelah sinkronisasi lain.

## 5. Muat tanpa gulir di layar 844 px

Uji widget `beranda_page_test.dart` memakai layar 390×844, inset atas 47 px,
dan bilah bawah 80 px (64 px navbar + 16 px inset yang dipakai shell saat ini),
serta huruf Plus Jakarta Sans asli:

- viewport daftar 717 px, tinggi isi 713 px, `maxScrollExtent` 0. Sisa 4 px —
  tipis, jadi harus diperiksa ulang di emulator (emulator 411×914 memberi ruang
  lebih lega). Setelah Perubahan 5 menambah `extendBody`, jarak bawah Beranda
  akan dibuat eksplisit setinggi navbar + inset.

## 6. Berkas

- `app/lib/features/home/last_trip_summary_card.dart` — kartu ringkasan, dua
  pelukis (rute mini dan sparkline), animasi masuk.
- `app/lib/features/home/expandable_features_card.dart` — kartu lipat, morph
  gooey ↔ kaca, jeda kartu, semantik, gulir otomatis.
- `app/lib/features/home/beranda_page.dart` — pemuatan sesi selesai terbaru,
  nama gunung dari grup, dan rute `Lihat kartu`.
- `app/lib/features/kartu/domain/kartu_data.dart` — `dateText`, `scaledBy`, dan
  `fitRoute` dipakai bersama layar Kartu dan ringkasan.
- `app/test/widget/last_trip_summary_card_test.dart` — 13 tes.
- `app/test/widget/expandable_features_card_test.dart` — 9 tes.
- `app/test/widget/beranda_page_test.dart` — 7 tes, termasuk muat 844 px.
- `app/test/support/real_font.dart` — memuat huruf asli untuk uji piksel.

## 7. Sudah dijalankan

- `flutter analyze lib test` bersih.
- Seluruh suite aplikasi lulus: **376 tes** (sebelumnya 341).
- 13 tes kartu ringkasan lulus, mencakup keadaan kosong dan galat, isi kartu,
  judul cadangan tanggal, hitung-naik, dua pelukis, profil hilang, tinggi
  190–210 px dengan huruf asli, ketukan **Lihat kartu**, kurangi animasi, data
  yang tiba terlambat, dan semantik tombol.
- 9 tes kartu lipat lulus, mencakup tinggi tertutup 64 px, tidak ada grid saat
  tertutup, ketukan di luar baris tidak membuka, buka/tutup dengan 8 kartu,
  gooey hanya di tengah morph pada kedua arah, gulir otomatis, semantik
  expanded, kurangi animasi, dan profil daya Hemat.
- 7 tes Beranda lulus, mencakup tamu, grup + status kunci, tujuan navigasi
  fitur, label tombol fitur, ringkasan sesi selesai terbaru, tombol
  **Lihat kartu** membawa id sesi, nama gunung dari grup, dan muat tanpa gulir
  di 844 px.
- 3 tes layar Kartu baru lulus: sesi yang diminta dipakai, sesi yang tidak ada
  ditolak jujur, dan sesi yang belum selesai ditolak.

## 8. Ditulis tetapi belum diuji di perangkat

- Tampilan Beranda baru pada mode terang dan malam di emulator, termasuk
  kualitas kaca, keterbacaan label 9 px, dan rasa morph gooey 550 ms.
- Gulir otomatis setelah membuka "Semua fitur" di layar 411×914 emulator.
- Sisa 4 px pada uji muat 844 px; di layar lain jarak aman belum diukur.
- TalkBack untuk label kartu lipat dan ringkasan; semantik baru diuji lewat
  pohon semantik widget, bukan pembaca layar.
