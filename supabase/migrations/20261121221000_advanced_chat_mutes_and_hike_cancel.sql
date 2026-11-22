-- ============================================================================
-- Migration: Advanced Chat (Soft-Delete, Reply, @Mention, Mutes),
--            Hike Invite Cancellation, & Dynamic Profile Message Joins
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. `public.group_messages`: soft-delete + hike invitation cancellation
-- ----------------------------------------------------------------------------
alter table if exists public.group_messages
  add column if not exists is_deleted boolean not null default false,
  add column if not exists deleted_at timestamptz,
  add column if not exists is_cancelled boolean not null default false,
  add column if not exists cancelled_at timestamptz;

create index if not exists idx_group_messages_active
  on public.group_messages (group_id, created_at desc)
  where is_deleted = false;

create or replace function public.guard_group_messages_e2ee_upsert()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.id := old.id;
  new.group_id := old.group_id;
  new.sender_id := old.sender_id;
  new.client_id := old.client_id;
  new.created_at := old.created_at;

  if old.is_deleted or new.is_deleted or new.deleted_at is not null then
    new.is_deleted := true;
    new.deleted_at := coalesce(old.deleted_at, new.deleted_at, now());
    new.ciphertext := '';
    new.nonce := '';
    new.voice_path := null;
  else
    new.voice_path := coalesce(nullif(btrim(new.voice_path), ''), old.voice_path);
  end if;

  if old.is_cancelled or new.is_cancelled or new.cancelled_at is not null then
    new.is_cancelled := true;
    new.cancelled_at := coalesce(old.cancelled_at, new.cancelled_at, now());
  end if;

  return new;
end;
$$;

do $$
begin
  if to_regclass('public.group_messages') is not null then
    drop trigger if exists trg_group_messages_e2ee_upsert on public.group_messages;
    create trigger trg_group_messages_e2ee_upsert
      before update on public.group_messages
      for each row
      execute function public.guard_group_messages_e2ee_upsert();

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
        sender_id = (select auth.uid())
        and public.is_group_member(group_id)
      );

    drop policy if exists group_messages_update_own on public.group_messages;
    create policy group_messages_update_own
      on public.group_messages
      for update
      to authenticated
      using (
        sender_id = (select auth.uid())
        and public.is_group_member(group_id)
      )
      with check (
        sender_id = (select auth.uid())
        and public.is_group_member(group_id)
      );

    drop policy if exists group_messages_delete_own on public.group_messages;
    create policy group_messages_delete_own
      on public.group_messages
      for delete
      to authenticated
      using (
        sender_id = (select auth.uid())
        and public.is_group_member(group_id)
      );
  end if;
end;
$$;

revoke all on function public.guard_group_messages_e2ee_upsert() from public, anon;

