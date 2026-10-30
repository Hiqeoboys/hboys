# Uji lapangan: layanan pelacakan GPS + UI rekam

Status dokumen: **RENCANA UJI. BELUM ADA SKENARIO YANG DIJALANKAN DI
PERANGKAT NYATA. SEMUA ITEM DI BAWAH BERSTATUS "BELUM DIUJI".**

Dokumen ini bukan bukti bahwa fitur berfungsi. Hasil otomatis yang sudah
dijalankan hanya analisis statis dan tes unit di mesin pengembang; lihat
laporan akhir tugas. Build Android belum diverifikasi karena Android SDK tidak
tersedia di mesin pengembangan saat pekerjaan ini dibuat.

## Aturan pencatatan

- Gunakan status `BELUM DIUJI`, `LULUS`, atau `GAGAL`; jangan menulis "lulus"
  tanpa bukti perangkat.
- Catat untuk setiap sesi: tanggal, lokasi dan cuaca, merek/model, versi OS/ROM,
  versi build aplikasi, level baterai awal, status pengisian daya, status kunci
  layar, izin yang aktif, dan pengaturan baterai/autostart merek.
- Simpan bukti: rekaman layar, tangkapan notifikasi, `adb logcat`, export DB,
  dan nomor sesi.
- Satu skenario = satu sesi bersih. Hapus data aplikasi atau selesaikan sesi
  lama sebelum memulai skenario yang membutuhkan kondisi awal baru.
- Untuk skenario yang menguji pemulihan, catat jumlah baris `track_points`
  sebelum dan sesudah proses dibunuh.
- Jangan memakai data pendakian nyata untuk eksperimen yang berisiko. Uji jalur
  pendek yang aman dan dikenal.

## Prasyarat build

- [ ] BELUM DIUJI: build debug dan release dipasang di perangkat.
- [ ] BELUM DIUJI: `flutter analyze` dan seluruh tes otomatis lulus pada commit
      yang diuji (catat hash/commit; repositori ini belum memiliki git).
- [ ] BELUM DIUJI: nomor versi dan checksum APK/IPA dicatat.

## Matriks minimum perangkat

Minimal satu perangkat untuk tiap baris. Semua baris BELUM DIUJI.

| ID | Perangkat / ROM | Fokus |
| --- | --- | --- |
| D1 | Android 14/15, ROM mendekati stok (Pixel/AOSP) | baseline Android |
| D2 | Xiaomi/Redmi/POCO, MIUI/HyperOS | autostart, hemat baterai, Recents |
| D3 | Samsung, One UI | aplikasi tidur, batas latar |
| D4 | OPPO/OnePlus, ColorOS/OxygenOS | optimasi baterai, peluncuran otomatis |
| D5 | Vivo/iQOO, FuntouchOS/OriginOS | konsumsi daya latar |
| D6 | Realme UI | optimasi baterai |
| D7 | Huawei/Honor, EMUI/MagicOS | peluncuran aplikasi |
| D8 | Transsion (Tecno/Infinix/itel) | optimasi daya, autostart |
| D9 | Asus/Zenfone, ZenUI | pengelolaan daya |
| D10 | iPhone fisik + akun Apple Developer/TestFlight | background location iOS |

## GPS-01: onboarding izin dari instalasi bersih

Langkah:
1. Hapus data aplikasi, lalu buka aplikasi.
2. Buka menu "Izin & Baterai".
3. Ikuti tombol izin dasar, lalu izin lokasi "Selalu".
4. Untuk Android, minta pengecualian optimasi baterai atau ikuti panduan merek.
5. Kembali ke halaman rekam.

Hasil yang diharapkan:
- Dialog izin muncul pada waktu yang wajar dan status daftar berubah menjadi
  "Siap" hanya setelah sistem benar-benar memberi izin.
- Bila dialog "Selalu" tidak muncul, pengguna diarahkan ke setelan aplikasi.
- Lokasi presisi dan notifikasi (Android) terdeteksi dengan benar.

