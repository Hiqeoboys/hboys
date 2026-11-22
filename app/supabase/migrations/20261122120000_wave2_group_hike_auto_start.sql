-- ============================================================================
-- Migration: Wave 2 — Group Hike Auto-Start (`status = 'started'`),
--            Atomic Readiness Toggle RPCs, & Instant FCM Dispatch
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. `public.group_hike_prep`: add `started_at`, `started_by`, & allow `'started'`
-- ----------------------------------------------------------------------------
alter table if exists public.group_hike_prep
  add column if not exists started_at timestamptz,
  add column if not exists started_by uuid references public.profiles (id) on delete set null;

do $$
declare
  v_con record;
begin
  if to_regclass('public.group_hike_prep') is not null then
    for v_con in
      select conname
      from pg_constraint
      where conrelid = 'public.group_hike_prep'::regclass
        and contype = 'c'
        and pg_get_constraintdef(oid) ilike '%status%'
    loop
      execute format(
        'alter table public.group_hike_prep drop constraint if exists %I',
        v_con.conname
      );
    end loop;

    alter table public.group_hike_prep
      add constraint group_hike_prep_status_check
      check (status in ('active', 'started', 'completed', 'cancelled'));

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

-- ----------------------------------------------------------------------------
-- 2. `public.user_notifications`: allow `'hike_started'` inbox items
-- ----------------------------------------------------------------------------
do $$
declare
  v_con record;
begin
  if to_regclass('public.user_notifications') is not null then
    for v_con in
      select conname
      from pg_constraint
      where conrelid = 'public.user_notifications'::regclass
        and contype = 'c'
        and pg_get_constraintdef(oid) ilike '%type%'
    loop
      execute format(
        'alter table public.user_notifications drop constraint if exists %I',
        v_con.conname
      );
    end loop;

    alter table public.user_notifications
      add constraint user_notifications_type_check
      check (
        type in (
          'friend_request',
          'group_invitation',
          'group_ready',
          'group_hike_cancelled',
          'hike_started',
          'community_mention',
          'emergency_contact_request',
          'sos'
        )
      );
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. Atomic RPCs: `mark_group_hike_ready`, `unmark_group_hike_ready`, `start_group_hike_prep`
-- ----------------------------------------------------------------------------
create or replace function public.mark_group_hike_ready(p_group_id uuid)
returns public.group_hike_prep
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.group_hike_prep%rowtype;
  v_member_count integer := 1;
  v_now timestamptz := now();
  v_udt text;
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

  if coalesce(v_row.is_cancelled, false) or v_row.status = 'cancelled' then
    return v_row;
  end if;

  select greatest(1, count(*)::integer)
  into v_member_count
  from public.group_members gm
  where gm.group_id = p_group_id;

  select c.udt_name into v_udt
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'group_hike_prep'
    and c.column_name = 'ready_user_ids';

  if v_udt = '_uuid' then
    execute $q$
      update public.group_hike_prep
      set ready_user_ids = array(
            select distinct x
            from unnest(coalesce(ready_user_ids, '{}'::uuid[]) || $1) as x
            where x is not null
          ),
          member_count = $2,
          updated_at = $3
      where group_id = $4
      returning *
    $q$
    into v_row
    using v_uid, v_member_count, v_now, p_group_id;
  else
    execute $q$
      update public.group_hike_prep
      set ready_user_ids = array(
            select distinct x
            from unnest(coalesce(ready_user_ids, '{}'::text[]) || $1) as x
            where x is not null and btrim(x) <> ''
          ),
          member_count = $2,
          updated_at = $3
      where group_id = $4
      returning *
    $q$
    into v_row
    using v_uid::text, v_member_count, v_now, p_group_id;
  end if;

  return v_row;
end;
$$;

create or replace function public.unmark_group_hike_ready(p_group_id uuid)
returns public.group_hike_prep
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.group_hike_prep%rowtype;
  v_member_count integer := 1;
  v_now timestamptz := now();
  v_udt text;
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

  if coalesce(v_row.is_cancelled, false) or v_row.status in ('cancelled', 'completed', 'started') then
    return v_row;
  end if;

  select greatest(1, count(*)::integer)
  into v_member_count
  from public.group_members gm
  where gm.group_id = p_group_id;

  select c.udt_name into v_udt
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'group_hike_prep'
    and c.column_name = 'ready_user_ids';

  if v_udt = '_uuid' then
    execute $q$
      update public.group_hike_prep
      set ready_user_ids = array_remove(coalesce(ready_user_ids, '{}'::uuid[]), $1),
          member_count = $2,
          updated_at = $3
      where group_id = $4
      returning *
    $q$
    into v_row
    using v_uid, v_member_count, v_now, p_group_id;
  else
    execute $q$
      update public.group_hike_prep
      set ready_user_ids = array_remove(coalesce(ready_user_ids, '{}'::text[]), $1),
          member_count = $2,
          updated_at = $3
      where group_id = $4
      returning *
    $q$
    into v_row
    using v_uid::text, v_member_count, v_now, p_group_id;
  end if;

  return v_row;
end;
$$;

