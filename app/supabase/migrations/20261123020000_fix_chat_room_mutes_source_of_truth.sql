-- ============================================================================
-- Migration: Unify Group & Community Notification Mute Source of Truth
--   1. Ensure `is_muted` + `muted_until` exist on `chat_notification_mutes`,
--      `group_members`, and `community_members`.
--   2. Sync `chat_notification_mutes` <-> `group_members` / `community_members`
--      automatically via trigger and atomic `set_room_mute()` RPC.
--   3. Add partial indexes & strict `(select auth.uid())` RLS policies.
-- ============================================================================

-- 1. Ensure `chat_notification_mutes` table & `is_muted` column exist
create table if not exists public.chat_notification_mutes (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  room_type   text not null check (room_type in ('group', 'community')),
  room_id     uuid not null,
  is_muted    boolean not null default false,
  muted_until timestamptz,
  updated_at  timestamptz not null default now(),
  primary key (user_id, room_type, room_id)
);

alter table if exists public.chat_notification_mutes
  add column if not exists is_muted boolean not null default false,
  add column if not exists muted_until timestamptz,
  add column if not exists updated_at timestamptz not null default now();

-- Backfill `is_muted` on existing rows
update public.chat_notification_mutes
set is_muted = (muted_until is not null)
where is_muted is distinct from (muted_until is not null);

-- Partial index for fast active-mute lookups per room
drop index if exists idx_chat_notification_mutes_room_active;
create index if not exists idx_chat_notification_mutes_room_active
  on public.chat_notification_mutes (room_type, room_id, user_id)
  where is_muted = true or muted_until is not null;

-- 2. Add `is_muted` & `muted_until` columns to `group_members` and `community_members`
alter table if exists public.group_members
  add column if not exists is_muted boolean not null default false,
  add column if not exists muted_until timestamptz;

alter table if exists public.community_members
  add column if not exists is_muted boolean not null default false,
  add column if not exists muted_until timestamptz;

create index if not exists idx_group_members_muted_active
  on public.group_members (group_id, user_id)
  where is_muted = true or muted_until is not null;

create index if not exists idx_community_members_muted_active
  on public.community_members (community_id, user_id)
  where is_muted = true or muted_until is not null;

-- Backfill existing mute rows into `group_members` & `community_members`
update public.group_members gm
set
  is_muted = cnm.is_muted,
  muted_until = cnm.muted_until
from public.chat_notification_mutes cnm
where cnm.room_type = 'group'
  and cnm.room_id = gm.group_id
  and cnm.user_id = gm.user_id;

update public.community_members cm
set
  is_muted = cnm.is_muted,
  muted_until = cnm.muted_until
from public.chat_notification_mutes cnm
where cnm.room_type = 'community'
  and cnm.room_id = cm.community_id
  and cnm.user_id = cm.user_id;

-- 3. Strict RLS on `chat_notification_mutes` using `(select auth.uid())`
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

-- 4. Keep `is_muted` normalized and mirrored into membership tables
create or replace function public.sync_chat_mute_to_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    if old.room_type = 'group' then
      update public.group_members
      set is_muted = false,
          muted_until = null
      where group_id = old.room_id
        and user_id = old.user_id;
    elsif old.room_type = 'community' then
      update public.community_members
      set is_muted = false,
          muted_until = null
      where community_id = old.room_id
        and user_id = old.user_id;
    end if;
    return old;
  end if;

  -- Normalize `is_muted` from `muted_until` when caller only writes `muted_until`
  if new.muted_until is null then
    new.is_muted := coalesce(new.is_muted, false);
  else
    new.is_muted := true;
  end if;
  new.updated_at := coalesce(new.updated_at, now());

  if new.room_type = 'group' then
    update public.group_members
    set is_muted = new.is_muted,
        muted_until = new.muted_until
    where group_id = new.room_id
      and user_id = new.user_id;
  elsif new.room_type = 'community' then
    update public.community_members
    set is_muted = new.is_muted,
        muted_until = new.muted_until
    where community_id = new.room_id
      and user_id = new.user_id;
  end if;

  return new;
end;
$$;

revoke all on function public.sync_chat_mute_to_membership() from public, anon;

drop trigger if exists trg_sync_chat_mute_to_membership_write on public.chat_notification_mutes;
create trigger trg_sync_chat_mute_to_membership_write
  before insert or update on public.chat_notification_mutes
  for each row
  execute function public.sync_chat_mute_to_membership();

drop trigger if exists trg_sync_chat_mute_to_membership_delete on public.chat_notification_mutes;
create trigger trg_sync_chat_mute_to_membership_delete
  after delete on public.chat_notification_mutes
  for each row
  execute function public.sync_chat_mute_to_membership();

-- 5. Atomic RPCs for setting and listing current user's muted rooms
create or replace function public.set_room_mute(
  p_room_type text,
  p_room_id uuid,
  p_is_muted boolean default true,
  p_muted_until timestamptz default null
)
returns table (
  room_type text,
  room_id uuid,
  is_muted boolean,
  muted_until timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_type text := lower(btrim(coalesce(p_room_type, '')));
  v_until timestamptz;
  v_muted boolean;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;
  if v_type not in ('group', 'community') then
    raise exception 'INVALID_ROOM_TYPE' using errcode = '22023';
  end if;
  if p_room_id is null then
    raise exception 'INVALID_ROOM_ID' using errcode = '22023';
  end if;

  if coalesce(p_is_muted, false) = false then
    v_muted := false;
    v_until := null;
  else
    v_muted := true;
    v_until := coalesce(p_muted_until, '9999-12-31T23:59:59Z'::timestamptz);
  end if;

  insert into public.chat_notification_mutes as cnm (
    user_id,
    room_type,
    room_id,
    is_muted,
    muted_until,
    updated_at
  )
  values (
    v_uid,
    v_type,
    p_room_id,
    v_muted,
    v_until,
    now()
  )
  on conflict (user_id, room_type, room_id) do update
    set is_muted = excluded.is_muted,
        muted_until = excluded.muted_until,
        updated_at = now();

  return query
    select v_type, p_room_id, v_muted, v_until;
end;
$$;

revoke all on function public.set_room_mute(text, uuid, boolean, timestamptz) from public, anon;
grant execute on function public.set_room_mute(text, uuid, boolean, timestamptz) to authenticated;

create or replace function public.my_chat_mutes()
returns table (
  room_type text,
  room_id uuid,
  is_muted boolean,
  muted_until timestamptz
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
    select
      m.room_type,
      m.room_id,
      (m.is_muted or (m.muted_until is not null and m.muted_until > now())) as is_muted,
      m.muted_until
    from public.chat_notification_mutes m
    where m.user_id = v_uid
      and (m.is_muted = true or (m.muted_until is not null and m.muted_until > now()))
    union
    select
      'group'::text as room_type,
      gm.group_id as room_id,
      true as is_muted,
      coalesce(gm.muted_until, '9999-12-31T23:59:59Z'::timestamptz) as muted_until
    from public.group_members gm
    where gm.user_id = v_uid
      and (gm.is_muted = true or (gm.muted_until is not null and gm.muted_until > now()))
    union
    select
      'community'::text as room_type,
      cm.community_id as room_id,
      true as is_muted,
      coalesce(cm.muted_until, '9999-12-31T23:59:59Z'::timestamptz) as muted_until
    from public.community_members cm
    where cm.user_id = v_uid
      and (cm.is_muted = true or (cm.muted_until is not null and cm.muted_until > now()));
end;
$$;

revoke all on function public.my_chat_mutes() from public, anon;
grant execute on function public.my_chat_mutes() to authenticated;