Status: **BELUM DIUJI** (ulangi untuk setiap perangkat D1-D10).

## GPS-02: rekaman di depan layar

Langkah:
1. Di luar ruangan dengan sinyal GPS, mulai rekam.
2. Berjalan minimal 300 m selama 5 menit dengan layar menyala.
3. Periksa jarak, waktu bergerak, elevasi, laju, jumlah titik, dan baterai.
4. Hentikan rekaman dan buka sesi yang tersimpan.

Hasil yang diharapkan:
- Metrik bertambah wajar; tidak ada titik yang terlihat lompat jauh tanpa alasan.
- Sesi berstatus selesai setelah tombol hentikan dikonfirmasi.
- Titik tetap ada setelah aplikasi ditutup dan dibuka kembali.

Status: **BELUM DIUJI**.

## GPS-03: layar terkunci / aplikasi di latar (Android)

Langkah:
1. Mulai rekam, lalu kunci layar selama 10 menit sambil bergerak minimal 500 m.
2. Jangan membuka aplikasi. Periksa notifikasi layanan tetap.
3. Buka kunci dan kembali ke halaman rekam.

Hasil yang diharapkan:
- Titik tetap bertambah saat layar terkunci.
- Notifikasi layanan tetap terlihat dan tombol "Hentikan" tersedia.
- Halaman rekam menampilkan status terbaru tanpa membuat sesi baru.
- Baterai tidak turun lebih cepat dari batas yang disepakati (belum ada angka
  target; lihat GPS-10).

Status: **BELUM DIUJI**.

## GPS-04: aplikasi disapu dari Recents (Android)

Langkah:
1. Mulai rekam, tekan tombol Recents, sapu aplikasi keluar.
2. Tunggu 5 menit sambil bergerak.
3. Buka aplikasi kembali.

Hasil yang diharapkan:
- Layanan latar tetap berjalan; rekaman tidak berhenti hanya karena Recents.
- Saat aplikasi dibuka, sesi yang sedang aktif terhubung kembali tanpa sesi
  duplikat.
- Pada ROM yang membunuh layanan, aplikasi harus menampilkan sesi aktif dan
  menawarkan pemulihan, bukan diam-diam membuat sesi baru.

Status: **BELUM DIUJI**. Perilaku ROM berbeda-beda; catat nama pengaturan yang
dipakai.

## GPS-05: proses aplikasi dibunuh, lalu dibuka lagi (recovery)

Langkah:
1. Mulai rekam dan biarkan terkumpul minimal 10 titik.
2. Catat nomor sesi dan jumlah baris `track_points` untuk sesi tersebut.
3. Hentikan proses paksa, misalnya `adb shell am force-stop <applicationId>`
   (ganti dengan applicationId build sebenarnya).
4. Buka aplikasi lagi.
5. Periksa sesi, jumlah titik, jarak, elevasi, dan lanjutkan bergerak.
6. Hentikan sesi dan periksa ringkasan akhir.

Hasil yang diharapkan:
- Sesi yang sama ditemukan sebagai sesi aktif; tidak dibuat sesi baru.
- Titik yang sudah tersimpan tidak hilang dan jumlahnya tidak berkurang.
- Metrik hasil pemulihan mendekati nilai sebelum proses dibunuh (selisih hanya
  dari titik yang belum sempat tersimpan).
- Rekaman dapat dilanjutkan setelah izin masih lengkap.
- Bila izin "Selalu" dicabut, aplikasi menampilkan permintaan melengkapi izin,
  bukan mengklaim rekaman berjalan.

Status: **BELUM DIUJI**. Ini skenario paling penting untuk kriteria tugas.

## GPS-06: proses dibunuh saat menghentikan sesi

Langkah:
1. Mulai rekam, lalu hentikan dari UI.
2. Segera setelah tombol ditekan, matikan proses paksa.
3. Buka aplikasi dan periksa status sesi.

