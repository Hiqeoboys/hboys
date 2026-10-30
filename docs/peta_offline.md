# Peta, unduhan offline, dan atribusi Mapbox

Status dokumen: **sebagian diuji otomatis dan terlihat di emulator. Tile peta,
unduhan offline nyata, kompas perangkat fisik, dan uji lapangan BELUM DIUJI.**
Lihat bagian akhir untuk pemisahan yang jelas.

Dokumen ini mencatat batasan resmi Mapbox yang dibaca pada **2026-10-25**
sebelum kode ditulis, lalu aturan yang diterapkan aplikasi.

## 1. Batasan resmi Mapbox

Sumber yang dibaca:

- Halaman harga dan dokumentasi penagihan Mapbox:
  <https://www.mapbox.com/pricing/> dan
  <https://docs.mapbox.com/help/account/pricing/>.
- Panduan offline Android:
  <https://docs.mapbox.com/android/maps/guides/offline/>.
- Panduan atribusi:
  <https://docs.mapbox.com/help/getting-started/attribution/>.

### 1.1 Penagihan Maps SDK Mobile

Maps SDK untuk aplikasi mobile ditagih berdasarkan **monthly active users
(MAU)**, bukan berdasarkan jumlah tile atau jumlah panggilan peta.

| Rentang MAU | Tarif yang tercatat saat dokumen dibuat |
| --- | --- |
| 0 - 25.000 | gratis |
| 25.001 - 125.000 | USD 4,00 per 1.000 MAU |
| 125.001 - 250.000 | USD 3,20 per 1.000 MAU |
| 250.001 - 1.250.000 | USD 2,40 per 1.000 MAU |
| di atas 1.250.000 | hubungi Mapbox |

Catatan penting:

- Angka di atas adalah ringkasan, bukan kutipan kontrak. Tarif, mata uang,
  pajak, dan definisi MAU dapat berubah. **Verifikasi di akun Mapbox dan
  perjanjian tertulis sebelum rilis.**
- Dokumentasi bantuan Mapbox yang dibaca menyatakan sumber daya offline
  termasuk dalam penagihan MAU biasa. Sebagian halaman lama menyebut
  permintaan tile offline ditagih terpisah. Kedua sumber ini **bertentangan**;
  jangan mengambil keputusan biaya berdasarkan dokumen ini. Konfirmasikan ke
  Mapbox atau kontrak akun.
- Batas 750 tile pack di bawah adalah batas teknis SDK, bukan batas
  penagihan. Tidak ada klaim bahwa unduhan offline gratis atau berbayar
  berdasarkan dokumen ini.

### 1.2 Batas teknis offline

- Jumlah **tile pack unik kumulatif** tidak boleh melebihi **750** untuk semua
  region. SDK menolak unduhan yang melewatinya. Batas lebih tinggi harus
  diminta ke Mapbox dan dapat menimbulkan biaya atau persetujuan tambahan.
- Data offline **tidak diperbarui otomatis**. Style pack dan tile region harus
  diunduh ulang/disegarkan secara manual setelah data berubah.
- Data offline tidak boleh dibundel di dalam aplikasi, dipra-muat untuk
  distribusi, atau dibagikan ulang. Pengguna harus mengunduh dari Mapbox.
- Aplikasi memakai dua komponen: **style pack** (style, font/glyph, sprite) dan
  **tile region** (tile untuk area dan rentang zoom tertentu).

### 1.3 Atribusi wajib

Saat peta tampil, termasuk saat memakai data offline:

- Logo Mapbox harus tetap terlihat.
- Teks **© Mapbox**, **© OpenStreetMap**, dan tautan **Improve this map** harus
  tetap tersedia.
- Jangan menutupi ornamen atribusi dengan panel, tombol, atau overlay.

`MapWidget` menampilkan ornamen atribusi bawaannya. Layar peta aplikasi
menempatkan indikator memuat dan pesan galat di **atas** peta, dan tidak
menaruh kontrol di sudut bawah tempat logo/atribusi berada. Scale bar bawaan
dimatikan karena tidak ada di rancangan dan menabrak status bar. Logo Mapbox
dan tombol atribusi `ⓘ` terlihat di atas navbar pada emulator (mode terang dan
gelap), tetapi teks atribusi lengkap dan perilaku saat mode pesawat belum
diuji di perangkat.**

