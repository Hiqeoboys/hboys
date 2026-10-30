# Mode gelap dan performa (M12)

Milestone terakhir membahas tiga hal: konsistensi mode gelap di sepuluh layar,
keterbacaan layar Peta di mode gelap, dan pemborosan render saat polling jejak.
Tidak ada fitur baru dan tidak ada data contoh yang ditambahkan.

## Lingkup

- Audit mode gelap pada Beranda, Siap Naik, Lacak, Peta, Grup Chat, SOS,
  Kartu Pendakian, dan Profil (tamu).
- Peredup peta pada mode gelap tanpa mengganti gaya dasar peta.
- Penyelarasan ulang warna layer jalur, jejak, dan posisi saat tema berubah.
- Penghematan rebuild layar Peta saat polling tidak menemukan data baru.
- Dokumentasi status akhir.

## Keputusan yang disengaja

- Palet dan tema gelap sudah dibuat pada M1 (`AltracqColors.dark`,
  `ThemeModeController`); M12 hanya memastikan semua layar memakainya dan tidak
  menambah warna baru.
- **Gaya peta tetap `OUTDOORS` di kedua tema.** Paket unduhan offline Mapbox
  mengikat style pack ke URL gaya; mengganti ke `MapboxStyles.DARK` akan
  membutuhkan style pack kedua dan menggandakan unduhan offline. Katalog paket
  saat ini kosong, jadi biaya itu belum bisa diukur. Sebagai gantinya, lapisan
  peredup navy (`background` 35%) dipasang di atas permukaan peta dan di bawah
  seluruh kartu/kaca UI.
- Peredup memakai `IgnorePointer` supaya gestur peta tetap lewat, dan tidak
  dipasang saat peta tidak tersedia (layar sudah memakai latar gelap) atau saat
  mode terang (opasitas 0). Fungsi `mapDimOpacityFor` menyimpan nilai itu dan
  diuji unit.
- Layer GeoJSON tidak dihapus dan dipasang ulang. Saat `Theme.of(context)`
  berubah, `didChangeDependencies` memanggil `updateLayer` untuk enam layer
  (casing jalur, jalur, casing jejak, jejak, halo posisi, titik posisi) dengan
  warna dari palet aktif, sehingga garis tetap kontras tanpa memuat ulang gaya.
- Polling jejak berjalan tiap 5 detik. `_refreshTrack` kini melewati `setState`
  dan dorongan GeoJSON bila jumlah titik dan stempel waktu terbaru tidak
  berubah dan tidak ada galat sebelumnya.
- Peringatan drift "multiple `AppDatabase` instances" yang muncul di log
  (layar Peta, Profil, dan layar lain membuka instance sendiri) sudah ada
  sebelum M12. Pola ini tidak diubah pada M12 karena refactor koneksi lintas
  layar berisiko dan di luar lingkup.

## Berkas utama

- `app/lib/features/map/presentation/map_page.dart` — `mapDimOpacityFor`,
  peredup `map-dark-dim`, `_syncLayerPalette`, `_mapLayers`, dan polling
  `_refreshTrack`.
- `app/lib/design/tokens.dart` dan `app/lib/design/app_theme.dart` — palet
  gelap yang sudah ada; tidak diubah.
- `app/test/widget/map_page_test.dart` — tes opasitas peredup dan mode gelap
  tanpa peta.

## Sudah dijalankan

- `flutter analyze lib test` bersih.
- Seluruh suite aplikasi lulus: **322 tes** (dua tes baru: nilai
  `mapDimOpacityFor` dan mode gelap tanpa peta yang tidak menambah peredup).
- APK debug dibangun dan dipasang di emulator Android API 37.
- Mode gelap sistem (`cmd uimode night yes`) diaktifkan, lalu kedelapan layar
  diperiksa lewat tangkapan layar: Beranda, Siap Naik, Lacak, Peta, Grup Chat,
  SOS, Kartu Pendakian, dan Profil. Warna, kaca, gooey, dan teks konsisten
  dengan palet gelap; tidak ada layar yang tetap memakai latar terang.
- Layar Peta mode gelap memperlihatkan peredup navy di atas permukaan peta;
  logo Mapbox dan tombol atribusi masih terlihat di atas navbar.
- Berpindah ke mode terang (`cmd uimode night no`) menghapus peredup tanpa
  memulai ulang aplikasi.
- `_refreshTrack` yang tidak menemukan data baru tidak lagi memanggil
  `setState`; perilakunya dibaca dari kode dan seluruh tes layar Peta tetap
  lulus, tetapi belum diukur dengan profiler.

## Ditulis tetapi belum diuji

- Keterbacaan peta di atas tile `OUTDOORS` sungguhan. Di emulator,
  `onStyleLoaded` tidak pernah selesai dan logcat mencatat
  `GFXSTREAM GL error 0x501`; permukaan peta tetap hitam atau hanya
  menampilkan bayangan terrain. Nilai 35% karena itu belum bisa dinilai
  terhadap tile asli.
- `_syncLayerPalette` pada perangkat. Karena gaya tidak selesai dimuat, keenam
  layer belum pernah terpasang dan `updateLayer` belum pernah berjalan di
  emulator. Logikanya hanya ditinjau kode dan diuji tidak langsung lewat
  palet.
- Penghematan performa terukur. Tidak ada pengukuran frame time atau jumlah
  rebuild sebelum/sesudah; klaimnya terbatas pada kode yang tidak lagi
  memanggil `setState` saat data polling sama.
- Peredup di atas logo/atribusi Mapbox pada perangkat sungguhan dan penilaian
  formal terhadap pedoman atribusi Mapbox.
- TalkBack, ukuran teks besar, dan seluruh sisi iOS.

## Catatan

- Pelacakan latar belakang dan layanan lokasi tidak berubah pada M12.
- Data uji perangkat tetap data lokal yang sudah ada (8 sesi selesai); tidak
  ada sesi atau titik contoh baru yang dibuat untuk tangkapan layar.

## Cara memeriksa

```bash
cd nama_app/app
flutter analyze lib test
flutter test
flutter build apk --debug --dart-define-from-file=../.run-artifacts/keys.local.json
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell cmd uimode night yes
adb shell am start -n id.nama.nama_app/.MainActivity
```

Tangkapan layar mode gelap ada di `nama_app/.run-artifacts/`
(`m12-*-dark.png`, `m12-beranda-dark-final.png`, `m12-peta-dark-final.png`,
`m12-peta-light-final.png`). Direktori itu tidak masuk repositori.
