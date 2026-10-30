# Altracq

Aplikasi pendampingan pendakian gunung untuk Android dan iOS: **pelacakan**, **peta topografi offline**, **navigasi jalur**, **grup chat pendaki**, dan **SOS** — dirancang agar tetap berguna di tempat tanpa sinyal seluler.

Blueprint v1.0 · Oktober 2026 · tahap pengembangan · wilayah awal: Jawa Barat

> **Batasan penting (baca dulu).** Altracq adalah alat bantu, bukan pengganti persiapan, perlengkapan, pengalaman, registrasi pendakian resmi, atau layanan pencarian dan pertolongan (SAR).
> **SOS tidak menjamin bantuan datang** — pengirimannya bergantung pada ketersediaan jaringan, baterai, dan perangkat. Aplikasi tidak pernah mengklaim telah menghubungi Basarnas.
> Perkiraan kalori adalah estimasi. Data jalur dan peta dapat berubah serta dapat mengandung ketidakakuratan; keputusan navigasi tetap tanggung jawab pengguna.

---

## Masalah yang diselesaikan

- Sinyal seluler tidak merata di gunung — aplikasi yang bergantung internet berhenti berfungsi tepat saat dibutuhkan.
- Rombongan sering terpisah; anggota yang tertinggal atau salah jalur sulit ditemukan tanpa catatan posisi terakhir.
- Informasi jalur, pos, dan sumber air tersebar di komunitas dan sering tidak terverifikasi.
- Laporan darurat tidak terstruktur: koordinat, kondisi korban, dan waktu kontak terakhir sering tidak lengkap.
- Baterai terbatas; aplikasi boros daya membuat HP mati lebih cepat.

## Prinsip rancangan

1. **Offline-first.** Antarmuka hanya membaca dan menulis database lokal (SQLite melalui drift). Jaringan diurus layanan latar belakang, bukan layar.
2. **Satu log, banyak jalur pengiriman.** Pesan disimpan sebagai log per-penulis (penulis, nomor urut). Internet (Rilis 1), BLE mesh (Rilis 2), dan hotspot lokal (Rilis 3) hanyalah cara memindahkan log yang sama.
3. **Tidak ada pesan hilang karena tidak ada koneksi.** Semua yang gagal dikirim masuk antrean `outbox` berprioritas dan dicoba ulang.
4. **Status jujur.** Antarmuka hanya menampilkan "terkirim" bila benar-benar terkirim, dengan tangga status: *Tersimpan di HP* → *Diterima N anggota* → *Diteruskan ke server* → *Sampai ke kontak darurat*.
5. **Privasi lokasi dikontrol pengguna.** Siapa yang melihat, sampai kapan, tombol berhenti berbagi, dan opsi menyembunyikan titik awal/akhir pada kartu berbagi.
6. **Hemat daya.** Profil daya adaptif: Normal (>40%), Hemat (20–40%), Kritis (<20%). Level baterai dibagikan ke grup agar anggota yang kritis mudah dikenali.

## Fitur

Prioritas: **P0** inti keselamatan · **P1** nilai tinggi · **P2** pelengkap.