## 2. Batas yang diterapkan aplikasi

Batas keras ada di `app/lib/features/map/domain/map_package.dart`
(`MapGuardrails`):

| Aturan | Nilai |
| --- | --- |
| Zoom minimum | 8 |
| Zoom maksimum | 16 |
| Luas area per paket | maksimum 250 km² |
| Perkiraan jumlah tile per paket | maksimum 5.000 |
| Batas tile pack Mapbox | 750 kumulatif (hanya ditampilkan, tidak dihitung lokal) |

Setiap paket wajib punya `min_zoom`, `max_zoom`, `max_area_km2`, dan
`max_tiles` di katalog. Batas per paket **boleh lebih ketat** dari batas
aplikasi, tetapi tidak boleh lebih longgar. Parser menolak:

- batas area/tile paket yang melebihi batas aplikasi,
- zoom di luar 8-16,
- area atau perkiraan tile aktual yang melebihi batas paket/aplikasi,
- jalur yang keluar dari batas area offline,
- semua koordinat jalur identik.

Batas ini adalah pengaman biaya/penyimpanan tingkat aplikasi, bukan jaminan
tagihan. Batas 750 tile pack tidak dapat dihitung dari jumlah tile.

## 3. Dua jenis estimasi yang berbeda

1. **Perkiraan jumlah tile** (`TileCountEstimator`): hitungan deterministik
   alamat tile Web Mercator yang menutupi `GeoBounds` pada setiap zoom.
   Ditampilkan sebelum unduhan. Ini **bukan** jumlah aset yang benar-benar
   diunduh; Mapbox mengelompokkan tile menjadi tile pack.
2. **Estimasi byte SDK** (`OfflineMapService.estimate`): memanggil
   `TileStore.estimateTileRegion` Mapbox dan mengembalikan perkiraan ukuran
   transfer/penyimpanan beserta margin galat. Estimasi ini memerlukan Mapbox
   aktif dan dapat gagal karena jaringan atau batas SDK.

Keduanya ditampilkan di panel offline. Panel menjelaskan bahwa angka tile
bukan jumlah aset unduhan. Tombol unduh baru aktif setelah rencana lolos
guardrail.

## 4. Alur kode

- Domain dan guardrail: `app/lib/features/map/domain/map_package.dart`
- GeoJSON jalur dan jejak: `app/lib/features/map/domain/track_geojson.dart`
- Antarmuka layanan offline: `app/lib/features/map/application/offline_map_service.dart`
- Pengatur estimasi/unduhan: `app/lib/features/map/application/offline_download_controller.dart`
- Kesiapan offline untuk Siap Naik: `app/lib/features/map/application/offline_readiness.dart`
- Implementasi Mapbox: `app/lib/infrastructure/map/mapbox_offline_map_service.dart`
- Layar peta: `app/lib/features/map/presentation/map_page.dart`
- Sheet pengelolaan offline: `app/lib/features/map/presentation/offline_sheet.dart`
- Sheet kompas: `app/lib/features/compass/presentation/compass_sheet.dart`

Alur unduhan:

1. Pengguna memilih paket secara eksplisit; aplikasi tidak memilih otomatis.
2. Rencana offline dievaluasi dan jumlah tile dihitung.
3. SDK diminta memperkirakan byte. Hasil estimasi lama diabaikan bila
   pengguna berganti paket.
4. Tombol unduh memuat style pack (`OUTDOORS`) lalu tile region dengan id
   `nama_<pack_id>`.
5. Progres style pack dan tile ditampilkan. Bila SDK melaporkan resource
   gagal atau belum lengkap, unduhan dinyatakan gagal.
6. Setelah SDK melaporkan selesai, UI menyatakan "SDK melaporkan unduhan
   selesai pada sesi ini", bukan "seluruh tile terverifikasi".

