# Model ancaman (draf awal)

Tinjau bersama ahli keamanan sebelum implementasi kripto.

| Aset | Ancaman | Mitigasi awal |
|---|---|---|
| Lokasi pengguna | Penyadap BLE, server bocor | Enkripsi E2E grup, akses server terbatas, retensi singkat |
| Isi pesan | Relay jahat membaca/mengubah | AEAD dengan header sebagai associated data |
| Keaslian SOS | SOS palsu atau dimodifikasi | Tanda tangan Ed25519, verifikasi di server |
| Keanggotaan grup | Orang asing masuk | Undangan harus diterima, kunci dibagi setelah terima |
| Anggota keluar/HP hilang | Masih bisa membaca | Rotasi kunci grup |
| Ketersediaan mesh | Banjir paket dari node jahat | Kuota per peer, batas TTL, batas ukuran |
| Pelacakan perangkat | ID BLE tetap | Rotasi pengenal iklan |
| Pencarian pengguna | Enumerasi username | Kecocokan persis, pembatasan laju |
| Kontak darurat | Spam SMS | Persetujuan kontak, pembatasan laju, opsi berhenti |
