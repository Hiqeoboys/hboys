-- ============================================================================
-- Migrasi 001: Penggantian Username, Jeda 7 Hari, & Moderasi Server-Side
-- Proyek: Hiqeo (Supabase Postgres)
--
-- CATATAN: Jalankan migrasi ini di Supabase SQL Editor bersama
-- `002_seed_blocked_terms.sql`. Jangan menjalankan langsung dari klien.
--
-- ASUMSI:
-- 1. Tabel `public.profiles` sudah ada dengan kolom `id uuid primary key`
--    yang merujuk ke `auth.users(id)` dan kolom `username text`.
-- 2. Pembaruan profil selain kolom `username` dan `username_changed_at`
--    tetap boleh dilakukan sesuai kebijakan RLS yang sudah ada.
-- ============================================================================

-- 1. Kolom waktu perubahan username terakhir & indeks unik case-insensitive
alter table public.profiles
  add column if not exists username_changed_at timestamptz;

create unique index if not exists idx_profiles_username_lower_unique
  on public.profiles (lower(username))
  where username is not null;

-- 2. Tabel daftar kata terlarang di server (TIDAK pernah dikirim ke klien)
create table if not exists public.blocked_terms (
  id bigserial primary key,
  term text not null unique,
  category text not null check (
    category in (
      'reserved',
      'profanity_id',
      'profanity_regional',
      'profanity_en',
      'pornography',
      'sara_hate',
      'violence'
    )
  ),
  match_mode text not null default 'substring' check (
    match_mode in ('substring', 'exact')
  ),
  created_at timestamptz not null default now()
);

-- Kunci penuh dari klien: RLS aktif tanpa policy SELECT/INSERT/UPDATE/DELETE.
alter table public.blocked_terms enable row level security;
revoke all on table public.blocked_terms from public, anon, authenticated;

-- 3. Normalisasi moderasi:
--    lowercase -> leetspeak (0=o,1=i,3=e,4=a,5=s,7=t,@=a,$=s) ->
--    hapus pemisah (., _, spasi, -) -> ciutkan pengulangan huruf berturut-turut.
create or replace function public.normalize_username(input text)
returns text
language plpgsql
immutable
strict
set search_path = public
as $$
declare
  v text;
begin
  v := lower(input);
  v := translate(v, '013457@$', 'oieastas');
  v := regexp_replace(v, '[._\-\s]+', '', 'g');
  v := regexp_replace(v, '(.)\1+', '\1', 'g');
  return v;
end;
$$;

