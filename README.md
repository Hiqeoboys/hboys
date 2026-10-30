# Altracq

Aplikasi teman mendaki gunung untuk Android dan iOS. Isinya pelacakan, peta topografi offline, navigasi jalur, chat grup, dan SOS. Semuanya dibuat supaya masih bisa dipakai di tempat yang tidak ada sinyal.

Blueprint v1.0, Oktober 2026. Masih tahap pengembangan, wilayah awal Jawa Barat.

> **Baca ini dulu.** Altracq cuma alat bantu. Ia tidak menggantikan persiapan, perlengkapan, pengalaman, registrasi pendakian resmi, atau tim SAR.
> SOS tidak menjamin bantuan datang. Pesannya baru terkirim kalau jaringan, baterai, dan perangkatnya mendukung. Aplikasi tidak pernah mengklaim sudah menghubungi Basarnas.
> Kalori hanya perkiraan. Data jalur dan peta bisa berubah dan bisa saja keliru, jadi keputusan navigasi tetap di tangan pengguna.

---

## Kenapa dibuat

- Sinyal di gunung putus-putus. Aplikasi yang butuh internet justru mati saat paling dibutuhkan.
- Rombongan gampang terpisah, dan sulit mencari anggota yang tertinggal atau salah jalur kalau tidak ada catatan posisi terakhirnya.
- Info soal jalur, pos, dan sumber air tersebar di grup komunitas dan sering tidak jelas benar-tidaknya.
- Laporan darurat biasanya berantakan. Koordinat, kondisi korban, dan waktu terakhir kontak sering tidak lengkap.
- Baterai HP terbatas, dan aplikasi yang boros daya bikin HP cepat mati.

## Cara berpikir di balik rancangannya

1. **Offline dulu.** Layar hanya membaca dan menulis ke database lokal (SQLite lewat drift). Urusan jaringan ditangani layanan di latar belakang, bukan oleh layar.
2. **Satu log, beberapa jalur kirim.** Pesan disimpan sebagai log per penulis (penulis + nomor urut). Internet (Rilis 1), BLE mesh (Rilis 2), dan hotspot lokal (Rilis 3) hanya cara berbeda untuk memindahkan log yang sama.
3. **Pesan tidak boleh hilang gara-gara tidak ada koneksi.** Yang gagal terkirim masuk ke antrean `outbox` berprioritas dan dicoba lagi nanti.
4. **Status apa adanya.** Aplikasi baru menulis "terkirim" kalau memang sudah terkirim. Urutannya: Tersimpan di HP, Diterima N anggota, Diteruskan ke server, Sampai ke kontak darurat.
5. **Lokasi di tangan pengguna.** Pengguna menentukan siapa yang boleh melihat, sampai kapan, kapan berhenti berbagi, dan bisa menyembunyikan titik awal dan akhir di kartu berbagi.
6. **Hemat daya.** Ada tiga profil: Normal (di atas 40%), Hemat (20–40%), dan Kritis (di bawah 20%). Level baterai ikut dibagikan ke grup supaya anggota yang hampir mati gampang dikenali.

## Fitur

P0 = inti keselamatan, P1 = nilai tinggi, P2 = pelengkap.

