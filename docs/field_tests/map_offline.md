# Uji lapangan: peta Mapbox, offline, kompas, dan deteksi keluar jalur

Status dokumen: **RENCANA UJI. BELUM ADA SKENARIO YANG DIJALANKAN DI
PERANGKAT NYATA. SEMUA ITEM BERSTATUS "BELUM DIUJI".**

Tes otomatis hanya memverifikasi logika domain, parser, controller, dan widget
dengan data palsu. Tes tersebut tidak membuktikan peta Mapbox, unduhan offline,
sensor kompas, GPS, atau atribusi bekerja di perangkat.

## Aturan pencatatan

- Gunakan status `BELUM DIUJI`, `LULUS`, atau `GAGAL`; jangan menulis "lulus"
  tanpa bukti perangkat.
- Catat tanggal, lokasi, cuaca, merek/model, versi OS/ROM, versi build,
  koneksi (Wi-Fi/seluler), penyimpanan kosong, dan level baterai.
- Simpan bukti: tangkapan layar peta dan atribusi, rekaman progres unduhan,
  `adb logcat`, tangkapan mode pesawat, dan catatan jarak/jalur.
- Untuk uji biaya, catat tanggal, akun Mapbox, dan angka MAU/penggunaan di
  dashboard Mapbox sebelum dan sesudah sesi. Jangan menyimpulkan biaya dari
  jumlah tile aplikasi.
- Uji area pendek yang aman dan dikenal. Jangan memakai jalur pendakian nyata
  untuk eksperimen berisiko.

## Prasyarat build

- [ ] BELUM DIUJI: token publik Mapbox dengan scope minimal tersedia dan tidak
      di-commit.
- [ ] BELUM DIUJI: build debug/release dipasang dengan
      `--dart-define=MAPBOX_ACCESS_TOKEN=...`.
- [ ] BELUM DIUJI: `flutter analyze` dan seluruh tes otomatis lulus pada
      commit yang diuji (repositori ini belum memiliki git).
- [ ] BELUM DIUJI: katalog berisi minimal satu paket nyata yang sudah
      diverifikasi, dengan jalur yang berada di dalam batas area.
- [ ] BELUM DIUJI: perangkat Android dan iPhone fisik tersedia untuk matriks
      di `docs/field_tests/tracking_gps.md` (D1 dan D10 minimal).

## Matriks perangkat minimum

| ID | Perangkat | Fokus peta/offline |
| --- | --- | --- |
| M1 | Android stok (Pixel/AOSP) | baseline Mapbox, offline, atribusi |
| M2 | Xiaomi/Redmi/POCO | hemat baterai saat mengunduh, penyimpanan |
| M3 | Samsung One UI | mode pesawat, render peta |
| M4 | iPhone fisik | kompas iOS, background, offline |

Semua baris BELUM DIUJI.

## MAP-01: peta tampil dan token terbaca

Langkah:
1. Pasang build dengan token publik.
2. Buka menu "Peta & Offline".
3. Tunggu style `Outdoors` termuat.
4. Geser dan zoom peta.

Hasil yang diharapkan:
- Peta tampil, bukan kartu "Peta belum dikonfigurasi".
- Interaksi geser/zoom berjalan wajar.
- Tidak ada pesan galat style/token.

Status: **BELUM DIUJI**.

## MAP-02: atribusi terlihat, termasuk saat offline

Langkah:
1. Perhatikan sudut peta: logo Mapbox, teks © Mapbox/© OpenStreetMap, dan
   tautan "Improve this map".
2. Buka panel bawah dan pastikan tidak menutupi ornamen.
3. Unduh satu paket (MAP-04), aktifkan mode pesawat, buka peta lagi.
4. Periksa atribusi saat memakai tile offline.

Hasil yang diharapkan:
- Semua atribusi wajib terlihat dan dapat ditekan.
- Tidak ada overlay aplikasi yang menutupi sudut atribusi.
- Atribusi tetap ada saat offline.

Status: **BELUM DIUJI**.

## MAP-03: memilih paket dan melihat estimasi sebelum unduh

Langkah:
1. Pilih paket gunung dari daftar.
2. Catat area, rentang zoom, dan perkiraan jumlah tile yang tampil.
3. Tunggu estimasi byte SDK selesai.
4. Bandingkan dengan batas paket dan batas aplikasi.

Hasil yang diharapkan:
- Kamera mengarah ke batas area paket.
- Zoom dan area tidak melebihi batas paket/aplikasi.
- Perkiraan tile dan estimasi byte adalah dua angka berbeda dengan label jelas.
- Tombol unduh nonaktif bila ada pelanggaran batas.

Status: **BELUM DIUJI**.

## MAP-04: batas area/zoom/tile menolak paket berlebih

Gunakan salinan katalog uji lokal (jangan commit data fiktif ke rilis):
1. Buat paket dengan zoom di luar 8-16, area > 250 km², atau `max_tiles` >
   5.000.
2. Buka aplikasi dan coba muat katalog tersebut.

Hasil yang diharapkan:
- Katalog ditolak dengan pesan yang menyebut pelanggaran.
- Tidak ada panggilan estimasi/unduhan untuk paket yang ditolak.
- Aplikasi tidak crash.

Status: **BELUM DIUJI**.

## MAP-05: unduhan offline di Wi-Fi

Prasyarat: satu paket nyata dengan area kecil dan zoom rendah.

Langkah:
1. Di Wi-Fi, pilih paket dan catat estimasi transfer/penyimpanan.
2. Tekan "Unduh paket".
3. Catat progres style pack dan tile region, waktu, serta ukuran aktual di
   penyimpanan perangkat.
4. Setelah selesai, tutup dan buka kembali layar peta.

