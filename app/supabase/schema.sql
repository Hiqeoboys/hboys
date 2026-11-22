-- ============================================================================
-- SKEMA LENGKAP SUPABASE UNTUK PROYEK BARU
-- Aplikasi: Hiqeo (nama_app)
-- Dihasilkan otomatis berdasarkan analisis kode aplikasi & riwayat migrasi.
-- ============================================================================
-- Jalankan skrip ini langsung di Supabase SQL Editor pada proyek baru Anda.
-- Urutan eksekusi:
-- 1. Ekstensi PostgreSQL
-- 2. Tipe Kustom (Enum)
-- 3. Tabel-tabel Utama
-- 4. Fungsi & Trigger (termasuk trigger auth.users -> profiles)
-- 5. Fungsi RPC Server (Security Definer untuk Profil, Grup, Undangan, Kunci)
-- 6. Row Level Security (RLS) & Kebijakan Akses
-- 7. Storage Bucket (Opsional) & Seed Data
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. EKSTENSI POSTGRESQL
-- ----------------------------------------------------------------------------
create extension if not exists pgcrypto with schema extensions;
create extension if not exists citext with schema extensions;

grant usage on schema extensions to postgres, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. TIPE KUSTOM (ENUM)
-- ----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'invitation_status') then
    create type invitation_status as enum (
      'pending',
      'accepted',
      'rejected',
      'expired',
      'cancelled'
    );
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 3. TABEL-TABEL UTAMA
-- ----------------------------------------------------------------------------

-- [Tabel 1] profiles: Menyimpan profil publik dan kunci publik perangkat (X25519)
-- ASUMSI: Kolom username dan public_key dibuat NULLABLE agar trigger otomatis dari
-- auth.users dapat membuat baris profil awal saat pengguna baru mendaftar lewat
-- Google OAuth. Setelah itu, pengguna melengkapi username & public_key lewat RPC
-- `register_profile` di dalam aplikasi.
-- Menggunakan tipe data standard `text` dengan validasi regex huruf kecil agar tidak
-- bergantung pada skema citext dan mencegah error type does not exist.
create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  username    text unique check (username is null or username ~ '^[a-z0-9_.]{3,20}$'),
  public_key  text,                                    -- Kunci publik X25519 perangkat (base64 44 karakter)
  full_name   text,
  avatar_url  text,
  email       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.profiles is 'Profil publik pengguna dan direktori kunci publik perangkat.';

-- [Tabel 2] groups: Menyimpan informasi grup pendakian
create table if not exists public.groups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(btrim(name)) between 1 and 60),
  owner_id    uuid not null references public.profiles (id) on delete cascade,
  mountain    text check (mountain is null or char_length(btrim(mountain)) <= 80),
  key_version integer not null default 1,
  created_at  timestamptz not null default now()
);

comment on table public.groups is 'Grup pendakian dengan versi kunci enkripsi.';

