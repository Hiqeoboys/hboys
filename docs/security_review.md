# Hal yang perlu ditinjau ahli keamanan

Status dokumen: 2026-10-25. Ini **bukan** hasil audit dan **bukan** jaminan
keamanan. Isinya menandai bagian yang perlu diperiksa ulang oleh ahli keamanan
independen sebelum aplikasi dipakai di lapangan.

## 1. Ruang lingkup

Yang ditulis pada tugas ini:

- Login OAuth Google/Apple lewat Supabase; tidak ada kata sandi, OTP, atau magic
  link.
- Profil publik dengan username unik dan direktori kunci publik perangkat.
- Alur undangan grup: buat, undang dengan kecocokan username persis,
  terima/tolak, kedaluwarsa.
- Kunci grup simetris per versi, dibungkus untuk kunci publik X25519 tiap
  anggota, disimpan server hanya sebagai blob terenkripsi.
- Penyimpanan sesi, kunci privat identitas, dan kunci grup di
  Keystore/Keychain, bukan SharedPreferences atau SQLite.

Bukan bagian dari tugas ini dan belum ada:

- Enkripsi pesan grup end-to-end yang benar-benar dipakai aplikasi. Antarmuka
  `AeadCipher` dan implementasi AES-256-GCM ada, tetapi belum disambungkan ke
  jalur pesan.
- Tanda tangan pesan/ SOS dan tanda tangan distribusi kunci (`Signer` belum
  diimplementasikan).
- Multi-perangkat, escrow kunci, pemulihan akun, hapus akun, dan rotasi kunci
  terjadwal.
- Pengujian di Supabase nyata, build Android/iOS, perangkat nyata, atau
  PostgreSQL. Tidak ada proyek Supabase, Android SDK, PostgreSQL, atau
  perangkat pada mesin ini.

## 2. Status verifikasi

| Bagian | Status |
|---|---|
| `flutter analyze` app | **Sudah dijalankan**: tanpa isu. |
| Suite penuh `./tools/test_all.sh` | **Sudah dijalankan** 2026-10-25: analyzer paket Dart, seluruh tes Flutter (163 tes), dan validasi GeoJSON lulus (0 galat, 1 peringatan `verified=false`). |
| Tes kripto klien (round trip, tamper, AAD salah, penerima salah) | **Sudah dijalankan** di Dart VM: lulus. |
| Tes manajer kunci grup (distribusi, pending, pemulihan, rotasi) | **Sudah dijalankan** di Dart VM dengan server palsu: lulus. |
| Tes alur akun/undangan dan widget halaman akun | **Sudah dijalankan** di Dart VM dengan fake: lulus. |
| Migrasi `0002_auth_groups.sql` | **Ditulis, belum dijalankan**. Tidak ada PostgreSQL/psql. |
| RLS dan fungsi RPC | **Ditulis, belum diuji** sama sekali di server. |
| Konfigurasi OAuth Supabase, Google, Apple | **Belum dikonfigurasi**; hanya instruksi di `docs/native_setup.md`. |
| Intent filter Android dan `CFBundleURLTypes` iOS | **Ditulis, belum dibangun/diuji** di perangkat. |
| Penyimpanan Keystore/Keychain | **Ditulis, belum diuji** di perangkat nyata. |
| Build Android/iOS | **Belum dijalankan** (tidak ada Android SDK/Xcode). |

Tes klien lulus hanya membuktikan logika Dart dengan fake. Tes itu tidak
membuktikan perilaku Supabase, RLS, deep link, Keychain/Keystore, atau build
native.

## 3. Ringkasan arsitektur dan batas kepercayaan

- Server: Supabase (PostgreSQL + GoTrue + PostgREST). Server menyimpan profil,
  keanggotaan, undangan, dan blob kunci terenkripsi.
- Klien: Flutter. Kunci privat X25519 dan kunci grup 32 byte disimpan di
  `flutter_secure_storage`; pemilik grup membungkus kunci grup untuk setiap
  anggota memakai kunci publik dari direktori.
- Skema bungkusan buatan sendiri, bukan primitif buatan sendiri:
  X25519 ephemeral + HKDF-SHA256 + AES-256-GCM dari paket `cryptography` 2.9.0.
  Format: `versi(1) + ephemeralPublic(32) + nonce(12) + ciphertext + MAC(16)`.
  AAD: `nama.group-key|<group_id>|v<key_version>`.
