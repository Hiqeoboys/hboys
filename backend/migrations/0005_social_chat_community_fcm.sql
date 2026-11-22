-- ============================================================================
-- Migration 0005: Sosial (Grup, Komunitas, Moderasi, Siap Naik & FCM)
-- Mencakup:
-- 1. Tabel `group_hike_prep` (1 baris aktif per group_id, anti-duplikasi Siap)
-- 2. Trigger `BEFORE INSERT` pada `community_messages` pengisi `sender_name`
-- 3. Policy RLS bucket `community-media` (fallback bila R2 belum dikonfigurasi)
-- 4. Dukungan laporan `group_message` di `moderation_reports`
-- 5. Policy pertemanan untuk semua user terautentikasi + Realtime
-- 6. Trigger webhook FCM untuk group_messages, community_messages, friendships,
--    group_hike_prep, dan sos_events
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. TABEL `group_hike_prep` (1 BARIS AKTIF PER GRUP — ANTI-DUPLIKASI)
-- ---------------------------------------------------------------------------
create table if not exists group_hike_prep (
  group_id          uuid primary key references groups (id) on delete cascade,
  invite_id         text not null,
  mountain_id       text not null,
  mountain_name     text not null,
  trail_id          text,
  trail_name        text,
  organizer_user_id uuid not null references profiles (id) on delete cascade,
  organizer_name    text not null default 'Ketua Rombongan',
  ready_user_ids    uuid[] not null default '{}',
  member_count      integer not null default 1 check (member_count >= 1),
  status            text not null default 'active'
    check (status in ('active', 'cancelled', 'completed')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

alter table group_hike_prep enable row level security;

drop policy if exists group_hike_prep_member_all on group_hike_prep;
create policy group_hike_prep_member_all on group_hike_prep
  for all
  using (
    exists (
      select 1 from group_members gm
      where gm.group_id = group_hike_prep.group_id and gm.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from group_members gm
      where gm.group_id = group_hike_prep.group_id and gm.user_id = auth.uid()
    )
  );

-- Menandai anggota siap secara atomik pada baris `group_hike_prep` yang sama
-- tanpa menimpa kesiapan anggota lain dan tanpa mengirim ulang tombol Siap.
create or replace function mark_group_hike_ready(p_group_id uuid)
returns group_hike_prep
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row group_hike_prep%rowtype;
  v_member_count integer;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if not exists (
    select 1 from group_members gm
    where gm.group_id = p_group_id and gm.user_id = v_uid
  ) then
    raise exception 'GROUP_MEMBERSHIP_REQUIRED';
  end if;

  select count(*)::integer into v_member_count
  from group_members gm
  where gm.group_id = p_group_id;

  update group_hike_prep
  set
    ready_user_ids = case
      when v_uid = any(ready_user_ids) then ready_user_ids
      else array_append(ready_user_ids, v_uid)
    end,
    member_count = greatest(member_count, coalesce(v_member_count, 1)),
    updated_at = now()
  where group_id = p_group_id and status = 'active'
  returning * into v_row;

  if not found then
    raise exception 'NO_ACTIVE_HIKE_PREP';
  end if;

  return v_row;
end;
$$;

revoke all on function mark_group_hike_ready(uuid) from public;
grant execute on function mark_group_hike_ready(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. TRIGGER `BEFORE INSERT` PADA `community_messages` (FIX 23502 sender_name)
-- ---------------------------------------------------------------------------
create or replace function fill_community_message_sender()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_avatar text;
begin
  if new.sender_name is null or btrim(new.sender_name) = '' or new.sender_avatar is null then
    select
      coalesce(
        nullif(btrim(p.full_name), ''),
        nullif(btrim(p.username::text), ''),
        'Pendaki'
      ),
      p.avatar_url
    into v_name, v_avatar
    from public.profiles p
    where p.id = new.sender_id;

    if new.sender_name is null or btrim(new.sender_name) = '' then
      new.sender_name := coalesce(v_name, 'Pendaki');
    end if;
    if (new.sender_avatar is null or btrim(new.sender_avatar) = '') and v_avatar is not null then
      new.sender_avatar := v_avatar;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_community_messages_fill_sender on community_messages;
create trigger trg_community_messages_fill_sender
  before insert on community_messages
  for each row execute function fill_community_message_sender();

-- ---------------------------------------------------------------------------
-- 3. STORAGE BUCKET `community-media` RLS FALLBACK (FIX StorageException 403)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('community-media', 'community-media', true)
on conflict (id) do update set public = true;

drop policy if exists community_media_public_read on storage.objects;
create policy community_media_public_read on storage.objects
  for select using (bucket_id = 'community-media');

drop policy if exists community_media_auth_insert on storage.objects;
create policy community_media_auth_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'community-media');

drop policy if exists community_media_auth_update on storage.objects;
create policy community_media_auth_update on storage.objects
  for update to authenticated
  using (bucket_id = 'community-media' and owner = auth.uid())
  with check (bucket_id = 'community-media');

drop policy if exists community_media_auth_delete on storage.objects;
create policy community_media_auth_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'community-media' and owner = auth.uid());

-- ---------------------------------------------------------------------------
-- 4. MODERATION REPORTS: DUKUNG `group_message` + PERTEMANAN
-- ---------------------------------------------------------------------------
alter table moderation_reports
  drop constraint if exists moderation_reports_report_type_check;

alter table moderation_reports
  add constraint moderation_reports_report_type_check
  check (report_type in ('group_message', 'community_message', 'community', 'user_account'));

drop policy if exists friendships_insert_plus on friendships;
drop policy if exists friendships_insert_auth on friendships;
create policy friendships_insert_auth on friendships
  for insert with check (requester_id = auth.uid());

-- Publikasi Realtime untuk `group_hike_prep` dan `friendships`
do $$
declare
  v_tbl text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach v_tbl in array array['group_hike_prep', 'friendships'] loop
      if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = v_tbl
      ) then
        execute format('alter publication supabase_realtime add table public.%I', v_tbl);
      end if;
    end loop;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. TRIGGER WEBHOOK FCM (`send-fcm-notification`) VIA `pg_net`