Hasil yang diharapkan:
- Progres bertambah dan tidak macet tanpa pesan.
- Kegagalan resource dilaporkan sebagai gagal, bukan "selesai".
- Setelah selesai, peta tetap dapat dibuka pada area tersebut.
- Tidak ada klaim bahwa seluruh tile diverifikasi ulang oleh aplikasi.

Status: **BELUM DIUJI**.

## MAP-06: mode pesawat dan data offline

Langkah:
1. Setelah MAP-05 selesai, aktifkan mode pesawat.
2. Buka area paket dan geser di dalam batas area.
3. Geser ke luar area paket.
4. Ulangi setelah menghapus cache/aplikasi (untuk memastikan yang dipakai
   benar-benar region offline).

Hasil yang diharapkan:
- Area yang diunduh tetap tampil saat offline.
- Area di luar unduhan boleh kosong; UI tidak menyesatkan.
- Atribusi tetap terlihat.
- Tidak ada klaim bahwa seluruh area Indonesia tersedia offline.

Status: **BELUM DIUJI**.

## MAP-07: data offline tidak memperbarui otomatis

Langkah:
1. Catat waktu unduhan paket.
2. Tunggu lebih dari satu siklus pembaruan data.
3. Buka peta tanpa mengunduh ulang.

Hasil yang diharapkan:
- Aplikasi tetap memakai data offline lama.
- Tidak ada pembaruan otomatis yang tersembunyi.
- Pengguna dapat mengunduh ulang secara manual setelah membuka halaman.

Status: **BELUM DIUJI**.

## MAP-08: batas 750 tile pack

Langkah:
1. Di akun uji, unduh beberapa region sampai mendekati 750 tile pack unik.
2. Catat pesan SDK saat batas tercapai.
3. Jangan mengubah batas akun produksi tanpa persetujuan.

Hasil yang diharapkan:
- SDK menolak unduhan melewati 750 tile pack.
- Aplikasi menampilkan galat, bukan mengklaim selesai.
- Catatan biaya dan kontak Mapbox disiapkan bila perlu batas lebih tinggi.

Status: **BELUM DIUJI** dan berisiko biaya; hanya lakukan di akun uji.

## MAP-09: layer jalur dari GeoJSON

Langkah:
1. Pilih paket dengan satu jalur terverifikasi dan satu jalur belum
   terverifikasi (bila tersedia).
2. Amati layer jalur di peta.
3. Baca panel deteksi keluar jalur.

Hasil yang diharapkan:
- Jalur tampil sebagai garis sesuai properti GeoJSON.
- Jalur `verified=false` diberi label "Belum terverifikasi"; jalur
  `verified=true` baru boleh berlabel terverifikasi bila bukti ada.
- Sumber jalur ditampilkan.

Status: **BELUM DIUJI**.

## MAP-10: layer jejak dari sesi rekaman

Langkah:
1. Rekam sesi GPS singkat (lihat `docs/field_tests/tracking_gps.md`).
2. Buka "Peta & Offline" saat sesi masih aktif.
3. Berjalan beberapa meter dan tunggu pembaruan polling (5 detik).
4. Pilih trail yang dekat dengan posisi.

Hasil yang diharapkan:
- Jejak rekaman tampil sebagai garis dan bertambah mengikuti titik baru.
- Titik terakhir yang dipakai deteksi sesuai titik terbaru di sesi.
- Tidak ada kebocoran timer atau panggilan berulang setelah halaman ditutup.

Status: **BELUM DIUJI**.

## MAP-11: kompas dan koreksi manual

Langkah:
1. Bandingkan heading aplikasi dengan kompas fisik/acuan yang diketahui di
   area terbuka.
2. Gerakkan perangkat membentuk angka 8 sesuai panduan OS.
3. Buka "Kalibrasi manual", masukkan arah acuan yang benar, simpan.
4. Tutup dan buka kembali aplikasi; periksa koreksi tersimpan.
5. Reset koreksi.

Hasil yang diharapkan:
- Heading dan akurasi tampil; pesan akurasi Android tidak dilebih-lebihkan.
- Koreksi manual menggeser heading dan tersimpan di SharedPreferences.
- UI menyatakan ini bukan kalibrasi sensor.
- Reset mengembalikan offset ke 0.

Status: **BELUM DIUJI**.

## MAP-12: deteksi keluar jalur

Langkah:
1. Pilih jalur pendek yang aman dan dikenal.
2. Berjalan di jalur sekitar 100 m; catat status.
3. Menyimpang > 50 m dari jalur selama minimal 3 titik GPS.
4. Kembali ke < 30 m.
5. Catat akurasi GPS dan setiap peringatan palsu.

Hasil yang diharapkan:
- Status berubah ke "Di luar jalur" setelah 3 titik, bukan satu titik.
- Status kembali ke "Di jalur" setelah jarak < 30 m.
- Jarak dan akurasi ditampilkan.
- Aplikasi tidak mengklaim ini alarm keselamatan.

Status: **BELUM DIUJI**.

## MAP-13: biaya dan kuota setelah sesi

Langkah:
1. Catat dashboard Mapbox (MAU/penggunaan) sebelum dan sesudah uji.
2. Catat pemakaian data seluler perangkat selama unduhan.
3. Catat ukuran penyimpanan region.
4. Verifikasi tarif dan ketentuan offline di akun Mapbox.

Hasil yang diharapkan:
- Tidak ada klaim biaya yang tidak didukung dashboard/kontrak.
- Batas 25.000 MAU gratis dan tarif diperiksa ulang pada tanggal uji.
- Bila ada konflik dokumen penagihan offline, dicatat dan dikonfirmasi ke
  Mapbox.

Status: **BELUM DIUJI**.