Hasil yang diharapkan:
- Sesi tidak boleh tetap "aktif" tanpa alasan jika `finish()` sudah tersimpan.
- Jika penghentian belum sempat tersimpan, sesi tetap aktif dan dapat dipulihkan;
  UI harus menampilkan peringatan yang jujur, bukan mengklaim sesi selesai.

Status: **BELUM DIUJI**.

## GPS-07: tombol "Hentikan" di notifikasi

Langkah:
1. Mulai rekam, kirim aplikasi ke latar, tarik notifikasi.
2. Tekan tombol "Hentikan".
3. Periksa notifikasi, lalu buka aplikasi.

Hasil yang diharapkan:
- Sesi selesai dan tersimpan; layanan berhenti; notifikasi hilang.
- Membuka aplikasi tidak memulai sesi baru secara otomatis.
- Tombol UI dan tombol notifikasi tidak dapat menyelesaikan sesi dua kali.

Status: **BELUM DIUJI**.

## GPS-08: kehilangan sinyal / mode pesawat

Langkah:
1. Mulai rekam di area terbuka.
2. Aktifkan mode pesawat selama 10 menit sambil bergerak, lalu matikan.
3. Tunggu hingga GPS kembali dan lanjutkan 5 menit.

Hasil yang diharapkan:
- Aplikasi tidak crash dan sesi tetap aktif.
- Tidak ada lompatan jarak palsu yang besar ketika sinyal kembali.
- Titik baru kembali tersimpan setelah sinyal pulih.
- Waktu tetap konsisten dalam UTC dan durasi tidak menjadi negatif.

Status: **BELUM DIUJI**.

## GPS-09: perubahan profil daya

Langkah:
1. Mulai rekam pada baterai di atas 50% (profil normal).
2. Catat interval timestamp titik GPS dari log/DB selama 2 menit.
3. Turunkan baterai hingga di bawah 40% (atau gunakan kondisi baterai terkontrol
   yang aman) dan ulangi pengamatan.
4. Turunkan hingga di bawah 20% dan ulangi.
5. Hubungkan pengisi daya dan amati apakah profil kembali normal.

Hasil yang diharapkan:
- Pada Android, profil normal menghasilkan interval sekitar 5 detik, hemat
  sekitar 15 detik, dan kritis sekitar 60 detik; angka ini adalah target desain,
  bukan hasil kalibrasi.
- Pada iOS, interval ditentukan sistem; yang perlu diamati adalah perubahan
  akurasi dan apakah sesi tetap berjalan. Jangan mengharapkan interval yang sama
  dengan Android.
- Perubahan profil terlihat pada notifikasi/UI dan tidak memutus sesi.
- Histeresis mencegah profil bolak-balik di sekitar ambang 20%/40%.
- Pengisian daya mengembalikan profil normal.

Status: **BELUM DIUJI**. Angka interval dan ambang baterai perlu dikalibrasi
dari hasil nyata; jangan mengklaim angka tersebut sebagai jaminan.

## GPS-10: konsumsi baterai

Langkah:
1. Isi baterai ke 100%, matikan pengisian, aktifkan mode pesawat untuk
   menghilangkan variabel jaringan bila skenario mengizinkan, dan kunci layar.
2. Rekam selama 60 menit pada profil normal; catat level awal/akhir.
3. Ulangi dengan profil hemat dan kritis pada hari terpisah atau perangkat
   terpisah dengan kondisi setara.
4. Catat suhu perangkat dan apakah OS membatasi aplikasi.

Hasil yang diharapkan:
- Konsumsi per jam tercatat untuk tiap profil.
- Tidak ada kenaikan suhu atau drain yang tidak wajar dibanding aplikasi GPS
  pembanding.
- Target maksimum drain belum ditetapkan; tetapkan setelah data awal terkumpul.

Status: **BELUM DIUJI**. Jangan mencantumkan klaim "hemat baterai" sebelum ada
angka dari perangkat nyata.

