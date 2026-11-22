# Layar Hiqeo Plus D1–D9 dan animasinya

Dokumen ini melengkapi `docs/plus_entitlement.md`. Isinya: daftar layar,
pintu masuk, sumber data, aturan gerbang, keputusan animasi, dan batas
pengujian. Tahap ini masih UI + logika lokal; tidak ada backend, toko, atau
penerbitan token produksi.

## Peta layar

| Kode | Layar | Rute | Pintu masuk |
| --- | --- | --- | --- |
| D1 | Paywall | `/plus` | Tombol "Buka Hiqeo Plus" di layar terkunci, baris Hiqeo Plus di Profil untuk pengguna gratis |
| D2 | Cuaca Rute | `/plus/cuaca?rute=` | Baris Cuaca di Siap Naik dan Peta |
| D3 | Estimasi & Itinerary | `/plus/estimasi?rute=` | Baris Estimasi di Siap Naik |
| D4 | Analitik Lanjutan | `/plus/analitik` | Baris Analitik lanjutan di Profil |
| D5 | Rekap Tahunan | `/plus/rekap` | Baris Rekap tahunan di Profil |
| D6 | Kelola Langganan | `/plus/kelola` | Baris Hiqeo Plus di Profil saat aktif, tombol "Kelola langganan" di paywall, "Buka kelola langganan" di kartu aktif |
| D7 | Leaderboard Nasional | `/plus/leaderboard` | Baris Leaderboard di Profil, hanya bila flag `leaderboard` menyala |
| D8 | Leaderboard Grup | tab di D7 | Tab "Grup" |
| D9 | Persetujuan dan moderasi | sheet di D7 | Ketuk baris sendiri; tombol opsi (⋮) per baris |
| — | Lencana puncak | bagian Rekap Tahunan | Hanya bila flag `peakBadges` menyala |

Pemilih Nasional/Grup, kategori, dan periode berada di luar area konten.
Pilihannya bertahan saat tab berganti; hanya isi papan yang dimuat ulang.

## Sumber data

- **Nyata dari perangkat:** Analitik, Rekap, dan statistik lokal memakai sesi
  pelacakan yang sudah selesai di database perangkat. Tidak ada angka contoh.
- **Demo hanya di debug:** Cuaca rute dan Leaderboard memakai repositori demo
  `DebugRouteWeatherRepository`/`DebugLeaderboardRepository` ketika
  `kDebugMode` (atau `enabled: true` pada konstruktor). Build rilis memakai
  repositori "belum tersedia" dan menampilkan pesan jujur, bukan data palsu.
- **Tidak pernah memanggil BMKG dari HP.** Cuaca lewat antarmuka repositori
  yang kelak dilayani backend ber-cache. Atribusi BMKG dan label "perkiraan"
  hanya muncul untuk sumber resmi; data demo diberi label demo.
- **Leaderboard dihitung server.** UI hanya menampilkan 10 besar per kategori
  dan catatan bahwa papan dihitung ulang dari jejak mentah serta diperbarui
  terjadwal. Laporan dan blokir saat ini hanya diteruskan ke repositori dummy
  dan tidak diklaim tersimpan di server.
- **Harga dan kuota** berasal dari `PlusRemoteConfig`; UI tidak memuat harga
  sendiri. Paywall tanpa konfigurasi menampilkan "Paket belum tersedia".

## Aturan gerbang

- Fitur inti tetap gratis. Plus hanya menambah cuaca rute, estimasi, analitik,
  rekap, cadangan cloud, leaderboard nasional, dan lencana puncak.
- Status Plus dibaca offline dari token bertanda tangan. Masa tenggang 7–14
  hari dari konfigurasi; layar tidak memanggil jaringan untuk memeriksa status.
- Papan nasional boleh **dilihat** semua pengguna. Yang **berkompetisi** di
  papan nasional hanya pengguna Plus; ini keputusan desain karena papan nasional
  adalah fitur tambahan, sedangkan statistik grup tetap gratis untuk anggota.
- Berhenti berlangganan tidak menghapus riwayat, data, peta unduhan, atau ekspor
  GPX. Layar kelola menjelaskan hal ini dan tetap membuka ekspor.
- Kedua flag (`leaderboard`, `peakBadges`) default mati. Build rilis tanpa
  konfigurasi menampilkan materi yang belum tersedia, bukan papan kosong.
- Tidak ada kategori kecepatan di layar mana pun, termasuk leaderboard, rekap,
  dan analitik.

## Keputusan desain yang tidak dirinci rancangan

- **Paywall memilih satu paket, bukan langganan otomatis.** Tombol utama baru
  memulai transaksi setelah diketuk. Indikator vertikal mengikuti tinggi kartu
  tujuan, termasuk baris kuota Founding Member; karena itu tinggi indikator
  ikut berubah saat berpindah paket.