- Server saat ini **dipercaya penuh** untuk identitas, direktori kunci, dan
  integritas blob kunci. Tidak ada tanda tangan dari pemilik grup dan tidak ada
  verifikasi kunci antar-pengguna.
- OAuth Google/Apple dan Supabase Auth dipercaya untuk identitas akun. Supabase
  hanya memegang kunci publik; kunci privat tidak pernah dikirim ke server.

## 4. Temuan kriptografi

### 4.1. Komposisi bungkusan kunci belum diaudit — P0

X25519 + HKDF-SHA256 + AES-256-GCM adalah komposisi yang wajar, tetapi tetap
komposisi buatan proyek ini. Perlu ditinjau:

- Apakah salt HKDF (kunci publik ephemeral) dan `info` (`nama.group-key-wrap.v1`
  + AAD) sudah memenuhi pemisahan domain.
- Apakah urutan framing byte, panjang minimum 61 byte, dan pemotongan MAC 16 byte
  benar untuk semua kasus.
- Apakah penolakan titik publik X25519 berorde rendah sudah ditangani. Kode
  belum memeriksa hasil ECDH semua-nol; perilaku `cryptography` perlu
  diverifikasi dan diuji dengan vektor uji.
- Apakah AAD string dengan pemisah `|` aman. Saat ini `group_id` diasumsikan UUID
  dari server; bila server mengirim string berisi `|`, dua konteks berbeda bisa
  memiliki AAD yang sama. Sebaiknya pakai encoding panjang-eksplisit atau
  validasi UUID di klien.
- Perlu vektor uji lintas implementasi (Dart, OpenSSL/libsodium) dan uji
  properti untuk blob rusak/terpotong.

### 4.2. Tidak ada autentikasi pengirim blob kunci — P0

Blob kunci yang diterbitkan pemilik tidak ditandatangani. Server (atau pihak yang
menguasai database) dapat mengganti blob milik anggota dengan blob yang dibuat
untuk kunci publik anggota tersebut. Anggota akan berhasil membuka blob itu dan
memakai kunci pilihan penyerang. Pemilik juga mengambil daftar kunci publik
anggota dari server, sehingga server dapat mengganti kunci anggota dan membuat
pemilik membungkus kunci grup untuk penyerang.

Ini adalah **key substitution attack** yang belum dimitigasi. Diperlukan minimal:

- Kunci tanda tangan Ed25519 per akun/perangkat yang terdaftar terpisah dari
  kunci X25519, dan
- Tanda tangan pemilik atas `(group_id, key_version, daftar user_id, hash blob)`,
  serta verifikasi oleh anggota sebelum menyimpan kunci.

Sampai itu ada, server harus dinyatakan sebagai komponen tepercaya dalam model
ancaman. Jangan mengklaim grup "end-to-end secure" terhadap server.

### 4.3. Direktori kunci tidak memiliki verifikasi sidik jari — P1

`lookup_user` mengembalikan username dan kunci publik berdasarkan username
persis. Tidak ada verifikasi out-of-band (QR/sidik jari) dan tidak ada
_transparency log_. Pengguna tidak dapat mendeteksi pergantian kunci oleh server.
Pergantian kunci perangkat oleh pemilik akun juga tidak memerlukan tanda tangan
kunci lama; ini mempermudah pemulihan setelah perangkat hilang, tetapi berarti
pengambilalihan akun dapat mengganti kunci dan menerima kunci grup berikutnya.

### 4.4. Kunci grup statis per versi — P1

- Tidak ada _ratchet_ per pesan; kompromi kunci grup membuka semua pesan pada
  versi itu, termasuk pesan lama yang disimpan.
- Rotasi hanya terjadi saat anggota dihapus (versi naik di server) atau saat
  kunci perangkat pemilik berubah (server menaikkan versi grup yang dimilikinya).
  Tidak ada rotasi berkala atau tombol rotasi manual.
- Kunci grup lama tetap tersimpan di perangkat dan blob lama tetap ada di server
  untuk anggota yang tersisa. Ini memungkinkan dekripsi riwayat, tetapi juga
  memperpanjang masa hidup kunci.
- Pemilik yang kehilangan cache kunci lokal akan memulihkan kunci dari blob
  miliknya sendiri; bila blob itu hilang tetapi anggota lain sudah punya kunci,
  pemilik akan membuat kunci baru pada versi yang sama dan memecah grup. Kasus
  ini terdeteksi sebagai risiko server, belum ada prosedur rotasi paksa.