## GPS-11: akurasi di kondisi sulit

Langkah:
1. Uji di jalur lurus yang sudah diketahui panjangnya (minimal 1 km).
2. Ulangi di bawah pohon lebat, di antara gedung, dan di lembah.
3. Bandingkan jarak aplikasi dengan jarak referensi.

Hasil yang diharapkan:
- Filter GPS menolak titik dengan akurasi buruk sesuai aturan yang ada.
- Jarak tidak membengkak ekstrem saat sinyal memantul.
- Penyimpangan dicatat per kondisi, bukan dirata-ratakan menjadi satu klaim.

Status: **BELUM DIUJI**.

## GPS-12: izin dicabut atau layanan lokasi dimatikan saat merekam

Langkah:
1. Saat merekam, buka setelan dan ubah izin "Selalu" menjadi "Saat digunakan"
   (Android) atau matikan layanan lokasi.
2. Kembali ke aplikasi dan amati 10 menit.
3. Pulihkan izin/layanan dan amati apakah rekaman berlanjut.

Hasil yang diharapkan:
- UI menampilkan peringatan izin yang jelas.
- Aplikasi tidak mengklaim titik baru saat lokasi tidak tersedia.
- Setelah izin dipulihkan, perilaku (lanjut otomatis atau perlu mulai ulang)
  dicatat sesuai kenyataan.

Status: **BELUM DIUJI**. Perilaku saat izin dicabut di tengah sesi belum
diimplementasikan khusus; hasil uji menentukan perbaikan berikutnya.

## GPS-13: buka aplikasi saat layanan masih berjalan

Langkah:
1. Mulai rekam, kirim ke latar, tunggu 2 menit.
2. Buka aplikasi dari ikon (bukan dari notifikasi).
3. Periksa status, jumlah titik, dan sesi.
4. Ulangi dengan membuka dari notifikasi.

Hasil yang diharapkan:
- Status tersambung kembali ke sesi yang sama.
- Tidak ada titik ganda atau sesi ganda.
- Tombol hentikan tetap berfungsi.

Status: **BELUM DIUJI**.

## GPS-14: perangkat dimulai ulang

Langkah:
1. Mulai rekam, lalu restart perangkat.
2. Setelah menyala, buka aplikasi.
3. Periksa sesi aktif dan coba lanjutkan.

Hasil yang diharapkan:
- Rekaman tidak otomatis berjalan tanpa aksi pengguna (konfigurasi
  `autoRunOnBoot: false`).
- Sesi yang belum selesai ditemukan dan dapat dilanjutkan setelah izin lengkap.
- Tidak ada sesi ganda.

Status: **BELUM DIUJI**.

## GPS-15: iOS background location

Langkah:
1. Pasang build iOS di iPhone fisik.
2. Berikan izin "Always" dan "Precise Location".
3. Mulai rekam, kunci layar 15 menit sambil bergerak.
4. Periksa indikator lokasi latar, notifikasi/status, dan titik baru.
5. Uji dengan Low Power Mode.
6. Uji setelah aplikasi disapu dari app switcher.
7. Buka aplikasi kembali dan periksa pemulihan sesi.

Hasil yang diharapkan:
- Rekaman berlanjut saat layar terkunci dengan indikator lokasi yang benar.
- Low Power Mode tidak menghentikan sesi tanpa peringatan.
- Jika pengguna memaksa keluar aplikasi, iOS boleh menghentikan lokasi; aplikasi
  harus memulihkan sesi yang tersimpan saat dibuka lagi dan tidak boleh
  mengklaim rekaman terus berjalan.
- Tidak ada crash saat masuk/keluar latar berulang.

Status: **BELUM DIUJI**. Membutuhkan macOS/Xcode dan perangkat fisik.

## GPS-16: perbedaan waktu perangkat / zona waktu

Langkah:
1. Rekam 10 menit.
2. Ubah zona waktu perangkat (bukan waktu secara manual bila memungkinkan).
3. Lanjutkan rekam 5 menit, lalu hentikan.

