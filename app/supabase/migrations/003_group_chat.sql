-- ============================================================================
-- Migrasi 003: Ruang Obrolan Grup Terenkripsi (E2EE), Pesan Suara, & Lokasi Terakhir
-- Proyek: Hiqeo (Supabase Postgres + Realtime + Storage)
--
-- AMAN UNTUK:
-- 1. Database baru (tabel belum ada).
-- 2. Upgrade dari skema lama (`20261119_add_group_chat_and_member_locations.sql`
--    atau `supabase/schema.sql`) yang sebelumnya masih memakai kolom plaintext
--    (`client_msg_id`, `content`, `audio_url`, `latitude`, `longitude`, dll.).
-- 3. Dijalankan ulang berkali-kali secara idempoten (tidak menghapus data E2EE
--    yang sudah ada jika kolom `ciphertext` sudah terpasang).
--
-- CATATAN KEAMANAN:
-- Klien TIDAK pernah mengirim isi pesan teks, audio mentah, atau koordinat
-- mentah ke server; seluruh isi dienkripsi AES-256-GCM memakai kunci grup
-- (`group_key_blobs`) sebelum diunggah.
-- ============================================================================

-- 0. Fungsi pembantu parsing UUID aman untuk kebijakan Storage (mencegah galat
--    cast UUID pada objek bucket lain karena evaluasi AND tidak selalu urut).
create or replace function public.try_parse_uuid(raw text)
returns uuid
language plpgsql
immutable
set search_path = public
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

revoke all on function public.try_parse_uuid(text) from public;
grant execute on function public.try_parse_uuid(text) to authenticated;

-- 1. Tabel pesan grup terenkripsi (`public.group_messages`)
--    Idempoten melalui `unique (group_id, client_id)` dan diurutkan oleh
--    `created_at` server.
create table if not exists public.group_messages (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  client_id uuid not null,
  kind text not null constraint chk_group_messages_kind check (kind in ('text', 'voice', 'location')),
  ciphertext text not null,
  nonce text not null,
  voice_path text,
  key_version integer not null default 1 constraint chk_group_messages_key_version check (key_version >= 1),
  created_at timestamptz not null default now(),
  constraint uq_group_messages_group_client unique (group_id, client_id)
);

-- Upgrade otomatis dari skema plaintext lama bila tabel `public.group_messages`
-- sudah terlanjur dibuat sebelum migrasi E2EE ini.
do $$
begin
  -- Hapus trigger & fungsi idempotensi lama yang merujuk kolom `audio_url`.
  drop trigger if exists trg_group_messages_idempotency on public.group_messages;
  drop function if exists public.guard_group_messages_idempotency();

  -- Jika kolom `ciphertext` belum ada, artinya tabel masih memakai skema
  -- plaintext lama: bersihkan data plaintext lama (tidak kompatibel E2EE &
  -- tidak boleh tertinggal dalam bentuk plaintext di server).
  if not exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'group_messages'
       and column_name = 'ciphertext'
  ) then
    truncate table public.group_messages;
  end if;

  -- Tambahkan kolom-kolom E2EE jika belum ada.
  alter table public.group_messages
    add column if not exists client_id uuid,
    add column if not exists kind text,
    add column if not exists ciphertext text,
    add column if not exists nonce text,
    add column if not exists voice_path text,
    add column if not exists key_version integer default 1;

  -- Hapus kolom-kolom plaintext lama (beserta indeks/constraint NOT NULL lama
  -- seperti `sender_name`, `message_type`, `client_msg_id`, `client_created_at`).
  alter table public.group_messages
    drop column if exists client_msg_id cascade,
    drop column if exists sender_name cascade,
    drop column if exists message_type cascade,
    drop column if exists content cascade,
    drop column if exists audio_url cascade,
    drop column if exists audio_duration_sec cascade,
    drop column if exists origin_transport cascade,
    drop column if exists client_created_at cascade;

  -- Tegakkan NOT NULL & default pada kolom E2EE.
  alter table public.group_messages
    alter column client_id set not null,
    alter column kind set not null,
    alter column ciphertext set not null,
    alter column nonce set not null,
    alter column key_version set default 1,
    alter column key_version set not null;

  -- Pastikan constraint unik `(group_id, client_id)` & validasi `kind`/`key_version`.
  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.group_messages'::regclass
       and conname = 'uq_group_messages_group_client'
  ) then
    alter table public.group_messages
      add constraint uq_group_messages_group_client unique (group_id, client_id);
  end if;

  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.group_messages'::regclass
       and conname = 'chk_group_messages_kind'
  ) then
    alter table public.group_messages
      add constraint chk_group_messages_kind
      check (kind in ('text', 'voice', 'location'));
  end if;

  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.group_messages'::regclass
       and conname = 'chk_group_messages_key_version'
  ) then
    alter table public.group_messages
      add constraint chk_group_messages_key_version
      check (key_version >= 1);
  end if;
end;
$$;

create index if not exists idx_group_messages_group_created
  on public.group_messages (group_id, created_at desc);