-- [Tabel 3] group_members: Relasi keanggotaan pengguna di dalam grup
create table if not exists public.group_members (
  group_id  uuid not null references public.groups (id) on delete cascade,
  user_id   uuid not null references public.profiles (id) on delete cascade,
  role      text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

comment on table public.group_members is 'Daftar anggota dan peran pengguna di dalam grup.';

-- [Tabel 4] invitations: Undangan bergabung ke dalam grup
create table if not exists public.invitations (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.groups (id) on delete cascade,
  inviter_id   uuid not null references public.profiles (id) on delete cascade,
  invitee_id   uuid not null references public.profiles (id) on delete cascade,
  status       invitation_status not null default 'pending',
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default (now() + interval '7 days'),
  responded_at timestamptz,
  constraint no_self_invite check (inviter_id <> invitee_id)
);

-- Hanya boleh ada satu undangan berstatus 'pending' per pasangan (grup, pengguna)
create unique index if not exists one_pending_invite
  on public.invitations (group_id, invitee_id)
  where status = 'pending';

comment on table public.invitations is 'Undangan masuk ke grup pendakian.';

-- [Tabel 5] group_key_blobs: Blob kunci simetris terenkripsi per anggota per versi grup
-- Server hanya bertindak sebagai relay blob terenkripsi dan tidak memiliki kunci privat.
create table if not exists public.group_key_blobs (
  group_id    uuid not null references public.groups (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  key_version integer not null,
  wrapped_key text not null,                          -- Kunci simetris grup dibungkus dengan public key anggota
  created_at  timestamptz not null default now(),
  primary key (group_id, user_id, key_version)
);

comment on table public.group_key_blobs is 'Kunci grup terenkripsi untuk tiap anggota.';

-- [Tabel 6] emergency_contacts: Kontak darurat pengguna
create table if not exists public.emergency_contacts (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles (id) on delete cascade,
  name            text not null,
  phone_e164      text not null check (phone_e164 ~ '^\+[0-9]{8,15}$'),
  channel         text not null default 'sms' check (channel in ('sms', 'whatsapp')),
  consent_status  text not null default 'pending' check (consent_status in ('pending', 'granted', 'revoked')),
  consent_at      timestamptz,
  created_at      timestamptz not null default now()
);

comment on table public.emergency_contacts is 'Daftar kontak darurat pengguna untuk relay SOS.';

-- [Tabel 7] sos_events: Kejadian SOS darurat yang dikirim perangkat
create table if not exists public.sos_events (
  id           uuid primary key,                      -- ID dibuat di perangkat (idempoten saat di-retry)
  author_id    uuid not null references public.profiles (id) on delete cascade,
  group_id     uuid references public.groups (id) on delete set null,
  category     smallint not null,
  lat          double precision not null check (lat between -90 and 90),
  lon          double precision not null check (lon between -180 and 180),
  accuracy_m   integer,
  battery_pct  smallint check (battery_pct between 0 and 100),
  created_at   timestamptz not null,                  -- Waktu perekaman di perangkat (UTC)
  received_at  timestamptz not null default now(),    -- Waktu diterima server (UTC)
  signature    text,                                  -- Tanda tangan digital perangkat (base64)
  status       text not null default 'active' check (status in ('active', 'cancelled', 'resolved')),
  cancelled_at timestamptz
);

create index if not exists sos_active_idx
  on public.sos_events (status, received_at desc);

comment on table public.sos_events is 'Event darurat SOS dari pengguna.';

-- [Tabel 8] sos_dispatch_log: Log pengiriman relay SOS ke kontak/anggota
create table if not exists public.sos_dispatch_log (
  id           bigserial primary key,
  sos_id       uuid not null references public.sos_events (id) on delete cascade,
  target_kind  text not null check (target_kind in ('emergency_contact', 'group_member')),
  target_ref   uuid not null,
  channel      text not null,
  status       text not null check (status in ('queued', 'sent', 'delivered', 'failed')),
  attempted_at timestamptz not null default now(),
  detail       text
);

comment on table public.sos_dispatch_log is 'Riwayat dispatch notifikasi darurat SOS.';

-- [Tabel 9] last_known_locations: Lokasi terakhir pengguna untuk pemantauan grup
create table if not exists public.last_known_locations (
  user_id      uuid primary key references public.profiles (id) on delete cascade,
  lat          double precision not null check (lat between -90 and 90),
  lon          double precision not null check (lon between -180 and 180),
  accuracy_m   integer,
  battery_pct  smallint check (battery_pct between 0 and 100),
  recorded_at  timestamptz not null,                  -- Waktu GPS di perangkat
  received_at  timestamptz not null default now()
);

comment on table public.last_known_locations is 'Posisi GPS terakhir anggota grup untuk sinkronisasi.';

-- ----------------------------------------------------------------------------
-- 4. FUNGSI PEMBANTU & TRIGGER OTOMATIS
-- ----------------------------------------------------------------------------

-- Fungsi untuk memeriksa apakah pemanggil saat ini (auth.uid()) adalah anggota grup tertentu
create or replace function public.is_group_member(gid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1
    from public.group_members
    where group_id = gid and user_id = auth.uid()
  );
$$;

-- Trigger: Otomatis membuat baris profil di public.profiles saat user baru mendaftar di auth.users
-- ASUMSI: Username dan public_key dibiarkan null terlebih dahulu sampai user mengisi
-- username dan mengunggah public key perangkat melalui antarmuka pendaftaran di aplikasi.
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

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ----------------------------------------------------------------------------
-- 5. FUNGSI SERVER (RPC) SECURITY DEFINER
-- ----------------------------------------------------------------------------

-- [RPC 1] register_profile: Mendaftarkan username dan public key perangkat (X25519)
create or replace function public.register_profile(
  p_username text,
  p_public_key text
)
returns table (id uuid, username text, public_key text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_username text;
  v_existing public.profiles%rowtype;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  v_username := lower(btrim(coalesce(p_username, '')));
  if v_username !~ '^[a-z0-9_.]{3,20}$' then
    raise exception 'USERNAME_INVALID';
  end if;

  -- Kunci publik X25519: 32 byte, base64 standar 44 karakter (diakhiri dengan '=')
  if p_public_key is null
     or length(p_public_key) <> 44
     or p_public_key !~ '^[A-Za-z0-9+/]{43}=$'
     or length(decode(p_public_key, 'base64')) <> 32 then
    raise exception 'PUBLIC_KEY_INVALID';
  end if;

  select * into v_existing from public.profiles p where p.id = v_uid;

  if found then
    -- Jika sudah memiliki username dan berbeda dari input, username tidak boleh diubah
    if v_existing.username is not null and v_existing.username <> v_username then
      raise exception 'USERNAME_IMMUTABLE';
    end if;

    update public.profiles p
    set username = v_username,
        public_key = p_public_key
    where p.id = v_uid;

    -- Bila kunci publik perangkat berubah, hapus blob kunci grup lama karena perangkat baru
    -- tidak bisa membukanya. Naikkan juga versi kunci untuk grup yang dimiliki user ini.
    if v_existing.public_key is not null and v_existing.public_key <> p_public_key then
      delete from public.group_key_blobs b where b.user_id = v_uid;
      update public.groups g
      set key_version = g.key_version + 1
      where g.owner_id = v_uid;
    end if;
  else
    insert into public.profiles (id, username, public_key)
    values (v_uid, v_username, p_public_key);
  end if;

  return query
    select p.id, p.username::text, p.public_key
    from public.profiles p
    where p.id = v_uid;
exception
  when unique_violation then
    raise exception 'USERNAME_TAKEN';
end;
$$;

-- [RPC 2] lookup_user: Mencari pengguna berdasarkan username persis (untuk undangan)
create or replace function public.lookup_user(p_username text)
returns table (id uuid, username text, public_key text)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_username text;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid and p.username is not null) then
    raise exception 'PROFILE_REQUIRED';
  end if;

  v_username := lower(btrim(coalesce(p_username, '')));
  if v_username !~ '^[a-z0-9_.]{3,20}$' then
    return;
  end if;

  return query
    select p.id, p.username::text, p.public_key
    from public.profiles p
    where p.username = v_username;
end;
$$;

-- [RPC 3] create_group: Membuat grup baru dan menambahkan pembuat sebagai pemilik
create or replace function public.create_group(
  p_name text,
  p_mountain text default null
)
returns table (
  id uuid,
  name text,
  owner_id uuid,
  mountain text,
  key_version integer,
  created_at timestamptz,
  role text
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_group public.groups%rowtype;
  v_mountain text;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid and p.username is not null) then
    raise exception 'PROFILE_REQUIRED';
  end if;
  if p_name is null or char_length(btrim(p_name)) not between 1 and 60 then
    raise exception 'GROUP_NAME_INVALID';
  end if;

  v_mountain := nullif(btrim(coalesce(p_mountain, '')), '');
  if v_mountain is not null and char_length(v_mountain) > 80 then
    raise exception 'GROUP_NAME_INVALID';
  end if;

  insert into public.groups (name, owner_id, mountain)
  values (btrim(p_name), v_uid, v_mountain)
  returning * into v_group;

  insert into public.group_members (group_id, user_id, role)
  values (v_group.id, v_uid, 'owner');

  return query
    select g.id, g.name, g.owner_id, g.mountain, g.key_version,
           g.created_at, 'owner'::text
    from public.groups g
    where g.id = v_group.id;
end;
$$;

-- [RPC 4] invite_user: Mengundang pengguna lain ke dalam grup berdasarkan username
create or replace function public.invite_user(
  p_group_id uuid,
  p_username text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_username text;
  v_invitee uuid;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid and p.username is not null) then
    raise exception 'PROFILE_REQUIRED';
  end if;

  select g.owner_id into v_owner from public.groups g where g.id = p_group_id;
  if not found then
    raise exception 'GROUP_NOT_FOUND';
  end if;
  if v_owner <> v_uid then
    raise exception 'OWNER_REQUIRED';
  end if;

  v_username := lower(btrim(coalesce(p_username, '')));
  select p.id into v_invitee from public.profiles p where p.username = v_username;
  if not found then
    raise exception 'USER_NOT_FOUND';
  end if;

  if exists (
    select 1 from public.group_members m
    where m.group_id = p_group_id and m.user_id = v_invitee
  ) then
    raise exception 'ALREADY_MEMBER';
  end if;

  -- Tandai undangan kedaluwarsa agar tidak memblokir undangan baru
  update public.invitations i
  set status = 'expired', responded_at = now()
  where i.group_id = p_group_id
    and i.invitee_id = v_invitee
    and i.status = 'pending'
    and i.expires_at <= now();

  begin
    insert into public.invitations (group_id, inviter_id, invitee_id)
    values (p_group_id, v_uid, v_invitee);
  exception
    when unique_violation then
      raise exception 'INVITE_PENDING';
  end;
end;
$$;

-- [RPC 5] my_groups: Mendapatkan seluruh grup tempat pengguna menjadi anggota/pemilik
create or replace function public.my_groups()
returns table (
  id uuid,
  name text,
  owner_id uuid,
  mountain text,
  key_version integer,
  created_at timestamptz,
  role text
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid and p.username is not null) then
    raise exception 'PROFILE_REQUIRED';
  end if;

  return query
    select g.id, g.name, g.owner_id, g.mountain, g.key_version,
           g.created_at, m.role
    from public.group_members m
    join public.groups g on g.id = m.group_id
    where m.user_id = v_uid
    order by m.joined_at asc;
end;
$$;

-- [RPC 6] my_pending_invitations: Mendapatkan daftar undangan pending yang masuk
create or replace function public.my_pending_invitations()
returns table (
  id uuid,
  group_id uuid,
  group_name text,
  inviter_username text,
  created_at timestamptz,
  expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  return query
    select i.id, i.group_id, g.name, inviter.username::text,
           i.created_at, i.expires_at
    from public.invitations i
    join public.groups g on g.id = i.group_id
    join public.profiles inviter on inviter.id = i.inviter_id
    where i.invitee_id = v_uid
      and i.status = 'pending'
      and i.expires_at > now()
    order by i.created_at desc;
end;
$$;

-- [RPC 7] respond_invitation: Menerima atau menolak undangan grup
create or replace function public.respond_invitation(
  p_invitation_id uuid,
  p_accept boolean
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_invitation public.invitations%rowtype;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select * into v_invitation
  from public.invitations i
  where i.id = p_invitation_id
  for update;

  if not found then
    raise exception 'INVITATION_NOT_FOUND';
  end if;
  if v_invitation.invitee_id <> v_uid then
    raise exception 'NOT_INVITEE';
  end if;
  if v_invitation.status <> 'pending' then
    raise exception 'INVITATION_NOT_PENDING';
  end if;

  if v_invitation.expires_at <= now() then
    update public.invitations i
    set status = 'expired', responded_at = now()
    where i.id = p_invitation_id;
    return 'expired';
  end if;

  if p_accept then
    insert into public.group_members (group_id, user_id, role)
    values (v_invitation.group_id, v_uid, 'member')
    on conflict (group_id, user_id) do nothing;

    update public.invitations i
    set status = 'accepted', responded_at = now()
    where i.id = p_invitation_id;
    return 'accepted';
  end if;

  update public.invitations i
  set status = 'rejected', responded_at = now()
  where i.id = p_invitation_id;
  return 'rejected';
end;
$$;

-- [RPC 8] group_members_directory: Menampilkan direktori kunci publik anggota grup
create or replace function public.group_members_directory(p_group_id uuid)
returns table (
  user_id uuid,
  username text,
  role text,
  public_key text,
  joined_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid and p.username is not null) then
    raise exception 'PROFILE_REQUIRED';
  end if;
  if not exists (
    select 1 from public.group_members m
    where m.group_id = p_group_id and m.user_id = v_uid
  ) then
    raise exception 'NOT_MEMBER';
  end if;

  return query
    select m.user_id, p.username::text, m.role, p.public_key, m.joined_at
    from public.group_members m
    join public.profiles p on p.id = m.user_id
    where m.group_id = p_group_id
    order by m.joined_at asc;
end;
$$;

-- [RPC 9] publish_group_keys: Pemilik grup menerbitkan blob kunci terenkripsi untuk semua anggota
create or replace function public.publish_group_keys(
  p_group_id uuid,
  p_key_version integer,
  p_wrapped_keys jsonb
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_version integer;
  v_count integer;
  v_distinct integer;
  v_member_count integer;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid and p.username is not null) then
    raise exception 'PROFILE_REQUIRED';
  end if;

  select g.key_version into v_version
  from public.groups g
  where g.id = p_group_id
  for update;

  if not found then
    raise exception 'GROUP_NOT_FOUND';
  end if;
  if not exists (
    select 1 from public.group_members m
    where m.group_id = p_group_id and m.user_id = v_uid and m.role = 'owner'
  ) then
    raise exception 'OWNER_REQUIRED';
  end if;
  if p_key_version is null or p_key_version <> v_version then
    raise exception 'KEY_VERSION_INVALID';
  end if;

  if p_wrapped_keys is null or jsonb_typeof(p_wrapped_keys) <> 'array' then
    raise exception 'MISSING_MEMBER_KEY';
  end if;

  -- Validasi skema item JSON sebelum casting
  if exists (
    select 1
    from jsonb_array_elements(p_wrapped_keys) elem
    where jsonb_typeof(elem) <> 'object'
       or (elem->>'user_id') is null
       or (elem->>'user_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or (elem->>'wrapped_key') is null
       or char_length(elem->>'wrapped_key') not between 64 and 4096
       or char_length(elem->>'wrapped_key') % 4 <> 0
       or (elem->>'wrapped_key') !~ '^[A-Za-z0-9+/]+={0,2}$'
  ) then
    raise exception 'MISSING_MEMBER_KEY';
  end if;

  select count(*), count(distinct lower(elem->>'user_id'))
  into v_count, v_distinct
  from jsonb_array_elements(p_wrapped_keys) elem;

  if v_count <> v_distinct then
    raise exception 'RECIPIENT_NOT_MEMBER';
  end if;

  select count(*) into v_member_count
  from public.group_members m
  where m.group_id = p_group_id;

  if v_count <> v_member_count then
    if exists (
      select 1
      from jsonb_array_elements(p_wrapped_keys) elem
      where not exists (
        select 1 from public.group_members m
        where m.group_id = p_group_id
          and m.user_id = (elem->>'user_id')::uuid
      )
    ) then
      raise exception 'RECIPIENT_NOT_MEMBER';
    end if;
    raise exception 'MISSING_MEMBER_KEY';
  end if;

  insert into public.group_key_blobs (group_id, user_id, key_version, wrapped_key)
  select
    p_group_id,
    (elem->>'user_id')::uuid,
    p_key_version,
    elem->>'wrapped_key'
  from jsonb_array_elements(p_wrapped_keys) elem
  on conflict (group_id, user_id, key_version)
  do update set wrapped_key = excluded.wrapped_key, created_at = now();
end;
$$;

-- [RPC 10] remove_group_member: Pemilik menghapus anggota, menaikkan versi kunci grup
create or replace function public.remove_group_member(
  p_group_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select g.owner_id into v_owner
  from public.groups g
  where g.id = p_group_id
  for update;

  if not found then
    raise exception 'GROUP_NOT_FOUND';
  end if;
  if v_owner <> v_uid then
    raise exception 'OWNER_REQUIRED';
  end if;
  if p_user_id = v_owner then
    raise exception 'OWNER_IMMUTABLE';
  end if;
  if not exists (
    select 1 from public.group_members m
    where m.group_id = p_group_id and m.user_id = p_user_id
  ) then
    raise exception 'NOT_MEMBER';
  end if;

  delete from public.group_members m
  where m.group_id = p_group_id and m.user_id = p_user_id;

  delete from public.group_key_blobs b
  where b.group_id = p_group_id and b.user_id = p_user_id;

  -- Naikkan versi kunci grup agar pemilik membagikan kunci baru ke anggota tersisa
  update public.groups g
  set key_version = g.key_version + 1
  where g.id = p_group_id;
end;
$$;

-- [RPC 11] delete_my_account: Menghapus akun pengguna saat ini beserta seluruh datanya (ON DELETE CASCADE)
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  -- Menghapus baris di auth.users otomatis menghapus profiles, groups, group_members,
  -- invitations, group_key_blobs, emergency_contacts, sos_events, dan last_known_locations
  -- karena semua foreign key memakai ON DELETE CASCADE.
  delete from auth.users where id = v_uid;
end;
$$;

-- Hak eksekusi RPC hanya untuk authenticated users
revoke all on function public.register_profile(text, text) from public;
revoke all on function public.lookup_user(text) from public;
revoke all on function public.create_group(text, text) from public;
revoke all on function public.invite_user(uuid, text) from public;
revoke all on function public.my_groups() from public;
revoke all on function public.my_pending_invitations() from public;
revoke all on function public.respond_invitation(uuid, boolean) from public;
revoke all on function public.group_members_directory(uuid) from public;
revoke all on function public.publish_group_keys(uuid, integer, jsonb) from public;
revoke all on function public.remove_group_member(uuid, uuid) from public;
revoke all on function public.delete_my_account() from public;

grant execute on function public.register_profile(text, text) to authenticated;
grant execute on function public.lookup_user(text) to authenticated;
grant execute on function public.create_group(text, text) to authenticated;
grant execute on function public.invite_user(uuid, text) to authenticated;
grant execute on function public.my_groups() to authenticated;
grant execute on function public.my_pending_invitations() to authenticated;
grant execute on function public.respond_invitation(uuid, boolean) to authenticated;
grant execute on function public.group_members_directory(uuid) to authenticated;
grant execute on function public.publish_group_keys(uuid, integer, jsonb) to authenticated;
grant execute on function public.remove_group_member(uuid, uuid) to authenticated;
grant execute on function public.delete_my_account() to authenticated;

-- ----------------------------------------------------------------------------
-- 6. ROW LEVEL SECURITY (RLS) & KEBIJAKAN AKSES
-- ----------------------------------------------------------------------------

alter table public.profiles             enable row level security;
alter table public.groups               enable row level security;
alter table public.group_members        enable row level security;
alter table public.invitations          enable row level security;
alter table public.group_key_blobs      enable row level security;
alter table public.emergency_contacts   enable row level security;
alter table public.sos_events           enable row level security;
alter table public.sos_dispatch_log     enable row level security;
alter table public.last_known_locations enable row level security;

-- [RLS: profiles]
-- Pengguna hanya bisa membaca profilnya sendiri secara langsung.
-- Pencarian profil orang lain dilakukan lewat RPC `lookup_user` dengan pencocokan username persis.
drop policy if exists profiles_self_read on public.profiles;
create policy profiles_self_read on public.profiles
  for select using (id = auth.uid());

drop policy if exists profiles_self_update on public.profiles;
create policy profiles_self_update on public.profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

-- [RLS: groups]
-- Hanya anggota grup yang dapat membaca data grup. Pembuatan & perubahan lewat RPC.
drop policy if exists groups_member_read on public.groups;
create policy groups_member_read on public.groups
  for select using (public.is_group_member(id));

-- [RLS: group_members]
-- Hanya sesama anggota grup yang dapat membaca daftar keanggotaan.
drop policy if exists members_group_read on public.group_members;
create policy members_group_read on public.group_members
  for select using (public.is_group_member(group_id));

-- [RLS: invitations]
-- Pengundang atau penerima undangan dapat membaca undangan terkait.
drop policy if exists invitations_party_read on public.invitations;
create policy invitations_party_read on public.invitations
  for select using (inviter_id = auth.uid() or invitee_id = auth.uid());

-- [RLS: group_key_blobs]
-- Setiap anggota hanya bisa membaca blob kunci milik akunnya sendiri.
drop policy if exists keyblobs_self_read on public.group_key_blobs;
create policy keyblobs_self_read on public.group_key_blobs
  for select using (user_id = auth.uid());

-- [RLS: emergency_contacts]
-- Kontak darurat bersifat privat untuk pemilik akun.
drop policy if exists contacts_owner_all on public.emergency_contacts;
create policy contacts_owner_all on public.emergency_contacts
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- [RLS: sos_events]
-- Pembuat SOS atau sesama anggota grup dapat membaca event SOS.
drop policy if exists sos_author_or_group_read on public.sos_events;
create policy sos_author_or_group_read on public.sos_events
  for select using (
    author_id = auth.uid()
    or (group_id is not null and public.is_group_member(group_id))
  );

drop policy if exists sos_author_insert on public.sos_events;
create policy sos_author_insert on public.sos_events
  for insert with check (author_id = auth.uid());

drop policy if exists sos_author_update on public.sos_events;
create policy sos_author_update on public.sos_events
  for update using (author_id = auth.uid()) with check (author_id = auth.uid());

-- [RLS: sos_dispatch_log]
-- Hanya pengirim SOS atau anggota grup yang dapat membaca log pengiriman SOS terkait.
drop policy if exists sos_dispatch_read on public.sos_dispatch_log;
create policy sos_dispatch_read on public.sos_dispatch_log
  for select using (
    exists (
      select 1 from public.sos_events s
      where s.id = sos_dispatch_log.sos_id
        and (s.author_id = auth.uid() or (s.group_id is not null and public.is_group_member(s.group_id)))
    )
  );

-- [RLS: last_known_locations]
-- Pengguna sendiri dan sesama anggota grup dapat membaca posisi terakhir.
drop policy if exists last_known_group_read on public.last_known_locations;
create policy last_known_group_read on public.last_known_locations
  for select using (
    user_id = auth.uid()
    or exists (
      select 1
      from public.group_members me
      join public.group_members other on other.group_id = me.group_id
      where me.user_id = auth.uid()
        and other.user_id = last_known_locations.user_id
    )
  );

drop policy if exists last_known_self_upsert on public.last_known_locations;
create policy last_known_self_upsert on public.last_known_locations
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- 7. STORAGE BUCKET (OPSIONAL) & SEED DATA
-- ----------------------------------------------------------------------------

-- ASUMSI STORAGE:
-- Berdasarkan hasil penelusuran kode, aplikasi Hiqeo saat ini offline-first dan
-- belum menggunakan Supabase Storage (.storage). Seluruh peta dan cache disimpan lokal.
-- Jika di masa depan Anda ingin menambahkan upload avatar profil, Anda dapat
-- mengaktifkan bucket di bawah ini:
/*
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

create policy "Avatar dapat dibaca publik"
  on storage.objects for select
  using (bucket_id = 'avatars');

create policy "Pengguna hanya bisa mengunggah avatarnya sendiri"
  on storage.objects for insert
  with check (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);
*/

-- ASUMSI SEED DATA:
-- Aplikasi ini tidak membutuhkan seed data awal statis untuk berjalan karena
-- data akun, grup, dan kontak sepenuhnya dibuat secara dinamis oleh pengguna.
-- Jika ingin membuat akun pengujian atau grup percontohan, jalankan pendaftaran
-- dari antarmuka aplikasi setelah login Google pertama kali.

-- ----------------------------------------------------------------------------
-- 8. RUANG OBROLAN GRUP (group_messages), LOKASI TERAKHIR (member_locations),
--    STORAGE BUCKET VOICE NOTE (chat-voice-notes), & REALTIME
-- (Disinkronkan dengan migrasi 20261119_add_group_chat_and_member_locations.sql)
-- ----------------------------------------------------------------------------

create or replace function public.is_user_in_group(gid uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select gid is not null
    and uid is not null
    and exists (
      select 1
      from public.group_members gm
      where gm.group_id = gid
        and gm.user_id = uid
    );
$$;

create or replace function public.try_parse_uuid(raw text)
returns uuid
language plpgsql
immutable
set search_path = public, extensions
as $$
begin
  if raw is null or btrim(raw) = '' then
    return null;
  end if;
  return raw::uuid;
exception
  when invalid_text_representation then
    return null;
end;
$$;

revoke all on function public.is_user_in_group(uuid, uuid) from public;
grant execute on function public.is_user_in_group(uuid, uuid) to authenticated;

revoke all on function public.try_parse_uuid(text) from public;
grant execute on function public.try_parse_uuid(text) to authenticated;

create table if not exists public.group_messages (
  id                 uuid primary key default gen_random_uuid(),
  client_msg_id      uuid unique not null,
  group_id           uuid not null references public.groups (id) on delete cascade,
  sender_id          uuid not null references auth.users (id) on delete cascade,
  sender_name        text not null check (char_length(btrim(sender_name)) >= 1),
  message_type       text not null check (message_type in ('text', 'audio')),
  content            text,
  audio_url          text,
  audio_duration_sec integer check (audio_duration_sec is null or audio_duration_sec >= 0),
  key_version        integer not null default 1 check (key_version >= 1),
  origin_transport   text not null default 'online'
                       check (origin_transport in ('online', 'ble_mesh', 'wifi_direct')),
  client_created_at  timestamptz not null,
  created_at         timestamptz not null default now()
);

create index if not exists idx_group_messages_group_client_created
  on public.group_messages (group_id, client_created_at asc);

create or replace function public.guard_group_messages_idempotency()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  new.id := old.id;
  new.created_at := old.created_at;
  new.audio_url := coalesce(nullif(btrim(new.audio_url), ''), old.audio_url);
  new.audio_duration_sec := coalesce(new.audio_duration_sec, old.audio_duration_sec);
  return new;
end;
$$;

drop trigger if exists trg_group_messages_idempotency on public.group_messages;
create trigger trg_group_messages_idempotency
  before update on public.group_messages
  for each row execute function public.guard_group_messages_idempotency();

create table if not exists public.member_locations (
  group_id         uuid not null references public.groups (id) on delete cascade,
  user_id          uuid not null references auth.users (id) on delete cascade,
  display_name     text not null check (char_length(btrim(display_name)) >= 1),
  latitude         double precision not null check (latitude between -90 and 90),
  longitude        double precision not null check (longitude between -180 and 180),
  altitude_mdpl    integer,
  battery_percent  integer check (battery_percent is null or (battery_percent >= 0 and battery_percent <= 100)),
  source_transport text not null default 'online'
                     check (source_transport in ('online', 'ble_mesh', 'wifi_direct')),
  recorded_at      timestamptz not null,
  updated_at       timestamptz not null default now(),
  primary key (group_id, user_id)
);

create index if not exists idx_member_locations_group_recorded
  on public.member_locations (group_id, recorded_at desc);

create or replace function public.guard_member_locations_chronology()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  if new.recorded_at < old.recorded_at then
    return old;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_member_locations_guard_chronology on public.member_locations;
create trigger trg_member_locations_guard_chronology
  before update on public.member_locations
  for each row execute function public.guard_member_locations_chronology();

alter table public.group_messages   enable row level security;
alter table public.member_locations enable row level security;

drop policy if exists group_messages_member_select on public.group_messages;
create policy group_messages_member_select on public.group_messages
  for select to authenticated
  using (public.is_group_member(group_id));

drop policy if exists group_messages_member_insert on public.group_messages;
create policy group_messages_member_insert on public.group_messages
  for insert to authenticated
  with check (
    public.is_group_member(group_id)
    and public.is_user_in_group(group_id, sender_id)
  );

drop policy if exists group_messages_member_update on public.group_messages;
create policy group_messages_member_update on public.group_messages
  for update to authenticated
  using (
    public.is_group_member(group_id)
    and public.is_user_in_group(group_id, sender_id)
  )
  with check (
    public.is_group_member(group_id)
    and public.is_user_in_group(group_id, sender_id)
  );

drop policy if exists member_locations_member_select on public.member_locations;
create policy member_locations_member_select on public.member_locations
  for select to authenticated
  using (public.is_group_member(group_id));

drop policy if exists member_locations_member_insert on public.member_locations;
create policy member_locations_member_insert on public.member_locations
  for insert to authenticated
  with check (
    public.is_group_member(group_id)
    and public.is_user_in_group(group_id, user_id)
  );

drop policy if exists member_locations_member_update on public.member_locations;
create policy member_locations_member_update on public.member_locations
  for update to authenticated
  using (
    public.is_group_member(group_id)
    and public.is_user_in_group(group_id, user_id)
  )
  with check (
    public.is_group_member(group_id)
    and public.is_user_in_group(group_id, user_id)
  );

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'chat-voice-notes',
  'chat-voice-notes',
  false,
  10485760,
  array['audio/mp4', 'audio/m4a', 'audio/x-m4a', 'audio/aac']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists chat_voice_notes_member_select on storage.objects;
create policy chat_voice_notes_member_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'chat-voice-notes'
    and public.try_parse_uuid((storage.foldername(name))[1]) is not null
    and public.is_group_member(public.try_parse_uuid((storage.foldername(name))[1]))
  );

drop policy if exists chat_voice_notes_member_insert on storage.objects;
create policy chat_voice_notes_member_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'chat-voice-notes'
    and public.try_parse_uuid((storage.foldername(name))[1]) is not null
    and public.is_group_member(public.try_parse_uuid((storage.foldername(name))[1]))
  );

drop policy if exists chat_voice_notes_member_update on storage.objects;
create policy chat_voice_notes_member_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'chat-voice-notes'
    and public.try_parse_uuid((storage.foldername(name))[1]) is not null
    and public.is_group_member(public.try_parse_uuid((storage.foldername(name))[1]))
  )
  with check (
    bucket_id = 'chat-voice-notes'
    and public.try_parse_uuid((storage.foldername(name))[1]) is not null
    and public.is_group_member(public.try_parse_uuid((storage.foldername(name))[1]))
  );

alter table public.group_messages   replica identity full;
alter table public.member_locations replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'group_messages'
    ) then
      alter publication supabase_realtime add table public.group_messages;
    end if;

    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'member_locations'
    ) then
      alter publication supabase_realtime add table public.member_locations;
    end if;
  end if;
end
$$;

