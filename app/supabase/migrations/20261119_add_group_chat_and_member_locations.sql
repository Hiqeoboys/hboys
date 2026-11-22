-- ============================================================================
-- HIQEO - MIGRASI RUANG OBROLAN GRUP, LOKASI TERAKHIR ANGGOTA, & VOICE NOTE
-- Kompatibel dengan Supabase PostgreSQL, RLS, Storage, dan Realtime.
-- Mendukung online realtime serta sinkronisasi relay offline (BLE Mesh & Wi-Fi Direct).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. FUNGSI PEMBANTU KEAMANAN & PARSING UUID
-- ----------------------------------------------------------------------------

-- Memeriksa apakah pengguna tertentu (uid) merupakan anggota sah dari grup (gid).
-- SECURITY DEFINER mencegah rekursi RLS saat dipanggil dari policy tabel chat/lokasi,
-- sekaligus memungkinkan relay pesan/lokasi offline oleh anggota grup lain yang valid.
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

-- Parsing UUID secara aman untuk path folder Storage (mengembalikan NULL bila format invalid)
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

-- ----------------------------------------------------------------------------
-- 2. TABEL group_messages (Pesan Teks & Pesan Suara + Relay Offline)
-- ----------------------------------------------------------------------------

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

comment on table public.group_messages is
  'Riwayat pesan teks & pesan suara ruang obrolan grup (realtime & sinkronisasi relay offline BLE Mesh/Wi-Fi Direct).';

-- Trigger idempotensi saat beberapa anggota menyinkronkan client_msg_id yang sama:
-- menjaga created_at asli & tidak menghapus audio_url yang sudah terunggah.
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

-- ----------------------------------------------------------------------------
-- 3. TABEL member_locations (Lokasi Terakhir Anggota per Grup)
-- ----------------------------------------------------------------------------

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

comment on table public.member_locations is
  'Posisi GPS terakhir tiap anggota di dalam grup pendakian (mendukung pembaruan realtime & relay offline).';

-- Trigger penjaga kronologi: mencegah paket relay offline yang lebih lama
-- menimpa titik lokasi yang lebih baru di server saat UPSERT.
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

-- ----------------------------------------------------------------------------
-- 4. ROW LEVEL SECURITY (RLS) UNTUK group_messages & member_locations
-- ----------------------------------------------------------------------------

alter table public.group_messages   enable row level security;
alter table public.member_locations enable row level security;

-- [RLS: group_messages]
drop policy if exists group_messages_member_select on public.group_messages;
create policy group_messages_member_select on public.group_messages
  for select to authenticated
  using (public.is_group_member(group_id));

-- Mengizinkan pengiriman langsung (sender_id = auth.uid()) MAUPUN relay offline
-- oleh anggota grup lain selama uploader & pengirim asli keduanya anggota grup.
drop policy if exists group_messages_member_insert on public.group_messages;
create policy group_messages_member_insert on public.group_messages
  for insert to authenticated
  with check (
    public.is_group_member(group_id)
    and public.is_user_in_group(group_id, sender_id)
  );

-- Dibutuhkan oleh operasi UPSERT ON CONFLICT (client_msg_id) & pengaitan audio_url.
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

-- [RLS: member_locations]
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

-- Mengizinkan anggota meng-upsert lokasi dirinya sendiri maupun lokasi rekan
-- yang diterima lewat relay BLE Mesh / Wi-Fi Direct.
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

-- ----------------------------------------------------------------------------
-- 5. SUPABASE STORAGE BUCKET & POLICY UNTUK VOICE NOTE (.m4a)
-- Konvensi path objek: <group_id>/<client_msg_id>.m4a
-- ----------------------------------------------------------------------------

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

-- ----------------------------------------------------------------------------
-- 6. AKTIFKAN SUPABASE REALTIME
-- ----------------------------------------------------------------------------

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