create or replace function public.soft_delete_group_message(
  p_group_id uuid,
  p_client_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.group_messages%rowtype;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  if not public.is_group_member(p_group_id) then
    raise exception 'NOT_MEMBER' using errcode = '42501';
  end if;

  select * into v_row
  from public.group_messages gm
  where gm.group_id = p_group_id
    and (gm.client_id = p_client_id or gm.id = p_client_id)
  for update;

  if not found then
    return false;
  end if;

  if v_row.sender_id <> v_uid then
    raise exception 'FORBIDDEN_DELETE_MESSAGE' using errcode = '42501';
  end if;

  if v_row.voice_path is not null and btrim(v_row.voice_path) <> '' then
    delete from storage.objects
    where bucket_id = 'group-voice'
      and name = v_row.voice_path;
  end if;

  update public.group_messages
  set is_deleted = true,
      deleted_at = coalesce(deleted_at, now()),
      ciphertext = '',
      nonce = '',
      voice_path = null
  where id = v_row.id;

  return true;
end;
$$;

revoke all on function public.soft_delete_group_message(uuid, uuid) from public, anon;
grant execute on function public.soft_delete_group_message(uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 2. `public.community_messages`: soft-delete, reply_to, mentioned_user_ids,
--    and dynamic profile joins
-- ----------------------------------------------------------------------------
alter table if exists public.community_messages
  add column if not exists is_deleted boolean not null default false,
  add column if not exists deleted_at timestamptz,
  add column if not exists reply_to_message_id uuid references public.community_messages (id) on delete set null,
  add column if not exists mentioned_user_ids uuid[] not null default '{}';

create index if not exists idx_community_messages_reply_to
  on public.community_messages (reply_to_message_id)
  where reply_to_message_id is not null;

create index if not exists idx_community_messages_mentioned_gin
  on public.community_messages using gin (mentioned_user_ids)
  where cardinality(mentioned_user_ids) > 0;

create index if not exists idx_community_messages_active
  on public.community_messages (community_id, created_at desc)
  where is_deleted = false;

create or replace function public.validate_community_message_meta()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_clean_mentions uuid[];
begin
  if new.reply_to_message_id is not null then
    if not exists (
      select 1
      from public.community_messages rm
      where rm.id = new.reply_to_message_id
        and rm.community_id = new.community_id
    ) then
      raise exception 'INVALID_REPLY_TARGET' using errcode = '22023';
    end if;
  end if;

  if new.mentioned_user_ids is null or cardinality(new.mentioned_user_ids) = 0 then
    new.mentioned_user_ids := '{}';
  else
    select coalesce(array_agg(distinct cm.user_id), '{}')
    into v_clean_mentions
    from public.community_members cm
    where cm.community_id = new.community_id
      and cm.user_id = any(new.mentioned_user_ids)
      and cm.user_id <> new.sender_id;

    new.mentioned_user_ids := coalesce(v_clean_mentions, '{}');
  end if;

  return new;
end;
$$;

create or replace function public.guard_community_message_soft_delete()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('postgres', 'service_role', 'supabase_admin') then
    if new.id is distinct from old.id
       or new.community_id is distinct from old.community_id
       or new.sender_id is distinct from old.sender_id
       or new.created_at is distinct from old.created_at
       or new.reply_to_message_id is distinct from old.reply_to_message_id
       or new.mentioned_user_ids is distinct from old.mentioned_user_ids then
      raise exception 'COMMUNITY_MESSAGE_METADATA_IMMUTABLE' using errcode = '42501';
    end if;

    if old.is_deleted then
      raise exception 'COMMUNITY_MESSAGE_ALREADY_DELETED' using errcode = '42501';
    end if;

    if not (new.is_deleted or new.deleted_at is not null) then
      raise exception 'COMMUNITY_MESSAGE_EDIT_FORBIDDEN' using errcode = '42501';
    end if;
  end if;

  if new.is_deleted or new.deleted_at is not null then
    new.is_deleted := true;
    new.deleted_at := coalesce(old.deleted_at, new.deleted_at, now());
    new.content := null;
    new.media_url := null;
    new.media_thumbnail_url := null;
    new.media_mime := null;
    new.media_duration_sec := null;
    new.message_type := 'text';
  end if;

  return new;
end;
$$;

do $$
begin
  if to_regclass('public.community_messages') is not null then
    drop trigger if exists trg_community_messages_validate_meta on public.community_messages;
    create trigger trg_community_messages_validate_meta
      before insert on public.community_messages
      for each row
      execute function public.validate_community_message_meta();

    drop trigger if exists trg_community_messages_guard_soft_delete on public.community_messages;
    create trigger trg_community_messages_guard_soft_delete
      before update on public.community_messages
      for each row
      execute function public.guard_community_message_soft_delete();

    drop policy if exists community_messages_read on public.community_messages;
    create policy community_messages_read
      on public.community_messages
      for select
      to authenticated
      using (
        exists (
          select 1
          from public.community_members cm
          where cm.community_id = community_messages.community_id
            and cm.user_id = (select auth.uid())
        )
      );

    drop policy if exists community_messages_insert_plus on public.community_messages;
    create policy community_messages_insert_plus
      on public.community_messages
      for insert
      to authenticated
      with check (
        sender_id = (select auth.uid())
        and public.has_full_plus_social((select auth.uid()))
        and exists (
          select 1
          from public.community_members cm
          where cm.community_id = community_messages.community_id
            and cm.user_id = (select auth.uid())
        )
      );

    drop policy if exists community_messages_update_own_delete on public.community_messages;
    create policy community_messages_update_own_delete
      on public.community_messages
      for update
      to authenticated
      using (
        sender_id = (select auth.uid())
        and exists (
          select 1
          from public.community_members cm
          where cm.community_id = community_messages.community_id
            and cm.user_id = (select auth.uid())
        )
      )
      with check (
        sender_id = (select auth.uid())
        and is_deleted = true
        and deleted_at is not null
      );
  end if;
end;
$$;

revoke all on function public.validate_community_message_meta() from public, anon;
revoke all on function public.guard_community_message_soft_delete() from public, anon;

create or replace function public.soft_delete_community_message(p_message_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.community_messages%rowtype;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  select * into v_row
  from public.community_messages cm
  where cm.id = p_message_id
  for update;

  if not found then
    return false;
  end if;

  if v_row.sender_id <> v_uid then
    raise exception 'FORBIDDEN_DELETE_MESSAGE' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.community_members cm
    where cm.community_id = v_row.community_id
      and cm.user_id = v_uid
  ) then
    raise exception 'NOT_MEMBER' using errcode = '42501';
  end if;

  update public.community_messages
  set is_deleted = true,
      deleted_at = coalesce(deleted_at, now()),
      content = null,
      media_url = null,
      media_thumbnail_url = null,
      media_mime = null,
      media_duration_sec = null,
      message_type = 'text'
  where id = p_message_id;

  return true;
end;
$$;

revoke all on function public.soft_delete_community_message(uuid) from public, anon;
grant execute on function public.soft_delete_community_message(uuid) to authenticated;

-- Dynamic profile-joined community messages RPC (live sender_name, username, avatar_url)
create or replace function public.get_community_messages(
  p_community_id uuid,
  p_limit integer default 150,
  p_before timestamptz default null
)
returns table (
  id uuid,
  community_id uuid,
  sender_id uuid,
  sender_name text,
  sender_username text,
  sender_avatar_url text,
  message_type text,
  content text,
  media_url text,
  media_thumbnail_url text,
  media_duration_sec integer,
  is_deleted boolean,
  deleted_at timestamptz,
  reply_to_message_id uuid,
  reply_to_sender_id uuid,
  reply_to_sender_name text,
  reply_to_content text,
  reply_to_message_type text,
  reply_to_is_deleted boolean,
  mentioned_user_ids uuid[],
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_lim integer := least(greatest(coalesce(p_limit, 150), 1), 200);
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  if not exists (
    select 1
    from public.community_members cm
    where cm.community_id = p_community_id
      and cm.user_id = v_uid
  ) then
    raise exception 'NOT_MEMBER' using errcode = '42501';
  end if;

  return query
    with recent as (
      select m.*
      from public.community_messages m
      where m.community_id = p_community_id
        and (p_before is null or m.created_at < p_before)
      order by m.created_at desc
      limit v_lim
    )
    select
      m.id,
      m.community_id,
      m.sender_id,
      coalesce(
        nullif(btrim(p.full_name), ''),
        nullif(btrim(p.username::text), ''),
        nullif(btrim(m.sender_name), ''),
        'Pendaki'
      ) as sender_name,
      p.username::text as sender_username,
      p.avatar_url as sender_avatar_url,
      m.message_type,
      case when m.is_deleted then null else m.content end as content,
      case when m.is_deleted then null else m.media_url end as media_url,
      case when m.is_deleted then null else m.media_thumbnail_url end as media_thumbnail_url,
      case when m.is_deleted then null else m.media_duration_sec end as media_duration_sec,
      m.is_deleted,
      m.deleted_at,
      m.reply_to_message_id,
      rm.sender_id as reply_to_sender_id,
      coalesce(
        nullif(btrim(rp.full_name), ''),
        nullif(btrim(rp.username::text), ''),
        nullif(btrim(rm.sender_name), ''),
        case when rm.id is not null then 'Pendaki' else null end
      ) as reply_to_sender_name,
      case when rm.is_deleted then null else rm.content end as reply_to_content,
      rm.message_type as reply_to_message_type,
      coalesce(rm.is_deleted, false) as reply_to_is_deleted,
      coalesce(m.mentioned_user_ids, '{}') as mentioned_user_ids,
      m.created_at
    from recent m
    left join public.profiles p on p.id = m.sender_id
    left join public.community_messages rm on rm.id = m.reply_to_message_id
    left join public.profiles rp on rp.id = rm.sender_id
    order by m.created_at asc;
end;
$$;

revoke all on function public.get_community_messages(uuid, integer, timestamptz) from public, anon;
grant execute on function public.get_community_messages(uuid, integer, timestamptz) to authenticated;

do $$
begin
  if to_regclass('public.community_messages') is not null then
    alter table public.community_messages replica identity full;
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
      if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'community_messages'
      ) then
        alter publication supabase_realtime add table public.community_messages;
      end if;
    end if;
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. `public.chat_notification_mutes`: per-room mute preferences
-- ----------------------------------------------------------------------------
create table if not exists public.chat_notification_mutes (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  room_type   text not null check (room_type in ('group', 'community')),
  room_id     uuid not null,
  muted_until timestamptz,
  updated_at  timestamptz not null default now(),
  primary key (user_id, room_type, room_id)
);

create index if not exists idx_chat_notification_mutes_room_active
  on public.chat_notification_mutes (room_type, room_id, user_id)
  where muted_until is not null;

alter table public.chat_notification_mutes enable row level security;

drop policy if exists chat_notification_mutes_self_select on public.chat_notification_mutes;
create policy chat_notification_mutes_self_select
  on public.chat_notification_mutes
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists chat_notification_mutes_self_insert on public.chat_notification_mutes;
create policy chat_notification_mutes_self_insert
  on public.chat_notification_mutes
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists chat_notification_mutes_self_update on public.chat_notification_mutes;
create policy chat_notification_mutes_self_update
  on public.chat_notification_mutes
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists chat_notification_mutes_self_delete on public.chat_notification_mutes;
create policy chat_notification_mutes_self_delete
  on public.chat_notification_mutes
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

-- ----------------------------------------------------------------------------
-- 4. `public.group_hike_prep`: invite_message_id & atomic cancellation RPC
-- ----------------------------------------------------------------------------
alter table if exists public.group_hike_prep
  add column if not exists invite_message_id uuid,
  add column if not exists is_cancelled boolean not null default false,
  add column if not exists cancelled_at timestamptz;

do $$
begin
  if to_regclass('public.group_hike_prep') is not null then
    alter table public.group_hike_prep replica identity full;
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
      if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'group_hike_prep'
      ) then
        alter publication supabase_realtime add table public.group_hike_prep;
      end if;
    end if;
  end if;
end;
$$;

create or replace function public.cancel_group_hike_prep(
  p_group_id uuid,
  p_invite_id text default null
)
returns public.group_hike_prep
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.group_hike_prep%rowtype;
  v_owner_id uuid;
  v_now timestamptz := now();
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  if not public.is_group_member(p_group_id) then
    raise exception 'NOT_MEMBER' using errcode = '42501';
  end if;

  select * into v_row
  from public.group_hike_prep ghp
  where ghp.group_id = p_group_id
  for update;

  if not found then
    raise exception 'HIKE_PREP_NOT_FOUND' using errcode = 'P0002';
  end if;

  select g.owner_id into v_owner_id
  from public.groups g
  where g.id = p_group_id;

  if v_row.organizer_user_id <> v_uid and coalesce(v_owner_id, v_uid) <> v_uid then
    raise exception 'ORGANIZER_REQUIRED' using errcode = '42501';
  end if;

  if p_invite_id is not null and btrim(p_invite_id) <> '' and v_row.invite_id <> p_invite_id then
    return v_row;
  end if;

  update public.group_hike_prep
  set status = 'cancelled',
      is_cancelled = true,
      cancelled_at = coalesce(cancelled_at, v_now),
      updated_at = v_now
  where group_id = p_group_id
  returning * into v_row;

  if v_row.invite_message_id is not null and to_regclass('public.group_messages') is not null then
    update public.group_messages gm
    set is_cancelled = true,
        cancelled_at = coalesce(gm.cancelled_at, v_now)
    where gm.group_id = p_group_id
      and (gm.id = v_row.invite_message_id or gm.client_id = v_row.invite_message_id);
  end if;

  return v_row;
end;
$$;

revoke all on function public.cancel_group_hike_prep(uuid, text) from public, anon;
grant execute on function public.cancel_group_hike_prep(uuid, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 5. Update `social_latest_messages()` to include `is_deleted`, `is_cancelled`,
--    and live profile names
-- ----------------------------------------------------------------------------
drop function if exists public.social_latest_messages();
create or replace function public.social_latest_messages()
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
  is_deleted boolean,
  is_cancelled boolean,
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
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  if to_regclass('public.group_messages') is not null then
    return query execute $q$
      select distinct on (gm.group_id)
        'group'::text as room_kind,
        gm.group_id as room_id,
        coalesce(gm.client_id::text, gm.id::text) as message_id,
        gm.sender_id,
        null::text as sender_name,
        coalesce(gm.kind, 'text')::text as message_type,
        null::text as content,
        gm.ciphertext,
        coalesce(gm.key_version, 1)::integer as key_version,
        coalesce(gm.is_deleted, false) as is_deleted,
        coalesce(gm.is_cancelled, false) as is_cancelled,
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
      coalesce(
        nullif(btrim(p.full_name), ''),
        nullif(btrim(p.username::text), ''),
        nullif(btrim(cm.sender_name), ''),
        'Pendaki'
      ) as sender_name,
      cm.message_type,
      case when cm.is_deleted then null else cm.content end as content,
      null::text as ciphertext,
      null::integer as key_version,
      coalesce(cm.is_deleted, false) as is_deleted,
      false as is_cancelled,
      cm.created_at
    from public.community_messages cm
    join public.community_members m
      on m.community_id = cm.community_id and m.user_id = v_uid
    left join public.profiles p on p.id = cm.sender_id
    order by cm.community_id, cm.created_at desc;
end;
$$;

revoke all on function public.social_latest_messages() from public, anon;
grant execute on function public.social_latest_messages() to authenticated;