create or replace function public.start_group_hike_prep(
  p_group_id uuid,
  p_mountain_id text default null,
  p_trail_id text default null
)
returns public.group_hike_prep
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.group_hike_prep%rowtype;
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

  if coalesce(v_row.is_cancelled, false) or v_row.status = 'cancelled' then
    raise exception 'HIKE_PREP_CANCELLED' using errcode = '42501';
  end if;

  if v_row.status = 'started' then
    return v_row;
  end if;

  update public.group_hike_prep
  set status = 'started',
      started_at = coalesce(started_at, v_now),
      started_by = coalesce(started_by, v_uid),
      mountain_id = coalesce(nullif(btrim(p_mountain_id), ''), mountain_id),
      trail_id = coalesce(nullif(btrim(p_trail_id), ''), trail_id),
      updated_at = v_now
  where group_id = p_group_id
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.mark_group_hike_ready(uuid) from public, anon;
grant execute on function public.mark_group_hike_ready(uuid) to authenticated;

revoke all on function public.unmark_group_hike_ready(uuid) from public, anon;
grant execute on function public.unmark_group_hike_ready(uuid) to authenticated;

revoke all on function public.start_group_hike_prep(uuid, text, text) from public, anon;
grant execute on function public.start_group_hike_prep(uuid, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 4. Update FCM webhook triggers to also dispatch on `status = 'started'`
-- ----------------------------------------------------------------------------
create or replace function public.dispatch_fcm_webhook()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text := coalesce(
    nullif(btrim(current_setting('app.settings.fcm_webhook_url', true)), ''),
    nullif(btrim(current_setting('app.fcm_edge_url', true)), '')
  );
  v_secret text := coalesce(
    nullif(btrim(current_setting('app.settings.fcm_webhook_secret', true)), ''),
    nullif(btrim(current_setting('app.fcm_webhook_secret', true)), '')
  );
begin
  if v_url is null or v_secret is null or to_regnamespace('net') is null then
    return new;
  end if;

  if tg_table_name = 'group_messages' and coalesce(new.is_deleted, false) then
    return new;
  end if;

  if tg_table_name = 'community_messages' and coalesce(new.is_deleted, false) then
    return new;
  end if;

  if tg_table_name = 'friendships' and new.status <> 'pending' then
    return new;
  end if;

  if tg_table_name = 'invitations' and new.status <> 'pending' then
    return new;
  end if;

  if tg_table_name = 'group_hike_prep' then
    if new.status = 'active' then
      if tg_op = 'UPDATE'
         and old.invite_id is not distinct from new.invite_id
         and old.status = 'active' then
        return new;
      end if;
    elsif new.status = 'started' then
      if tg_op <> 'UPDATE' or old.status is not distinct from 'started' then
        return new;
      end if;
    elsif new.status = 'cancelled' then
      if tg_op <> 'UPDATE' or old.status is distinct from 'active' then
        return new;
      end if;
    else
      return new;
    end if;
  end if;

  if tg_table_name = 'sos_events' then
    if new.status <> 'active' then
      return new;
    end if;
    if tg_op = 'UPDATE' and old.status = 'active' then
      return new;
    end if;
  end if;

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', v_secret,
      'x-hiqeo-webhook-secret', v_secret
    ),
    body := jsonb_build_object(
      'type', tg_op,
      'table', tg_table_name,
      'record', row_to_json(new),
      'old_record', case when tg_op = 'UPDATE' then row_to_json(old) else null end
    )
  );
  return new;
exception when others then
  return new;
end;
$$;

create or replace function public.dispatch_group_hike_prep_fcm()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text := coalesce(
    nullif(btrim(current_setting('app.fcm_edge_url', true)), ''),
    nullif(btrim(current_setting('app.settings.fcm_webhook_url', true)), '')
  );
  v_secret text := coalesce(
    nullif(btrim(current_setting('app.fcm_webhook_secret', true)), ''),
    nullif(btrim(current_setting('app.settings.fcm_webhook_secret', true)), '')
  );
begin
  if new.status = 'active' then
    if tg_op = 'UPDATE'
       and old.invite_id is not distinct from new.invite_id
       and old.status = 'active' then
      return new;
    end if;
  elsif new.status = 'started' then
    if tg_op <> 'UPDATE' or old.status is not distinct from 'started' then
      return new;
    end if;
  elsif new.status = 'cancelled' then
    if tg_op <> 'UPDATE' or old.status is distinct from 'active' then
      return new;
    end if;
  else
    return new;
  end if;

  if v_url is null or v_secret is null or to_regnamespace('net') is null then
    return new;
  end if;

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', v_secret,
      'x-hiqeo-webhook-secret', v_secret
    ),
    body := jsonb_build_object(
      'type', tg_op,
      'table', 'group_hike_prep',
      'record', row_to_json(new),
      'old_record', case when tg_op = 'UPDATE' then row_to_json(old) else null end
    )
  );
  return new;
exception when others then
  return new;
end;
$$;

revoke all on function public.dispatch_fcm_webhook() from public, anon;
revoke all on function public.dispatch_group_hike_prep_fcm() from public, anon;