### 4.5. Nonce dan penggunaan ulang kunci — P2

AES-256-GCM memakai nonce acak 12 byte per enkripsi dari `cryptography`. Batas
teoretis penggunaan kunci GCM dengan nonce acak perlu dihitung untuk volume pesan
nyata. Untuk kunci grup jangka panjang, pertimbangkan rekey sebelum batas aman
dan pemisahan kunci per arah/pengirim.

### 4.6. Kunci di memori tidak dihapus — P2

`Uint8List` berisi kunci grup dan hasil ECDH tidak di-zero setelah dipakai. Dart
GC tidak menjamin penghapusan memori. Ini risiko residual terhadap malware,
core dump, atau proses debug; perlu tinjauan apakah memori sensitif dapat
dikurangi (misalnya library native dengan zeroization).

## 5. Temuan autentikasi

### 5.1. OAuth + PKCE — perlu verifikasi end-to-end

- `signInWithOAuth` memakai `AuthFlowType.pkce`, browser eksternal, dan callback
  `id.nama.namaapp://login-callback`.
- Keberhasilan login hanya diambil dari `onAuthStateChange`, bukan nilai balik
  `signInWithOAuth`; UI menyatakan hal ini.
- Sesi dan PKCE verifier disimpan di Keystore/Keychain lewat
  `SecureSupabaseLocalStorage` dan `SecureGotrueAsyncStorage`.
- `Supabase.initialize` memakai publishable key, bukan service role key.
- Predikat `detectSessionInUri` dibatasi ke skema/host callback aplikasi agar
  deep link lain tidak diperlakukan sebagai callback login.

Yang belum ada / perlu ditinjau:

- **Custom scheme dapat dibajak** (`id.nama.namaapp`). Aplikasi lain di Android
  dapat mendaftarkan skema yang sama dan menerima code OAuth. PKCE membuat code
  tidak dapat ditukar tanpa verifier yang tersimpan di aplikasi sah, tetapi ini
  tetap lebih lemah daripada App Links/Universal Links terverifikasi. Untuk
  produksi, pertimbangkan HTTPS App Links/Universal Links dan verifikasi
  `assetlinks.json` / `apple-app-site-association`.
- Supabase URL allowlist, provider Google, dan provider Apple **belum diatur**.
  Apple memerlukan capability Sign in with Apple dan konfigurasi di Apple
  Developer; belum dikerjakan.
- Supabase default `signOut()` pada SDK ini memakai scope lokal. Belum ada UI
  "keluar dari semua perangkat". Perlu keputusan produk/keamanan.
- Belum ada perlindungan tambahan sesi (reautentikasi sebelum mengganti kunci
  perangkat, daftar sesi, pencabutan sesi lain). Penggantian kunci perangkat
  hanya memerlukan sesi OAuth aktif dan konfirmasi dialog.
- Tidak ada penghapusan akun atau kebijakan retensi data; belum ada alur
  persetujuan/privasi.
- Error dari server dipetakan ke pesan Indonesia umum; detail mentah tidak
  ditampilkan. Perlu dicek apakah pesan server dapat membocorkan informasi saat
  dikembangkan.

### 5.2. Username dan enumerasi

- Username `citext` 3-20 karakter, huruf kecil/angka/titik/garis bawah, unik, dan
  tidak dapat diubah. Pencarian hanya cocok persis.
- `lookup_user` dapat dipanggil oleh pengguna terautentikasi yang sudah punya
  profil. Dengan begitu, pengguna dapat memeriksa keberadaan username satu per
  satu. Rate limit, CAPTCHA, atau pembatasan undangan **belum ada**.
- UI tidak menampilkan detail sensitif akun lain, tetapi respons RPC membedakan
  `USER_NOT_FOUND`, `ALREADY_MEMBER`, dan `INVITE_PENDING`. Tinjau apakah
  pembedaan ini dapat dipakai untuk enumerasi/penyalahgunaan.

## 6. Temuan server, SQL, dan RLS

### 6.1. Semua penulisan lewat fungsi security definer

`0002_auth_groups.sql` menambahkan fungsi dan menghapus policy update profil
langsung. Fungsi memeriksa `auth.uid()`, kepemilikan grup, dan keanggotaan.
Fungsi dieksekusi hanya oleh role `authenticated`. Ini arah yang benar, tetapi
**belum dijalankan atau diuji**.

