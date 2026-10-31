# Navigasi bawah dan indikator blob

Dokumen ini menjelaskan apa yang benar-benar dikerjakan navigasi bawah, apa
yang sudah dijalankan, dan apa yang belum diuji.

## 1. Lingkup yang sudah ada

- **Satu widget persisten.** `AltracqShell` memegang satu `AltracqNavBar` di
  luar `StatefulShellRoute.indexedStack`. Berpindah tab mengganti cabang di
  dalam `IndexedStack`, bukan membangun ulang navbar; tes memastikan instance
  `State` navbar sama sebelum dan sesudah pindah tab.
- **Layar penuh tanpa navbar.** Splash, Siap Naik, SOS, dan Kartu Pendakian
  berada di rute top-level, di luar shell. Karena itu layar-layar tersebut
  tidak memiliki navigasi bawah.
- **Permukaan.** Tinggi 64 px, radius sudut 32, menjorok 16 px dari tepi kiri,
  kanan, dan bawah, memakai `GlassSurface` yang sudah ada. Kaca, garis tepi,
  kilau 1 px, dan bayangan berada di luar lapisan gooey, jadi tidak ikut
  dikaburkan oleh filter blob.
- **Satu blob, bukan gelembung terpisah.** Indikator berupa satu bentuk krem
  (`colors.primary`) berukuran 66 × 52 px saat diam. Selama pindah tab, bentuk
  itu terdiri dari pill kepala, pill ekor, dan leher yang menyatukan keduanya
  dalam satu `Path` (`PathOperation.union`). Tidak ada lingkaran, gelembung,
  atau tetesan yang terlepas dari bentuk utama.
- **Gerak 500 ms.** Kepala bergerak lebih dulu dengan `easeOutBack` yang
  dipangkas; ekor menyusul mulai 60 ms (interval 0,12 dari 500 ms) dengan
  `easeOutCubic` tanpa pantulan. Blob memanjang di tengah perjalanan lalu
  menyatu kembali di tab tujuan. Jarak antar-tab yang jauh, mis. Beranda ke
  Profil, tetap satu bentuk yang memanjang melintasi tab di antaranya.
- **Pantulan dibatasi.** `easeOutBack` memantul sekitar 9,9%; skala 0,45
  menyisakan pantulan ≈ 4,5% jarak perpindahan, di bawah batas 5%.
- **Warna tab mengikuti blob.** Ikon dan label berubah warna hanya saat blob
  benar-benar menutupi atau meninggalkan area pill tab itu. Perhitungan
  memakai rentang yang disapu blob (dari pusat ekor ke pusat kepala, termasuk
  leher) terhadap area pill tab, lalu di-clamp 0..1. Ikon: `textPrimary` →
  `onPrimary`; label: `textSecondary` → `onPrimary`; bobot label 500 → 700 saat
  cakupan mencapai 0,5. Tidak ada warna baru.
- **Ketukan tab aktif tidak beranimasi.** Shell mengabaikan ketukan pada tab
  yang sudah aktif: tidak ada perubahan indeks, tidak ada geseran blob, dan
  tidak ada fade isi.
- **Isi tab memudar masuk 180 ms.** Shell membungkus isi cabang dengan
  `FadeTransition` yang dimulai dari 0 saat indeks berubah. Isi lama hilang
  seketika karena cabang disimpan di `IndexedStack`; pemilik proyek memilih
  fade-in isi baru, bukan silang dua cabang. Navbar tidak ikut memudar dan
  tidak menunggu fade selesai.
- **Kurangi animasi.** Bila sistem meminta animasi dikurangi, kepala dan ekor
  bergerak lurus bersama selama 180 ms tanpa tarikan ekor, tanpa gooey, dan
  tanpa fade isi. Profil daya Hemat/Kritis dan perangkat lemah mematikan gooey
  tetapi tetap memakai gerak 500 ms yang memanjang; bentuk saat diam tetap
  tajam.
- **Aksesibilitas.** Setiap tab tetap satu tombol semantik berlabel dengan
  status terpilih. Blob dan teks yang terlihat dikecualikan dari semantik agar
  nama tidak dobel. Tinggi 64 px dengan lima sel memberi area sentuh lebih dari
  44 px.
