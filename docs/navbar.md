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
- **Navbar melayang di atas peta (Perubahan 5).** Shell memakai
  `extendBody: true`, jadi isi tab (termasuk Peta) memanjang sampai tepi layar
  dan navbar mengambang 16 px di atasnya. Di tab Peta, `AltracqNavBar` menerima
  `overMap: true`: `GlassSurface` mendapat `tint` navy
  (`colors.background` alfa 0,6, hanya mode gelap) supaya peta terang tidak
  membuat label tidak terbaca, dan label diam memakai `textPrimary` (bukan
  `textSecondary`). Warna tetap dari token yang ada; tidak ada warna baru.
- **Inset sistem transparan.** `bootstrap.dart` memanggil
  `SystemUiMode.edgeToEdge` di Android dan `AltracqSystemUiRegion` memasang
  `SystemUiOverlayStyle` transparan dengan ikon yang mengikuti tema aktif.
- **Jarak bawah isi tab.** `extendBody` menaikkan
  `MediaQuery.padding.bottom` isi tab setinggi navbar + 16 px + inset sistem,
  dan Beranda/Lacak/Grup/Profil memakai nilai itu untuk padding bawah daftar.
  Inset sistem mentah tidak terbaca lewat `viewPadding` di dalam body (Scaffold
  menguranginya saat ada `bottomNavigationBar`), jadi shell menyediakan
  `AltracqSystemInset`; Peta memakainya untuk jarak panel, logo, dan atribusi.

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
- **Tint navy 60% hanya di mode gelap.** Peta aplikasi memakai style
  `OUTDOORS` yang tetap terang; tanpa tint, kaca navbar di mode gelap akan
  memantulkan peta terang dan label gelap kehilangan kontras. Di mode terang,
  kaca krem sudah memberi kontras 11,3:1 di atas peta terang, jadi tint tidak
  dipasang. Angka 0,6 dipilih agar peta masih terlihat di balik kaca (bukan
  blok warna) sambil menurunkan luminansi latar di bawah ambang 4,5:1.
- **Label diam menjadi `textPrimary` di atas Peta.** `textSecondary` hanya
  mencapai sekitar 2,5:1 di atas peta terang; `textPrimary` mencapai 4,6:1 di
  mode gelap dan 11,3:1 di mode terang. Di tab lain label tetap
  `textSecondary`.
- **Jarak bawah memakai `extendBody`, bukan pembungkus router.** Alternatifnya
  adalah membungkus setiap cabang dengan padding di router. Cara itu membangun
  padding ganda di layar penuh di luar shell dan menyulitkan Peta yang butuh
  edge-to-edge. Dengan `extendBody`, Scaffold sendiri menaikkan padding bawah
  isi tab; hanya Peta yang perlu jarak eksplisit untuk panel dan ornamennya.
- **`AltracqSystemInset` disediakan shell.** `MediaQueryData.removePadding`
  milik Scaffold mengurangi `viewPadding` saat ada `bottomNavigationBar`,
  sehingga `viewPadding.bottom` menjadi 0 di dalam isi tab. InheritedWidget ini
  membawa inset asli dari luar shell dan dipakai Peta; di luar shell ia jatuh
  ke `viewPadding` biasa.
- **Tinggi Peta tidak dikurangi untuk status bar.** Peta digambar dari y=0
  sampai tepi bawah layar; kartu jalur, kompas, dan tombol pusatkan digeser ke
  bawah dengan `SafeArea(bottom: false)` agar tidak menabrak ikon status.
- **Panel "Peta offline" dan panduan memakai jarak tetap.** Panel diletakkan
  `floatingBottomInset + 44` dari bawah (navbar 64 + 16 + inset + jarak 44),
  ornamen Mapbox `+ 8`. Angka 44 memberi ruang logo/atribusi di antara panel
  dan navbar tanpa menutupi keduanya, sesuai syarat atribusi Mapbox.

## 3. Berkas utama

- `app/lib/design/widgets/altracq_nav_bar.dart` — navbar, kurva gerak,
  perhitungan cakupan, tint peta, warna label, dan `NavBarBlobPainter`.
- `app/lib/features/shell/altracq_shell.dart` — shell persisten, fade 180 ms,
  `extendBody`, pengabaian ketukan tab aktif, dan `AltracqSystemInset`.
- `app/lib/design/system_ui.dart` — gaya system bar transparan,
  `AltracqSystemUiRegion`, dan `AltracqSystemInset`.
- `app/lib/bootstrap.dart` — `SystemUiMode.edgeToEdge` di Android.
- `app/lib/app/app.dart` — memasang `AltracqSystemUiRegion` mengikuti tema.
- `app/lib/design/gooey/gooey_layer.dart` — blur + ambang alfa metaball.
- `app/lib/design/tokens.dart` — `AltracqGooey`, ukuran navbar, dan
  `AltracqMetrics.floatingBottomInset`.
