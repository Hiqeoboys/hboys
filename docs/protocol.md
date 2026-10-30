# Spesifikasi paket (v1)

Semua angka big-endian. Header 32 byte, diikuti payload, lalu tanda tangan opsional.
Implementasi acuan: `packages/mesh_protocol/lib/src/packet.dart`.

| Offset | Ukuran | Isi |
|---|---|---|
| 0 | 1 | versi (=1) |
| 1 | 1 | tipe |
| 2 | 1 | TTL |
| 3 | 1 | flags (bit0 = ada tanda tangan 64 byte di akhir) |
| 4 | 8 | authorId |
| 12 | 8 | groupId |
| 20 | 4 | seq (uint32, mulai 1, naik per penulis) |
| 24 | 4 | waktu kirim (detik sejak epoch, UTC) |
| 28 | 1 | fragIndex |
| 29 | 1 | fragTotal |
| 30 | 2 | panjang payload |
| 32 | N | payload (terenkripsi, kecuali HELLO) |

## Tipe

| Kode | Tipe | Prioritas (0 = tertinggi) |
|---|---|---|
| 3 | SOS | 0 |
| 4 | ACK | 0 |
| 2 | LOKASI | 1 |
| 1 | TEKS | 2 |
| 0 | HELLO | 3 |
| 5 | SUARA (fragmen) | 4 |
| 6 | THUMBNAIL (fragmen) | 5 |

## Aturan

- Identitas pesan = `(authorId, seq)`. Fragmen berbagi identitas yang sama.
- Dedup relay memakai `(authorId, seq, fragIndex)`.
- TTL dibatasi penerima (`maxTtl`, awal 8). Paket TTL 1 diserahkan ke aplikasi tetapi tidak disebar.
- SOS wajib bertanda tangan dan tidak boleh difragmentasi (payload 20 byte).
- Kode tipe tidak boleh diubah setelah rilis; tambahkan kode baru dan naikkan versi bila perlu.
- Tukar-menukar: dua perangkat saling mengirim `SummaryVector`, lalu mengirim rentang yang kurang urut prioritas.

## Belum diputuskan

- Format wire ACK dan HELLO.
- Tanda tangan untuk pesan terfragmentasi.
- Mode enkripsi per-paket vs per-pesan.
