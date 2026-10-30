# Backend

Backend sengaja **tipis**: akun, direktori kunci, undangan, relay SOS, sinkronisasi.
Server tidak membaca isi pesan.

Keputusan (2026-10-25): **Supabase** untuk autentikasi dan data; login memakai
**OAuth Google/Apple**. Firebase tidak dipakai.

- `migrations/0001_init.sql`: skema awal PostgreSQL/Supabase. Status **DRAFT,
  belum dijalankan**.
- `migrations/0002_auth_groups.sql`: fungsi security definer untuk profil,
  direktori kunci, undangan, grup, dan blob kunci; menghapus penulisan profil
  langsung. Status **DRAFT, belum dijalankan** dan belum diuji sama sekali.
- `functions/` (belum dibuat): fungsi server untuk `ingest_sos`, `dispatch_sos`,
  `publish_last_known`, `delete_account`, `cleanup_retention`.
- Semua perubahan status undangan, keanggotaan, grup, dan blob kunci lewat fungsi
  server, bukan tulis langsung dari klien.
- Klien hanya memakai publishable key Supabase. Service role key tidak boleh
  dimasukkan ke aplikasi.

RPC yang diharapkan klien:

| RPC | Tujuan |
|---|---|
| `register_profile(p_username, p_public_key)` | Daftarkan/ubah kunci perangkat; username tidak dapat diubah. |
| `lookup_user(p_username)` | Cari satu profil dengan username persis. |
| `create_group(p_name, p_mountain)` | Buat grup + keanggotaan pemilik. |
| `invite_user(p_group_id, p_username)` | Undang pengguna; hanya pemilik. Undangan pending yang sudah kedaluwarsa ditandai `expired` agar tidak memblokir undangan baru. |
| `my_groups()` | Grup dan peran pengguna. |
| `my_pending_invitations()` | Undangan pending yang belum kedaluwarsa. |
| `respond_invitation(p_invitation_id, p_accept)` | Terima/tolak; hanya penerima. |
| `group_members_directory(p_group_id)` | Username + kunci publik anggota; hanya anggota. |
| `publish_group_keys(p_group_id, p_key_version, p_wrapped_keys)` | Simpan blob kunci; hanya pemilik, tepat satu blob per anggota. |
| `remove_group_member(p_group_id, p_user_id)` | Hapus anggota, hapus blob-nya, naikkan versi kunci. |

Peringatan: migrasi belum pernah diparse PostgreSQL karena tidak ada PostgreSQL
di mesin pengembangan. Risiko kesalahan SQL/RLS tinggi sampai diuji di staging.
Lihat `docs/security_review.md` untuk daftar hal yang harus ditinjau ahli
keamanan.
