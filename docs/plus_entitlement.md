# Hak akses Plus, konfigurasi jarak jauh, dan feature flag

Dokumen ini menjelaskan lapisan Plus tahap UI + logika lokal. Belum ada
backend, toko pembelian, maupun penerbitan token produksi.

## Lapisan

```
features/plus/
  domain/
    plus_plan.dart              paket dari konfigurasi (harga, kuota, durasi)
    plus_remote_config.dart     paket + tenggang + feature flag + waktu cache
    plus_entitlement.dart       payload token dan evaluasi status akses
    plus_repositories.dart      antarmuka konfigurasi, penyimpanan, verifikasi,
                                dan pembelian
  application/
    plus_controller.dart        sumber status tunggal (ChangeNotifier)
    plus_scope.dart             InheritedNotifier + penyegaran saat app resumed
  infrastructure/
    entitlement_token.dart      verifier Ed25519 offline
    dev_entitlement_issuer.dart penerbit token debug
    dummy_plus_repositories.dart konfigurasi/pembelian demo (debug saja)
    dummy_plus_data.dart        harga contoh; tidak dipakai build rilis
    debug_route_weather.dart    prakiraan demo (debug saja)
    debug_leaderboard.dart      papan peringkat demo (debug saja)
    plus_local_caches.dart      cache cuaca di perangkat
    device_sharing.dart         lembar berbagi teks/berkas
    local_plus_stores.dart      SharedPreferences + InMemory untuk uji
  plus_dependencies.dart        perakitan default
  plus_content_dependencies.dart perakitan repositori konten Plus
```

`NamaApp` membungkus `MaterialApp` dengan `PlusScope`. Bootstrap memanggil
`loadCached()` sebelum `runApp` (lokal saja), lalu `refreshRemote()` setelah
aplikasi hidup (satu kali, dengan cache 12 jam).

## Status akses

Status dihitung murni dari token dan waktu lokal (`Clock.nowUtc()`), tanpa
jaringan:

| Keadaan | Syarat | Fitur Plus |
| --- | --- | --- |
| `free` | tidak ada token sah | terkunci |
| `active` | sekarang < `exp` atau token seumur hidup | terbuka |
| `grace` | `exp` ≤ sekarang < `exp` + tenggang | terbuka |
| `expired` | sekarang ≥ `exp` + tenggang | terkunci |

Masa tenggang berasal dari `graceDays` konfigurasi dan dijepit ke 7–14 hari.
Bila konfigurasi belum pernah diterima (offline pertama kali), dipakai batas
bawah 7 hari agar pengguna yang sudah membeli tidak kehilangan akses; angka
ini satu-satunya nilai cadangan dan bukan harga.

Token seumur hidup memakai `exp: null` (Founding Member). Paket berdurasi
memakai `durationDays` dari konfigurasi saat token diterbitkan.

### Token bertanda tangan

Format: `payloadB64url.tandaTanganB64url`, tanpa padding `=`.

Payload yang ditandatangani (byte ASCII segmen payload apa adanya):

```json
{"v":1,"sub":"local-device","plan":"annual",
 "iat":"2026-10-31T09:00:00.000Z",
 "exp":"2027-10-31T09:00:00.000Z"}
```

Verifikasi memakai Ed25519 dan hanya kunci publik; tidak ada panggilan
jaringan saat memeriksa status. Payload dengan versi tidak dikenal, subjek/
paket kosong, tanggal tidak valid, atau `exp` sebelum `iat` ditolak.

### Jam perangkat

Pemeriksaan menyimpan waktu UTC tertinggi yang pernah dipakai
(`plus_entitlement_last_seen_v1`). Waktu efektif adalah
`max(jam sekarang, checkpoint)`, sehingga memundurkan jam perangkat tidak
menghidupkan kembali token yang sudah lewat. Ini bukan anti-tamper penuh:
menghapus data aplikasi juga menghapus checkpoint. Keputusan ini didokumentasikan
agar tidak diklaim sebagai perlindungan yang lebih kuat dari kenyataannya.

## Konfigurasi jarak jauh

`PlusRemoteConfig` memuat daftar paket, `graceDays`, `flags`, dan waktu cache.
Harga dan kuota Founding Member adalah string/angka dari server; UI tidak
memuat harga sendiri.