| Area | Fitur | Prioritas |
|---|---|---|
| Pelacakan | Metrik real-time dari GPS: jarak, waktu bergerak, pace, kecepatan vertikal, kalori (perkiraan) | P0 |
| Pelacakan | Elevasi dan grafik: total tanjakan/turunan, profil ketinggian, barometer digabung GPS | P1 |
| Pelacakan | Hitung langkah dari sensor HP | P1 |
| Peta & rute | Posisi pengguna real-time dan mode ikuti posisi | P0 |
| Peta & rute | Peta topografi offline per gunung, jejak digambar di peta | P0 |
| Peta & rute | Kompas: arah HP, kalibrasi, bearing dan jarak ke target | P0 |
| Peta & rute | Jalur, basecamp, pos, sumber air, area berbahaya, deteksi keluar jalur, dan navigasi balik lewat jejak sendiri | P1 |
| Keselamatan | Lokasi terakhir tiap anggota, disinkronkan ke kontak darurat dan server begitu ada sinyal | P0 |
| Keselamatan | SOS: tekan tahan sekitar 3 detik, ada hitung mundur yang bisa dibatalkan, kategori (CEDERA/TERSESAT/CUACA), kirim ulang sampai ada ACK, plus tombol panggil ke Basarnas 115 dan darurat 112 | P0 |
| Grup | Buat grup dan undang lewat username. Yang diundang harus menerima dulu | P0 |
| Grup | Pesan teks dengan batas panjang supaya hemat data | P0 |
| Grup | Berbagi lokasi, dengan kontrol siapa yang melihat dan kapan berhenti | P0 |
| Grup | SOS ke grup, dikirim sebagai pesan berprioritas tertinggi | P0 |
| Grup | Pesan suara dan gambar terkompresi (gambar ukuran penuh menyusul saat koneksi lebih baik) | P1 |
| Berbagi | Kartu Pendakian: PNG transparan berisi jarak, rute, dan kecepatan, dengan opsi menyembunyikan titik awal dan akhir | P2 |

Video tidak masuk cakupan.

## Layar

Ada sepuluh layar, dan inilah acuan untuk tampilan dan alurnya:

1. **Splash**: menyiapkan data lokal di HP.
2. **Beranda**: sapaan dan baterai, kartu pendakian berikutnya, grid fitur, kartu SOS.
3. **Siap Naik**: cek kesiapan rombongan. Tiap anggota dicentang (kunci grup sudah diterima, peta sudah diunduh, izin aktif). Ada juga kontak darurat dan tombol mulai pendakian.
4. **Pelacakan**: jalan tanpa sinyal. Berisi timer, enam metrik, grafik elevasi, tombol jeda/selesai, dan indikator profil daya.
5. **Peta Offline**: peta topografi, jalur terverifikasi, posisi pengguna, pos, sumber air, kompas, mode ikuti, panel pos berikutnya, dan navigasi kembali lewat jejak.
6. **Grup Chat**: strip status anggota, bubble pesan, kartu berbagi lokasi, pesan suara, dan status kirim yang jujur sesuai kemampuan saat ini.
7. **SOS**: hitung mundur 3 detik, tombol "Batal, saya aman", pilihan kategori, tangga status, tombol 115/112, dan penafian.
8. **Kartu Pendakian**: ringkasan pendakian di atas foto, tiga gaya (Profil, Tengah, Peta), ekspor PNG transparan, lalu simpan atau bagikan.
9. **Profil (belum masuk)**: statistik lokal, manfaat punya akun, tombol masuk dengan Google atau Apple.
10. **Profil (sudah masuk)**: identitas, statistik, kontak darurat, peta terunduh, profil daya, privasi lokasi, tampilan (terang/gelap/ikuti sistem), keluar, dan hapus akun.

## Teknologi

| Bidang | Pilihan |
|---|---|
| Aplikasi | Flutter (satu basis kode untuk Android dan iOS) |
| Kode native | Kotlin dan Swift untuk layanan latar belakang. Di Rilis 2 ditambah BLE peripheral |
| Lokasi & sensor | `geolocator`, `flutter_compass`, `pedometer`, `sensors_plus`, `battery_plus` |
| Peta | Mapbox Maps SDK v11, dengan unduhan offline per gunung |
| Database lokal | SQLite lewat `drift` |
| Backend | Supabase (akun, direktori kunci publik, undangan, relay SOS, cadangan jejak) |
| Autentikasi | Google dan Apple OAuth dengan PKCE |
| Notifikasi | FCM dan APNs |
| SMS/WhatsApp | Gateway pihak ketiga, dikirim dari server (penyedia belum dipilih) |
| Kriptografi | X25519 (tukar kunci), Ed25519 (tanda tangan), ChaCha20-Poly1305 (enkripsi) |

