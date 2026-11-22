---
trigger: always_on
---

# Aturan Eksekusi & Verifikasi Flutter

1. DILARANG menjalankan `flutter test` secara global (seluruh folder `test/`), karena terdapat legacy test lama dan animasi berulang yang menyebabkan `pumpAndSettle()` menggantung tanpa batas.
2. Jika perlu menjalankan unit/widget test, jalankan HANYA pada file test baru/spesifik yang relevan dengan batas waktu:
   `flutter test test/<nama_file_spesifik>_test.dart --timeout 30s`
3. DILARANG menjalankan `flutter analyze` berulang-ulang di setiap langkah kecil. Cukup jalankan `flutter analyze` SATU KALI di tahap paling akhir, dan spesifik hanya pada file Dart yang baru dibuat atau dimodifikasi (contoh: `flutter analyze lib/path/file_ubah.dart`).
4. Jika perintah terminal tidak merespons lebih dari 60 detik atau gagal karena isu environment/legacy test, segera hentikan perintah tersebut tanpa mengulanginya dalam loop, lalu langsung laporkan ringkasan perubahan kode.