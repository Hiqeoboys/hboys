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
6. **Grup Chat**: strip lokasi anggota (termasuk yang baterainya kritis), bubble pesan, kartu berbagi lokasi, pesan suara, dan status kirim bertingkat.
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

- Semua tes otomatis: 226 tes aplikasi, 23 tes `mesh_protocol`, 7 tes `geo_utils`. Analyzer bersih.
- `data_pipeline/scripts/validate_trails.py` lolos untuk data contoh dan gagal untuk data yang sengaja dirusak.
- APK debug sudah dibangun, dipasang, dan dicoba di emulator Android: rekam jejak, titik GPS tersimpan, sesi selesai. Baris database memakai stempel waktu UTC.
- Permukaan kaca navigasi bawah (blur latar + saturasi) terlihat benar di emulator pada mode terang dan gelap, dan otomatis jatuh ke isi pekat saat kebijakan efek mati.
- Efek gooey (metaball) pada pill tab aktif terlihat menyatu sebagai cairan di emulator, dan hilang rapi saat kebijakan mematikan efek.
- Splash selalu biru gelap, menunggu `TrackingController.initialize()` sungguhan dengan durasi tampil minimum 1,4 detik, terlihat di emulator.
- Beranda menampilkan sapaan sesuai jam, baterai asli dari `PowerProfileController`, dan keadaan kosong yang jujur saat belum ada grup; grid 8 fitur dan kartu SOS terlihat di emulator pada mode terang dan gelap.
- Siap Naik memakai data nyata: grup terbaru sebagai pendakian berikutnya, daftar anggota dari server, status kunci grup, izin lokasi, dan kontak darurat dari database lokal. Keadaan tamu dan mode terang/gelap terlihat di emulator.
- Migrasi `0001` dan `0002` sudah diterapkan di proyek Supabase (dicek lewat REST dan RPC).
- Inisialisasi Supabase di aplikasi berhasil dengan kredensial publishable.

**Sudah ditulis, belum diuji**

- Login Google/Apple dari awal sampai akhir. Penyedia OAuth belum diaktifkan di dasbor Supabase.
- Tile peta Mapbox. Di emulator masih kosong, jadi perlu dicoba di perangkat sungguhan.
- Pelacakan latar belakang untuk durasi panjang, perilaku saat layar terkunci, dan perbedaan antarmerek Android.
- Seluruh sisi iOS, karena belum ada perangkat atau Xcode untuk mengujinya.
- Build release/AOT, keystore, dan penandatanganan aplikasi.
- Alur SOS yang sebenarnya, penerusan ke kontak darurat, dan uji lapangan.
- Mesh BLE (Rilis 2). Yang ada baru paket protokolnya saja, belum ada `BleTransport`.
- Kriptografi belum diaudit. Cara pembungkusan kunci grup adalah rancangan sendiri, jadi jangan dianggap setara dengan enkripsi end-to-end yang sudah ditinjau ahli keamanan.
- Pelaporan kesiapan antaranggota dan status unduhan peta offline belum ada. Siap Naik karena itu hanya menghitung kesiapan dari perangkat sendiri, menampilkan "Belum melapor" untuk anggota lain, dan tidak mengklaim peta siap sebelum penyimpanan status unduhan dibuat.

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
- Mode gelap memakai palet yang dibalik: latar `#313851`, primer dan teks `#F6F3ED`, sekunder `#4B5573`, teks sekunder `#A9B0C2`, peringatan `#E0705C`. Pilihan Terang/Gelap/Ikuti sistem disimpan lokal dan langsung berlaku tanpa restart.
- Tipografi memakai Plus Jakarta Sans (400/500/700/800), ikon garis 1,8 px dengan ujung membulat, area sentuh minimal 44 px, dan kontras minimal 4,5:1.
- *Liquid glass* (`BackdropFilter` sungguhan) dipakai di navbar, kartu, panel peta, dan tombol sekunder. Untuk perangkat lemah dan profil daya Hemat/Kritis, tersedia fallback tanpa blur.
- *Gooey UI* (metaball: blur lalu ambang alpha) dipakai di navbar dan tombol utama/berpasangan. Efek ini selalu opsional. Ia mati kalau sistem meminta animasi dikurangi, saat profil daya Hemat/Kritis, atau di perangkat lemah, dan tidak pernah dipasang di kontrol SOS. Fungsi aplikasi tidak boleh bergantung padanya.

## Lisensi dan atribusi

- Font Plus Jakarta Sans memakai SIL Open Font License 1.1. Berkas lisensinya ada di `app/assets/fonts/`.
- Peta dan tile dari Mapbox. Atribusi wajib ditampilkan di aplikasi, dan lisensi data serta biaya unduhan offline harus dicek dulu sebelum produksi.
- Blueprint proyek ini dokumen internal tim. Bagian yang bertanda `[isi]` harus dilengkapi sebelum dibagikan ke pihak luar.
