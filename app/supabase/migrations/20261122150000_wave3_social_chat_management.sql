-- Wave 3 Migration:
-- 1. Old message cutoff on group_members.joined_at & community_room_visits.first_entered_at (#13, #16)
-- 2. Non-member community room preview + manual join flow without owner auto-rejoin (#14)
-- 3. Persistent server read cursor (last_read_at & last_read_message_id) synced by mark_room_read (#25)
-- 4. Group avatars (#29) & creator leave_group without destroying group for other members (#30)

-- ----------------------------------------------------------------------------
-- 1. Schema updates: groups.avatar_url, group_members cursors, community_members
--    & community_room_visits
-- ----------------------------------------------------------------------------
alter table if exists public.groups
  add column if not exists avatar_url text;

alter table if exists public.group_members
  add column if not exists joined_at timestamptz not null default now(),
  add column if not exists last_read_at timestamptz,
  add column if not exists last_read_message_id text;

create index if not exists idx_group_members_user_group_joined
  on public.group_members (user_id, group_id, joined_at);

alter table if exists public.community_members
  add column if not exists first_entered_at timestamptz,
  add column if not exists last_read_at timestamptz,
  add column if not exists last_read_message_id text;

update public.community_members
set first_entered_at = coalesce(first_entered_at, joined_at, now())
where first_entered_at is null;

create table if not exists public.community_room_visits (
  user_id              uuid not null references public.profiles (id) on delete cascade,
  community_id         uuid not null references public.communities (id) on delete cascade,
  first_entered_at     timestamptz not null default now(),
  last_read_at         timestamptz,
  last_read_message_id text,
  primary key (user_id, community_id)
);

create index if not exists idx_community_room_visits_comm_user
  on public.community_room_visits (community_id, user_id);

alter table public.community_room_visits enable row level security;

drop policy if exists community_room_visits_self_select on public.community_room_visits;
create policy community_room_visits_self_select
  on public.community_room_visits
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists community_room_visits_self_insert on public.community_room_visits;
create policy community_room_visits_self_insert
  on public.community_room_visits
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists community_room_visits_self_update on public.community_room_visits;
create policy community_room_visits_self_update
  on public.community_room_visits
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Backfill visits for existing community members so first_entered_at is durable even if they leave.
insert into public.community_room_visits (
  user_id,
  community_id,
  first_entered_at,
  last_read_at,
  last_read_message_id
)
select
  cm.user_id,
  cm.community_id,
  coalesce(cm.first_entered_at, cm.joined_at, now()),
  cm.last_read_at,
  cm.last_read_message_id
from public.community_members cm
on conflict (user_id, community_id) do nothing;

-- ----------------------------------------------------------------------------
-- 2. RLS: enforce joined_at on group_messages and first_entered_at on
--    community_messages (#13, #14)
-- ----------------------------------------------------------------------------
drop policy if exists group_messages_member_select on public.group_messages;
drop policy if exists group_messages_select_member on public.group_messages;
create policy group_messages_select_member
  on public.group_messages
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.group_members gm
      where gm.group_id = group_messages.group_id
        and gm.user_id = (select auth.uid())
        and group_messages.created_at >= gm.joined_at
    )
  );

drop policy if exists community_messages_read on public.community_messages;
create policy community_messages_read
  on public.community_messages
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.community_room_visits v
      where v.community_id = community_messages.community_id
        and v.user_id = (select auth.uid())
        and community_messages.created_at >= v.first_entered_at
    )
    or exists (
      select 1
      from public.community_members cm
      where cm.community_id = community_messages.community_id
        and cm.user_id = (select auth.uid())
        and community_messages.created_at >= coalesce(cm.first_entered_at, cm.joined_at)
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

-- ----------------------------------------------------------------------------
-- 3. Community RPCs: first_entered_at recording, non-member message preview,
--    and list_communities_with_meta without forcing owner_id -> is_joined (#13, #14, #30)
-- ----------------------------------------------------------------------------
create or replace function public.record_community_first_entry(
  p_community_id uuid
)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_first_entered timestamptz;
  v_member_ts timestamptz;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  if not exists (
    select 1 from public.communities c where c.id = p_community_id
  ) then
    raise exception 'COMMUNITY_NOT_FOUND' using errcode = 'P0002';
  end if;

  select v.first_entered_at into v_first_entered
  from public.community_room_visits v
  where v.user_id = v_uid
    and v.community_id = p_community_id;

  if v_first_entered is not null then
    return v_first_entered;
  end if;

  select coalesce(cm.first_entered_at, cm.joined_at) into v_member_ts
  from public.community_members cm
  where cm.user_id = v_uid
    and cm.community_id = p_community_id;

  v_first_entered := coalesce(v_member_ts, now());

  insert into public.community_room_visits (
    user_id,
    community_id,
    first_entered_at
  ) values (
    v_uid,
    p_community_id,
    v_first_entered
  )
  on conflict (user_id, community_id) do nothing;

  select v.first_entered_at into v_first_entered
  from public.community_room_visits v
  where v.user_id = v_uid
    and v.community_id = p_community_id;

  return coalesce(v_first_entered, now());
end;
$$;

revoke all on function public.record_community_first_entry(uuid) from public, anon;
grant execute on function public.record_community_first_entry(uuid) to authenticated;

drop function if exists public.get_community_messages(uuid, integer, timestamptz);
drop function if exists public.get_community_messages(uuid, integer, timestamptz, timestamptz);

create function public.get_community_messages(
  p_community_id uuid,
  p_limit integer default 40,
  p_before timestamptz default null,
  p_since timestamptz default null
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
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_lim integer := least(greatest(coalesce(p_limit, 40), 1), 200);
  v_first_entered timestamptz;
  v_effective_since timestamptz;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  v_first_entered := public.record_community_first_entry(p_community_id);
  v_effective_since := greatest(v_first_entered, coalesce(p_since, v_first_entered));

  return query
    with recent as (
      select m.*
      from public.community_messages m
      where m.community_id = p_community_id
        and m.created_at >= v_effective_since
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

revoke all on function public.get_community_messages(uuid, integer, timestamptz, timestamptz) from public, anon;
grant execute on function public.get_community_messages(uuid, integer, timestamptz, timestamptz) to authenticated;

drop function if exists public.list_communities_with_meta();
create function public.list_communities_with_meta()
returns table (
  id uuid,
  name text,
  description text,
  avatar_url text,
  owner_id uuid,
  created_by uuid,
  creator_name text,
  creator_username text,
  creator_avatar_url text,
  member_count integer,
  is_joined boolean,
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

  return query
    with counts as (
      select
        cm.community_id,
        count(*)::integer as cnt,
        bool_or(cm.user_id = v_uid) as joined
      from public.community_members cm
      group by cm.community_id
    )
    select
      c.id,
      c.name,
      c.description,
      c.avatar_url,
      c.owner_id,
      coalesce(c.created_by, c.owner_id) as created_by,
      coalesce(nullif(btrim(p.full_name), ''), nullif(btrim(p.username::text), ''), 'Pendaki') as creator_name,
      p.username::text as creator_username,
      p.avatar_url as creator_avatar_url,
      greatest(coalesce(cnt.cnt, 0), 0)::integer as member_count,
      coalesce(cnt.joined, false) as is_joined,
      c.created_at
    from public.communities c
    left join public.profiles p on p.id = coalesce(c.created_by, c.owner_id)
    left join counts cnt on cnt.community_id = c.id
    order by c.created_at desc;
end;
$$;

revoke all on function public.list_communities_with_meta() from public, anon;
grant execute on function public.list_communities_with_meta() to authenticated;

-- ----------------------------------------------------------------------------
-- 4. Group RPCs: avatar_url, joined_at, read cursor, update_group_avatar,
--    and creator leave_group (#25, #29, #30)
-- ----------------------------------------------------------------------------
drop function if exists public.create_group(text, text);
drop function if exists public.create_group(text, text, text);

create function public.create_group(
  p_name text,
  p_mountain text default null,
  p_avatar_url text default null
)
returns table (
  id uuid,
  name text,
  owner_id uuid,
  mountain text,
  avatar_url text,
  key_version integer,
  created_at timestamptz,
  joined_at timestamptz,
  last_read_at timestamptz,
  last_read_message_id text,
  role text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_group public.groups%rowtype;
  v_mountain text;
  v_avatar text;
  v_joined_at timestamptz;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_uid) then
    raise exception 'PROFILE_REQUIRED';
  end if;
  if p_name is null or char_length(btrim(p_name)) not between 1 and 60 then
    raise exception 'GROUP_NAME_INVALID';
  end if;

  v_mountain := nullif(btrim(coalesce(p_mountain, '')), '');
  if v_mountain is not null and char_length(v_mountain) > 80 then
    raise exception 'GROUP_NAME_INVALID';
  end if;
  v_avatar := nullif(btrim(coalesce(p_avatar_url, '')), '');

  insert into public.groups (name, owner_id, mountain, avatar_url)
  values (btrim(p_name), v_uid, v_mountain, v_avatar)
  returning * into v_group;

  insert into public.group_members (group_id, user_id, role, joined_at, last_read_at)
  values (v_group.id, v_uid, 'owner', v_group.created_at, v_group.created_at)
  returning public.group_members.joined_at into v_joined_at;

  return query
    select
      g.id,
      g.name,
      g.owner_id,
      g.mountain,
      g.avatar_url,
      g.key_version,
      g.created_at,
      v_joined_at as joined_at,
      v_joined_at as last_read_at,
      null::text as last_read_message_id,
      'owner'::text as role
    from public.groups g
    where g.id = v_group.id;
end;
$$;

revoke all on function public.create_group(text, text, text) from public, anon;
grant execute on function public.create_group(text, text, text) to authenticated;

drop function if exists public.my_groups();
create function public.my_groups()
returns table (
  id uuid,
  name text,
  owner_id uuid,
  mountain text,
  avatar_url text,
  key_version integer,
  created_at timestamptz,
  joined_at timestamptz,
  last_read_at timestamptz,
  last_read_message_id text,
  role text
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
  if not exists (select 1 from public.profiles p where p.id = v_uid) then
    raise exception 'PROFILE_REQUIRED';
  end if;

  return query
    select
      g.id,
      g.name,
      g.owner_id,
      g.mountain,
      g.avatar_url,
      g.key_version,
      g.created_at,
      m.joined_at,
      m.last_read_at,
      m.last_read_message_id,
      m.role
    from public.group_members m
    join public.groups g on g.id = m.group_id
    where m.user_id = v_uid
    order by m.joined_at asc;
end;
$$;

revoke all on function public.my_groups() from public, anon;
grant execute on function public.my_groups() to authenticated;

create or replace function public.update_group_avatar(
  p_group_id uuid,
  p_avatar_url text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_is_owner boolean := false;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  v_is_owner := exists (
    select 1
    from public.groups g
    where g.id = p_group_id and g.owner_id = v_uid
  ) or exists (
    select 1
    from public.group_members gm
    where gm.group_id = p_group_id and gm.user_id = v_uid and gm.role = 'owner'
  );

  if not v_is_owner then
    raise exception 'OWNER_REQUIRED' using errcode = '42501';
  end if;

  update public.groups
  set avatar_url = nullif(btrim(coalesce(p_avatar_url, '')), '')
  where id = p_group_id;
end;
$$;

revoke all on function public.update_group_avatar(uuid, text) from public, anon;
grant execute on function public.update_group_avatar(uuid, text) to authenticated;

drop function if exists public.leave_group(uuid);
create function public.leave_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_next_owner uuid;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  select g.owner_id into v_owner
  from public.groups g
  where g.id = p_group_id
  for update;

  if not found then
    return;
  end if;

  if to_regclass('public.member_locations') is not null then
    execute 'delete from public.member_locations where group_id = $1 and user_id = $2'
      using p_group_id, v_uid;
  end if;

  delete from public.group_key_blobs
  where group_id = p_group_id and user_id = v_uid;

  delete from public.group_members
  where group_id = p_group_id and user_id = v_uid;

  if v_owner = v_uid then
    select gm.user_id into v_next_owner
    from public.group_members gm
    where gm.group_id = p_group_id
    order by gm.joined_at asc
    limit 1;

    if v_next_owner is not null then
      update public.groups
      set owner_id = v_next_owner
      where id = p_group_id;

      update public.group_members
      set role = 'owner'
      where group_id = p_group_id and user_id = v_next_owner;
    end if;
  end if;
end;
$$;

revoke all on function public.leave_group(uuid) from public, anon;
grant execute on function public.leave_group(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 5. Read cursor sync RPC & social_latest_messages() with joined_at /
--    first_entered_at filtering and durable last_read_at / last_read_message_id
-- ----------------------------------------------------------------------------
create or replace function public.mark_room_read(
  p_room_kind text,
  p_room_id uuid,
  p_last_read_at timestamptz default now(),
  p_last_read_message_id text default null
)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_kind text := lower(btrim(coalesce(p_room_kind, '')));
  v_read_at timestamptz := coalesce(p_last_read_at, now());
  v_msg_id text := nullif(btrim(coalesce(p_last_read_message_id, '')), '');
  v_stored timestamptz;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;
  if p_room_id is null then
    return v_read_at;
  end if;

  if v_kind = 'group' then
    update public.group_members gm
    set
      last_read_at = greatest(coalesce(gm.last_read_at, '-infinity'::timestamptz), v_read_at),
      last_read_message_id = coalesce(v_msg_id, gm.last_read_message_id)
    where gm.group_id = p_room_id
      and gm.user_id = v_uid
    returning gm.last_read_at into v_stored;

    return coalesce(v_stored, v_read_at);
  elsif v_kind = 'community' then
    if not exists (select 1 from public.communities c where c.id = p_room_id) then
      return v_read_at;
    end if;

    perform public.record_community_first_entry(p_room_id);

    update public.community_room_visits v
    set
      last_read_at = greatest(coalesce(v.last_read_at, '-infinity'::timestamptz), v_read_at),
      last_read_message_id = coalesce(v_msg_id, v.last_read_message_id)
    where v.user_id = v_uid
      and v.community_id = p_room_id
    returning v.last_read_at into v_stored;

    update public.community_members cm
    set
      last_read_at = greatest(coalesce(cm.last_read_at, '-infinity'::timestamptz), v_read_at),
      last_read_message_id = coalesce(v_msg_id, cm.last_read_message_id)
    where cm.user_id = v_uid
      and cm.community_id = p_room_id;

    return coalesce(v_stored, v_read_at);
  end if;

  return v_read_at;
end;
$$;

revoke all on function public.mark_room_read(text, uuid, timestamptz, text) from public, anon;
grant execute on function public.mark_room_read(text, uuid, timestamptz, text) to authenticated;

drop function if exists public.social_latest_messages();
create function public.social_latest_messages()
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
  created_at timestamptz,
  last_read_at timestamptz,
  last_read_message_id text
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
        gm.created_at,
        m.last_read_at,
        m.last_read_message_id
      from public.group_messages gm
      join public.group_members m
        on m.group_id = gm.group_id and m.user_id = $1
      where gm.created_at >= m.joined_at
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
      cm.created_at,
      case
        when v.last_read_at is null then m.last_read_at
        when m.last_read_at is null then v.last_read_at
        else greatest(v.last_read_at, m.last_read_at)
      end as last_read_at,
      coalesce(v.last_read_message_id, m.last_read_message_id) as last_read_message_id
    from public.community_messages cm
    join public.community_members m
      on m.community_id = cm.community_id and m.user_id = v_uid
    left join public.community_room_visits v
      on v.community_id = cm.community_id and v.user_id = v_uid
    left join public.profiles p on p.id = cm.sender_id
    where cm.created_at >= coalesce(v.first_entered_at, m.first_entered_at, m.joined_at)
    order by cm.community_id, cm.created_at desc;
end;
$$;

revoke all on function public.social_latest_messages() from public, anon;
grant execute on function public.social_latest_messages() to authenticated;
