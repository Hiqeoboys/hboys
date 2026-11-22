-- ============================================================================
-- Wave D Migration (Mirror 0017):
-- 1. Hiqeo Plus 3-Day Grace Period + Strict Community/Leaderboard Expiry Lock
--    + Subscription History (`public.subscription_history` + `my_subscription_history`)
--    + Ultima lifetime detection (`is_ultima`)
-- 2. Verified `@hiqeo` / `Hiqeo Official` whitelist (`hiqeoofficial@gmail.com`)
--    & `profiles.is_official` column + anti-spoofing guard trigger
-- 3. Realtime username availability check RPC (`check_username_available`)
--    & official flag propagation across public profile / member / leaderboard RPCs
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Profiles columns & Official verification helper
-- ----------------------------------------------------------------------------
alter table if exists public.profiles
  add column if not exists is_official boolean not null default false,
  add column if not exists plus_started_at timestamptz;

create or replace function public.is_verified_official_email(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_uid is null then false
    else exists (
      select 1
      from auth.users u
      where u.id = p_uid
        and lower(coalesce(u.email, '')) = 'hiqeoofficial@gmail.com'
        and u.email_confirmed_at is not null
    )
  end;
$$;

revoke all on function public.is_verified_official_email(uuid) from public, anon, authenticated;

-- Backfill `is_official` cleanly from verified email truth source.
do $$
begin
  if to_regclass('public.profiles') is not null then
    perform set_config('app.allow_official_sync', 'on', true);
    update public.profiles p
    set is_official = public.is_verified_official_email(p.id)
    where p.is_official is distinct from public.is_verified_official_email(p.id);
  end if;
end;
$$;

-- Protect sensitive profile columns (`is_official`, `plus_started_at`, etc.)
-- from direct client tampering, while auto-marking official accounts on insert.
create or replace function public.guard_profile_sensitive_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if current_user not in ('postgres', 'service_role', 'supabase_admin')
       and coalesce(current_setting('app.allow_official_sync', true), '') <> 'on' then
      new.is_plus := false;
      new.plus_plan_id := null;
      new.plus_expires_at := null;
      new.plus_started_at := null;
      new.is_official := public.is_verified_official_email(new.id);
    end if;
    return new;
  end if;

  if current_user not in ('postgres', 'service_role', 'supabase_admin') then
    if new.id is distinct from old.id
       or new.is_plus is distinct from old.is_plus
       or new.plus_plan_id is distinct from old.plus_plan_id
       or new.plus_expires_at is distinct from old.plus_expires_at
       or new.plus_started_at is distinct from old.plus_started_at
       or new.created_at is distinct from old.created_at
       or (to_jsonb(new) ->> 'email') is distinct from (to_jsonb(old) ->> 'email') then
      raise exception 'SENSITIVE_PROFILE_COLUMN_FORBIDDEN'
        using errcode = '42501';
    end if;

    if new.is_official is distinct from old.is_official
       and coalesce(current_setting('app.allow_official_sync', true), '') <> 'on' then
      raise exception 'SENSITIVE_PROFILE_COLUMN_FORBIDDEN'
        using errcode = '42501';
    end if;

    if (
      new.username is distinct from old.username
      or new.username_changed_at is distinct from old.username_changed_at
    ) and coalesce(current_setting('app.allow_username_update', true), '') <> 'on' then
      raise exception 'DIRECT_USERNAME_UPDATE_FORBIDDEN'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_profile_sensitive_columns on public.profiles;
create trigger trg_guard_profile_sensitive_columns
  before insert or update on public.profiles
  for each row
  execute function public.guard_profile_sensitive_columns();

revoke all on function public.guard_profile_sensitive_columns() from public, anon;

-- ----------------------------------------------------------------------------
-- 2. Subscription History table + strict owner-only RLS + RPC
-- ----------------------------------------------------------------------------
create table if not exists public.subscription_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id text not null,
  plan_title text not null,
  status text not null check (status in ('active', 'lifetime', 'grace', 'expired', 'cancelled')),
  started_at timestamptz not null default now(),
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_subscription_history_user_started
  on public.subscription_history (user_id, started_at desc, created_at desc);

alter table public.subscription_history enable row level security;

drop policy if exists subscription_history_owner_select on public.subscription_history;
create policy subscription_history_owner_select
  on public.subscription_history
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

revoke insert, update, delete on table public.subscription_history from anon, authenticated;

create or replace function public.my_subscription_history()
returns table (
  id uuid,
  plan_id text,
  plan_title text,
  status text,
  started_at timestamptz,
  expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_has_rows boolean := false;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  select exists (
    select 1
    from public.subscription_history sh
    where sh.user_id = v_uid
  ) into v_has_rows;

  if v_has_rows then
    return query
      select
        sh.id,
        sh.plan_id,
        sh.plan_title,
        case
          when sh.expires_at is null
               and lower(coalesce(sh.plan_id, '')) in ('lifetime', 'founding', 'ultima')
            then 'lifetime'
          when sh.status = 'cancelled' then 'cancelled'
          when sh.expires_at is null or sh.expires_at > now() then 'active'
          when sh.expires_at + interval '3 days' > now() then 'grace'
          else 'expired'
        end as status,
        sh.started_at,
        sh.expires_at
      from public.subscription_history sh
      where sh.user_id = v_uid
      order by sh.started_at desc, sh.created_at desc
      limit 50;
    return;
  end if;

  -- Fallback: synthesize a single history entry from `profiles` ONLY if user has
  -- subscribed or previously subscribed (`plus_plan_id` / `plus_expires_at` / `is_plus`).
  return query
    select
      p.id,
      coalesce(nullif(btrim(p.plus_plan_id), ''), 'annual') as plan_id,
      case lower(coalesce(p.plus_plan_id, ''))
        when 'student_annual' then 'Paket Mahasiswa'
        when 'mahasiswa' then 'Paket Mahasiswa'
        when 'annual' then 'Hiqeo Plus Tahunan'
        when 'tahunan' then 'Hiqeo Plus Tahunan'
        when 'trip_pass_3d' then 'Tiket 1x Naik'
        when 'trip3d' then 'Tiket 1x Naik'
        when 'trip7d' then 'Tiket 1x Naik'
        when 'founding' then 'Founding Member'
        when 'lifetime' then 'Hiqeo Plus Ultima'
        when 'ultima' then 'Hiqeo Plus Ultima'
        else 'Hiqeo Plus'
      end as plan_title,
      case
        when p.is_plus = true
             and (p.plus_expires_at is null
                  or lower(coalesce(p.plus_plan_id, '')) in ('lifetime', 'founding', 'ultima'))
          then 'lifetime'
        when p.plus_expires_at is not null and p.plus_expires_at > now() then 'active'
        when p.plus_expires_at is not null and (p.plus_expires_at + interval '3 days') > now() then 'grace'
        when p.is_plus = true and p.plus_expires_at is null then 'lifetime'
        else 'expired'
      end as status,
      coalesce(p.plus_started_at, p.updated_at, p.created_at, now()) as started_at,
      p.plus_expires_at as expires_at
    from public.profiles p
    where p.id = v_uid
      and (
        p.is_plus = true
        or nullif(btrim(p.plus_plan_id), '') is not null
        or p.plus_expires_at is not null
      );
end;
$$;

revoke all on function public.my_subscription_history() from public, anon;
grant execute on function public.my_subscription_history() to authenticated;

-- ----------------------------------------------------------------------------
-- 3. Strict immediate lock (NO 3-day grace) for Community Chat & Leaderboard
-- ----------------------------------------------------------------------------
create or replace function public.has_full_plus_social(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = p_uid
      and p.is_plus = true
      and lower(coalesce(p.plus_plan_id, '')) in (
        'student_annual',
        'mahasiswa',
        'annual',
        'tahunan',
        'lifetime',
        'founding',
        'ultima'
      )
      and (p.plus_expires_at is null or p.plus_expires_at > now())
  );
$$;

revoke all on function public.has_full_plus_social(uuid) from public;
grant execute on function public.has_full_plus_social(uuid) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 4. Moderation Normalization + Official Whitelist + Username Availability
-- ----------------------------------------------------------------------------
create or replace function public.normalize_username_moderation(p_raw text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_lower text := lower(coalesce(p_raw, ''));
  v_mapped text;
  v_len integer;
  v_i integer := 1;
  v_ch text;
  v_prev text := '';
  v_out text := '';
begin
  v_mapped := translate(
    v_lower,
    '013457@$',
    'oieastas'
  );
  v_mapped := regexp_replace(v_mapped, '[._\-\s]+', '', 'g');
  v_len := char_length(v_mapped);
  if v_len = 0 then
    return '';
  end if;
  while v_i <= v_len loop
    v_ch := substr(v_mapped, v_i, 1);
    if v_ch <> v_prev then
      v_out := v_out || v_ch;
      v_prev := v_ch;
    end if;
    v_i := v_i + 1;
  end loop;
  return v_out;
end;
$$;

revoke all on function public.normalize_username_moderation(text) from public, anon;

create or replace function public.is_username_reserved_or_blocked(
  p_clean text,
  p_uid uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_mod text := public.normalize_username_moderation(p_clean);
  v_is_official boolean := public.is_verified_official_email(p_uid);
  v_reserved text[] := array[
    'admin', 'administrator', 'hiqeo', 'hiqeoid', 'hiqeo_id', 'hiqeo.id',
    'hiqeo_official', 'hiqeofficial', 'timhiqeo', 'support', 'bantuan',
    'layanan', 'moderator', 'mod', 'official', 'resmi', 'staff', 'system',
    'sistem', 'root', 'help', 'security', 'keamanan', 'info', 'api', 'bot',
    'owner', 'founder', 'null', 'undefined', 'test', 'testing', 'basarnas',
    'sar', 'polisi', 'darurat', 'sos'
  ];
  v_term text;
  v_blocked_hit boolean := false;
begin
  -- Strict verified whitelist: ONLY hiqeoofficial@gmail.com may claim `hiqeo`.
  if v_is_official and p_clean = 'hiqeo' then
    return false;
  end if;

  if p_clean = any(v_reserved) or v_mod = any(v_reserved) then
    return true;
  end if;

  -- Prevent impersonation containing 'hiqeo' unless verified official.
  if not v_is_official and (p_clean like '%hiqeo%' or v_mod like '%hiqeo%') then
    return true;
  end if;

  if to_regclass('public.blocked_terms') is not null then
    for v_term in
      execute 'select term::text from public.blocked_terms'
    loop
      if v_term is not null and btrim(v_term) <> '' then
        if p_clean like '%' || lower(btrim(v_term)) || '%'
           or v_mod like '%' || public.normalize_username_moderation(v_term) || '%' then
          v_blocked_hit := true;
          exit;
        end if;
      end if;
    end loop;
  end if;

  return v_blocked_hit;
end;
$$;

revoke all on function public.is_username_reserved_or_blocked(text, uuid) from public, anon;

create or replace function public.check_username_available(p_username text)
returns table (
  available boolean,
  reason text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_clean text := lower(btrim(regexp_replace(coalesce(p_username, ''), '^@+', '')));
  v_taken boolean := false;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  if v_clean = ''
     or char_length(v_clean) < 3
     or char_length(v_clean) > 20
     or v_clean !~ '^[a-z0-9_.]+$'
     or v_clean ~ '^[._]|[._]$'
     or v_clean ~ '\.\.' then
    return query select false, 'invalid_format'::text;
    return;
  end if;

  if public.is_username_reserved_or_blocked(v_clean, v_uid) then
    return query select false, 'blocked'::text;
    return;
  end if;

  select exists (
    select 1
    from public.profiles p
    where lower(coalesce(p.username::text, '')) = v_clean
      and p.id <> v_uid
  ) into v_taken;

  if v_taken then
    return query select false, 'taken'::text;
    return;
  end if;

  return query select true, null::text;
end;
$$;

revoke all on function public.check_username_available(text) from public, anon;
grant execute on function public.check_username_available(text) to authenticated;

drop function if exists public.set_username(text);
create or replace function public.set_username(new_username text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_clean text := lower(btrim(regexp_replace(coalesce(new_username, ''), '^@+', '')));
  v_is_official boolean := public.is_verified_official_email(auth.uid());
  v_existing_username text;
  v_changed_at timestamptz;
  v_days_left integer := 0;
  v_taken boolean := false;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  if v_clean = ''
     or char_length(v_clean) < 3
     or char_length(v_clean) > 20
     or v_clean !~ '^[a-z0-9_.]+$'
     or v_clean ~ '^[._]|[._]$'
     or v_clean ~ '\.\.' then
    return jsonb_build_object('ok', false, 'error', 'invalid_format');
  end if;

  if public.is_username_reserved_or_blocked(v_clean, v_uid) then
    return jsonb_build_object('ok', false, 'error', 'blocked');
  end if;

  select p.username::text, p.username_changed_at
  into v_existing_username, v_changed_at
  from public.profiles p
  where p.id = v_uid
  for update;

  if found
     and v_existing_username is not null
     and btrim(v_existing_username) <> ''
     and lower(v_existing_username) <> v_clean
     and not (v_is_official and v_clean = 'hiqeo')
     and v_changed_at is not null
     and v_changed_at + interval '7 days' > now() then
    v_days_left := greatest(
      1,
      ceil(extract(epoch from ((v_changed_at + interval '7 days') - now())) / 86400.0)::integer
    );
    return jsonb_build_object('ok', false, 'error', format('cooldown:%s', v_days_left));
  end if;

  select exists (
    select 1
    from public.profiles p
    where lower(coalesce(p.username::text, '')) = v_clean
      and p.id <> v_uid
  ) into v_taken;

  if v_taken then
    return jsonb_build_object('ok', false, 'error', 'taken');
  end if;

  perform set_config('app.allow_username_update', 'on', true);
  perform set_config('app.allow_official_sync', 'on', true);

  if found then
    update public.profiles p
    set username = v_clean,
        username_changed_at = now(),
        is_official = v_is_official,
        updated_at = now()
    where p.id = v_uid;
  else
    insert into public.profiles (id, username, username_changed_at, is_official)
    values (v_uid, v_clean, now(), v_is_official);
  end if;

  return jsonb_build_object(
    'ok', true,
    'username', v_clean,
    'is_official', v_is_official
  );
end;
$$;

revoke all on function public.set_username(text) from public, anon;
grant execute on function public.set_username(text) to authenticated;

drop function if exists public.register_profile(text, text);
create or replace function public.register_profile(
  p_username text,
  p_public_key text
)
returns table (id uuid, username text, public_key text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_clean text := lower(btrim(regexp_replace(coalesce(p_username, ''), '^@+', '')));
  v_is_official boolean := public.is_verified_official_email(auth.uid());
  v_existing public.profiles%rowtype;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  if v_clean = ''
     or char_length(v_clean) < 3
     or char_length(v_clean) > 20
     or v_clean !~ '^[a-z0-9_.]+$'
     or v_clean ~ '^[._]|[._]$'
     or v_clean ~ '\.\.' then
    raise exception 'USERNAME_INVALID' using errcode = '22023';
  end if;

  if public.is_username_reserved_or_blocked(v_clean, v_uid) then
    raise exception 'USERNAME_BLOCKED' using errcode = '42501';
  end if;

  if p_public_key is null
     or length(p_public_key) <> 44
     or p_public_key !~ '^[A-Za-z0-9+/]{43}=$'
     or length(decode(p_public_key, 'base64')) <> 32 then
    raise exception 'PUBLIC_KEY_INVALID' using errcode = '22023';
  end if;

  perform set_config('app.allow_username_update', 'on', true);
  perform set_config('app.allow_official_sync', 'on', true);

  select * into v_existing from public.profiles p where p.id = v_uid for update;

  if found then
    if coalesce(v_existing.username::text, '') = '' then
      update public.profiles p
      set username = v_clean,
          public_key = p_public_key,
          is_official = v_is_official,
          updated_at = now()
      where p.id = v_uid;
    else
      if lower(v_existing.username::text) <> v_clean then
        raise exception 'USERNAME_IMMUTABLE' using errcode = '42501';
      end if;
      if v_existing.public_key is distinct from p_public_key
         or v_existing.is_official is distinct from v_is_official then
        update public.profiles p
        set public_key = p_public_key,
            is_official = v_is_official,
            updated_at = now()
        where p.id = v_uid;
        if v_existing.public_key is distinct from p_public_key then
          delete from public.group_key_blobs b where b.user_id = v_uid;
          update public.groups g
          set key_version = g.key_version + 1
          where g.owner_id = v_uid;
        end if;
      end if;
    end if;
  else
    insert into public.profiles (id, username, public_key, is_official)
    values (v_uid, v_clean, p_public_key, v_is_official);
  end if;

  return query
    select p.id, p.username::text, p.public_key
    from public.profiles p
    where p.id = v_uid;
exception
  when unique_violation then
    raise exception 'USERNAME_TAKEN' using errcode = '23505';
end;
$$;

revoke all on function public.register_profile(text, text) from public, anon;
grant execute on function public.register_profile(text, text) to authenticated;

drop function if exists public.update_my_full_name(text);
create or replace function public.update_my_full_name(p_full_name text)
returns table (
  id uuid,
  full_name text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_name text := btrim(coalesce(p_full_name, ''));
  v_norm text := public.normalize_username_moderation(v_name);
  v_is_official boolean := public.is_verified_official_email(auth.uid());
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  if v_name = '' then
    raise exception 'FULL_NAME_EMPTY' using errcode = '22023';
  end if;

  if char_length(v_name) > 40 then
    raise exception 'FULL_NAME_TOO_LONG' using errcode = '22023';
  end if;

  if not v_is_official and (
    lower(v_name) like '%hiqeo official%'
    or v_norm like '%hiqeofficial%'
    or v_norm = 'hiqeo'
  ) then
    raise exception 'USERNAME_BLOCKED' using errcode = '42501';
  end if;

  perform set_config('app.allow_official_sync', 'on', true);

  update public.profiles p
  set full_name = v_name,
      is_official = v_is_official,
      updated_at = now()
  where p.id = v_uid;

  return query
    select p.id, p.full_name
    from public.profiles p
    where p.id = v_uid;
end;
$$;

revoke all on function public.update_my_full_name(text) from public, anon;
grant execute on function public.update_my_full_name(text) to authenticated;

-- ----------------------------------------------------------------------------
-- 5. Update Public Read RPCs with `is_official` (+ `is_ultima`, `plus_plan_id`)
-- ----------------------------------------------------------------------------
drop function if exists public.user_public_profile(uuid);
create or replace function public.user_public_profile(p_user_id uuid)
returns table (
  user_id uuid,
  username text,
  full_name text,
  avatar_url text,
  has_plus_badge boolean,
  mountains_climbed integer,
  total_distance_m double precision,
  total_moving_seconds bigint,
  plus_plan_id text,
  is_ultima boolean,
  is_official boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  return query
    select
      p.id as user_id,
      p.username::text as username,
      coalesce(nullif(btrim(p.full_name), ''), p.username::text) as full_name,
      p.avatar_url,
      public.has_full_plus_social(p.id) as has_plus_badge,
      coalesce(
        count(distinct coalesce(nullif(btrim(hs.mountain_name), ''), hs.id::text))
          filter (where hs.id is not null and hs.activity_type = 'hiking'),
        0
      )::integer as mountains_climbed,
      coalesce(sum(hs.distance_m) filter (where hs.activity_type = 'hiking'), 0)::double precision as total_distance_m,
      coalesce(sum(hs.moving_seconds) filter (where hs.activity_type = 'hiking'), 0)::bigint as total_moving_seconds,
      p.plus_plan_id,
      (
        p.is_plus = true
        and (
          p.plus_expires_at is null
          or lower(coalesce(p.plus_plan_id, '')) in ('lifetime', 'founding', 'ultima')
        )
      ) as is_ultima,
      p.is_official
    from public.profiles p
    left join public.hike_sessions hs on hs.user_id = p.id
    where p.id = p_user_id
    group by p.id, p.username, p.full_name, p.avatar_url, p.plus_plan_id, p.is_plus, p.plus_expires_at, p.is_official;
end;
$$;

revoke all on function public.user_public_profile(uuid) from public, anon;
grant execute on function public.user_public_profile(uuid) to authenticated;

drop function if exists public.get_public_profiles(uuid[]);
create or replace function public.get_public_profiles(p_user_ids uuid[])
returns table (
  id uuid,
  username text,
  full_name text,
  avatar_url text,
  last_seen_at timestamptz,
  is_official boolean
)
language plpgsql
stable
security definer
set search_path = ''
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
      p.last_seen_at,
      p.is_official
    from public.profiles p
    where p.id = any(p_user_ids)
    limit 200;
end;
$$;

revoke all on function public.get_public_profiles(uuid[]) from public, anon;
grant execute on function public.get_public_profiles(uuid[]) to authenticated;

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
  last_seen_at timestamptz,
  is_official boolean
)
language plpgsql
stable
security definer
set search_path = ''
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
      p.last_seen_at,
      p.is_official
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

drop function if exists public.list_community_members(uuid);
create or replace function public.list_community_members(p_community_id uuid)
returns table (
  user_id uuid,
  username text,
  full_name text,
  avatar_url text,
  role text,
  joined_at timestamptz,
  last_seen_at timestamptz,
  is_official boolean
)
language plpgsql
stable
security definer
set search_path = ''
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
      p.last_seen_at,
      p.is_official
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

drop function if exists public.search_users_by_username(text, integer);
create or replace function public.search_users_by_username(
  p_query text,
  p_limit integer default 15
)
returns table (
  id uuid,
  username text,
  full_name text,
  avatar_url text,
  is_official boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_clean text;
  v_escaped text;
  v_lim integer := least(greatest(coalesce(p_limit, 15), 1), 15);
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
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
      p.avatar_url,
      p.is_official
    from public.profiles p
    where p.id <> v_uid
      and lower(coalesce(p.username::text, '')) like (v_escaped || '%') escape '\'
    order by lower(p.username::text) asc
    limit v_lim;
end;
$$;

revoke all on function public.search_users_by_username(text, integer) from public, anon;
grant execute on function public.search_users_by_username(text, integer) to authenticated;

drop function if exists public.leaderboard_rankings(text, text);
create or replace function public.leaderboard_rankings(
  p_category text default 'mountains',
  p_period text default 'monthly'
)
returns table (
  rank_pos bigint,
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  mountains_count bigint,
  total_distance_m double precision,
  is_official boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_since timestamptz;
  v_category text := lower(coalesce(nullif(btrim(p_category), ''), 'mountains'));
  v_period text := lower(coalesce(nullif(btrim(p_period), ''), 'monthly'));
begin
  if auth.uid() is null
     and coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'AUTH_REQUIRED';
  end if;

  if v_period = 'yearly' then
    v_since := date_trunc('year', now());
  else
    v_since := date_trunc('month', now());
  end if;

  return query
    with aggregated as (
      select
        p.id as uid,
        p.username::text as uname,
        nullif(btrim(p.full_name), '') as dname,
        p.avatar_url as aurl,
        p.is_official as official_flag,
        count(
          distinct coalesce(nullif(btrim(hs.mountain_name), ''), hs.id::text)
        )::bigint as mcount,
        coalesce(sum(hs.distance_m), 0)::double precision as dist_m
      from public.hike_sessions hs
      join public.profiles p on p.id = hs.user_id
      where hs.activity_type = 'hiking'
        and hs.started_at >= v_since
        and public.has_full_plus_social(p.id)
      group by p.id, p.username, p.full_name, p.avatar_url, p.is_official
      having (
        case
          when v_category = 'distance' then coalesce(sum(hs.distance_m), 0) > 0
          else count(hs.id) > 0
        end
      )
    )
    select
      row_number() over (
        order by
          case
            when v_category = 'distance' then a.dist_m
            else a.mcount::double precision
          end desc,
          a.dist_m desc,
          a.mcount desc,
          coalesce(a.dname, a.uname) asc
      )::bigint as rank_pos,
      a.uid as user_id,
      a.uname as username,
      a.dname as display_name,
      a.aurl as avatar_url,
      a.mcount as mountains_count,
      a.dist_m as total_distance_m,
      a.official_flag as is_official
    from aggregated a
    order by rank_pos asc
    limit 100;
end;
$fn$;

revoke all on function public.leaderboard_rankings(text, text) from public, anon;
grant execute on function public.leaderboard_rankings(text, text) to authenticated, service_role;