| Area | Fitur | Prioritas |
|---|---|---|
| Pelacakan | Metrik real-time dari GPS: jarak, waktu bergerak, pace, kecepatan vertikal, kalori (estimasi) | P0 |
| Pelacakan | Elevasi & grafik: total tanjakan/turunan, profil ketinggian, barometer digabung GPS | P1 |
| Pelacakan | Penghitung langkah dari sensor internal HP | P1 |
| Peta & rute | Posisi pengguna real-time + mode ikuti posisi | P0 |
| Peta & rute | Peta topografi offline per gunung, jejak digambar di peta | P0 |
| Peta & rute | Kompas: arah HP, kalibrasi, bearing dan jarak ke target | P0 |
| Peta & rute | Jalur, basecamp, pos, sumber air, area berbahaya + deteksi keluar jalur + navigasi kembali menyusuri jejak sendiri | P1 |
| Keselamatan | Lokasi terakhir tiap anggota, disinkronkan ke kontak darurat dan server saat ada sinyal | P0 |
| Keselamatan | SOS: tekan-tahan ±3 detik, hitung mundur dengan opsi batal, kategori (CEDERA/TERSESAT/CUACA), kirim ulang sampai ada ACK, nomor **Basarnas 115** dan **darurat 112** sebagai tombol panggil | P0 |
| Grup | Buat grup dan undang lewat username; undangan harus diterima yang diundang | P0 |
| Grup | Pesan teks (dengan batas panjang untuk efisiensi) | P0 |
| Grup | Berbagi lokasi dengan kontrol siapa yang melihat dan kapan berhenti | P0 |
| Grup | SOS ke grup sebagai tipe pesan berprioritas tertinggi | P0 |
| Grup | Pesan suara dan gambar terkompresi (gambar penuh menyusul saat koneksi lebih baik) | P1 |
| Berbagi | **Kartu Pendakian**: PNG transparan berisi jarak, rute, dan kecepatan; opsi menyembunyikan titik awal dan akhir | P2 |

Video **tidak** termasuk cakupan.

## Layar

Sepuluh layar menjadi sumber kebenaran tampilan dan alur:

1. **Splash** — menyiapkan data lokal di HP.
2. **Beranda** — sapaan + baterai, kartu pendakian berikutnya, grid fitur, kartu SOS.
3. **Siap Naik** — kesiapan rombongan: centang per anggota (kunci grup diterima, peta terunduh, izin aktif), kontak darurat, tombol mulai pendakian.
4. **Pelacakan** — berjalan tanpa sinyal: timer, enam metrik, grafik elevasi, jeda/selesai, indikator profil daya.
5. **Peta Offline** — peta topografi, jalur terverifikasi, posisi pengguna, pos, sumber air, kompas, mode ikuti, panel pos berikutnya, kembali menyusuri jejak.
6. **Grup Chat** — strip lokasi anggota (termasuk baterai kritis), bubble pesan, kartu berbagi lokasi, pesan suara, status pengiriman bertingkat.
7. **SOS** — hitung mundur 3 detik, "Batal, saya aman", kategori, tangga status yang jujur, tombol 115/112, penafian.
8. **Kartu Pendakian** — ringkasan pendakian di atas foto, tiga gaya (Profil, Tengah, Peta), ekspor PNG transparan, simpan dan bagikan.
9. **Profil (belum masuk)** — statistik lokal, manfaat akun, masuk dengan Google atau Apple.
10. **Profil (sudah masuk)** — identitas, statistik, kontak darurat, peta terunduh, profil daya, privasi lokasi, tampilan (terang/gelap/ikuti sistem), keluar, hapus akun.

## Teknologi

| Bidang | Pilihan |
|---|---|
| Aplikasi | Flutter (satu basis kode Android dan iOS) |
| Kode native | Kotlin dan Swift untuk layanan latar belakang; di Rilis 2 juga BLE peripheral |
| Lokasi & sensor | `geolocator`, `flutter_compass`, `pedometer`, `sensors_plus`, `battery_plus` |
| Peta | Mapbox Maps SDK v11 dengan unduhan offline per gunung |
| Database lokal | SQLite melalui `drift` |
| Backend | Supabase (akun, direktori kunci publik, undangan, relay SOS, cadangan jejak) |
| Autentikasi | Google dan Apple OAuth dengan alur PKCE |
| Notifikasi | FCM dan APNs |
| SMS/WhatsApp | Gateway pihak ketiga, dikirim dari server (penyedia belum dipilih) |
| Kriptografi | X25519 (pertukaran kunci), Ed25519 (tanda tangan), ChaCha20-Poly1305 (enkripsi) |

**Backend sengaja tipis.** Tugasnya: akun dan username unik, direktori username → kunci publik, pengiriman undangan dan status terima/tolak, penyimpanan sementara blob kunci grup terenkripsi untuk anggota yang belum online, menerima SOS serta lokasi terakhir lalu meneruskannya ke kontak darurat dan grup, dan cadangan/sinkronisasi jejak. **Backend tidak membaca isi pesan**; enkripsi end-to-end dipegang di perangkat.