-- 4. Pemeriksa kepatuhan format username (3–20 karakter [a-z0-9_.], tidak
--    diawali/diakhiri titik atau garis bawah, tanpa dua titik berurutan).
create or replace function public.is_username_format_valid(input text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select
    input is not null
    and length(input) between 3 and 20
    and input ~ '^[a-z0-9_.]{3,20}$'
    and input !~ '^[._]'
    and input !~ '[._]$'
    and position('..' in input) = 0;
$$;

-- 5. Pemeriksa apakah username menyentuh tabel blocked_terms.
create or replace function public.is_username_blocked(input text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  with normalized as (
    select
      lower(trim(input)) as raw_val,
      public.normalize_username(input) as norm_val
  )
  select exists (
    select 1
    from public.blocked_terms bt, normalized n
    where (
      bt.match_mode = 'exact'
      and (n.raw_val = bt.term or n.norm_val = bt.term)
    ) or (
      bt.match_mode = 'substring'
      and length(bt.term) >= 3
      and position(bt.term in n.norm_val) > 0
    )
  );
$$;

-- 6. Guard trigger untuk mencegah UPDATE langsung kolom username /
--    username_changed_at dari klien (pertahanan berlapis di samping REVOKE).
create or replace function public.guard_profile_username_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if (
    new.username is distinct from old.username
    or new.username_changed_at is distinct from old.username_changed_at
  ) then
    if coalesce(current_setting('app.allow_username_update', true), '') <> 'on'
       and current_user not in ('postgres', 'service_role') then
      raise exception 'DIRECT_USERNAME_UPDATE_FORBIDDEN'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_profile_username_update on public.profiles;
create trigger trg_guard_profile_username_update
  before update on public.profiles
  for each row
  execute function public.guard_profile_username_update();

-- Cabut hak UPDATE langsung kolom username & username_changed_at dari klien.
revoke update (username, username_changed_at) on public.profiles from anon, authenticated;

-- 7. RPC utama: public.set_username(new_username text)
--    Mengembalikan JSONB:
--    - sukses : { "ok": true, "username": "...", "username_changed_at": "..." }
--    - gagal  : { "ok": false, "error": "invalid_format" | "blocked" | "taken" | "cooldown:N" }
create or replace function public.set_username(new_username text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_candidate text;
  v_old_username text;
  v_old_changed_at timestamptz;
  v_profile_exists boolean := false;
  v_old_compliant boolean;
  v_remaining_seconds double precision;
  v_remaining_days integer;
  v_now timestamptz := now();
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  v_candidate := lower(trim(coalesce(new_username, '')));
  if left(v_candidate, 1) = '@' then
    v_candidate := substr(v_candidate, 2);
  end if;

  -- (a) Validasi format
  if not public.is_username_format_valid(v_candidate) then
    return jsonb_build_object('ok', false, 'error', 'invalid_format');
  end if;

  -- (b) Moderasi kata terlarang & kata cadangan
  if public.is_username_blocked(v_candidate) then
    return jsonb_build_object('ok', false, 'error', 'blocked');
  end if;

  -- Ambil data profil saat ini (lock baris agar aman terhadap race condition)
  select p.username, p.username_changed_at
    into v_old_username, v_old_changed_at
    from public.profiles p
   where p.id = v_uid
     for update;
  v_profile_exists := found;

  -- Jika username sama persis (case-insensitive), tidak perlu memakan kuota jeda
  if v_old_username is not null and lower(v_old_username) = v_candidate then
    return jsonb_build_object(
      'ok', true,
      'username', v_old_username,
      'username_changed_at', v_old_changed_at
    );
  end if;

  -- (c) Cek jeda 7 hari:
  --     - Pengaturan pertama (v_old_username is null atau v_old_changed_at is null): boleh langsung.
  --     - Username lama tidak memenuhi aturan saat ini: boleh langsung diperbaiki.
  v_old_compliant :=
    v_old_username is not null
    and public.is_username_format_valid(lower(v_old_username))
    and not public.is_username_blocked(v_old_username);

  if v_old_compliant and v_old_changed_at is not null then
    v_remaining_seconds :=
      extract(epoch from ((v_old_changed_at + interval '7 days') - v_now));
    if v_remaining_seconds > 0 then
      v_remaining_days := greatest(1, ceil(v_remaining_seconds / 86400.0)::integer);
      return jsonb_build_object(
        'ok', false,
        'error', format('cooldown:%s', v_remaining_days)
      );
    end if;
  end if;

  -- (d) Cek keunikan case-insensitive
  if exists (
    select 1
    from public.profiles p
    where lower(p.username) = v_candidate
      and p.id <> v_uid
  ) then
    return jsonb_build_object('ok', false, 'error', 'taken');
  end if;

  -- (e) Simpan username baru (buka guard lokal khusus transaksi ini)
  perform set_config('app.allow_username_update', 'on', true);

  if not v_profile_exists then
    insert into public.profiles (id, username, username_changed_at)
    values (v_uid, v_candidate, v_now)
    on conflict (id) do update
      set username = excluded.username,
          username_changed_at = excluded.username_changed_at;
  else
    update public.profiles
       set username = v_candidate,
           username_changed_at = v_now
     where id = v_uid;
  end if;

  return jsonb_build_object(
    'ok', true,
    'username', v_candidate,
    'username_changed_at', v_now
  );
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'error', 'taken');
end;
$$;

-- 8. Hak eksekusi minimal: REVOKE ALL dari public, GRANT EXECUTE ke authenticated.
revoke all on function public.normalize_username(text) from public;
revoke all on function public.is_username_format_valid(text) from public;
revoke all on function public.is_username_blocked(text) from public;
revoke all on function public.guard_profile_username_update() from public;
revoke all on function public.set_username(text) from public;

grant execute on function public.set_username(text) to authenticated;