Perlu ditinjau khusus:

- Apakah setiap fungsi `security definer` aman terhadap `search_path` dan objek
  sementara. Saat ini `set search_path = public`; best practice Supabase adalah
  `search_path = ''` dengan nama objek terqualifikasi, atau skema privat.
- Apakah `profiles_self_read` dan `keyblobs_self_read` cukup. `profiles` hanya
  dapat dibaca sendiri; direktori grup dibaca lewat fungsi yang memeriksa
  keanggotaan.
- Apakah ada grant tabel yang masih membolehkan INSERT/UPDATE/DELETE langsung.
  RLS menolak tanpa policy, tetapi grant eksplisit sebaiknya dicabut dan diuji.
- Apakah policy `invitations_party_read` membocorkan status undangan ke mantan
  pengundang atau pihak lain.
- Apakah RPC `group_members_directory` seharusnya juga membatasi data untuk
  anggota yang sudah dihapus pada permintaan yang sedang berjalan.
- Apakah `publish_group_keys` benar-benar memaksa tepat satu blob per anggota
  saat ada balapan undangan diterima bersamaan. Validasi jumlah anggota dan
  penguncian baris grup sudah ditulis, tetapi belum diuji dengan konkurensi.
- Apakah kenaikan `key_version` saat kunci pemilik berubah cukup untuk semua
  grup yang dimiliki; belum ada uji integrasi.
- Apakah fungsi mengembalikan bentuk JSON yang sama dengan yang diparse klien
  (`my_groups`, `create_group`, `respond_invitation` mengembalikan teks, dll.).
- Tidak ada audit log, rate limit, batas jumlah grup/undangan, atau pembersihan
  blob versi lama. `cleanup_retention` belum dibuat.
- `is_group_member` dan fungsi lain adalah `security definer`; pastikan owner
  fungsi dan grant-nya benar di Supabase (bukan role yang dapat diubah pengguna).
- Semua data ini adalah metadata yang dapat dibaca server. "Server tidak membaca
  isi pesan" belum berlaku karena pesan terenkripsi belum diimplementasikan.

### 6.2. Belum ada pengujian SQL

Tidak ada PostgreSQL/psql di mesin ini, jadi migrasi tidak pernah diparse oleh
PostgreSQL. Risiko nyata: kesalahan sintaks PL/pgSQL, tipe hasil RPC yang tidak
cocok dengan klien, dan perilaku RLS yang tidak sesuai. Wajib:

- Jalankan `0001` lalu `0002` di Supabase staging.
- Uji sebagai anon, authenticated tanpa profil, anggota, pemilik, dan mantan
  anggota.
- Uji undangan bersamaan, undang ulang setelah undangan kedaluwarsa, publish
  kunci bersamaan, penghapusan anggota, dan penggantian kunci pemilik.
- Uji bahwa `anon` tidak dapat mengeksekusi RPC dan tidak dapat membaca tabel.
- Uji payload `p_wrapped_keys` rusak/duplikat/asing.

## 7. Temuan klien dan penyimpanan

- Kunci privat X25519 dan kunci grup disimpan di `flutter_secure_storage` 11.2.0.
  iOS memakai `first_unlock_this_device`; Android memakai penyimpanan default
  plugin (AES-GCM/RSA-OAEP). Tidak ada autentikasi biometrik per kunci dan tidak
  ada attestation hardware.
- `android:allowBackup="false"` ditambahkan. Ini mengurangi risiko backup cloud,
  tetapi migrasi perangkat/transfer OEM pada Android tertentu perlu diuji;
  pertimbangkan juga `dataExtractionRules` untuk API 31+.
- Sesi Supabase dan PKCE verifier memakai penyimpanan yang sama. Bila keystore
  rusak, `SupabaseServices.initialize` menonaktifkan fitur akun/grup; ini
  fail-closed, tetapi perlu dipastikan tidak menghapus data pengguna.
- Kunci grup tidak disimpan di SQLite. Namun metadata grup/undangan di memori
  belum dienkripsi; pesan belum ada.
- `AccountController` memblokir operasi kunci grup saat kunci perangkat berbeda
  dari direktori. Ini mencegah pembungkusan dengan identitas yang salah, tetapi
  tidak mencegah dua instance controller (dua halaman akun) melakukan operasi
  bersamaan. Server harus tetap otoritatif.
