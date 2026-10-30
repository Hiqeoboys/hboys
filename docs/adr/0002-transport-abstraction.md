# ADR-0002: Abstraksi transport

**Status:** diterima

**Konteks.** Android dan iOS tidak punya transport lokal bersama selain BLE. Wi-Fi Direct hanya Android,
Multipeer hanya iOS. Mesh BLE masih berisiko (perilaku background iOS).

**Keputusan.** Semua jalur mengikuti antarmuka `Transport`. Rilis 1 hanya `InternetTransport`.
`BleTransport` dan `HotspotTransport` berupa stub sampai spike Fase 0 lulus. `FakeTransport` dipakai
untuk menguji relay, outbox, dan SOS tanpa Bluetooth.

**Konsekuensi.** Rilis 2 dan 3 sebagian besar penambahan implementasi. Risiko: abstraksi bisa bocor
(BLE punya MTU kecil dan koneksi singkat); tinjau ulang antarmuka setelah spike.

**Pertanyaan terbuka.** Inti mesh dijalankan di engine Dart tanpa antarmuka atau di kode native?
Putuskan berdasarkan hasil spike.
