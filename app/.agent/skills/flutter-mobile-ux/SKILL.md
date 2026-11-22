---
name: flutter-mobile-ux
description: Pedoman desain Mobile UI/UX khusus Flutter untuk ergonomi perangkat genggam, manajemen keyboard & safe area, keterbacaan glassmorphism, dan performa scroll 120fps. Gunakan setiap kali membuat atau merombak halaman dan komponen UI Flutter.
---

# Standar Desain Mobile UI/UX Flutter

## 1. Ergonomi Sentuh & Thumb Zone
- Pastikan setiap elemen interaktif (tombol kembali, ikon menu, tombol kirim, chip filter) memiliki area sentuh minimal **48×48 dp** (atau hit area transparan minimal 44×44 dp via `HitTestBehavior.opaque`) dengan jarak antar-elemen aktif minimal **8 px**.
- Tempatkan aksi utama (*primary CTA*) di area bawah layar yang mudah dijangkau ibu jari, dengan padding aman di atas navigation bar sistem.

## 2. Manajemen Safe Area, Keyboard, & Scroll
- Selalu bungkus elemen melayang di atas/bawah layar dengan `SafeArea` atau `MediaQuery.paddingOf(context)` agar tidak bertabrakan dengan status bar Android, poni layar, maupun gesture bar bawah.
- Untuk modal/bottom sheet berisi kolom teks: gunakan `isScrollControlled: true`, terapkan `MediaQuery.viewInsetsOf(context).bottom` HANYA SATU KALI, dan bungkus isi dengan `SingleChildScrollView` agar card tidak terdorong keluar layar saat keyboard muncul.
- Di halaman Room Chat, pastikan saat keyboard muncul daftar pesan terdorong mulus agar pesan terakhir tidak pernah tertutup bilah input atau keyboard.
- Pastikan konten paling bawah di dalam halaman scrollable memiliki `bottom padding` lebih besar dari tinggi Floating Bottom Navbar sehingga elemen terakhir tidak pernah tertimpa navbar.

## 3. Keterbacaan & Anggaran GPU Glassmorphism (120fps)
- **Floating Glass (`BackdropFilter`):** Gunakan `BackdropFilter` aktif HANYA pada elemen yang melayang diam di atas konten bergerak (header mengambang, floating navbar, dropdown menu, bilah input chat, fullscreen overlay, modal). Tambahkan `textShadow` halus pada teks putih di atas kaca transparan agar tetap terbaca jelas saat konten cerah menggulir di belakangnya.
- **Scrollable Cards:** Untuk kartu di dalam `ListView` atau `SingleChildScrollView` di atas latar polos, gunakan permukaan semi-transparan dengan border tipis tanpa `BackdropFilter` untuk mencegah *nested blur pass* dan menjaga kelancaran scroll 120fps.
- **Over Map:** Hindari `BackdropFilter` bersarang di atas `MapWidget` native jika berisiko artefak hitam; gunakan frosted fill kontras tinggi khusus peta.

## 4. Proporsi Konten, Media, & State UI
- Gelembung teks/chat wajib mengikuti lebar alami konten (`ConstrainedBox(maxWidth: screenWidth * 0.76)`) dan tidak boleh merentang penuh untuk pesan singkat.
- Pratinjau foto/video dalam daftar wajib menghormati rasio aspek alami media (`BoxFit.contain` atau rasio adaptif dengan batas tinggi maksimum) agar subjek tidak terpotong ekstrem.
- Pastikan setiap halaman berbasis data memiliki *loading state*, *empty state*, dan *error/offline state* yang rapi dengan tombol aksi (mis. "Coba lagi"), tanpa membocorkan pesan error mentah (`$e`).
