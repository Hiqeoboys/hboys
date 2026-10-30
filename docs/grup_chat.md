# Grup Chat

Dokumen ini menjelaskan apa yang benar-benar dikerjakan layar Grup Chat, apa
yang sudah dijalankan, dan apa yang belum diuji.

## 1. Lingkup yang sudah ada

- Layar membaca grup terbaru dari `AccountController.groups` (lewat
  `nextHikeOf`). Tidak ada grup contoh dan tidak ada pesan contoh.
- Daftar anggota diambil dari server melalui `AccountController.membersOf`.
  Bila gagal, layar menampilkan pesan dan tombol **Coba lagi**.
- Strip anggota berisi nama pengguna dan keterangan jujur:
  - `Perangkat ini` untuk pengguna sendiri;
  - `Lokasi belum dibagikan` untuk anggota lain, karena belum ada
    penyimpanan atau pengiriman lokasi anggota.
- Pesan dibaca dari database perangkat lewat `ChatRepository.watchMessages`
  dan ditampilkan sebagai bubble masuk/keluar. Teks lokal dibaca sebagai
  UTF-8; kartu lokasi hanya muncul bila payload benar-benar berisi
  `LocationPayload` yang tersimpan.
- Mengirim teks menulis satu baris `ChatMessage` ke database perangkat:
  - `authorId` = pengguna yang sedang masuk;
  - `seq` = nomor urut berikutnya untuk pasangan grup+pengguna, sehingga
    identitas `authorId:seq` tidak dipakai ulang;
  - `sentAtUtc`/`receivedAtUtc` memakai `Clock` dan UTC;
  - payload berupa byte UTF-8.
- Status pesan keluar selalu `Tersimpan di HP · belum terkirim`. Belum ada
  transport chat di aplikasi, jadi tidak ada klaim terkirim, diterima, atau
  dibaca.
- Pesan suara hanya ditampilkan sebagai pemberitahuan. Tombol mikrofon
  dinonaktifkan dengan keterangan `Pesan suara belum tersedia`; tidak ada
  perekaman atau pemutaran.
- Keadaan kosong dibedakan dan jujur:
  - `Aplikasi berjalan offline` bila Supabase tidak dikonfigurasi;
  - `Belum masuk` bila terkonfigurasi tetapi belum ada sesi;
  - `Belum ada grup` bila sudah masuk tetapi belum mengikuti grup;
  - `Memuat grup…` selama data akun dimuat.
- Tema terang dan gelap mengikuti `ThemeModeController` yang sama dengan
  layar lain.

## 2. Yang sengaja tidak dilakukan

- Tidak ada pesan masuk buatan, baterai anggota buatan, atau lokasi anggota
  buatan. Semua nilai yang tampil berasal dari database atau server.
- Tidak ada klaim enkripsi end-to-end. Pesan teks yang dikirim dari layar ini
  disimpan sebagai UTF-8 tanpa enkripsi di database perangkat. Pembungkusan
  kunci grup yang ada belum diaudit dan bukan pengganti enkripsi pesan.
- Tidak ada pengiriman ke anggota lain. `OutboxService` dan
  `TransportManager` ada di repo, tetapi belum disambungkan ke runtime chat.
- Tidak ada pembuatan grup dari layar ini. Grup berasal dari server.
- Isi `PacketType.voiceFragment` dan tipe lain yang belum didukung hanya
  diberi keterangan, bukan diputar atau dirender sebagai media.

## 3. Berkas utama

- `app/lib/features/chat/presentation/chat_page.dart` — layar Grup.
- `app/lib/features/chat/domain/chat_message.dart` — model pesan; payload
  adalah byte transport yang tidak dienkripsi lapisan database.
- `app/lib/features/chat/domain/chat_repository.dart` — termasuk `nextSeq`.
- `app/lib/infrastructure/database/daos/chat_dao.dart` dan
  `drift_chat_repository.dart` — implementasi penyimpanan.
- `app/lib/app/router.dart` — rute `/grup` memakai `ChatPage`.
- `app/test/widget/chat_page_test.dart` — tes widget layar Grup.
- `app/test/database/repository_test.dart` — tes penyimpanan pesan, media,
  dan `nextSeq`.

## 4. Sudah dijalankan

- `flutter analyze lib test` bersih.
- Seluruh suite aplikasi lulus: **298 tes**.
- Tes widget Grup Chat (8 tes) mencakup:
  - keadaan tanpa sambungan;
  - terhubung tetapi belum masuk;
  - sudah masuk tanpa grup;
  - grup terbaru dengan anggota nyata dari data uji;
  - pengiriman teks menyimpan UTF-8, `seq` 1, dan status jujur;
  - pesan kosong tidak terkirim;
  - pesan masuk teks dan kartu lokasi terbaca dari database;
  - kegagalan memuat anggota menawarkan coba lagi.
- Tes database memastikan `nextSeq` mengembalikan 3 setelah dua pesan dari
  penulis yang sama dan 1 untuk penulis lain.
- Di emulator Android, layar Grup Chat dibuka pada mode terang dan gelap:
  judul `Grup Chat`, keadaan `Belum masuk`, navigasi bawah tetap di tempat,
  dan tidak ada pesan atau data contoh. Keadaan ini yang terlihat karena
  proyek Supabase terkonfigurasi tetapi belum ada sesi pengguna.

## 5. Ditulis tetapi belum diuji di perangkat

- Tampilan chat dengan grup nyata (strip anggota, bubble, kartu lokasi,
  composer, status pesan) baru diuji widget, belum terlihat di perangkat
  karena penyedia OAuth belum diaktifkan dan belum ada grup nyata di akun
  emulator.
- Pengiriman dan penerimaan pesan antaranggota, termasuk `OutboxService`,
  `TransportManager`, dan status bertingkat di atas "tersimpan lokal".
- Perekaman dan pemutaran pesan suara.
- Pembagian lokasi dan baterai anggota, termasuk pembaruan berkala.
- Perilaku keyboard, composer saat pesan panjang, dan gulir percakapan
  panjang di perangkat.
- Media gambar/berkas (tabel `MediaAttachment` ada, tetapi belum ada alur
  unggah atau tampilan gambar di layar ini).
- Seluruh sisi iOS dan build rilis, seperti bagian lain aplikasi.

## 6. Cara memeriksa

```sh
cd app
flutter analyze lib test
flutter test test/widget/chat_page_test.dart test/database/repository_test.dart
```

Untuk mencoba di perangkat, jalankan aplikasi dengan kredensial Supabase,
masuk lewat Profil, lalu buat atau ikuti grup nyata sebelum membuka tab Grup.
Tanpa langkah itu layar hanya menampilkan keadaan `Belum masuk` atau
`Belum ada grup`, dan itu memang perilaku yang diharapkan.