Aplikasi belum memiliki alur hapus region, pemeriksaan versi data offline,
atau penyegaran otomatis. Mengunduh ulang dapat dilakukan setelah halaman
dibuka kembali, tetapi tidak ada deteksi bahwa data di perangkat sudah usang.

## 5. Format katalog paket

Katalog default: `app/assets/map_packs/catalog.json`. Saat ini berisi
`{"packs": []}`. Aplikasi **tidak membundel data gunung fiktif**.

Contoh bentuk entri (nilai contoh, bukan data nyata yang boleh dirilis):

```json
{
  "packs": [
    {
      "pack_id": "gn_contoh",
      "name": "Gunung Contoh",
      "version": 1,
      "data_date": "2026-10-01T00:00:00Z",
      "verified": false,
      "trails": "assets/map_packs/gn_contoh_trails.geojson",
      "offline": {
        "bounds": {
          "south": -7.55,
          "west": 110.35,
          "north": -7.45,
          "east": 110.45
        },
        "min_zoom": 10,
        "max_zoom": 14,
        "max_area_km2": 120,
        "max_tiles": 3000
      }
    }
  ]
}
```

Aturan validasi:

- `pack_id`: huruf kecil, angka, garis bawah, maksimum 64 karakter.
- `version`: bilangan bulat > 0.
- `data_date`: timestamp ISO-8601; gunakan UTC.
- `verified=true` wajib punya `verified_at` dan `verified_by`;
  `verified=false` tidak boleh punya keduanya.
- `trails` harus menunjuk aset yang bisa dimuat dan berisi
  `FeatureCollection` minimal satu `LineString` dengan minimal dua koordinat
  berbeda.
- Properti tiap fitur: `id`, `name`, `source`, `verified`; `verified=true`
  wajib punya bukti `verified_at`/`verified_by`.
- Semua titik jalur harus berada di dalam `offline.bounds`.

Aset Flutter hanya membundel file yang berada langsung di direktori yang
terdaftar di `pubspec.yaml` (`assets/map_packs/`). Bila jalur GeoJSON
ditempatkan di subdirektori, direktori itu harus ditambahkan ke `pubspec.yaml`.

## 6. Konfigurasi Mapbox

- Token publik diberikan saat menjalankan/membangun aplikasi:

  ```sh
  flutter run --dart-define=MAPBOX_ACCESS_TOKEN=pk.xxxxxxxx
  ```

  Jangan memakai token rahasia (`sk.`) di aplikasi klien dan jangan
  meng-commit token. Batasi scope token di akun Mapbox.
- `bootstrap.dart` memanggil `MapboxOptions.setAccessToken` hanya di
  Android/iOS dan hanya bila token tidak kosong.
- Android memerlukan `INTERNET` dan `ACCESS_NETWORK_STATE`; keduanya sudah
  ditambahkan ke `AndroidManifest.xml`. Tidak ada izin runtime untuk
  keduanya.
- Tanpa token, layar peta menampilkan kartu setup dan tidak membuat
  `MapWidget`, tidak memanggil layanan offline, dan tidak mengunduh apa pun.
- Di luar Android/iOS (misalnya Windows), peta tidak dibuat. Pemilihan jalur,
  kompas, dan deteksi keluar jalur tetap tampil bila katalog berisi data.

APK debug dengan token Mapbox sudah dibangun dan dipasang di emulator Android.
Pemuatan style dan perilaku token di build rilis serta iOS belum diuji.

## 7. Kompas dan deteksi keluar jalur

- `flutter_compass` tidak menyediakan API kalibrasi sensor. Aplikasi hanya
  menyimpan **koreksi arah manual** (offset heading) di
  `SharedPreferences` dengan kunci `compass_heading_offset_deg`.
- Panduan angka 8 adalah panduan OS untuk kalibrasi sensor, bukan fungsi yang
  dijalankan aplikasi. UI menyatakan hal ini secara eksplisit.
- Akurasi Android dilaporkan kasar oleh plugin (nilai hard-coded); UI
  menyebutkan keterbatasan tersebut.