Backend sengaja dibuat tipis. Tugasnya hanya:

- mengurus akun dan username yang unik,
- menyimpan direktori username ke kunci publik,
- mengirim undangan dan mencatat diterima atau ditolak,
- menyimpan sementara blob kunci grup yang sudah terenkripsi untuk anggota yang belum online,
- menerima SOS dan lokasi terakhir, lalu meneruskannya ke kontak darurat dan grup,
- mencadangkan dan menyinkronkan jejak.

Backend tidak bisa membaca isi pesan. Enkripsi end-to-end dipegang di perangkat.

Data jalur kami simpan sendiri. Jalur, basecamp, pos, sumber air, dan area berbahaya disimpan sebagai GeoJSON berversi di dalam aplikasi, lalu digambar di atas peta. Dengan begitu tidak terikat penyedia peta, ukurannya kecil, dan bisa diperbarui terpisah. Label "jalur terverifikasi" hanya dipasang setelah ada verifikasi lapangan, lengkap dengan tanggalnya dan peringatan bahwa kondisi jalur bisa berubah.

## Struktur repo

```
app/                 aplikasi Flutter (feature-first: domain / application / infrastructure / presentation)
  lib/design/        sistem desain: token warna, tipografi, liquid glass, gooey UI, tema gelap
  lib/features/      splash, home, groups, tracking, map, chat, safety, sharing, auth, profile
  lib/infrastructure/  drift + DAO + repository, lokasi, peta, transport, sync, kripto, daya, Supabase
  test/              uji unit dan widget
  assets/map_packs/  katalog paket peta
packages/
  mesh_protocol/     codec paket 32-byte, fragmentasi, summary vector, relay policy (murni Dart)
  geo_utils/         haversine, bearing, jarak titik-ke-polyline, format koordinat (murni Dart)
backend/             migrasi SQL (tabel + RLS + fungsi RPC) untuk Supabase/Postgres
data_pipeline/       validasi dan pengemasan data jalur (GeoJSON + manifest)
docs/                protokol, ADR, model ancaman, tinjauan keamanan, setup native, templat uji lapangan
tools/               skrip bootstrap, pemasangan dependensi, dan semua tes
```

## Menjalankan

Yang dibutuhkan: Flutter stable (sudah termasuk Dart), Python 3, JDK 17 ke atas untuk Android, dan Android SDK atau Xcode kalau mau jalan di perangkat.

```bash
./tools/bootstrap.sh      # siapkan android/ios dan pasang dependensi
./tools/test_all.sh       # analisis + seluruh tes + validasi data jalur

cd app
flutter run -d <device-id> \
  --dart-define-from-file=../keys.local.json   # lihat di bawah
```

`keys.local.json` tidak ada di repo (sudah masuk `.gitignore`). Isinya kredensial publik milikmu sendiri:

```json
{
  "SUPABASE_URL": "https://<proyek>.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_...",
  "MAPBOX_ACCESS_TOKEN": "pk...."
}
```

Tanpa berkas ini aplikasi tetap jalan penuh secara offline. Yang mati hanya akun, undangan grup, dan penerusan SOS. Jangan pernah memakai `service_role` atau `sb_secret_...` di aplikasi.

Untuk migrasi backend, jalankan `backend/migrations/0001_init.sql` lalu `0002_auth_groups.sql` di proyek Supabase (lewat SQL editor atau `supabase db push`). Setelah itu aktifkan penyedia OAuth Google/Apple di dasbor Supabase dan daftarkan redirect `id.nama.namaapp://login-callback`.

> Nama paket `id.nama.nama_app` dan direktori `nama_app` masih placeholder. Ganti sebelum rilis.

## Status verifikasi

Di sini dipisahkan antara yang sudah benar-benar dijalankan dan yang baru ditulis.