Hasil yang diharapkan:
- Waktu tersimpan konsisten dalam UTC.
- Durasi tidak melompat negatif atau bertambah berlebihan.
- Pemulihan sesi tetap menghasilkan urutan waktu yang benar.

Status: **BELUM DIUJI**.

## GPS-17: sesi kosong

Langkah:
1. Mulai rekam di dalam ruangan tanpa sinyal GPS.
2. Biarkan 2 menit, lalu hentikan.
3. Buka kembali sesi tersebut.

Hasil yang diharapkan:
- Sesi selesai dengan nol titik tanpa crash.
- UI menampilkan jarak 0 dan tidak menampilkan laju palsu.
- Pemulihan sesi kosong yang masih aktif tidak menyebabkan error.

Status: **BELUM DIUJI**.

## GPS-18: layanan mati mendadak saat UI masih mengira merekam

Langkah:
1. Mulai rekam, lalu buat layanan latar berhenti tanpa menekan Hentikan,
   misalnya lewat pembatasan baterai ROM atau perintah pengembang yang tersedia
   di perangkat.
2. Periksa apakah UI masih menampilkan status merekam.
3. Buka kembali aplikasi, lalu tekan Hentikan.
4. Periksa isi DB: tidak boleh ada sesi yang tetap berstatus aktif setelah UI
   menyatakan selesai.

Hasil yang diharapkan:
- Jika layanan sudah mati, aplikasi menutup sesi aktif dari data tersimpan dan
  menampilkan peringatan bahwa layanan tidak mengonfirmasi selesai.
- Jika sesi sudah selesai sebelum layanan mati, aplikasi menampilkan status
  selesai tanpa membuat sesi baru.
- Membuka kembali aplikasi menawarkan pemulihan hanya jika masih ada sesi aktif.

Status: **BELUM DIUJI**. Jalur penutupan sesi yatim sudah ditulis tetapi belum
diuji di perangkat.

## Rekap status

| Skenario | Status | Bukti / catatan |
| --- | --- | --- |
| GPS-01 onboarding | BELUM DIUJI | |
| GPS-02 depan layar | BELUM DIUJI | |
| GPS-03 kunci layar Android | BELUM DIUJI | |
| GPS-04 sapu Recents | BELUM DIUJI | |
| GPS-05 bunuh proses + recovery | BELUM DIUJI | kriteria utama |
| GPS-06 bunuh proses saat stop | BELUM DIUJI | |
| GPS-07 stop dari notifikasi | BELUM DIUJI | |
| GPS-08 mode pesawat | BELUM DIUJI | |
| GPS-09 profil daya | BELUM DIUJI | |
| GPS-10 konsumsi baterai | BELUM DIUJI | target belum ditetapkan |
| GPS-11 akurasi sulit | BELUM DIUJI | |
| GPS-12 cabut izin | BELUM DIUJI | |
| GPS-13 buka saat layanan jalan | BELUM DIUJI | |
| GPS-14 restart perangkat | BELUM DIUJI | |
| GPS-15 iOS background | BELUM DIUJI | butuh perangkat Apple |
| GPS-16 zona waktu | BELUM DIUJI | |
| GPS-17 sesi kosong | BELUM DIUJI | |
| GPS-18 layanan mati mendadak | BELUM DIUJI | penutupan sesi yatim belum diuji |

## Keputusan rilis

Rilis hanya boleh mengklaim pelacakan latar berfungsi jika:
- semua skenario wajib (GPS-01 sampai GPS-07, GPS-11, GPS-12, GPS-15 untuk iOS)
  berstatus LULUS dengan bukti;
- panduan merek yang dipakai sudah diverifikasi pada perangkat merek tersebut;
- angka konsumsi baterai dan interval profil sudah diukur;
- temuan ROM yang membunuh layanan dicatat sebagai batasan yang terlihat oleh
  pengguna, bukan disembunyikan.