-- ---------------------------------------------------------------------------
create or replace function dispatch_fcm_webhook()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text := current_setting('app.settings.fcm_webhook_url', true);
  v_secret text := current_setting('app.settings.fcm_webhook_secret', true);
begin
  if v_url is null or length(v_url) = 0 or to_regnamespace('net') is null then
    return new;
  end if;

  if tg_table_name = 'friendships' and new.status <> 'pending' then
    return new;
  end if;

  if tg_table_name = 'group_hike_prep' then
    if new.status <> 'active' then
      return new;
    end if;
    if tg_op = 'UPDATE' and old.invite_id = new.invite_id and old.status = 'active' then
      -- Anggota menekan "Siap" memperbarui baris yang sama; jangan kirim ulang
      -- notifikasi ajakan baru.
      return new;
    end if;
  end if;

  if tg_table_name = 'sos_events' and new.status <> 'active' then
    return new;
  end if;

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-hiqeo-webhook-secret', coalesce(v_secret, '')
    ),
    body := jsonb_build_object(
      'type', tg_op,
      'table', tg_table_name,
      'record', row_to_json(new)
    )
  );
  return new;
exception when others then
  return new;
end;
$$;

drop trigger if exists trg_community_messages_fcm on community_messages;
create trigger trg_community_messages_fcm
  after insert on community_messages
  for each row execute function dispatch_fcm_webhook();

drop trigger if exists trg_friendships_fcm on friendships;
create trigger trg_friendships_fcm
  after insert on friendships
  for each row execute function dispatch_fcm_webhook();

drop trigger if exists trg_group_hike_prep_fcm on group_hike_prep;
create trigger trg_group_hike_prep_fcm
  after insert or update on group_hike_prep
  for each row execute function dispatch_fcm_webhook();

do $$
begin
  if to_regclass('public.group_messages') is not null then
    execute 'drop trigger if exists trg_group_messages_fcm on public.group_messages';
    execute 'create trigger trg_group_messages_fcm after insert on public.group_messages for each row execute function public.dispatch_fcm_webhook()';
  end if;
  if to_regclass('public.sos_events') is not null then
    execute 'drop trigger if exists trg_sos_events_fcm on public.sos_events';
    execute 'create trigger trg_sos_events_fcm after insert or update on public.sos_events for each row execute function public.dispatch_fcm_webhook()';
  end if;
end;
$$;