- Pemulihan sesi OAuth dan callback deep link belum diuji di perangkat.
- Belum ada logging terpusat; jangan pernah mencatat kunci, token, atau blob.
  Pastikan crash reporting (jika ditambahkan) tidak menangkap memori sensitif.

## 8. Temuan native

- Android: intent filter callback ditambahkan ke `MainActivity`, plus
  `android:allowBackup="false"`. `flutter_secure_storage` 11.2.0 membutuhkan
  minSdk 24; Flutter default saat ini 24. **Belum dibangun**.
- iOS: `CFBundleURLTypes` dengan skema `id.nama.namaapp` ditambahkan. Sign in with
  Apple capability, provisioning, dan konfigurasi provider belum ada. **Belum
  dibangun**.
- Redirect URL harus didaftarkan persis di Supabase Auth > URL Configuration.
  Bila tidak, login akan gagal atau kembali ke URL yang salah.
- Untuk produksi, pertimbangkan App Links/Universal Links, sertifikat pinning
  (dengan rencana rotasi), dan peninjauan izin/brankas kunci oleh tim mobile.

## 9. Prioritas tindakan sebelum produksi

**P0 — wajib sebelum ada klaim keamanan grup:**

1. Audit komposisi bungkusan kunci dan tambahkan vektor uji/fuzzing.
2. Tambahkan tanda tangan distribusi kunci dan verifikasi di klien; atau nyatakan
   server sepenuhnya tepercaya secara eksplisit dan batasi klaim.
3. Jalankan dan uji seluruh migrasi + RLS di staging dengan beberapa identitas.
4. Uji OAuth Google/Apple end-to-end di Android dan iOS nyata, termasuk callback,
   sesi setelah restart, dan sign-out.
5. Pastikan `service_role` tidak pernah masuk aplikasi; gunakan publishable key.

**P1 — sebelum rilis terbatas:**

6. Rate limit/abuse control untuk lookup username, undangan, dan pembuatan grup.
7. Kebijakan rotasi kunci, penghapusan anggota, dan pemulihan perangkat yang
   terdokumentasi serta teruji.
8. Pertimbangkan App Links/Universal Links dan reautentikasi untuk penggantian
   kunci.
9. Uji keystore/Keychain, backup Android, dan kehilangan perangkat.
10. Sediakan hapus akun, retensi, dan audit log minimal.

**P2 — peningkatan:**

11. Ratchet/pemisahan kunci per pesan bila enkripsi pesan dikerjakan.
12. Zeroization memori sensitif dan penanganan crash report.
13. Sertifikat pinning dengan strategi rotasi.
14. Uji beban/batas GCM dan rotasi berkala.

## 10. Pertanyaan untuk ahli keamanan

1. Apakah komposisi X25519 + HKDF-SHA256 + AES-256-GCM dengan framing dan AAD di
   atas dapat diterima, atau sebaiknya memakai skema standar seperti HPKE/ECIES
   yang sudah diaudit?
2. Apakah AAD string perlu diganti encoding biner panjang-eksplisit?
3. Bagaimana cara terbaik menandatangani distribusi kunci tanpa menambah
   kompleksitas multi-perangkat yang berlebihan pada Rilis 1?
4. Apakah model "server tepercaya" dapat diterima untuk Rilis 1, dan klaim
   produk apa yang harus dihindari?
5. Apakah custom scheme + PKCE cukup untuk OAuth di Android/iOS, atau wajib
   App Links/Universal Links?
6. Bagaimana kebijakan rotasi dan retensi blob kunci yang disarankan?
7. Apakah `security definer` + `search_path = public` cukup aman di Supabase, atau
   harus `search_path = ''` dengan skema privat?
8. Apakah batas dan validasi `publish_group_keys` sudah mencegah penyalahgunaan
   oleh pemilik grup yang berbahaya?
9. Apakah pesan error RPC membocorkan informasi yang dapat dipakai enumerasi?
10. Bagaimana uji minimal yang harus lulus sebelum fitur grup boleh dipakai di
    lapangan?

## 11. Pernyataan status

Semua yang berkaitan dengan Supabase, RLS, OAuth provider, build native,
Keystore/Keychain, dan perangkat nyata **ditulis tetapi belum diuji**. Jangan
menganggap fitur akun/grup "sudah berfungsi" sampai ada hasil uji di staging dan
perangkat nyata. Tes Dart yang lulus hanya memvalidasi logika klien dengan fake
dan operasi kripto di Dart VM.
