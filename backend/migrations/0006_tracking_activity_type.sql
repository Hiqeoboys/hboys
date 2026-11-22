-- ============================================================================
-- Migration 0006: Tracking Activity Type (Hiking vs Jogging) & Route Polyline
-- ============================================================================
-- 1. Tambah 1 kolom `activity_type` ('hiking' | 'jogging') pada `hike_sessions`
--    (tidak perlu tabel terpisah) + `route_polyline_b64` (~3-8 KB gzip+base64).
-- 2. Pisahkan sesi `jogging` dari hitungan gunung yang didaki di profil publik
--    dan dari papan peringkat (Leaderboard) pendakian.
-- ============================================================================

alter table hike_sessions
  add column if not exists activity_type text not null default 'hiking'
    check (activity_type in ('hiking', 'jogging')),
  add column if not exists route_polyline_b64 text;

create index if not exists idx_hike_sessions_user_activity_started
  on hike_sessions (user_id, activity_type, started_at desc);

-- Profil publik user lain: sesi jogging tidak ikut menambah hitungan gunung didaki.
create or replace function user_public_profile(p_user_id uuid)
returns table (
  user_id uuid,
  username text,
  full_name text,
  avatar_url text,
  has_plus_badge boolean,
  mountains_climbed integer,
  total_distance_m double precision,
  total_moving_seconds bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  return query
    select
      p.id as user_id,
      p.username::text as username,
      coalesce(nullif(btrim(p.full_name), ''), p.username::text) as full_name,
      p.avatar_url,
      has_full_plus_social(p.id) as has_plus_badge,
      coalesce(
        count(distinct coalesce(nullif(btrim(hs.mountain_name), ''), hs.id))
          filter (where hs.id is not null and hs.activity_type = 'hiking'),
        0
      )::integer as mountains_climbed,
      coalesce(sum(hs.distance_m) filter (where hs.activity_type = 'hiking'), 0)::double precision as total_distance_m,
      coalesce(sum(hs.moving_seconds) filter (where hs.activity_type = 'hiking'), 0)::bigint as total_moving_seconds
    from profiles p
    left join hike_sessions hs on hs.user_id = p.id
    where p.id = p_user_id
    group by p.id, p.username, p.full_name, p.avatar_url;
end;
$$;

-- Leaderboard pendakian: hanya menghitung sesi `activity_type = 'hiking'`.
create or replace function leaderboard_rankings(
  p_metric text, -- 'mountains' | 'distance'
  p_period text  -- 'monthly' | 'yearly'
)
returns table (
  rank_no integer,
  user_id uuid,
  display_name text,
  avatar_url text,
  score_value bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_since timestamptz;
begin
  if p_period = 'yearly' then
    v_since := date_trunc('year', now());
  else
    v_since := date_trunc('month', now());
  end if;

  return query
    with eligible as (
      select
        p.id as uid,
        coalesce(nullif(btrim(p.full_name), ''), p.username::text) as dname,
        p.avatar_url as aurl,
        case
          when p_metric = 'distance' then coalesce(round(sum(hs.distance_m))::bigint, 0)
          else coalesce(count(distinct coalesce(nullif(btrim(hs.mountain_name), ''), hs.id))::bigint, 0)
        end as score
      from profiles p
      join hike_sessions hs
        on hs.user_id = p.id
       and hs.activity_type = 'hiking'
       and hs.started_at >= v_since
      where has_full_plus_social(p.id)
      group by p.id, p.full_name, p.username, p.avatar_url
      having (
        case
          when p_metric = 'distance' then coalesce(sum(hs.distance_m), 0) > 0
          else count(hs.id) > 0
        end
      )
    )
    select
      row_number() over (order by e.score desc, e.dname asc)::integer as rank_no,
      e.uid as user_id,
      e.dname as display_name,
      e.aurl as avatar_url,
      e.score as score_value
    from eligible e
    order by rank_no asc
    limit 50;
end;
$$;

revoke all on function user_public_profile(uuid) from public;
revoke all on function leaderboard_rankings(text, text) from public;
grant execute on function user_public_profile(uuid) to authenticated;
grant execute on function leaderboard_rankings(text, text) to authenticated;