**Sudah dijalankan dan lulus**

- Semua tes otomatis: 341 tes aplikasi, 23 tes `mesh_protocol`, 11 tes `geo_utils`. Analyzer bersih.
- `data_pipeline/scripts/validate_trails.py` lolos untuk data contoh dan gagal untuk data yang sengaja dirusak.
- APK debug sudah dibangun, dipasang, dan dicoba di emulator Android: rekam jejak, titik GPS tersimpan, sesi selesai. Baris database memakai stempel waktu UTC.
- Permukaan kaca navigasi bawah (blur latar + saturasi) terlihat benar di emulator pada mode terang dan gelap, dan otomatis jatuh ke isi pekat saat kebijakan efek mati.
- Efek gooey (metaball) pada pill tab aktif terlihat menyatu sebagai cairan di emulator, dan hilang rapi saat kebijakan mematikan efek.
- Splash selalu biru gelap, menunggu `TrackingController.initialize()` sungguhan dengan durasi tampil minimum 1,4 detik, terlihat di emulator.
- Beranda menampilkan sapaan sesuai jam, baterai asli dari `PowerProfileController`, dan keadaan kosong yang jujur saat belum ada grup; grid 8 fitur dan kartu SOS terlihat di emulator pada mode terang dan gelap.
- Siap Naik memakai data nyata: grup terbaru sebagai pendakian berikutnya, daftar anggota dari server, status kunci grup, izin lokasi, dan kontak darurat dari database lokal. Keadaan tamu dan mode terang/gelap terlihat di emulator.
- Lacak memakai titik GPS nyata dan tersimpan: metrik, grafik ketinggian dari titik tersimpan, serta tombol Mulai/Jeda/Lanjut/Selesai. Di emulator, jeda menghentikan aliran GPS dan membekukan waktu bergerak, lanjut menyalakan kembali aliran sehingga jarak, pace, dan kec. vertikal berubah lagi, dan selesai menutup sesi lewat dialog konfirmasi. Mode terang dan gelap terlihat.
- Angka langkah dan kalori tampil "—" beserta catatan, karena sensor langkah belum dibaca dan berat badan pengguna belum ada. Tidak ada angka contoh.
- Peta memakai desain baru: kartu status jalur, tombol kompas/pusatkan, sheet panduan dengan pil status, sheet offline (katalog kosong yang jujur, estimasi SDK, catatan atribusi), dan sheet kompas dengan koreksi arah manual. Di emulator, sheet offline dan kompas terlihat pada mode terang dan gelap, kompas menampilkan `0° U`, dan logo/atribusi Mapbox tidak tertutup navbar. Kartu panduan disembunyikan saat sheet modal terbuka. Mode gelap menambahkan peredup navy 35% di atas permukaan peta dan menyelaraskan ulang warna layer jalur/jejak/posisi; peredup terlihat di emulator, tetapi gaya peta tidak selesai dimuat karena galat GL, jadi hasil di atas tile asli belum bisa dinilai.
- Atribusi Mapbox tetap tampil: logo dan tombol `ⓘ` terlihat di atas navbar; scale bar bawaan dimatikan karena tidak ada di rancangan dan menabrak status bar.
- Grup Chat memakai grup terbaru dan daftar anggota nyata dari server, dengan bubble pesan dari database perangkat. Pengiriman teks menyimpan pesan UTF-8 secara lokal dan berhenti pada status jujur `Tersimpan di HP · belum terkirim` karena belum ada transport chat. Di emulator, keadaan `Belum masuk` terlihat pada mode terang dan gelap; tata letak chat lengkap diuji lewat 8 tes widget. Rinciannya di `docs/grup_chat.md`.
- SOS memakai layar terbalik biru gelap: tekan-tahan 3 detik, hitung mundur 3 detik, lalu simpan lokal hanya bila ada perbaikan GPS nyata. **Pengamatan emulator berikut berasal dari build sebelum revisi UI gelombang ini**, jadi tombol 115/112 saat itu masih berupa tombol ketuk, bukan trek geser. Di emulator, baris database berisi penanda `perangkat-lokal`, grup kosong, koordinat dan akurasi nyata, status `active`; memilih CEDERA mengubah `category_code`, dan tombol batal menulis status `cancelled` beserta waktunya. Tangga status hanya menyalakan `Tersimpan di HP`; nomor 115 dan 112 membuka aplikasi telepon Android dengan nomor terisi tanpa menelpon. Rinciannya di `docs/sos.md`.
- Kartu Pendakian memakai sesi selesai terbaru dari database perangkat, dengan tiga gaya (Profil, Tengah, Peta), sakelar sembunyikan titik awal/akhir, pemilih foto, ekspor PNG transparan 1080×1350, dan lembar berbagi. Di emulator, ketiga gaya tampil, sakelar menghapus penanda, PNG tersimpan di `Pictures/Altracq` (MediaStore mencatat 1080×1350; berkas terbaca RGBA dengan sudut alfa 0), lembar berbagi terbuka, dan pemilih foto terbuka. Tidak ada pesan "terkirim" setelah berbagi. Rinciannya di `docs/kartu_pendakian.md`.
- Profil tamu memakai data lokal nyata: ringkasan hanya menjumlahkan sesi selesai, dan di emulator tampil **8 pendakian, 14.876 km, 1.469 m** dari database perangkat. Logo Google/Apple resmi tampil dan catatan privasi serta catatan "belum tersedia" terlihat. Profil sudah masuk (identitas, penyedia, lima baris pengaturan, sheet Tampilan, Keluar) baru diuji widget, belum dicoba di perangkat. Rinciannya di `docs/profil.md`.
- Migrasi `0001` dan `0002` sudah diterapkan di proyek Supabase (dicek lewat REST dan RPC).
- Inisialisasi Supabase di aplikasi berhasil dengan kredensial publishable.