- **Papan lama tidak dikosongkan saat memuat ulang.** Mengganti kategori,
  periode, atau tab mempertahankan papan sebelumnya sampai papan baru siap,
  lalu area konten berganti dengan crossfade 200 ms. Tanpa ini layar berkedip
  ke indikator muat setiap kali pemilih disentuh.
- **Baris muncul bertahap 28 ms.** Jeda berada di rentang rancangan 25–30 ms;
  fade tiap baris 200 ms. Podium memakai urutan 2–1–3, diikuti baris peringkat,
  baris sendiri, lalu catatan.
- **Grafik cuaca tumbuh dari 62% tinggi akhir.** Durasi 300 ms dengan
  `easeOutBack` ringan; konten hari baru tetap crossfade 200 ms. Batang tidak
  memantul melebihi tinggi akhir secara berlebihan.
- **Analitik berganti himpunan dengan crossfade 200 ms.** Deskripsi rentang
  berada di luar crossfade agar teks penjelas langsung mengikuti pilihan.
- **Saklar Rekap, Kelola, dan persetujuan memakai `GooeySwitch`.** Perilaku,
  durasi, dan pengurangan gerak mengikuti `docs/komponen_gooey.md`.
- **Persetujuan leaderboard default mati.** Fakta "yang tampil" dan "tidak
  tampil" ditulis sebelum saklar. Blokir menyembunyikan baris hanya di
  perangkat ini dan pesan menyatakan server peninjauan belum tersedia.
- **Layar kosong dan galat selalu punya jalan keluar.** Tombol "Coba lagi"
  memuat ulang; pesan galat tidak menyamar sebagai data.

## Kurangi gerakan

`VisualEffectPolicy.reduceMotion` mematikan gooey, stagger baris, dan pegas
batang; crossfade singkat tetap ada agar pergantian konten tidak terasa
meloncat. Indikator `GooeySelector` bergeser linear 150 ms pada kondisi ini.
Fungsi layar tidak pernah bergantung pada efek visual.

## Aksesibilitas

- Semua kontrol memenuhi area sentuh minimal 44 px; kartu paket dan baris
  leaderboard memakai padding sendiri agar tetap lega.
- Setiap item pemilih adalah tombol semantik dengan status `selected`; panah
  keyboard memindahkan pilihan dan Enter/Space memilih.
- Saklar memakai semantik `toggled`; baris leaderboard punya label peringkat,
  nama, dan nilai.
- Tidak ada informasi yang hanya disampaikan lewat warna.

## Tes

| Berkas | Jumlah | Cakupan |
| --- | --- | --- |
| `test/widget/paywall_page_test.dart` | 7 | Harga dari konfigurasi, pembelian, kelola, tanpa konfigurasi, pulihkan, flag lencana, indikator mengikuti tinggi kartu |
| `test/widget/route_weather_page_test.dart` | 8 | Cache offline, atribusi, galat, tab hari, pegas batang, kurangi gerakan |
| `test/widget/route_estimate_page_test.dart` | 7 | Estimasi dan itinerary |
| `test/widget/advanced_analytics_page_test.dart` | 6 | Analitik dari sesi lokal, rentang, crossfade, sheet, galat |
| `test/widget/annual_recap_page_test.dart` | 9 | Rekap, saklar, lencana di balik flag |
| `test/widget/manage_subscription_page_test.dart` | 11 | Kelola, cadangan dummy, saklar, status |
| `test/widget/leaderboard_page_test.dart` | 10 | Papan nasional/grup, persetujuan, lapor/blokir, galat, flag mati, stagger, kurangi gerakan |
| `test/unit/leaderboard_test.dart` | 19 | Model papan, label nilai, demo/debug, penyimpanan persetujuan |
| `test/widget/plus_gate_test.dart` | 4 | Gerbang fitur dan pembelian membuka isi |
| `test/design/gooey_selector_test.dart` + `gooey_switch_test.dart` | 13 | Geometri, warna, kurangi gerakan, semantik, keyboard |
| Golden gooey | 2 | Terang dan malam |

Seluruh suite saat dokumen ini ditulis: **564 tes lulus**, analyzer bersih
(`flutter analyze lib test`).

## Sudah dijalankan dan yang belum

Sudah dijalankan: seluruh tes unit/widget/golden di atas dengan font Plus
Jakarta Sans asli di mesin pengembangan Windows; analyzer bersih.

Belum diuji: pembayaran nyata, konfigurasi/leaderboard server nyata, perilaku
token produksi, TalkBack, ukuran teks besar, tablet, iOS, dan target 60 fps
pada perangkat menengah. Hasil percobaan emulator dicatat di laporan verifikasi
utama; pengamatan emulator bukan pengganti uji perangkat sungguhan.
