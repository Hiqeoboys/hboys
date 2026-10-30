# Pipeline data jalur dan peta

Data jalur adalah aset terpenting dan paling berisiko. Aturan:

1. Sumber: OSM, GPX komunitas/pengelola, rekaman tim. Catat sumber di tiap fitur (`properties.source`).
2. Jalur baru berstatus `verified: false`. Label "terverifikasi" hanya setelah tim
   mendaki dan mencocokkan di lapangan (`verified_at` + `verified_by`).
3. Jalankan validator sebelum paket dirilis:
   `python3 scripts/validate_trails.py packs/<gunung>/trails.geojson packs/<gunung>/poi.geojson`
4. Tiap paket punya `manifest.json` berversi. Aplikasi membandingkan versi untuk pembaruan.
5. `packs/contoh_gunung/` berisi data FIKTIF hanya untuk uji alat. Jangan dipakai di aplikasi.