**Sudah ditulis, belum diuji**

- Login Google/Apple dari awal sampai akhir. Penyedia OAuth belum diaktifkan di dasbor Supabase.
- Grup Chat dengan grup nyata di perangkat. Penyedia OAuth belum aktif dan belum ada sesi atau grup di emulator, jadi strip anggota, bubble, composer, dan pengiriman lokal baru diuji widget, bukan dicoba di perangkat.
- Pengiriman pesan ke anggota lain, pesan suara, media gambar/berkas, serta pembagian lokasi dan baterai anggota. Pesan teks hanya tersimpan lokal, tombol suara nonaktif, dan kartu lokasi hanya merender payload lokasi yang benar-benar tersimpan.
- Permukaan tile peta Mapbox. Di emulator, permukaan peta tampil hitam atau hanya bayangan terrain dengan galat `GFXSTREAM GL error 0x501`, dan `onStyleLoaded` tidak pernah selesai; warna style, layer jalur, dan kecocokan kamera belum bisa dinilai. Perlu dicoba di perangkat sungguhan.
- Unduhan peta offline nyata. Katalog paket masih kosong dan tidak ada data gunung fiktif yang dibundel, jadi estimasi byte dan unduhan style pack/tile region belum pernah dijalankan; alurnya baru diuji dengan layanan palsu.
- Keterbacaan peta mode gelap di atas tile sungguhan. Gaya tetap `OUTDOORS` agar style pack offline yang diunduh tetap terpakai, ditambah peredup navy 35% dan warna layer yang diselaraskan ulang; karena gaya peta tidak selesai dimuat di emulator, hasilnya di atas tile asli belum bisa dinilai. Rinciannya di `docs/mode_gelap_dan_performa.md`.
- Pelacakan latar belakang untuk durasi panjang, perilaku saat layar terkunci, dan perbedaan antarmerek Android.
- Akumulasi waktu bergerak saat benar-benar berjalan. Di emulator, `adb emu geo fix` melaporkan kecepatan 0 sehingga auto-pause berhenti menambah waktu bergerak setelah beberapa detik; jarak dan pace tetap dihitung dari titik. Perlu uji lapangan dengan GPS sungguhan.
- Status jeda tidak bertahan jika proses layanan dimatikan. Sesi yang dipulihkan kembali dalam keadaan merekam, dan waktu selama jeda tidak dihitung karena celah antar titik melewati batas auto-pause.
- Seluruh sisi iOS, karena belum ada perangkat atau Xcode untuk mengujinya.
- Kartu Pendakian: foto galeri yang benar-benar terdekode dan tampil di kartu (galeri emulator kosong; jalur pemilih foto dan `precacheImage` baru diuji widget), simpan MediaStore di Android 10 ke atas pada perangkat sungguhan (emulator API 37 berhasil), keadaan kosong di perangkat (database emulator sudah berisi sesi), lembar berbagi iOS, dan TalkBack.
- Profil sudah masuk di perangkat. Penyedia OAuth belum aktif, jadi identitas, pil penyedia, lima baris pengaturan, sheet Tampilan, kontak darurat nyata, dan Keluar baru diuji widget. Pembacaan region Mapbox nyata juga belum berjalan karena katalog paket masih kosong. TalkBack dan ukuran teks besar belum diuji.
- Revisi UI/UX gelombang ini di perangkat. Tombol pil solid (Perubahan 1) lulus 8 tes widget dan layar SOS baru (Perubahan 2: tombol tutup 44 px dengan konfirmasi batal, dua trek geser 115/112) lulus 18 tes widget SOS plus 9 tes widget `SlideToCall`, tetapi keduanya belum dilihat di emulator. Perubahan 3–5 (kartu ringkasan dan grid lipat di Beranda, indikator navbar tunggal, peta layar penuh) masih dikerjakan.
- Rasa geser trek SOS di jari: ambang 85%, overshoot saat knob membal, lensa label di dalam knob, dan kekuatan haptic sedang. Semua baru diuji lewat tes widget, belum di perangkat.
- Build release/AOT, keystore, dan penandatanganan aplikasi.
- Penerusan SOS ke anggota, server, atau kontak darurat, serta uji lapangan GPS di dalam hutan. Layar SOS dan penyimpanan lokalnya sudah diuji di emulator; jalur kirimnya belum ada.
- Mesh BLE (Rilis 2). Yang ada baru paket protokolnya saja, belum ada `BleTransport`.
- Kriptografi belum diaudit. Cara pembungkusan kunci grup adalah rancangan sendiri, jadi jangan dianggap setara dengan enkripsi end-to-end yang sudah ditinjau ahli keamanan.
- Pelaporan kesiapan antaranggota belum ada. Status unduhan peta offline kini dibaca dari penyimpanan SDK di perangkat sendiri, tetapi belum dilaporkan ke anggota lain; Siap Naik karena itu hanya menghitung kesiapan perangkat sendiri dan menampilkan "Belum melapor" untuk anggota lain.

