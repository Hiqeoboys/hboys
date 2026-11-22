-- ============================================================================
-- Migration 0016: Wave C — 3-Mode SOS (`solo_hike` | `group_hike` | `nearby`),
--                 5 km Nearby Geospatial Recipient Lookup, & `sos_nearby` Type
-- ============================================================================

alter table if exists public.sos_events
  add column if not exists sos_mode text not null default 'group_hike',
  add column if not exists area_label text,
  add column if not exists local_time_hhmm text;

do $$
declare
  v_con record;
begin
  if to_regclass('public.sos_events') is not null then
    for v_con in
      select conname
      from pg_constraint
      where conrelid = 'public.sos_events'::regclass
        and contype = 'c'
        and pg_get_constraintdef(oid) ilike '%sos_mode%'
    loop
      execute format(
        'alter table public.sos_events drop constraint if exists %I',
        v_con.conname
      );
    end loop;

    alter table public.sos_events
      add constraint sos_events_mode_check
      check (sos_mode in ('solo_hike', 'group_hike', 'nearby'));

    create index if not exists idx_sos_events_active_mode
      on public.sos_events (sos_mode, received_at desc)
      where status = 'active';
  end if;
end;
$$;

create table if not exists public.user_device_locations (
  user_id    uuid primary key references public.profiles (id) on delete cascade,
  lat        double precision not null check (lat between -90 and 90),
  lon        double precision not null check (lon between -180 and 180),
  accuracy_m integer,
  updated_at timestamptz not null default now()
);

create index if not exists idx_user_device_locations_updated_lat_lon
  on public.user_device_locations (updated_at desc, lat, lon);

alter table public.user_device_locations enable row level security;

revoke all on table public.user_device_locations from public, anon;
grant select, insert, update on table public.user_device_locations to authenticated;

drop policy if exists user_device_locations_self_select on public.user_device_locations;
create policy user_device_locations_self_select
  on public.user_device_locations
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists user_device_locations_self_insert on public.user_device_locations;
create policy user_device_locations_self_insert
  on public.user_device_locations
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists user_device_locations_self_update on public.user_device_locations;
create policy user_device_locations_self_update
  on public.user_device_locations
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create or replace function public.upsert_my_device_location(
  p_lat double precision,
  p_lon double precision,
  p_accuracy_m integer default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  if p_lat is null or p_lon is null
     or p_lat < -90 or p_lat > 90
     or p_lon < -180 or p_lon > 180 then
    raise exception 'INVALID_COORDS' using errcode = '22023';
  end if;

  insert into public.user_device_locations (
    user_id, lat, lon, accuracy_m, updated_at
  ) values (
    v_uid, p_lat, p_lon, p_accuracy_m, now()
  )
  on conflict (user_id) do update set
    lat = excluded.lat,
    lon = excluded.lon,
    accuracy_m = coalesce(excluded.accuracy_m, public.user_device_locations.accuracy_m),
    updated_at = now();
end;
$fn$;

revoke all on function public.upsert_my_device_location(double precision, double precision, integer) from public, anon;
grant execute on function public.upsert_my_device_location(double precision, double precision, integer) to authenticated;

create or replace function public.find_nearby_sos_recipients(
  p_author_id uuid,
  p_lat double precision,
  p_lon double precision,
  p_radius_m double precision default 5000,
  p_max_age_hours integer default 24
)
returns table (
  user_id uuid,
  distance_m double precision
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_radius double precision := greatest(100.0, least(coalesce(p_radius_m, 5000.0), 50000.0));
  v_dlat double precision := v_radius / 111000.0;
  v_dlon double precision := v_radius / (111000.0 * greatest(cos(radians(p_lat)), 0.01));
  v_cutoff timestamptz := now() - make_interval(hours => greatest(1, coalesce(p_max_age_hours, 24)));
begin
  if p_lat is null or p_lon is null
     or p_lat < -90 or p_lat > 90
     or p_lon < -180 or p_lon > 180 then
    return;
  end if;

  return query
    with candidates as (
      select
        udl.user_id as uid,
        (
          6371000.0 * 2.0 * asin(
            least(
              1.0,
              sqrt(
                power(sin(radians((udl.lat - p_lat) / 2.0)), 2) +
                cos(radians(p_lat)) * cos(radians(udl.lat)) *
                power(sin(radians((udl.lon - p_lon) / 2.0)), 2)
              )
            )
          )
        ) as dist_m
      from public.user_device_locations udl
      where udl.updated_at >= v_cutoff
        and udl.lat between (p_lat - v_dlat) and (p_lat + v_dlat)
        and udl.lon between (p_lon - v_dlon) and (p_lon + v_dlon)
        and (p_author_id is null or udl.user_id <> p_author_id)
    )
    select c.uid as user_id, c.dist_m as distance_m
    from candidates c
    where c.dist_m <= v_radius
    order by c.dist_m asc
    limit 200;
end;
$fn$;

revoke all on function public.find_nearby_sos_recipients(uuid, double precision, double precision, double precision, integer) from public, anon, authenticated;
grant execute on function public.find_nearby_sos_recipients(uuid, double precision, double precision, double precision, integer) to service_role;

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
          'sos',
          'sos_nearby'
        )
      );
  end if;
end;
$$;

do $$
begin
  if to_regclass('public.sos_events') is not null
     and to_regprocedure('public.dispatch_fcm_webhook()') is not null then
    drop trigger if exists trg_sos_events_fcm on public.sos_events;
    create trigger trg_sos_events_fcm
      after insert or update on public.sos_events
      for each row
      execute function public.dispatch_fcm_webhook();
  end if;
end;
$$;
