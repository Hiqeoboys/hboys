# ADR-0001: Offline-first dengan satu log pesan

**Status:** diterima

**Konteks.** Sinyal seluler di gunung tidak merata. Fitur inti tidak boleh bergantung pada internet.

**Keputusan.** UI hanya membaca/menulis database lokal. Layanan latar belakang memindahkan data.
Pesan disimpan sebagai log per-penulis `(authorId, seq)`; sinkronisasi bertukar `SummaryVector`.
Transport (internet, BLE, hotspot) hanyalah cara memindahkan log yang sama.

**Konsekuensi.** Dedup dan store-and-forward nyaris gratis. Menambah transport tidak mengubah logika
pesan. Biaya: kita harus mengelola penyimpanan, migrasi skema, dan antrean kirim dengan cermat.