## Keamanan dan privasi

- Pasangan kunci identitas dibuat di perangkat. Kunci publiknya didaftarkan ke direktori di server.
- Kunci grup baru dibagikan setelah undangan diterima, dan dienkripsi dengan kunci publik penerima. Kalau anggota dikeluarkan atau perangkat hilang, kunci diganti.
- Pencarian username harus persis, tidak ada pencarian terbuka. Jumlah undangan dibatasi, ada tombol blokir dan lapor, dan undangan punya masa berlaku.
- Detail, risiko yang masih tersisa, dan daftar bagian yang wajib ditinjau ahli keamanan sebelum pilot ada di `docs/security_review.md` dan `docs/threat_model.md`.
- Keputusan arsitektur ada di `docs/adr/`. Jangan diubah tanpa menulis ADR baru.

## Rencana rilis

| Fase | Perkiraan | Hasil utama |
|---|---|---|
| 0. Fondasi dan pembuktian risiko | Nov 2026 | Spike BLE, akun layanan, pilihan gunung pilot, kontak pengelola, wireframe |
| 1. Inti offline | Des 2026 – Feb 2027 | Pelacakan, elevasi, langkah, peta offline, kompas, jalur, layanan latar belakang |
| 2. Akun, grup, SOS via server | Feb – Apr 2027 | Akun, undangan terima/tolak, chat teks, lokasi terakhir, SOS ke kontak darurat |
| 3. Media, berbagi, beta tertutup | Apr – Mei 2027 | Suara dan gambar, kartu berbagi, beta untuk 10–20 pendaki |
| 4. Uji lapangan dan pilot | Mei – Jul 2027 | Uji keselamatan nyata, rilis pilot terbatas di satu gunung Jawa Barat |
| 5. Rilis 2 | Agu – Okt 2027 | Mesh BLE (kalau spike lulus), gunung tambahan |
| 6. Rilis 3 | Q4 2027 ke atas | Mode kumpul lewat hotspot, integrasi dengan pengelola dan SAR |