- **Ambang alfa gooey diperbaiki.** `ColorFilter.matrix` Flutter bekerja pada
  kanal 0–255, sedangkan nilai CSS `alpha' = alpha * 20 - 9` berlaku pada 0–1.
  Geseran yang benar adalah −9 × 255 = −2295; nilai lama −9 membuat ekor blur
  hampir sepenuhnya opak sehingga ambang tidak berfungsi.

Spesifikasi gooey lama untuk tombol — tonjolan cair di tepi tombol dan leher
penyambung antar-tombol — dibatalkan. `nav_bar_gooey_test.dart` yang menguji
gelembung dan tetesan ikut dihapus dan diganti `nav_bar_blob_test.dart`.

## 2. Keputusan di tempat yang tidak dispesifikasikan

- **Durasi 500 ms** dipilih di tengah rentang 450–550 ms supaya perjalanan
  lintas tab terasa cair tanpa terasa lambat.
- **Leher digambar eksplisit, bukan hanya disatukan filter.** Filter metaball
  saja tidak menjamin dua pill yang berjauhan tetap tersambung; pada lompatan
  Beranda–Profil keduanya bisa terlihat terpisah. Karena itu leher berupa
  rounded rect yang menyambung pusat kepala dan pusat ekor. Tingginya menipis
  dari 52 px ke 26 px saat jarak memanjang (rasio jarak / 132 px, clamp 0..1),
  sehingga bentuk terasa tertarik tetapi tidak pernah putus.
- **Ekor memakai `easeOutCubic`, bukan pegas yang memantul.** Spesifikasi
  meminta ekor menyusul dengan pegas lebih lembut; kurva ini memberi
  keterlambatan dan penyusulan yang halus tanpa pantulan yang bisa membuat
  ekor melewati kepala dan tampak terlepas di akhir.
- **Gooey hanya menyala saat blob benar-benar bergerak** (`nilai animasi > 0`).
  Saat diam, pill digambar tajam tanpa filter agar tepinya bersih dan tidak ada
  lapisan blur yang tertinggal. Pada nilai 0 belum ada perpindahan, jadi belum
  perlu bentuk cair.
- **Warna blob memakai `colors.primary`** karena pill aktif versi lama juga
  memakai token itu: krem di mode gelap dan navy di mode terang. Ini menjaga
  palet dan tidak menambah warna.
- **Ikon diam tetap `textPrimary`.** Rancangan menyebut transisi
  secondary↔active untuk ikon dan label; label diam memang sudah
  `textSecondary`, sedangkan ikon mempertahankan warna ikon navbar yang sudah
  ada. Mengubahnya menjadi secondary akan menurunkan kontras ikon diam.
- **Cakupan memakai rentang yang disapu, bukan hanya kepala.** Dengan begitu
  tab yang dilewati blob pada lompatan jauh ikut berubah warna saat tertutup
  lalu kembali, bukan melompat di awal atau akhir animasi.
- **Fade 180 ms hanya pada isi baru.** Angka ini dipilih di dalam rentang
  150–200 ms; isi lama tidak ikut memudar karena cabang `IndexedStack` harus
  tetap hidup agar navbar dan state tab tidak dibangun ulang.
- **Label semantik diambil alih widget induk.** Teks yang terlihat dibungkus
  `ExcludeSemantics` supaya pembaca layar tidak mengumumkan label dua kali.

## 3. Berkas utama

- `app/lib/design/widgets/altracq_nav_bar.dart` — navbar, kurva gerak,
  perhitungan cakupan, dan `NavBarBlobPainter`.
- `app/lib/features/shell/altracq_shell.dart` — shell persisten, fade 180 ms,
  dan pengabaian ketukan tab aktif.
- `app/lib/design/gooey/gooey_layer.dart` — blur + ambang alfa metaball.
- `app/lib/design/tokens.dart` — `AltracqGooey` (blur 6, alfa 20, geseran
  −2295) dan ukuran navbar.
- `app/lib/design/glass/glass_surface.dart` — kaca dan bayangan navbar.
- `app/lib/app/router.dart` — `StatefulShellRoute.indexedStack` dan rute
  top-level di luar tab.
