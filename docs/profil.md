# Profil tamu dan sudah masuk (M11)

Layar Profil punya dua keadaan: tamu dan sudah masuk. Keduanya memakai data
perangkat apa adanya; tidak ada kontak, peta, atau angka contoh.

## Lingkup

- **Tamu**: avatar, nama "Pendaki tamu", ringkasan tiga angka dari sesi selesai
  di database perangkat, kartu manfaat akun, tombol "Lanjutkan dengan Google"
  dan "Lanjutkan dengan Apple", serta catatan privasi.
- **Sudah masuk**: nama dari metadata penyedia (fallback username atau
  "Pendaki"), handle `@username` atau "Username belum dibuat", pil penyedia,
  ringkasan yang sama, lima baris pengaturan, tombol Keluar, dan Hapus akun.
- **Baris pengaturan**:
  - `Kontak darurat` membaca kontak lokal pengguna lewat `SafetyRepository`.
    Lembar menampilkan nama, kanal, nomor, dan status persetujuan; catatan jujur
    menyebut penerusan SOS ke kontak belum tersedia.
  - `Peta terunduh` menghitung region Mapbox yang benar-benar siap lewat
    `defaultDownloadedMountainCount`. Katalog kosong berarti 0, bukan klaim
    peta tersedia. Aksi "Buka Peta" menuju `/peta`.
  - `Profil daya` menampilkan level baterai dan interval GPS tiap profil dari
    `PowerProfileConfig`; profil berubah otomatis mengikuti baterai.
  - `Privasi lokasi` menyatakan bahwa lokasi hanya tersimpan di HP ini dan
    belum ada transport berbagi lokasi; kontrol berbagi grup belum tersedia.
  - `Tampilan` memilih Terang / Gelap / Ikuti sistem lewat
    `ThemeModeController` dan tersimpan di perangkat.
- **Statistik** hanya menjumlahkan sesi berstatus `completed`. Sesi aktif tidak
  dihitung. Selama data belum terbaca, angka tampil "—", bukan nol palsu.

## Keputusan yang disengaja

- Baris Tampilan hanya ada pada profil sudah masuk, sesuai blueprint alur.
  Gambar desain tamu tidak memuat baris pengaturan.
- Nama tampilan diambil dari metadata penyedia (`full_name` atau `name`);
  aplikasi tidak mengarang nama. Penyedia hanya ditampilkan bila
  `app_metadata.provider` bernilai `google` atau `apple`.
- Logo Google dan Apple memakai aset resmi yang dibundel di
  `assets/brand/`. Logo Apple putih diturunkan dari aset tombol resmi.
- Kedua pil login adalah pil solid terpisah dengan celah 14 px, memakai
  komponen `AltracqButton` yang sama dengan layar lain. Leher kapsul gooey
  yang dulu menyatukan keduanya dibatalkan bersama spesifikasi gooey tombol.
- Hapus akun belum tersedia. Dialog menjelaskan bahwa tidak ada akun atau data
  yang dihapus, lalu hanya menutup.
- Tidak ada kontrol berbagi lokasi, tambah kontak, atau pengaturan lain yang
  belum punya jalur nyata.

## Berkas utama

- `app/lib/features/profile/presentation/profil_page.dart` — layar, sheet, dan
  komponen profil.
- `app/lib/features/profile/domain/profile_summary.dart` — agregasi sesi
  selesai dan format angka.
- `app/lib/features/profile/application/profile_map_status.dart` — hitung
  region peta siap dan labelnya.
- `app/lib/features/auth/domain/auth_service.dart` — `AuthUser` membawa
  `displayName` dan `provider`.
- `app/lib/infrastructure/supabase/supabase_auth_service.dart` — membaca
  metadata penyedia.
- `app/assets/brand/google_g.png`, `app/assets/brand/apple_logo.png` — aset
  merek resmi.
- `app/lib/app/router.dart` — rute `/profil` kini memakai `ProfilPage`.

## Sudah dijalankan

- `flutter analyze lib test` bersih.
- Seluruh suite aplikasi lulus: **341 tes**, termasuk 22 tes Profil (8 unit
  `profile_summary_test.dart`, 14 widget `profil_page_test.dart`) dan 2 tes
  mode gelap Peta dari M12.
- Tes unit memastikan sesi aktif tidak dihitung, label jarak/tanjakan termasuk
  kasus nol, negatif, dan nilai tidak terhingga, serta label jumlah peta.
- Tes widget memastikan keadaan tamu, tombol login aktif/nonaktif beserta
  catatan jujur, identitas dan penyedia, statistik dari sesi selesai, baris
  pengaturan, sheet kontak/peta/daya/privasi, perubahan tema tanpa mulai ulang,
  peringatan kunci perangkat, data lokal gagal dibaca, penghapusan akun yang
  jujur, dan keluar kembali ke keadaan tamu.
- Di emulator Android API 37 (mode terang, build sebelum revisi UI), layar tamu
  menampilkan data lokal nyata: **8 pendakian, 14.876 km, 1.469 m**. Logo G
  resmi berwarna dan logo Apple putih tampil, tidak ada overflow, dan catatan
  privasi tampil di bawah tombol. Pada build itu kedua pil masih disatukan
  leher kapsul gooey; bentuk pil solid yang sekarang belum dilihat ulang di
  emulator.
- Angka jarak besar diberi titik ribuan (14.876 km) agar tetap terbaca.

## Ditulis tetapi belum diuji

- Bentuk pil solid kedua tombol login (Perubahan 1 revisi UI): tepi mulus pada
  keadaan normal, ditekan, dan nonaktif baru dipastikan lewat tes widget.
- Profil sudah masuk di perangkat: penyedia OAuth belum diaktifkan, jadi
  identitas, pil penyedia, lima baris, sheet Tampilan, dan Keluar baru diuji
  widget, belum dicoba di perangkat.
- Sheet kontak dengan kontak darurat nyata di perangkat. Database emulator
  belum punya sesi masuk, sehingga jalur baca kontak hanya diuji widget.
- Pembacaan status region Mapbox nyata di perangkat. Katalog paket masih kosong
  sehingga layar menampilkan "Belum ada peta terunduh" sebagai keadaan yang
  benar, bukan hasil pembacaan region.
- TalkBack, ukuran teks besar di luar font uji, dan seluruh sisi iOS.

## Catatan

- Setiap layar membuka `AppDatabase` sendiri. Drift mencatat peringatan debug
  "database class AppDatabase multiple times" saat Profil dan layar lain
  membuka koneksi ke berkas yang sama. Belum ada korupsi data yang teramati,
  tetapi satu koneksi bersama perlu dipertimbangkan sebelum rilis.
- Profil membuka database hanya bila repository tidak disuntikkan. Uji selalu
  menyuntikkan repository palsu.
- Tidak ada klaim bahwa lokasi dibagikan, SOS diteruskan, atau akun dihapus.

## Cara memeriksa

```bash
cd app
flutter analyze lib test
flutter test test/unit/profile_summary_test.dart test/widget/profil_page_test.dart
flutter test
flutter build apk --debug --dart-define-from-file=../.run-artifacts/keys.local.json
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n id.nama.nama_app/.MainActivity
```

Buka tab Profil di navigasi bawah. Keadaan sudah masuk memerlukan penyedia
OAuth yang aktif di dasbor Supabase dan akun uji.
