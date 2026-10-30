# Setup native (setelah `flutter create`)

Folder `app/android` dan `app/ios` dibuat oleh `tools/bootstrap.sh`. Tambahkan yang berikut.
Nama izin dan aturan toko berubah antar versi OS; verifikasi ke dokumentasi resmi.

## Android (`AndroidManifest.xml`)
- Lokasi: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`
- Layanan latar depan: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION` (+ `FOREGROUND_SERVICE_CONNECTED_DEVICE` di Rilis 2)
- Aktivitas: `ACTIVITY_RECOGNITION`
- Bluetooth (Android 12+): `BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`
- Lainnya: `POST_NOTIFICATIONS`, `RECORD_AUDIO`, `CAMERA`, `INTERNET`, `ACCESS_NETWORK_STATE`
- Panduan onboarding: matikan optimasi baterai dan aktifkan autostart (Xiaomi, Oppo, Vivo, Realme, dst.)

## iOS (`Info.plist`)
- `NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription`
- `NSMotionUsageDescription`, `NSMicrophoneUsageDescription`, `NSCameraUsageDescription`
- `NSPhotoLibraryUsageDescription` / `NSPhotoLibraryAddUsageDescription`
- `NSBluetoothAlwaysUsageDescription` (Rilis 2), `NSLocalNetworkUsageDescription` + `NSBonjourServices` (Rilis 3)
- `UIBackgroundModes`: `location` (Rilis 1), `bluetooth-central`, `bluetooth-peripheral` (Rilis 2)
- Capability **Hotspot Configuration** (Rilis 3)
- Jelaskan alasan lokasi background dengan jelas untuk peninjauan App Store.

## Status konfigurasi pelacakan saat ini

Semua konfigurasi di bawah sudah ditulis, tetapi **BELUM DIUJI di perangkat
nyata** dan build Android belum diverifikasi karena Android SDK tidak tersedia di
mesin pengembangan.

Android (`android/app/src/main/AndroidManifest.xml`):
- Izin: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`,
  `ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_LOCATION`, `POST_NOTIFICATIONS`, `WAKE_LOCK`,
  `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `INTERNET`,
  `ACCESS_NETWORK_STATE`.
- Layanan `com.pravera.flutter_foreground_task.service.ForegroundService` dengan
  `foregroundServiceType="location"`, `exported="false"`, `stopWithTask="false"`.
- Plugin `flutter_foreground_task` menambahkan `RECEIVE_BOOT_COMPLETED`; aplikasi
  tidak memakai `autoRunOnBoot`, jadi layanan tidak dijalankan otomatis setelah
  reboot.

iOS (`ios/Runner/Info.plist`):
- Deskripsi izin lokasi saat digunakan dan selalu.
- `UIBackgroundModes` berisi `location`.
- Geolocator dijalankan dengan `allowBackgroundLocationUpdates: true`,
  `showBackgroundLocationIndicator: true`, dan `ActivityType.fitness`.

Yang masih perlu ditambahkan sesuai rilis berikutnya: `ACTIVITY_RECOGNITION`,
Bluetooth, mikrofon, kamera, dan galeri. Jangan mengklaim dukungan fitur tersebut
sebelum izinnya ditambahkan dan diuji.

## Mapbox (peta dan unduhan offline)

Status: kode ditulis, **BELUM DIJALANKAN di perangkat** dan build native belum
diverifikasi. Tidak ada token Mapbox, Android SDK, atau perangkat pada mesin
pengembangan.

- Dependensi: `mapbox_maps_flutter: ^3.33.0` (sudah ada di `pubspec.yaml`).
- Token publik diberikan saat build/run:
  `flutter run --dart-define=MAPBOX_ACCESS_TOKEN=pk.xxx`.
  Jangan memakai token rahasia `sk.` di aplikasi dan jangan meng-commit token.
- `app/lib/bootstrap.dart` memanggil `MapboxOptions.setAccessToken` hanya di
  Android/iOS bila token tidak kosong. `MapPage` juga memanggilnya sebelum
  membuat peta.
- Android: izin `INTERNET` dan `ACCESS_NETWORK_STATE` sudah ditambahkan ke
  `AndroidManifest.xml`. Keduanya bukan izin runtime.
- iOS: token tidak ditaruh di `Info.plist`; token diatur lewat
  `MapboxOptions` saat runtime. Konfigurasi native lain mengikuti dokumentasi
  plugin Mapbox; belum diverifikasi di mesin ini.
- Aplikasi tidak membundel tile/style Mapbox. Katalog peta default
  (`app/assets/map_packs/catalog.json`) sengaja kosong; hanya GeoJSON jalur
  milik aplikasi yang dibundel.
- Batas area/zoom/tile dan batasan biaya dijelaskan di
  `docs/peta_offline.md`. Uji perangkat ada di
  `docs/field_tests/map_offline.md`.

## Supabase, OAuth, dan penyimpanan kunci

Status: kode dan konfigurasi **ditulis, belum dijalankan/dibangun** di perangkat.
Tidak ada proyek Supabase, Android SDK, atau Xcode pada mesin ini.

- Isi kredensial saat build, jangan commit:
  `flutter run --dart-define=SUPABASE_URL=https://PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=pk_...`.
  Jangan memakai service role key di aplikasi.
- Di Supabase Auth > URL Configuration, tambahkan redirect persis
  `id.nama.namaapp://login-callback`.
- Aktifkan penyedia Google dan Apple di Supabase. Untuk Apple, siapkan capability
  **Sign in with Apple**, App ID, Service ID, dan kunci di Apple Developer.
  Konfigurasi ini belum dikerjakan.
- Android: intent filter `VIEW` + `BROWSABLE` untuk
  `id.nama.namaapp://login-callback` sudah ditambahkan ke `MainActivity`, dan
  `android:allowBackup="false"` disetel di elemen `application`.
  `flutter_secure_storage` 11.2.0 membutuhkan minSdk 24; Flutter default saat ini
  24. Belum diverifikasi lewat build.
- iOS: `CFBundleURLTypes` dengan skema `id.nama.namaapp` sudah ditambahkan ke
  `Info.plist`. Callback deep link belum diuji; capability Apple belum diatur.
- Sesi Supabase, PKCE verifier, kunci privat identitas, dan kunci grup disimpan
  lewat `flutter_secure_storage` (Keystore/Keychain), bukan SharedPreferences.
  iOS memakai `first_unlock_this_device`. Belum diuji di perangkat.
- Skema callback kustom dapat dibajak aplikasi lain; PKCE mengurangi risiko code
  exchange, tetapi App Links/Universal Links perlu dipertimbangkan untuk produksi.
- Fitur grup memerlukan internet. Tanpa kredensial Supabase, halaman Akun & Grup
  menampilkan status nonaktif dan fitur rekam/peta/SOS tidak berubah.
- Untuk uji server, jalankan migrasi `backend/migrations/0001` lalu `0002` di
  staging. Keduanya belum pernah dijalankan. Lihat `docs/security_review.md`.

## Catatan lain

Lihat `docs/onboarding_izin_baterai.md`,
`docs/field_tests/tracking_gps.md`, dan `docs/peta_offline.md`. Semua item uji
perangkat di sana masih belum diuji.