- `OffTrailDetector` memakai histeresis: keluar jalur setelah jarak > 50 m
  selama 3 titik berturut-turut, kembali setelah < 30 m. Ini hanya peringatan
  visual, bukan alarm keselamatan. Akurasi GPS buruk dapat memicu peringatan
  palsu.
- Jejak rekaman diambil dari sesi aktif `TrackingController` dan digambar
  sebagai LineString GeoJSON; jalur paket digambar dari GeoJSON katalog.
  Jalur dengan `verified=false` selalu diberi label belum terverifikasi.
- Heading dibulatkan setelah dinormalisasi supaya 359,7° tampil sebagai 0°,
  bukan 360°. Ada tes regresi untuk ini.

## 8. Sudah dijalankan vs belum diuji

**Sudah dijalankan di mesin pengembang:**

- `flutter analyze lib test` bersih; seluruh suite aplikasi **258 tes lulus**.
  Tes paket terpisah: `geo_utils` 11 lulus, `mesh_protocol` 23 lulus.
- Tes unit: domain paket, estimator tile, guardrail, parser katalog, GeoJSON
  jalur/jejak, pengatur unduhan (termasuk perlombaan status-vs-estimasi),
  matematika kompas (termasuk pembulatan 359,7° → 0°), kesiapan offline, dan
  pemulihan sesi.
- Tes widget `offline_sheet_test.dart` (7 tes): katalog kosong yang jujur
  tanpa panggilan estimasi/status, teks "Belum diunduh di perangkat ini.",
  format estimasi SDK, unduhan selesai dengan catatan SDK, status SDK siap,
  pelanggaran `maxTiles`, catatan atribusi di footer, serta keadaan memuat,
  galat, dan "Muat ulang".
- Tes widget `compass_sheet_test.dart` (6 tes): offset tersimpan, simpan arah
  acuan, input tidak valid, reset, pembulatan arah, dan platform tanpa sensor.
- Tes widget `map_page_test.dart` dan tes deteksi keluar jalur memakai titik
  GPS uji; tidak ada panggilan Mapbox di lingkungan tes.
- APK debug dibangun, dipasang, dan dijalankan di emulator Android. Terlihat:
  kartu status jalur, tombol kompas/pusatkan, kartu panduan, sheet offline
  (keadaan kosong + catatan atribusi) pada mode terang dan gelap, serta sheet
  kompas dengan sensor perangkat (menampilkan `0° U`) dan kolom koreksi arah
  manual. Logo Mapbox dan tombol atribusi `ⓘ` terlihat di atas navbar; scale
  bar dimatikan. Kartu panduan disembunyikan saat sheet modal terbuka.

**Ditulis tetapi belum dijalankan/diuji:**

- Permukaan tile peta di perangkat sungguhan. Di emulator, permukaan peta
  tampil tidak konsisten (kadang putih kosong, kadang basemap gelap) dengan
  galat `GFXSTREAM GL error 0x501`; warna style, layer jalur, dan kecocokan
  kamera karena itu belum bisa dinilai.
- Estimasi byte dan unduhan nyata (style pack + tile region). Katalog saat ini
  `{"packs": []}`, jadi tidak ada paket yang bisa diunduh; alur unduhan hanya
  diuji dengan layanan palsu. Perilaku 750 tile pack, jaringan lambat,
  penyimpanan penuh, resume, dan penghapusan region belum diuji.
- Kompas fisik: kalibrasi OS, akurasi sebenarnya, dan pengaruh medan. Emulator
  hanya melaporkan heading statis.
- Deteksi keluar jalur dengan GPS nyata dan akurasi bervariasi.
- Keterbacaan mode gelap di layar Peta. Style peta masih `OUTDOORS` untuk
  semua tema, sehingga kaca gelap di atas peta terang bisa berkontras rendah;
  style peta gelap direncanakan pada M12.
- Build iOS, build rilis, dan token Mapbox untuk rilis.
- Semua skenario di `docs/field_tests/map_offline.md`.

Jangan menandai fitur ini "berfungsi" sampai uji lapangan di dokumen tersebut
dijalankan dan lulus.
