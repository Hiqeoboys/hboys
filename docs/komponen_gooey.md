# Komponen gooey: GooeySelector dan GooeySwitch

Dokumen ini menjelaskan dua komponen bersama untuk Hiqeo Plus. Keduanya
memakai efek gooey yang sama dengan indikator navbar: satu gumpalan cair,
tanpa tetesan terpisah, dan bersih saat diam.

## Batas pemakaian efek gooey

Efek gooey hanya muncul di empat tempat:

1. indikator navbar (sudah ada),
2. kartu "Semua fitur" di Beranda (sudah ada),
3. `GooeySelector`,
4. `GooeySwitch`.

Tombol biasa tetap pil solid tanpa tonjolan atau leher cair. Saklar lain di
aplikasi, termasuk "Sembunyikan titik awal dan akhir" di Kartu Pendakian,
belum dipindahkan ke `GooeySwitch` karena keputusan itu menunggu persetujuan.

## GooeySelector

Berkas: `app/lib/design/gooey/gooey_selector.dart`.

Kontrol pilih-satu. Indikatornya satu blok berwarna primer tema (navy di mode
terang, krem di mode malam) yang berpindah dari item lama ke item baru.

### Keputusan yang tidak dirinci rancangan

- **Geometri diukur, bukan diasumsikan.** Setiap item memakai `GlobalKey`.
  Setelah frame selesai, render box item diukur relatif terhadap tumpukan
  indikator. Selama belum ada pengukuran, indikator tidak digambar; ini hanya
  terjadi satu frame pertama. Item boleh berbeda lebar/tinggi dan pemilih
  boleh horizontal atau vertikal.
- **Bentuk analitik, bukan blur + ambang alfa.** Gumpalan dibentuk dari dua
  rounded rect (kepala dan ekor) yang disatukan leher. Cara ini tidak
  mengecilkan tepi seperti filter blur, dan tepi saat diam digambar tanpa
  filter sama sekali. Tidak ada `BackdropFilter` di lapisan gooey; kaca milik
  layar, bukan milik indikator.
- **Durasi 480 ms** (rentang rancangan 450–520 ms). Kepala memakai
  `easeOutBack` yang pantulannya dipotong menjadi sekitar 4,4% jarak; ekor
  memakai `Interval(0.12, 1)` dengan `easeOutCubic`. Leher menipis sampai 15%
  pada regangan puncak dan tidak pernah terputus.
- **Cakupan warna dua dimensi.** Warna isi item dihitung dari luas irisan
  antara indikator dan item, bukan dari posisi tengah. Teks baru berubah
  menjadi warna `onPrimary` penuh ketika indikator benar-benar menutup item,
  sesuai aturan "bergeser saat gumpalan menutupinya".
- **Tanpa perubahan tebal huruf.** Bobot teks tetap. Mengubah bobot saat
  animasi akan mengubah lebar item dan membuat target indikator bergeser.
- **Ketukan pada item terpilih tidak melakukan apa pun** (tanpa animasi dan
  tanpa haptic). Ketukan pada item lain mengirim `onChanged`; animasi dimulai
  ketika induk membangun ulang dengan nilai baru.
- **Kurangi gerakan.** Indikator bergeser linear 150 ms, ukuran tetap
  diinterpolasi, tanpa regangan atau leher. Warna teks tetap bergeser.
- **Perangkat lemah atau profil daya Hemat/Kritis.** `VisualEffectPolicy`
  mematikan gooey; indikator tetap bergerak sebagai satu rounded rect dengan
  pegas kepala, tanpa leher.
- **Aksesibilitas.** Setiap item adalah tombol semantik dengan label dan
  status `selected`. Fokus keyboard mengikuti urutan item; panah kiri/kanan
  (horizontal) atau atas/bawah (vertikal) memindahkan pilihan; Enter/Space
  memilih item yang sedang fokus.

### Parameter

- `axis`: horizontal atau vertikal.
- `items`: nilai, label semantik, dan `builder` opsional. Tanpa builder,
  label digambar sebagai teks yang warnanya mengikuti `coverage`.
- `itemPadding`: jarak di dalam area yang ditutup indikator. Bawaannya
  16×12; kartu paket memakai `EdgeInsets.zero` karena kartunya sendiri yang
  mengatur padding.
- `borderRadius`: `HiqeoRadius.pill` untuk tab, `HiqeoRadius.card` (18) untuk
  kartu paket.
- `gap`: jarak antar item; indikator tidak melintasi jarak ini saat diam.
- `indicatorColor`: bawaannya `HiqeoColors.primary`.

## GooeySwitch

Berkas: `app/lib/design/gooey/gooey_switch.dart`.

Trek 48×28, knob bulat 22, area sentuh minimal 44×44. Knob memanjang menjadi
gumpalan saat berpindah: kepala memimpin dengan pegas kaku, ekor menyusul
dengan pegas lembut, leher menipis sampai 15%, lalu knob kembali bulat di
tujuan. Durasi 400 ms, warna trek memudar 250 ms dengan `Curves.ease`.

### Keputusan yang tidak dirinci rancangan

- **Seret belum didukung.** Rancangan menyebut seret opsional dan ketuk
  wajib; hanya ketuk yang diimplementasikan pada tahap ini.
- **Tekan melebarkan knob 4 px** dan dilepas memicu perpindahan. Jika gerakan
  dibatalkan, lebar knob kembali tanpa mengubah nilai.
- **Gaya warna.** `GooeySwitchStyle.standard` menurunkan warna dari tema:
  trek mati `secondary`, trek hidup `primary`, knob mati krem (latar terang)
  atau krem (mode malam), knob hidup `onPrimary`. `GooeySwitchStyle.recap`
  dipakai di atas panel gelap Rekap Tahunan: trek mati krem 22%, trek hidup
  krem penuh, knob mati krem, knob hidup navy.
- **Kurangi gerakan.** Knob bergeser linear 150 ms tanpa regangan; warna trek
  tetap memudar 250 ms.
- **Aksesibilitas.** Semantik `toggled` dengan label deskriptif; Enter/Space
  menyalakan/mematikan saat fokus keyboard.

## Tes

- `app/test/design/gooey_selector_test.dart`: 7 tes (geometri, warna,
  ketukan ulang, item vertikal berbeda tinggi, kurangi gerakan, semantik,
  panah keyboard).
- `app/test/design/gooey_switch_test.dart`: 6 tes (perpindahan dan warna,
  tekan 4 px, kurangi gerakan, semantik, spasi keyboard, gaya recap).
- `app/test/golden/gooey_components_golden_test.dart`: golden terang dan
  malam, `test/golden/goldens/gooey_components_light.png` dan
  `gooey_components_dark.png`.

## Sudah dijalankan dan yang belum

Sudah dijalankan: seluruh tes unit/widget/golden di atas dengan font Plus
Jakarta Sans asli, di mesin pengembangan Windows.

Belum diuji: target 60 fps pada perangkat menengah, rekaman layar emulator,
dan perilaku pada iOS. Angka durasi dan regangan berasal dari rancangan, bukan
dari pengukuran frame di perangkat.