**Data jalur milik sendiri.** Jalur, basecamp, pos, sumber air, dan area berbahaya disimpan sebagai GeoJSON berversi di dalam aplikasi dan digambar di atas peta — tidak terikat penyedia peta, kecil, dan dapat diperbarui terpisah. Label "jalur terverifikasi" hanya diberikan setelah verifikasi lapangan, disertai tanggal verifikasi dan peringatan bahwa kondisi jalur dapat berubah.

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
tools/               skrip bootstrap, pemasangan dependensi, dan seluruh tes
```

## Menjalankan

Prasyarat: Flutter stable (sudah menyertakan Dart), Python 3, JDK 17+ untuk Android, dan Android SDK atau Xcode untuk menjalankan di perangkat.

```bash
./tools/bootstrap.sh      # siapkan android/ios dan pasang dependensi
./tools/test_all.sh       # analisis + seluruh tes + validasi data jalur

cd app
flutter run -d <device-id> \
  --dart-define-from-file=../keys.local.json   # lihat di bawah
```

`keys.local.json` **tidak** ada di repo (masuk `.gitignore`) dan berisi kredensial publik milikmu:

```json
{
  "SUPABASE_URL": "https://<proyek>.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_...",
  "MAPBOX_ACCESS_TOKEN": "pk...."
}
```

Tanpa berkas itu aplikasi tetap berjalan penuh secara offline; hanya akun, undangan grup, dan penerusan SOS yang nonaktif. Jangan pernah memakai `service_role`/`sb_secret_...` di aplikasi.

Migrasi backend: jalankan `backend/migrations/0001_init.sql` lalu `0002_auth_groups.sql` pada proyek Supabase (SQL editor atau `supabase db push`). Aktifkan penyedia OAuth Google/Apple di dasbor Supabase dan daftarkan redirect `id.nama.namaapp://login-callback`.

> Nama paket `id.nama.nama_app` dan direktori `nama_app` masih placeholder; ganti sebelum rilis.

## Status verifikasi

Pemisahan tegas antara yang sudah dijalankan dan yang baru ditulis.

**Sudah dijalankan dan lulus**

- Seluruh tes otomatis: 163 tes aplikasi, 23 tes `mesh_protocol`, 7 tes `geo_utils`; analyzer bersih.
- `data_pipeline/scripts/validate_trails.py` lolos untuk data contoh dan gagal untuk data rusak.
- APK debug dibangun, dipasang, dan diuji di emulator Android: perekaman jejak → titik GPS tersimpan → sesi selesai; baris database memakai stempel waktu UTC.
- Migrasi `0001` dan `0002` diterapkan pada proyek Supabase (diperiksa lewat REST dan RPC).
- Inisialisasi Supabase di aplikasi berhasil dengan kredensial publishable.

**Ditulis tetapi belum teruji**

- Login Google/Apple ujung-ke-ujung (penyedia OAuth belum diaktifkan di dasbor Supabase).
- Tile peta Mapbox di emulator masih kosong; perlu diuji di perangkat nyata.
- Pelacakan latar belakang durasi panjang, perilaku saat layar terkunci, dan lintas merek Android.
- Seluruh sisi iOS (belum ada perangkat/Xcode untuk verifikasi).
- Build release/AOT, keystore, dan penandatanganan aplikasi.
- Alur SOS nyata, penerusan ke kontak darurat, dan uji lapangan.
- Mesh BLE (Rilis 2) — yang ada baru paket protokol murninya, belum ada `BleTransport`.
- **Kriptografi belum diaudit.** Pembungkusan kunci grup adalah rancangan sendiri; jangan dianggap setara enkripsi end-to-end yang sudah ditinjau ahli keamanan.

## Keamanan dan privasi