```json
{
  "graceDays": 10,
  "flags": {"leaderboard": true, "peakBadges": true},
  "plans": [
    {
      "id": "annual",
      "title": "Hiqeo Plus Tahunan",
      "priceLabel": "Rp 249.000",
      "periodLabel": "per tahun",
      "note": "Setara Rp 20.750 per bulan.",
      "durationDays": 365,
      "badge": "Paling hemat"
    },
    {
      "id": "founding",
      "title": "Founding Member",
      "priceLabel": "Rp 499.000",
      "periodLabel": "sekali bayar",
      "durationDays": null,
      "quotaRemaining": 500,
      "quotaTotal": 500
    }
  ]
}
```

Aturan baca:

- Paket tidak lengkap, durasi ≤ 0, kuota negatif, atau id duplikat dilewati;
  satu entri rusak tidak menjatuhkan paywall.
- `graceDays` dijepit 7–14.
- Saklar yang tidak dikirim dianggap **mati**.
- Cache berumur 12 jam; `refreshRemote(force: true)` dipakai tombol coba lagi.
- Gagal jaringan mempertahankan cache terakhir, tidak mengubah status akses.

Dua feature flag yang diminta spesifikasi:

- `leaderboard` — seluruh layar leaderboard (grup, nasional, persetujuan).
- `peakBadges` — lencana puncak.

Keduanya harus dibaca lewat `PlusController`, bukan konstanta UI. Build rilis
tanpa konfigurasi menampilkan keduanya mati.

## Implementasi dummy

- `DebugPlusConfigRepository` mengembalikan `debugPlusRemoteConfigJson`
  (harga contoh, tenggang 10 hari, kedua flag hidup) hanya bila
  `kDebugMode`/`enabled: true`.
- Build rilis memakai `UnavailablePlusConfigRepository` dan
  `UnavailablePlusBillingRepository`; paywall harus menampilkan keadaan
  konfigurasi belum tersedia, bukan harga karangan.
- `DebugPlusBillingRepository` menerbitkan token dengan kunci pengembangan.
  Tidak memanggil Play Billing/StoreKit dan tidak memiliki riwayat toko;
  `restore()` menjawab jujur "tidak ada pembelian".
- Analytics dan rekap memakai sesi lokal nyata. Data cuaca/leaderboard demo
  hanya muncul di debug; build rilis menjawab "belum tersedia".

Kunci pengembangan:

```
public: A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=
```

Seed privatnya ada di `dev_entitlement_issuer.dart` dan **bukan rahasia**.
Untuk produksi, isi kunci publik lewat
`--dart-define=PLUS_PUBLIC_KEY=<base64url>`; tanpa itu build rilis memakai
`RejectingEntitlementVerifier` dan menolak semua token. Penerbitan token
nyata, penyimpanan kunci, dan verifikasi sisi server perlu tinjauan ahli
keamanan.

## Batasan yang disadari

- Ini belum sistem pembayaran. Tidak ada pembelian nyata, penagihan,
  pengembalian dana, atau verifikasi struk toko.
- Token disimpan di SharedPreferences (bukan rahasia; dilindungi tanda
  tangan). Mencadangkan/menyalin token antar perangkat tidak dicegah pada
  tahap ini.
- Harga dan kuota di `dummy_plus_data.dart` adalah contoh tata letak.
- Belum ada uji perangkat nyata untuk perilaku jam, cold start offline, atau
  penerbitan token produksi.

## Tes

Sudah dijalankan (43 tes baru):

- `test/unit/plus_entitlement_test.dart` — token sah, payload/tanda tangan
  diubah, token rusak, verifier rilis, aktif/tenggang/kedaluwarsa/seumur
  hidup, validasi payload.
- `test/unit/plus_remote_config_test.dart` — parsing paket/kuota/flag,
  penjepitan tenggang, entri rusak, bolak-balik JSON.
- `test/unit/plus_controller_test.dart` — cache offline, token tak sah,
  tenggang cadangan 7 hari, transisi status, jam dimundurkan, cache 12 jam,
  gagal jaringan, pembelian/pemulihan, alur demo lengkap.
- `test/unit/plus_stores_test.dart` — SharedPreferences config/token/
  checkpoint dan cache rusak.

Perintah: `flutter test test/unit/plus_*_test.dart` dan `flutter analyze`.
Seluruh suite saat dokumen ini diperbarui: 564 tes lulus, analyzer bersih.
Rincian layar D1–D9 dan animasinya ada di `docs/plus_layar.md`.

Belum diuji: pembayaran nyata, backend konfigurasi nyata, penerbitan token
produksi, dan perangkat fisik.
