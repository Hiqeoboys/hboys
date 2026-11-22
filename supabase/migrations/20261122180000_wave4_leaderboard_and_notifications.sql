-- Wave 4: Fix leaderboard_rankings RPC signature/columns (#21) &
-- Dispatch silent push sync when a community message is soft-deleted (#24).

-- ----------------------------------------------------------------------------
-- 1. Partial index & RPC signature alignment for Social Leaderboard (#21)
-- ----------------------------------------------------------------------------
create index if not exists idx_hike_sessions_leaderboard_started_at
  on public.hike_sessions (started_at desc, user_id)
  where activity_type = 'hiking';

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
  total_distance_m double precision
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
        count(
          distinct coalesce(nullif(btrim(hs.mountain_name), ''), hs.id::text)
        )::bigint as mcount,
        coalesce(sum(hs.distance_m), 0)::double precision as dist_m
      from public.hike_sessions hs
      join public.profiles p on p.id = hs.user_id
      where hs.activity_type = 'hiking'
        and hs.started_at >= v_since
        and public.has_full_plus_social(p.id)
      group by p.id, p.username, p.full_name, p.avatar_url
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
      a.dist_m as total_distance_m
    from aggregated a
    order by rank_pos asc
    limit 100;
end;
$fn$;

revoke all on function public.leaderboard_rankings(text, text) from public, anon;
grant execute on function public.leaderboard_rankings(text, text) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. Forward community_messages soft-delete transitions to FCM webhook (#24)
--    while preserving all Wave 2 group_hike_prep `started` auto-start logic.
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

  if tg_table_name = 'community_messages' then
    if tg_op = 'INSERT' then
      if coalesce(new.is_deleted, false) then
        return new;
      end if;
    elsif tg_op = 'UPDATE' then
      if not (
        coalesce(new.is_deleted, false) = true
        and coalesce(old.is_deleted, false) = false
      ) then
        return new;
      end if;
    else
      return new;
    end if;
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

revoke all on function public.dispatch_fcm_webhook() from public, anon;

do $$
begin
  if to_regclass('public.community_messages') is not null then
    drop trigger if exists trg_community_messages_fcm_delete on public.community_messages;
    create trigger trg_community_messages_fcm_delete
      after update of is_deleted on public.community_messages
      for each row
      when (
        coalesce(new.is_deleted, false) = true
        and coalesce(old.is_deleted, false) = false
      )
      execute function public.dispatch_fcm_webhook();
  end if;
end;
$$;