- `app/test/widget/nav_bar_blob_test.dart` — 10 tes widget navbar/blob.
- `app/test/widget/shell_router_test.dart` — 7 tes widget shell dan router.
- `app/test/design/glass_surface_test.dart` — tes kaca, termasuk tinggi navbar.

## 4. Sudah dijalankan

- `flutter analyze lib test` bersih.
- Seluruh suite aplikasi lulus: **385 tes**.
- Tes widget navbar/blob (10 tes) mencakup:
  - saat diam blob berupa satu pill tajam tanpa `GooeyLayer` maupun filter,
    berpusat di sel pertama, dengan warna `AltracqColors.light.primary`;
  - selama bergerak hanya ada satu `GooeyLayer`, kepala memimpin ekor, dan
    setelah selesai kembali menjadi satu pill tajam di tab tujuan;
  - lompatan Beranda–Profil memanjang lebih dari 0,7 sel di tengah jalan dan
    mendarat di pusat tab Profil tanpa terlepas;
  - pantulan kepala maksimum tetap di atas 1,0 dan tidak melebihi 1,05;
  - ekor tidak pernah mendahului kepala dan tidak melewati 1,0;
  - cakupan 1 saat blob menutup penuh, 0 saat jauh, dan berada di antara 0 dan 1
    untuk kedua tab di tengah jalan;
  - kurangi animasi: satu pill lurus tanpa tarikan ekor, tanpa filter, dan
    mendarat di tab tujuan;
  - profil daya Hemat: memanjang tetapi tanpa filter gooey;
  - mengetuk tab aktif tidak memulai animasi apa pun;
  - setiap tab tetap tombol berlabel dan tab aktif terpilih.
- Tes widget shell/router (7 tes) mencakup:
  - lima tab tersedia dan navbar muncul setelah splash;
  - ketukan tab mengganti isi, rute, dan penanda terpilih;
  - layar SOS dan Kartu Pendakian tidak menampilkan navbar;
  - instance navbar bertahan (objek `State` sama) saat berpindah tab;
  - isi tab baru memudar masuk tepat 180 ms (0 → sebagian → 1);
  - ketukan tab aktif tidak menjalankan animasi dan rute tidak berubah;
  - setiap tab adalah tombol berlabel untuk pembaca layar.
- Nomor suite di atas berasal dari `flutter test` di mesin pengembang; belum
  ada build yang dipasang ke emulator untuk gelombang revisi ini.

## 5. Ditulis tetapi belum diuji di perangkat

- Tampilan blob tunggal di emulator, baik mode terang maupun gelap, termasuk
  warna krem di mode gelap dan ketajaman pill saat diam.
- Rasa gerak 500 ms dan pantulan 4,5% di layar sungguhan; angka kurva sudah
  diuji, tetapi belum dinilai dengan mata.
- Target 60 fps di emulator dan perangkat kelas menengah. Lapisan gooey memakai
  satu `ImageFiltered` + satu `ColorFiltered` hanya selama animasi, tetapi
  biaya render sebenarnya belum diukur.
- Perilaku saat sistem Android benar-benar mengaktifkan "hapus animasi", serta
  saat profil daya Hemat/Kritis aktif di perangkat.
- Perangkat kelas bawah yang memicu `DeviceTier.lowEnd`; jalur tanpa gooey baru
  diuji lewat kebijakan palsu.
- Pembacaan TalkBack untuk lima tab, termasuk pengumuman status terpilih dan
  tidak dobelnya label.
- Interaksi navbar yang melayang di atas peta layar penuh (Perubahan 5):
  kontras label di atas peta terang/gelap dan posisi terhadap area gestur.

## 6. Cara memeriksa

```sh
cd app
flutter analyze lib test
flutter test test/widget/nav_bar_blob_test.dart test/widget/shell_router_test.dart
```

Untuk mencoba di perangkat, buka Beranda lalu ketuk Peta, Lacak, Grup, dan
Profil secara bergantian; perhatikan satu blob krem memanjang dan menyusul,
bukan dua bentuk terpisah. Ulangi dengan pengaturan Android "Hapus animasi"
untuk memastikan geseran menjadi lurus 180 ms tanpa tarikan.