- `app/lib/design/glass/glass_surface.dart` — kaca, tint, dan bayangan navbar.
- `app/lib/features/map/presentation/map_page.dart` — peta edge-to-edge,
  jarak panel/ornamen Mapbox, dan latar penuh saat peta tidak tersedia.
- `app/lib/app/router.dart` — `StatefulShellRoute.indexedStack` dan rute
  top-level di luar tab.
- `app/test/widget/nav_bar_blob_test.dart` — 10 tes widget navbar/blob.
- `app/test/widget/nav_bar_map_test.dart` — 6 tes tint, warna label, dan
  kontras di atas peta.
- `app/test/widget/shell_router_test.dart` — 7 tes widget shell dan router.
- `app/test/widget/shell_edge_to_edge_test.dart` — 3 tes shell edge-to-edge,
  inset, dan jarak bawah isi tab.
- `app/test/widget/system_ui_test.dart` — 3 tes gaya system bar.
- `app/test/widget/map_page_test.dart` — tes peta, termasuk jarak bawah,
  ornamen, dan latar penuh saat kosong.
- `app/test/design/glass_surface_test.dart` — tes kaca, tint, dan tinggi
  navbar.

## 4. Sudah dijalankan

- `flutter analyze lib test` bersih.
- Seluruh suite aplikasi lulus: **401 tes**.
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
- Tes shell edge-to-edge (3 tes) mencakup:
  - `Scaffold.extendBody` aktif dan navbar berhenti 16 px + inset 24 px dari
    tepi bawah layar pada viewport 390 × 844;
  - padding bawah isi Beranda, Lacak, dan Profil sama dengan
    `navbarHeight + navbarInset + inset sistem`, sedangkan peta menempati
    0..844;
  - `PageBackground.showBlobs` mati di Peta dan hidup di tab lain,
    `AltracqNavBar.overMap` hidup di Peta, dan `AltracqSystemInset` membawa
    inset mentah 24 px ke dalam Peta.
- Tes tint dan kontras navbar di atas peta (6 tes) mencakup:
  - `navBarMapTint` null di mode terang dan navy 60% di mode gelap;
  - label diam `textPrimary` di atas peta dan `textSecondary` di tab lain,
    serta berubah ke `onPrimary` mengikuti cakupan blob;
  - latar kaca navbar di Peta memakai `Color.alphaBlend(tint, glassFill)`;
  - `textPrimary` ≥ 4,5:1 di atas peta hitam maupun putih yang sudah diredupkan
    35%, `textSecondary` < 4,5:1 di atas peta putih, dan kaca terang ≥ 4,5:1.
- Tes system bar (3 tes) mencakup bilah transparan dengan ikon gelap di tema
  terang, ikon terang di tema gelap, dan `SystemUiOverlayStyle` yang terpasang
  lewat `AltracqSystemUiRegion`.
- Tes `map_page_test.dart` bertambah 2 tes: nilai jarak panel/ornamen untuk
  inset 0 dan 24 px beserta hubungannya, serta peta kosong tanpa
  `PageBackground`, berlatar `colors.background`, setinggi layar penuh, dengan
  panel berhenti `floatingBottomInset + 44` dari bawah.
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
  kontras label di atas peta sungguhan, posisi terhadap area gestur dan
  navigasi 3 tombol, serta apakah peta benar-benar terlihat di balik kaca
  (bukan blok warna). Semua ini baru diuji lewat widget test, belum di
  emulator.
- Warna ikon status bar mengikuti tema pada perangkat sungguhan; pergantian
  saat peta yang tampak berubah terang/gelap belum diuji (ikon mengikuti tema,
  bukan luminansi peta).
- Latar penuh saat peta tidak tersedia di emulator, termasuk saat sistem
  memakai navigasi 3 tombol (inset bawah lebih besar).

## 6. Cara memeriksa

```sh
cd app
flutter analyze lib test
flutter test test/widget/nav_bar_blob_test.dart test/widget/nav_bar_map_test.dart \
  test/widget/shell_router_test.dart test/widget/shell_edge_to_edge_test.dart \
  test/widget/system_ui_test.dart test/widget/map_page_test.dart
```

Untuk mencoba di perangkat, buka Beranda lalu ketuk Peta, Lacak, Grup, dan
Profil secara bergantian; perhatikan satu blob krem memanjang dan menyusul,
bukan dua bentuk terpisah. Di tab Peta, pastikan peta memanjang sampai status
bar dan tepi bawah, navbar mengambang dengan peta terlihat di baliknya, dan
panel "Peta offline" tidak menutupi logo/atribusi Mapbox. Ulangi dengan
pengaturan Android "Hapus animasi" untuk memastikan geseran menjadi lurus
180 ms tanpa tarikan, serta dengan navigasi gestur dan 3 tombol.
