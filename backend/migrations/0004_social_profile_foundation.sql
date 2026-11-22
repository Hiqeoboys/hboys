-- ============================================================================
-- Migration 0004: Social Tab Refresh, Profil/Avatar, Cloud Backup & Kontak Darurat
-- Mencakup:
-- 1. RPC 1-query social_latest_messages() (tanpa tabel group_read_state)
-- 2. Pencarian prefix @username (LIMIT maks 15) + update_my_avatar RPC
-- 3. Cadangan cloud otomatis per sesi terkompresi (cloud_session_backups)
-- 4. Kontak darurat dua jenis (Nomor HP langsung aktif & Akun Hiqeo persetujuan)
-- 5. Token FCM per perangkat (user_fcm_tokens) + webhook trigger awal
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. INDEX & RPC SOCIAL LATEST MESSAGES (1 LIGHTWEIGHT QUERY)
-- ---------------------------------------------------------------------------
create index if not exists idx_community_messages_comm_time_desc
  on community_messages (community_id, created_at desc);

do $$
begin
  if to_regclass('public.group_messages') is not null then
    execute 'create index if not exists idx_group_messages_group_time_desc on public.group_messages (group_id, created_at desc)';
  end if;
end;
$$;

create or replace function social_latest_messages()
returns table (
  room_kind text,
  room_id uuid,
  message_id text,
  sender_id uuid,
  sender_name text,
  message_type text,
  content text,
  ciphertext text,
  key_version integer,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if to_regclass('public.group_messages') is not null then
    return query execute $q$
      select distinct on (gm.group_id)
        'group'::text as room_kind,
        gm.group_id as room_id,
        coalesce(gm.client_id, gm.id::text) as message_id,
        gm.sender_id,
        null::text as sender_name,
        coalesce(gm.kind, 'text')::text as message_type,
        null::text as content,
        gm.ciphertext,
        coalesce(gm.key_version, 1)::integer as key_version,
        gm.created_at
      from public.group_messages gm
      join public.group_members m
        on m.group_id = gm.group_id and m.user_id = $1
      order by gm.group_id, gm.created_at desc
    $q$ using v_uid;
  end if;

  return query
    select distinct on (cm.community_id)
      'community'::text as room_kind,
      cm.community_id as room_id,
      cm.id::text as message_id,
      cm.sender_id,
      cm.sender_name,
      cm.message_type,
      cm.content,
      null::text as ciphertext,
      null::integer as key_version,
      cm.created_at
    from public.community_messages cm
    join public.community_members m
      on m.community_id = cm.community_id and m.user_id = v_uid
    order by cm.community_id, cm.created_at desc;
end;
$$;

revoke all on function social_latest_messages() from public;
grant execute on function social_latest_messages() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. PENCARIAN PREFIX USERNAME & PERBARUI AVATAR PROFIL
-- ---------------------------------------------------------------------------
create index if not exists idx_profiles_username_prefix
  on profiles (lower(username::text) text_pattern_ops);

create or replace function search_users_by_username(
  p_query text,
  p_limit integer default 15
)
returns table (
  id uuid,
  username text,
  full_name text,
  avatar_url text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_clean text;
  v_escaped text;
  v_lim integer := least(greatest(coalesce(p_limit, 15), 1), 15);
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  v_clean := lower(btrim(regexp_replace(coalesce(p_query, ''), '^@+', '')));
  if v_clean = '' then
    return;
  end if;

  v_escaped := replace(replace(replace(v_clean, '\', '\\'), '%', '\%'), '_', '\_');

  return query
    select
      p.id,
      p.username::text,
      coalesce(nullif(btrim(p.full_name), ''), p.username::text) as full_name,
      p.avatar_url
    from public.profiles p
    where p.id <> v_uid
      and lower(p.username::text) like (v_escaped || '%') escape '\'
    order by lower(p.username::text) asc
    limit v_lim;
end;
$$;

revoke all on function search_users_by_username(text, integer) from public;
grant execute on function search_users_by_username(text, integer) to authenticated;

create or replace function update_my_avatar(p_avatar_url text)
returns table (
  id uuid,
  avatar_url text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_url text := btrim(coalesce(p_avatar_url, ''));
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if v_url = '' or length(v_url) > 512 or v_url !~* '^https://' then
    raise exception 'AVATAR_URL_INVALID';
  end if;

  update public.profiles p
  set avatar_url = v_url
  where p.id = v_uid;

  return query
    select p.id, p.avatar_url
    from public.profiles p
    where p.id = v_uid;
end;
$$;

revoke all on function update_my_avatar(text) from public;
grant execute on function update_my_avatar(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. CADANGAN CLOUD OTOMATIS TERKOMPRESI (KHUSUS HIQEO PLUS)
-- ---------------------------------------------------------------------------
create table if not exists cloud_session_backups (
  user_id         uuid not null references profiles (id) on delete cascade,
  session_id      text not null,
  activity_type   text not null default 'hiking' check (activity_type in ('hiking', 'jogging')),
  started_at      timestamptz not null,
  ended_at        timestamptz,
  bundle_gzip_b64 text not null,
  bundle_bytes    integer not null check (bundle_bytes > 0 and bundle_bytes <= 65536),
  device_name     text,
  updated_at      timestamptz not null default now(),
  primary key (user_id, session_id)
);

create index if not exists idx_cloud_session_backups_user_started
  on cloud_session_backups (user_id, started_at desc);

alter table cloud_session_backups enable row level security;

drop policy if exists cloud_backups_owner_all on cloud_session_backups;
create policy cloud_backups_owner_all on cloud_session_backups
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 4. KONTAK DARURAT (NOMOR HP LANGSUNG AKTIF & AKUN HIQEO) + TOKEN FCM
-- ---------------------------------------------------------------------------
alter table emergency_contacts
  add column if not exists contact_kind text not null default 'phone'
    check (contact_kind in ('phone', 'hiqeo_account')),
  add column if not exists contact_user_id uuid references profiles (id) on delete cascade,
  add column if not exists contact_username text;

alter table emergency_contacts
  alter column phone_e164 drop not null;

alter table emergency_contacts
  drop constraint if exists emergency_contacts_phone_e164_check;

alter table emergency_contacts
  drop constraint if exists emergency_contacts_target_check;

alter table emergency_contacts
  add constraint emergency_contacts_target_check check (
    (contact_kind = 'phone' and phone_e164 is not null and phone_e164 ~ '^\+[0-9]{8,15}$')
    or (contact_kind = 'hiqeo_account' and contact_user_id is not null and contact_user_id <> user_id)
  );

create unique index if not exists idx_emergency_contacts_hiqeo_pair
  on emergency_contacts (user_id, contact_user_id)
  where contact_kind = 'hiqeo_account';

drop policy if exists contacts_target_read on emergency_contacts;
create policy contacts_target_read on emergency_contacts
  for select using (contact_user_id = auth.uid());

drop policy if exists contacts_target_respond on emergency_contacts;
create policy contacts_target_respond on emergency_contacts
  for update
  using (contact_user_id = auth.uid())
  with check (contact_user_id = auth.uid() and consent_status in ('granted', 'revoked'));

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'emergency_contacts'
    ) then
      alter publication supabase_realtime add table public.emergency_contacts;
    end if;
  end if;
end;
$$;

create table if not exists user_fcm_tokens (
  user_id    uuid not null references profiles (id) on delete cascade,
  token      text not null,
  platform   text not null default 'android',
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);

alter table user_fcm_tokens enable row level security;

drop policy if exists user_fcm_tokens_owner_all on user_fcm_tokens;
create policy user_fcm_tokens_owner_all on user_fcm_tokens
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create or replace function notify_fcm_on_emergency_contact_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text := current_setting('app.settings.fcm_webhook_url', true);
  v_secret text := current_setting('app.settings.fcm_webhook_secret', true);
begin
  if new.contact_kind = 'hiqeo_account'
     and new.consent_status = 'pending'
     and v_url is not null
     and length(v_url) > 0
     and to_regnamespace('net') is not null then
    perform net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-hiqeo-webhook-secret', coalesce(v_secret, '')
      ),
      body := jsonb_build_object(
        'type', 'INSERT',
        'table', 'emergency_contacts',
        'record', row_to_json(new)
      )
    );
  end if;
  return new;
exception when others then
  return new;
end;
$$;

drop trigger if exists trg_emergency_contacts_notify on emergency_contacts;
create trigger trg_emergency_contacts_notify
  after insert on emergency_contacts
  for each row execute function notify_fcm_on_emergency_contact_request();
