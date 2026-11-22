-- ============================================================================
-- Migrasi 005: Status Hiqeo Plus di Profil & Aktivasi untuk 2 Akun Google Testing
-- Proyek: Hiqeo (Supabase Postgres)
--
-- CARA PAKAI:
-- 1. Ganti placeholder 'email_akun_1@gmail.com' dan 'email_akun_2@gmail.com'
--    di bagian bawah dengan alamat email Google kedua akun pengujian Anda.
-- 2. Jalankan seluruh skrip ini di Supabase SQL Editor.
-- 3. Kedua akun wajib sudah pernah masuk (login Google) minimal 1x agar baris
--    `auth.users` sudah terbentuk. Setelah dijalankan, buka ulang aplikasi
--    Hiqeo (dalam keadaan online) -> status Hiqeo Plus langsung tersinkron
--    dan tersimpan di cache lokal sehingga tetap aktif saat mode offline.
-- ============================================================================

-- 1. Tambahkan kolom entitlement Hiqeo Plus pada `public.profiles` (idempoten)
alter table public.profiles
  add column if not exists is_plus boolean not null default false,
  add column if not exists plus_plan_id text,
  add column if not exists plus_expires_at timestamptz;

comment on column public.profiles.is_plus is 'Status aktif Hiqeo Plus yang disinkronkan server ke cache lokal perangkat.';
comment on column public.profiles.plus_plan_id is 'ID paket Plus aktif (mis. lifetime, yearly, monthly).';
comment on column public.profiles.plus_expires_at is 'Waktu kedaluwarsa UTC; NULL berarti berlaku selamanya (lifetime).';

-- 2. Lindungi kolom Plus agar klien tidak dapat memodifikasinya secara langsung
--    melalui API anon/authenticated (hanya postgres / service_role yang boleh).
create or replace function public.guard_profile_plus_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if (
    new.is_plus is distinct from old.is_plus
    or new.plus_plan_id is distinct from old.plus_plan_id
    or new.plus_expires_at is distinct from old.plus_expires_at
  ) then
    if current_user not in ('postgres', 'service_role', 'supabase_admin') then
      raise exception 'DIRECT_PLUS_UPDATE_FORBIDDEN'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_profile_plus_update on public.profiles;
create trigger trg_guard_profile_plus_update
  before update on public.profiles
  for each row
  execute function public.guard_profile_plus_update();

revoke update (is_plus, plus_plan_id, plus_expires_at)
  on public.profiles
  from anon, authenticated;

revoke all on function public.guard_profile_plus_update() from public;

-- 3. Aktifkan Hiqeo Plus (lifetime) untuk 2 akun Google testing
--    GANTI kedua alamat email di bawah sebelum menjalankan di SQL Editor!
with target_users as (
  select
    u.id,
    u.email,
    coalesce(
      nullif(btrim(u.raw_user_meta_data->>'full_name'), ''),
      nullif(btrim(u.raw_user_meta_data->>'name'), '')
    ) as full_name,
    coalesce(
      nullif(btrim(u.raw_user_meta_data->>'avatar_url'), ''),
      nullif(btrim(u.raw_user_meta_data->>'picture'), '')
    ) as avatar_url
  from auth.users u
  where lower(u.email) in (
    lower('email_akun_1@gmail.com'),
    lower('email_akun_2@gmail.com')
  )
)
insert into public.profiles (
  id,
  email,
  full_name,
  avatar_url,
  is_plus,
  plus_plan_id,
  plus_expires_at,
  updated_at
)
select
  tu.id,
  tu.email,
  tu.full_name,
  tu.avatar_url,
  true,
  'lifetime',
  null,
  now()
from target_users tu
on conflict (id) do update
  set is_plus = true,
      plus_plan_id = 'lifetime',
      plus_expires_at = null,
      email = coalesce(public.profiles.email, excluded.email),
      updated_at = now();

-- 4. Verifikasi hasil aktivasi (cek apakah kedua akun muncul dengan is_plus = true)
select
  p.id,
  u.email,
  p.username,
  p.is_plus,
  p.plus_plan_id,
  p.plus_expires_at
from public.profiles p
join auth.users u on u.id = p.id
where lower(u.email) in (
  lower('email_akun_1@gmail.com'),
  lower('email_akun_2@gmail.com')
);