create index if not exists idx_group_messages_voice_retention
  on public.group_messages (created_at)
  where voice_path is not null;

-- 2. Tabel lokasi terakhir anggota terenkripsi (`public.member_locations`)
--    Koordinat (lat, lon, akurasi, elevasi, baterai) hanya disimpan dalam
--    `ciphertext` + `nonce` yang dienkripsi memakai kunci grup.
create table if not exists public.member_locations (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  ciphertext text not null,
  nonce text not null,
  key_version integer not null default 1 constraint chk_member_locations_key_version check (key_version >= 1),
  updated_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

-- Upgrade otomatis dari skema lokasi plaintext lama bila tabel sudah ada.
do $$
begin
  -- Hapus trigger kronologi lama yang merujuk kolom `recorded_at`.
  drop trigger if exists trg_member_locations_guard_chronology on public.member_locations;
  drop function if exists public.guard_member_locations_chronology();

  if not exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'member_locations'
       and column_name = 'ciphertext'
  ) then
    truncate table public.member_locations;
  end if;

  alter table public.member_locations
    add column if not exists ciphertext text,
    add column if not exists nonce text,
    add column if not exists key_version integer default 1,
    add column if not exists updated_at timestamptz default now();

  -- Hapus kolom koordinat plaintext lama beserta NOT NULL constraint-nya.
  alter table public.member_locations
    drop column if exists display_name cascade,
    drop column if exists latitude cascade,
    drop column if exists longitude cascade,
    drop column if exists altitude_mdpl cascade,
    drop column if exists battery_percent cascade,
    drop column if exists source_transport cascade,
    drop column if exists recorded_at cascade;

  alter table public.member_locations
    alter column ciphertext set not null,
    alter column nonce set not null,
    alter column key_version set default 1,
    alter column key_version set not null,
    alter column updated_at set default now(),
    alter column updated_at set not null;

  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.member_locations'::regclass
       and conname = 'chk_member_locations_key_version'
  ) then
    alter table public.member_locations
      add constraint chk_member_locations_key_version
      check (key_version >= 1);
  end if;
end;
$$;

create index if not exists idx_member_locations_group_updated
  on public.member_locations (group_id, updated_at desc);

-- 3. Row Level Security (RLS) ketat — hanya anggota grup yang berwenang
alter table public.group_messages enable row level security;
alter table public.member_locations enable row level security;

-- Hapus kebijakan lama dari migrasi sebelumnya agar tidak ada policy longgar tersisa.
drop policy if exists group_messages_member_select on public.group_messages;
drop policy if exists group_messages_member_insert on public.group_messages;
drop policy if exists group_messages_member_update on public.group_messages;
drop policy if exists member_locations_member_select on public.member_locations;
drop policy if exists member_locations_member_insert on public.member_locations;
drop policy if exists member_locations_member_update on public.member_locations;

drop policy if exists group_messages_select_member on public.group_messages;
create policy group_messages_select_member
  on public.group_messages
  for select
  to authenticated
  using (public.is_group_member(group_id));

drop policy if exists group_messages_insert_member on public.group_messages;
create policy group_messages_insert_member
  on public.group_messages
  for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and public.is_group_member(group_id)
  );

-- Diperlukan agar retry idempoten `upsert(..., onConflict: 'group_id,client_id')`
-- milik pengirim yang sama tidak ditolak RLS saat sinkronisasi ulang outbox.
drop policy if exists group_messages_update_own on public.group_messages;
create policy group_messages_update_own
  on public.group_messages
  for update
  to authenticated
  using (
    sender_id = auth.uid()
    and public.is_group_member(group_id)
  )
  with check (
    sender_id = auth.uid()
    and public.is_group_member(group_id)
  );

drop policy if exists group_messages_delete_own on public.group_messages;
create policy group_messages_delete_own
  on public.group_messages
  for delete
  to authenticated
  using (
    sender_id = auth.uid()
    and public.is_group_member(group_id)
  );

drop policy if exists member_locations_select_member on public.member_locations;
create policy member_locations_select_member
  on public.member_locations
  for select
  to authenticated
  using (public.is_group_member(group_id));

drop policy if exists member_locations_insert_own on public.member_locations;
create policy member_locations_insert_own
  on public.member_locations
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and public.is_group_member(group_id)
  );

drop policy if exists member_locations_update_own on public.member_locations;
create policy member_locations_update_own
  on public.member_locations
  for update
  to authenticated
  using (
    user_id = auth.uid()
    and public.is_group_member(group_id)
  )
  with check (
    user_id = auth.uid()
    and public.is_group_member(group_id)
  );

drop policy if exists member_locations_delete_own on public.member_locations;
create policy member_locations_delete_own
  on public.member_locations
  for delete
  to authenticated
  using (user_id = auth.uid());

