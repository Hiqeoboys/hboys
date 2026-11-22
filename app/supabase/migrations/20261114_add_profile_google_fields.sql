-- ============================================================================
-- MIGRASI: Tambah Kolom Profil Google dan Perbarui Trigger Akun
-- Project: Hiqeo (id.nama.nama_app)
-- ============================================================================

-- 1. Tambahkan kolom full_name, avatar_url, email, dan updated_at pada public.profiles
alter table public.profiles
  add column if not exists full_name text,
  add column if not exists avatar_url text,
  add column if not exists email text,
  add column if not exists updated_at timestamptz default now();

-- 2. Perbarui fungsi trigger handle_new_user untuk mengekstrak data nama & foto
--    dari metadata OAuth Google (`raw_user_meta_data`).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  insert into public.profiles (
    id,
    full_name,
    avatar_url,
    email,
    username,
    public_key,
    created_at,
    updated_at
  )
  values (
    new.id,
    coalesce(
      nullif(btrim(new.raw_user_meta_data->>'full_name'), ''),
      nullif(btrim(new.raw_user_meta_data->>'name'), '')
    ),
    coalesce(
      nullif(btrim(new.raw_user_meta_data->>'avatar_url'), ''),
      nullif(btrim(new.raw_user_meta_data->>'picture'), '')
    ),
    new.email,
    null,
    null,
    now(),
    now()
  )
  on conflict (id) do update set
    full_name = coalesce(excluded.full_name, public.profiles.full_name),
    avatar_url = coalesce(excluded.avatar_url, public.profiles.avatar_url),
    email = coalesce(excluded.email, public.profiles.email),
    updated_at = now();
  return new;
end;
$$;

-- 3. Pastikan trigger aktif pada auth.users
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 4. RLS Policy: Pengguna dapat membaca dan memperbarui profil mereka sendiri
alter table public.profiles enable row level security;

drop policy if exists profiles_self_read on public.profiles;
create policy profiles_self_read on public.profiles
  for select using (id = auth.uid());

drop policy if exists profiles_self_update on public.profiles;
create policy profiles_self_update on public.profiles
  for update using (id = auth.uid()) with check (id = auth.uid());