- Identitas: pasangan kunci dibuat di perangkat; kunci publik terdaftar di direktori server.
- Grup: kunci grup dibagikan hanya setelah undangan diterima, terenkripsi dengan kunci publik penerima. Mengeluarkan anggota atau kehilangan perangkat memicu rotasi kunci.
- Pencarian username harus persis (tanpa pencarian terbuka), ada pembatasan jumlah undangan, tombol blokir/lapor, dan masa berlaku undangan.
- Rincian, sisa risiko, dan daftar yang **wajib** ditinjau ahli keamanan sebelum pilot: `docs/security_review.md` dan `docs/threat_model.md`.
- Keputusan arsitektur: `docs/adr/` (jangan diubah tanpa ADR baru).

## Rencana rilis

| Fase | Perkiraan | Hasil utama |
|---|---|---|
| 0. Fondasi & pembuktian risiko | Nov 2026 | Spike BLE, akun layanan, pilihan gunung pilot, kontak pengelola, wireframe |
| 1. Inti offline | Des 2026 – Feb 2027 | Pelacakan, elevasi, langkah, peta offline, kompas, jalur, layanan latar belakang |
| 2. Akun, grup, SOS via server | Feb – Apr 2027 | Akun, undangan terima/tolak, chat teks, lokasi terakhir, SOS ke kontak darurat |
| 3. Media, berbagi, beta tertutup | Apr – Mei 2027 | Suara dan gambar, kartu berbagi, beta 10–20 pendaki |
| 4. Uji lapangan & pilot | Mei – Jul 2027 | Uji keselamatan nyata, rilis pilot terbatas di satu gunung Jawa Barat |
| 5. Rilis 2 | Agu – Okt 2027 | Mesh BLE (jika spike lulus), gunung tambahan |
| 6. Rilis 3 | Q4 2027+ | Mode kumpul via hotspot, integrasi pengelola dan SAR |

Gerbang keputusan: akhir Fase 0 (apakah BLE lintas platform layak), akhir Fase 3 (kualitas beta), akhir Fase 4 (kriteria keselamatan untuk pilot publik).

Mesh Bluetooth adalah **janji bersyarat**: jangkauannya bergantung pada kepadatan pendaki di sekitar dan kami tidak menjanjikan jangkauan kilometer. Jika spike gagal, Rilis 2 dialihkan ke gateway atau LoRa tanpa mengubah fondasi aplikasi.

## Desain antarmuka

- Token warna terang: latar `#F6F3ED`, primer `#313851`, sekunder `#C2CBD3`, teks sekunder `#5B6275`, permukaan kaca `#FBF9F5`, peringatan `#B3412F` (hanya untuk SOS dan baterai kritis).
- Mode gelap dengan palet terbalik: latar `#313851`, primer/teks `#F6F3ED`, sekunder `#4B5573`, teks sekunder `#A9B0C2`, peringatan `#E0705C`. Pilihan Terang/Gelap/Ikuti sistem disimpan lokal dan diterapkan tanpa memulai ulang.
- Tipografi Plus Jakarta Sans (400/500/700/800), ikon garis 1,8 px dengan ujung membulat, area sentuh minimal 44 px, kontras minimal 4,5:1.
- *Liquid glass* (`BackdropFilter` nyata) pada navbar, kartu, panel peta, dan tombol sekunder, dengan fallback tanpa blur untuk perangkat lemah serta profil daya Hemat/Kritis.
- *Gooey UI* (metaball: blur lalu ambang alpha) pada navbar dan tombol utama/berpasangan. Efek ini **selalu** opsional: mati saat sistem meminta kurangi animasi, saat profil daya Hemat/Kritis, atau di perangkat lemah, dan tidak pernah dipakai pada kontrol SOS. Fungsi tidak boleh bergantung pada efek.

## Lisensi dan atribusi

- Font Plus Jakarta Sans: SIL Open Font License 1.1 (berkas lisensi disertakan di `app/assets/fonts/`).
- Peta dan tile: Mapbox — atribusi wajib ditampilkan di aplikasi; lisensi data dan biaya unduhan offline harus diverifikasi sebelum produksi.
- Blueprint proyek adalah dokumen internal tim; bagian bertanda `[isi]` harus dilengkapi sebelum dibagikan ke pihak luar.