Ada tiga titik keputusan: akhir Fase 0 (apakah BLE lintas platform memang layak), akhir Fase 3 (apakah kualitas beta cukup), dan akhir Fase 4 (apakah kriteria keselamatan untuk pilot publik terpenuhi).

Mesh Bluetooth masih janji bersyarat. Jangkauannya bergantung pada seberapa banyak pendaki di sekitar, dan kami tidak menjanjikan jangkauan sampai kilometer. Kalau spike gagal, Rilis 2 dialihkan ke gateway atau LoRa tanpa perlu mengubah fondasi aplikasi.

## Desain antarmuka

- Warna mode terang: latar `#F6F3ED`, primer `#313851`, sekunder `#C2CBD3`, teks sekunder `#5B6275`, permukaan kaca `#FBF9F5`, peringatan `#B3412F` (hanya untuk SOS dan baterai kritis).
- Mode gelap memakai palet yang dibalik: latar `#313851`, primer dan teks `#F6F3ED`, sekunder `#4B5573`, teks sekunder `#A9B0C2`, peringatan `#E0705C`. Pilihan Terang/Gelap/Ikuti sistem disimpan lokal dan langsung berlaku tanpa restart. Layar Peta mempertahankan gaya `OUTDOORS` agar paket offline tetap terpakai, dengan peredup navy 35% saat mode gelap.
- Tipografi memakai Plus Jakarta Sans (400/500/700/800), ikon garis 1,8 px dengan ujung membulat, area sentuh minimal 44 px, dan kontras minimal 4,5:1.
- *Liquid glass* (`BackdropFilter` sungguhan) dipakai di navbar, kartu, panel peta, dan tombol sekunder. Untuk perangkat lemah dan profil daya Hemat/Kritis, tersedia fallback tanpa blur.
- *Gooey UI* (metaball: blur lalu ambang alpha) hanya dipakai pada indikator navbar. Semua tombol adalah pil solid dengan tepi bersih; spesifikasi gooey untuk tombol (benjolan tepi dan leher penyambung) dibatalkan. Efek ini selalu opsional: ia mati kalau sistem meminta animasi dikurangi, saat profil daya Hemat/Kritis, atau di perangkat lemah, dan tidak pernah dipasang di kontrol SOS. Fungsi aplikasi tidak boleh bergantung padanya.

## Lisensi dan atribusi

- Font Plus Jakarta Sans memakai SIL Open Font License 1.1. Berkas lisensinya ada di `app/assets/fonts/`.
- Peta dan tile dari Mapbox. Atribusi wajib ditampilkan di aplikasi, dan lisensi data serta biaya unduhan offline harus dicek dulu sebelum produksi.
- Blueprint proyek ini dokumen internal tim. Bagian yang bertanda `[isi]` harus dilengkapi sebelum dibagikan ke pihak luar.
