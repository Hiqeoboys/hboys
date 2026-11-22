-- ============================================================================
-- Migration: Presence (`profiles.last_seen_at`), Safe Public Profile Lookup,
--            Community Creator Metadata, & Hardened Avatar URL Guard
-- ============================================================================

-- 1. Presence (`last_seen_at` based on opening the app, NOT location sharing)
alter table if exists public.profiles
  add column if not exists last_seen_at timestamptz;

create index if not exists idx_profiles_last_seen_present
  on public.profiles (last_seen_at desc)
  where last_seen_at is not null;

-- Keep column-scoped update grants strict while allowing authenticated self-updates
-- for `fcm_token`, `full_name`, and `last_seen_at`.
revoke update on table public.profiles from anon, authenticated;
grant update (fcm_token, full_name, last_seen_at) on table public.profiles to authenticated;

drop policy if exists profiles_self_update_safe on public.profiles;
create policy profiles_self_update_safe
  on public.profiles
  for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create or replace function public.touch_last_seen()
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_now timestamptz := now();
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  update public.profiles p
  set last_seen_at = v_now
  where p.id = v_uid;

  return v_now;
end;
$$;

revoke all on function public.touch_last_seen() from public, anon;
grant execute on function public.touch_last_seen() to authenticated;

-- 2. Update `group_members_detail` to return `profiles.last_seen_at`
drop function if exists public.group_members_detail(uuid);
create or replace function public.group_members_detail(p_group_id uuid)
returns table (
  user_id uuid,
  username text,
  full_name text,
  avatar_url text,
  role text,
  public_key text,
  joined_at timestamptz,
  last_seen_at timestamptz
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
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  if not public.is_group_member(p_group_id) then
    raise exception 'NOT_MEMBER' using errcode = '42501';
  end if;

  return query
    select
      m.user_id,
      coalesce(p.username::text, '') as username,
      p.full_name,
      p.avatar_url,
      m.role,
      coalesce(p.public_key, '') as public_key,
      m.joined_at,
      p.last_seen_at
    from public.group_members m
    join public.profiles p on p.id = m.user_id
    where m.group_id = p_group_id
    order by
      case when m.role = 'owner' then 0 else 1 end asc,
      m.joined_at asc;
end;
$$;

revoke all on function public.group_members_detail(uuid) from public, anon;
grant execute on function public.group_members_detail(uuid) to authenticated;

-- 3. Harden `update_my_avatar` so expired presigned / private R2 S3 API URLs
--    can never be persisted into `profiles.avatar_url`.
create or replace function public.update_my_avatar(p_avatar_url text)
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
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  if v_url = ''
     or length(v_url) > 512
     or v_url !~* '^https://'
     or v_url ~* '(x-amz-signature|x-amz-credential|r2\.cloudflarestorage\.com)' then
    raise exception 'AVATAR_URL_INVALID' using errcode = '22023';
  end if;

  update public.profiles p
  set avatar_url = v_url,
      updated_at = now()
  where p.id = v_uid;

  return query
    select p.id, p.avatar_url
    from public.profiles p
    where p.id = v_uid;
end;
$$;

revoke all on function public.update_my_avatar(text) from public, anon;
grant execute on function public.update_my_avatar(text) to authenticated;

-- 4. Safe public profile directory lookup (never leaks email, fcm_token, is_plus, or public_key)
create or replace function public.get_public_profiles(p_user_ids uuid[])
returns table (
  id uuid,
  username text,
  full_name text,
  avatar_url text,
  last_seen_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  if p_user_ids is null or cardinality(p_user_ids) = 0 then
    return;
  end if;

  return query
    select
      p.id,
      p.username::text,
      coalesce(nullif(btrim(p.full_name), ''), p.username::text) as full_name,
      p.avatar_url,
      p.last_seen_at
    from public.profiles p
    where p.id = any(p_user_ids)
    limit 200;
end;
$$;

revoke all on function public.get_public_profiles(uuid[]) from public, anon;
grant execute on function public.get_public_profiles(uuid[]) to authenticated;

-- 5. Community Creator Exposure (`communities.created_by` + dynamic join RPCs)
do $$
begin
  if to_regclass('public.communities') is not null then
    alter table public.communities
      add column if not exists created_by uuid references public.profiles (id) on delete set null;

    update public.communities
    set created_by = owner_id
    where created_by is null;

    create index if not exists idx_communities_created_by
      on public.communities (created_by)
      where created_by is not null;
  end if;
end;
$$;

create or replace function public.set_community_created_by()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.created_by := coalesce(new.created_by, new.owner_id, auth.uid());
  return new;
end;
$$;

do $$
begin
  if to_regclass('public.communities') is not null then
    drop trigger if exists trg_communities_set_created_by on public.communities;
    create trigger trg_communities_set_created_by
      before insert on public.communities
      for each row
      execute function public.set_community_created_by();
  end if;
end;
$$;

revoke all on function public.set_community_created_by() from public, anon;

create or replace function public.list_communities_with_meta()
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
      greatest(coalesce(cnt.cnt, 1), 1)::integer as member_count,
      (coalesce(cnt.joined, false) or c.owner_id = v_uid) as is_joined,
      c.created_at
    from public.communities c
    left join public.profiles p on p.id = coalesce(c.created_by, c.owner_id)
    left join counts cnt on cnt.community_id = c.id
    order by c.created_at desc;
end;
$$;

revoke all on function public.list_communities_with_meta() from public, anon;
grant execute on function public.list_communities_with_meta() to authenticated;

create or replace function public.list_community_members(p_community_id uuid)
returns table (
  user_id uuid,
  username text,
  full_name text,
  avatar_url text,
  role text,
  joined_at timestamptz,
  last_seen_at timestamptz
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
      cm.user_id,
      coalesce(p.username::text, '') as username,
      coalesce(nullif(btrim(p.full_name), ''), p.username::text, 'Pendaki') as full_name,
      p.avatar_url,
      cm.role,
      cm.joined_at,
      p.last_seen_at
    from public.community_members cm
    join public.profiles p on p.id = cm.user_id
    where cm.community_id = p_community_id
    order by
      case when cm.role = 'owner' then 0 else 1 end asc,
      cm.joined_at asc
    limit 500;
end;
$$;

revoke all on function public.list_community_members(uuid) from public, anon;
grant execute on function public.list_community_members(uuid) to authenticated;