-- 4. Bucket Storage privat `group-voice` untuk berkas pesan suara terenkripsi
--    Path objek: `<group_id>/<client_id>.enc`
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'group-voice',
  'group-voice',
  false,
  1048576, -- batas 1 MB per pesan suara (maks 60 detik AAC/Opus terenkripsi)
  array['application/octet-stream']
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists group_voice_select_member on storage.objects;
create policy group_voice_select_member
  on storage.objects
  for select
  to authenticated
  using (
    case
      when bucket_id = 'group-voice' then
        public.try_parse_uuid((storage.foldername(name))[1]) is not null
        and public.is_group_member(public.try_parse_uuid((storage.foldername(name))[1]))
      else false
    end
  );

drop policy if exists group_voice_insert_member on storage.objects;
create policy group_voice_insert_member
  on storage.objects
  for insert
  to authenticated
  with check (
    case
      when bucket_id = 'group-voice' then
        coalesce(owner, auth.uid()) = auth.uid()
        and public.try_parse_uuid((storage.foldername(name))[1]) is not null
        and public.is_group_member(public.try_parse_uuid((storage.foldername(name))[1]))
      else false
    end
  );

drop policy if exists group_voice_update_own on storage.objects;
create policy group_voice_update_own
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'group-voice'
    and owner = auth.uid()
  )
  with check (
    case
      when bucket_id = 'group-voice' then
        owner = auth.uid()
        and public.try_parse_uuid((storage.foldername(name))[1]) is not null
        and public.is_group_member(public.try_parse_uuid((storage.foldername(name))[1]))
      else false
    end
  );

drop policy if exists group_voice_delete_own on storage.objects;
create policy group_voice_delete_own
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'group-voice'
    and owner = auth.uid()
  );

-- 5. RPC Hapus grup (khusus pemilik) & Keluar dari grup (khusus anggota)
create or replace function public.delete_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  select owner_id into v_owner
    from public.groups
   where id = p_group_id;

  if not found then
    raise exception 'GROUP_NOT_FOUND' using errcode = 'P0002';
  end if;

  if v_owner <> v_uid then
    raise exception 'OWNER_REQUIRED' using errcode = '42501';
  end if;

  -- Bersihkan seluruh berkas suara terenkripsi milik grup di Storage
  delete from storage.objects
   where bucket_id = 'group-voice'
     and name like p_group_id::text || '/%';

  -- Hapus grup (cascade menghapus group_members, invitations, group_key_blobs,
  -- group_messages, dan member_locations)
  delete from public.groups
   where id = p_group_id;
end;
$$;

create or replace function public.leave_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  select owner_id into v_owner
    from public.groups
   where id = p_group_id;

  if not found then
    raise exception 'GROUP_NOT_FOUND' using errcode = 'P0002';
  end if;

  if v_owner = v_uid then
    raise exception 'OWNER_CANNOT_LEAVE' using errcode = '42501';
  end if;

  delete from public.member_locations
   where group_id = p_group_id
     and user_id = v_uid;

  delete from public.group_members
   where group_id = p_group_id
     and user_id = v_uid;
end;
$$;

-- 6. Retensi pesan suara 30 hari & pembersihan otomatis saat grup dihapus
create or replace function public.cleanup_expired_group_voice()
returns integer
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v_deleted integer := 0;
begin
  with expired as (
    select id, voice_path
      from public.group_messages
     where voice_path is not null
       and created_at < now() - interval '30 days'
  ),
  removed_storage as (
    delete from storage.objects o
     using expired e
     where o.bucket_id = 'group-voice'
       and o.name = e.voice_path
    returning o.name
  )
  update public.group_messages gm
     set voice_path = null
    from expired e
   where gm.id = e.id;

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

-- Trigger cadangan bila grup dihapus langsung oleh service_role / cascade
create or replace function public.trg_cleanup_group_voice_objects()
returns trigger
language plpgsql
security definer
set search_path = public, storage
as $$
begin
  delete from storage.objects
   where bucket_id = 'group-voice'
     and name like old.id::text || '/%';
  return old;
end;
$$;

drop trigger if exists trg_groups_cleanup_voice on public.groups;
create trigger trg_groups_cleanup_voice
  after delete on public.groups
  for each row
  execute function public.trg_cleanup_group_voice_objects();

-- Jadwalkan retensi 30 hari lewat pg_cron di Dashboard Supabase (opsional):
-- select cron.schedule(
--   'hiqeo-cleanup-expired-group-voice',
--   '0 3 * * *',
--   $$select public.cleanup_expired_group_voice();$$
-- );

-- 7. Hak eksekusi minimal
revoke all on function public.delete_group(uuid) from public;
revoke all on function public.leave_group(uuid) from public;
revoke all on function public.cleanup_expired_group_voice() from public;
revoke all on function public.trg_cleanup_group_voice_objects() from public;

grant execute on function public.delete_group(uuid) to authenticated;
grant execute on function public.leave_group(uuid) to authenticated;

-- 8. Aktifkan REPLICA IDENTITY FULL & daftarkan tabel ke publikasi Supabase Realtime
alter table public.group_messages replica identity full;
alter table public.member_locations replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'group_messages'
    ) then
      alter publication supabase_realtime add table public.group_messages;
    end if;

    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'member_locations'
    ) then
      alter publication supabase_realtime add table public.member_locations;
    end if;
  end if;
end;
$$;
