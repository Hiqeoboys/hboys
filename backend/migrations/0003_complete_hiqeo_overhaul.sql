-- ============================================================================
-- Migration 0003: Pembaruan Menyeluruh Hiqeo
-- Mencakup:
-- 1. Fix hapus grup permanen (RLS DELETE + RPC delete_group & leave_group)
-- 2. Fix auto key re-registration & group key distribution
-- 3. Fitur Sosial: Komunitas (online-only, media WebP/video <=60s), Pertemanan,
--    Profil Publik User Lain, dan Leaderboard (khusus Plus Mahasiswa & Tahunan)
-- 4. Sinkronisasi Riwayat Pendakian (hike_sessions + reached_summit)
-- 5. Sistem Moderasi Laporan Developer (moderation_reports + webhook trigger)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. PROFIL & PLAN HELPER (Hiqeo Plus Mahasiswa & Tahunan)
-- ---------------------------------------------------------------------------
alter table profiles
  add column if not exists full_name text,
  add column if not exists avatar_url text,
  add column if not exists is_plus boolean not null default false,
  add column if not exists plus_plan_id text,
  add column if not exists plus_expires_at timestamptz;

-- Hanya paket Mahasiswa ('student_annual'), Tahunan ('annual'), atau 'lifetime'
-- yang mendapatkan akses penuh sosial (buat/kirim komunitas, tambah teman,
-- peringkat leaderboard, badge Hiqeo Plus di profil publik).
create or replace function has_full_plus_social(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from profiles p
    where p.id = p_uid
      and p.is_plus = true
      and p.plus_plan_id in ('student_annual', 'annual', 'lifetime', 'founding')
      and (p.plus_expires_at is null or p.plus_expires_at > now())
  );
$$;

-- ---------------------------------------------------------------------------
-- 2. FIX HAPUS GRUP PERMANEN & KELUAR GRUP (RLS DELETE + SECURITY DEFINER RPC)
-- ---------------------------------------------------------------------------
drop policy if exists groups_owner_delete on groups;
create policy groups_owner_delete on groups
  for delete using (owner_id = auth.uid());

drop policy if exists members_owner_or_self_delete on group_members;
create policy members_owner_or_self_delete on group_members
  for delete using (
    user_id = auth.uid()
    or exists (
      select 1 from groups g where g.id = group_members.group_id and g.owner_id = auth.uid()
    )
  );

create or replace function delete_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select g.owner_id into v_owner
  from groups g
  where g.id = p_group_id
  for update;

  if not found then
    return; -- Idempoten: grup sudah terhapus
  end if;

  if v_owner <> v_uid then
    raise exception 'OWNER_REQUIRED';
  end if;

  -- Bersihkan tabel terkait bila ada sebelum menghapus baris groups
  if to_regclass('public.group_messages') is not null then
    execute 'delete from public.group_messages where group_id = $1' using p_group_id;
  end if;
  if to_regclass('public.member_locations') is not null then
    execute 'delete from public.member_locations where group_id = $1' using p_group_id;
  end if;

  delete from group_key_blobs where group_id = p_group_id;
  delete from invitations where group_id = p_group_id;
  delete from group_members where group_id = p_group_id;
  delete from groups where id = p_group_id;
end;
$$;

create or replace function leave_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select g.owner_id into v_owner
  from groups g
  where g.id = p_group_id
  for update;

  if not found then
    return;
  end if;

  if v_owner = v_uid then
    -- Pemilik yang keluar menghapus grup bila sendiri, atau menolak bila masih ada anggota.
    if (select count(*) from group_members where group_id = p_group_id) <= 1 then
      perform delete_group(p_group_id);
      return;
    end if;
    raise exception 'OWNER_IMMUTABLE';
  end if;

  delete from group_members where group_id = p_group_id and user_id = v_uid;
  delete from group_key_blobs where group_id = p_group_id and user_id = v_uid;

  update groups set key_version = key_version + 1 where id = p_group_id;
end;
$$;

-- Izinkan pemilik atau anggota memperbarui kunci publik perangkat secara silent
-- tanpa memblokir sinkronisasi grup.
create or replace function sync_device_public_key(p_public_key text)
returns table (id uuid, username text, public_key text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_existing profiles%rowtype;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if p_public_key is null
     or length(p_public_key) <> 44
     or p_public_key !~ '^[A-Za-z0-9+/]{43}=$'
     or length(decode(p_public_key, 'base64')) <> 32 then
    raise exception 'PUBLIC_KEY_INVALID';
  end if;

  select * into v_existing from profiles p where p.id = v_uid;
  if not found then
    raise exception 'PROFILE_REQUIRED';
  end if;

  if v_existing.public_key <> p_public_key then
    update profiles p set public_key = p_public_key where p.id = v_uid;
    delete from group_key_blobs b where b.user_id = v_uid;
  end if;

  return query
    select p.id, p.username::text, p.public_key
    from profiles p
    where p.id = v_uid;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. FITUR KOMUNITAS (ONLINE-ONLY)
-- ---------------------------------------------------------------------------
create table if not exists communities (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(btrim(name)) between 1 and 80),
  description text,
  avatar_url  text,
  owner_id    uuid not null references profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists community_members (
  community_id uuid not null references communities (id) on delete cascade,
  user_id      uuid not null references profiles (id) on delete cascade,
  role         text not null default 'member' check (role in ('owner', 'member')),
  joined_at    timestamptz not null default now(),
  primary key (community_id, user_id)
);

create table if not exists community_messages (
  id              uuid primary key default gen_random_uuid(),
  community_id    uuid not null references communities (id) on delete cascade,
  sender_id       uuid not null references profiles (id) on delete cascade,
  sender_name     text not null,
  sender_avatar   text,
  message_type    text not null default 'text' check (message_type in ('text', 'image', 'video')),
  content         text,
  media_url       text,
  media_mime      text,
  media_duration_sec integer check (media_duration_sec is null or media_duration_sec between 1 and 60),
  created_at      timestamptz not null default now()
);

create index if not exists idx_community_messages_comm_time
  on community_messages (community_id, created_at asc);

alter table communities        enable row level security;
alter table community_members  enable row level security;
alter table community_messages enable row level security;

-- Semua user terautentikasi bisa melihat daftar komunitas dan bergabung
drop policy if exists communities_read_all on communities;
create policy communities_read_all on communities
  for select using (auth.uid() is not null);

-- Hanya Hiqeo Plus Mahasiswa & Tahunan yang boleh membuat komunitas
drop policy if exists communities_insert_plus on communities;
create policy communities_insert_plus on communities
  for insert with check (owner_id = auth.uid() and has_full_plus_social(auth.uid()));

drop policy if exists communities_update_owner on communities;
create policy communities_update_owner on communities
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());

drop policy if exists communities_delete_owner on communities;
create policy communities_delete_owner on communities
  for delete using (owner_id = auth.uid());

drop policy if exists community_members_read on community_members;
create policy community_members_read on community_members
  for select using (auth.uid() is not null);

drop policy if exists community_members_join on community_members;
create policy community_members_join on community_members
  for insert with check (user_id = auth.uid());

drop policy if exists community_members_leave on community_members;
create policy community_members_leave on community_members
  for delete using (
    user_id = auth.uid()
    or exists (
      select 1 from communities c where c.id = community_members.community_id and c.owner_id = auth.uid()
    )
  );

-- Membaca pesan komunitas terbuka untuk anggota (Free, Tiket 1x Naik, Mahasiswa, Tahunan)
drop policy if exists community_messages_read on community_messages;
create policy community_messages_read on community_messages
  for select using (
    exists (
      select 1 from community_members cm
      where cm.community_id = community_messages.community_id and cm.user_id = auth.uid()
    )
  );

-- Mengirim pesan komunitas HANYA untuk anggota Hiqeo Plus Mahasiswa & Tahunan
drop policy if exists community_messages_insert_plus on community_messages;
create policy community_messages_insert_plus on community_messages
  for insert with check (
    sender_id = auth.uid()
    and has_full_plus_social(auth.uid())
    and exists (
      select 1 from community_members cm
      where cm.community_id = community_messages.community_id and cm.user_id = auth.uid()
    )
  );

create or replace function delete_community(p_community_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  select owner_id into v_owner from communities where id = p_community_id for update;
  if not found then return; end if;
  if v_owner <> v_uid then
    raise exception 'OWNER_REQUIRED';
  end if;
  delete from community_messages where community_id = p_community_id;
  delete from community_members where community_id = p_community_id;
  delete from communities where id = p_community_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. PERTEMANAN (FRIENDSHIPS) & PROFIL PUBLIK USER LAIN
-- ---------------------------------------------------------------------------
create table if not exists friendships (
  id           uuid primary key default gen_random_uuid(),
  requester_id uuid not null references profiles (id) on delete cascade,
  addressee_id uuid not null references profiles (id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending', 'accepted', 'rejected')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint friendships_no_self check (requester_id <> addressee_id)
);

create unique index if not exists idx_friendships_pair
  on friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));

alter table friendships enable row level security;

drop policy if exists friendships_party_read on friendships;
create policy friendships_party_read on friendships
  for select using (requester_id = auth.uid() or addressee_id = auth.uid());

-- Hanya Hiqeo Plus Mahasiswa & Tahunan yang bisa mengirim permintaan berteman
drop policy if exists friendships_insert_plus on friendships;
create policy friendships_insert_plus on friendships
  for insert with check (
    requester_id = auth.uid()
    and has_full_plus_social(auth.uid())
  );

drop policy if exists friendships_party_update on friendships;
create policy friendships_party_update on friendships
  for update using (requester_id = auth.uid() or addressee_id = auth.uid());

drop policy if exists friendships_party_delete on friendships;
create policy friendships_party_delete on friendships
  for delete using (requester_id = auth.uid() or addressee_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 5. RIWAYAT PENDAKIAN & LEADERBOARD (HANYA PLUS MAHASISWA & TAHUNAN)
-- ---------------------------------------------------------------------------
create table if not exists hike_sessions (
  id               text primary key,
  user_id          uuid not null references profiles (id) on delete cascade,
  mountain_name    text,
  trail_name       text,
  distance_m       double precision not null default 0 check (distance_m >= 0),
  moving_seconds   integer not null default 0 check (moving_seconds >= 0),
  elevation_gain_m double precision not null default 0 check (elevation_gain_m >= 0),
  elevation_loss_m double precision not null default 0 check (elevation_loss_m >= 0),
  reached_summit   boolean not null default false,
  started_at       timestamptz not null,
  ended_at         timestamptz not null,
  created_at       timestamptz not null default now()
);

create index if not exists idx_hike_sessions_user_started
  on hike_sessions (user_id, started_at desc);

alter table hike_sessions enable row level security;

drop policy if exists hike_sessions_owner_all on hike_sessions;
create policy hike_sessions_owner_all on hike_sessions
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Profil publik user lain (dipakai dari Daftar Teman -> Halaman Profil User Lain)
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
      coalesce(count(distinct coalesce(nullif(btrim(hs.mountain_name), ''), hs.id)) filter (where hs.id is not null), 0)::integer as mountains_climbed,
      coalesce(sum(hs.distance_m), 0)::double precision as total_distance_m,
      coalesce(sum(hs.moving_seconds), 0)::bigint as total_moving_seconds
    from profiles p
    left join hike_sessions hs on hs.user_id = p.id
    where p.id = p_user_id
    group by p.id, p.username, p.full_name, p.avatar_url;
end;
$$;

-- Leaderboard: HANYA akun Hiqeo Plus Mahasiswa & Tahunan yang masuk peringkat.
-- Semua akun (termasuk Free & Tiket 1x Naik) dapat memanggil fungsi ini untuk melihat papan.
-- Tidak mengembalikan nama/label paket agar UI tidak menampilkan label paket.
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
      join hike_sessions hs on hs.user_id = p.id and hs.started_at >= v_since
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

-- ---------------------------------------------------------------------------
-- 6. SISTEM MODERASI LAPORAN DEVELOPER (`moderation_reports`)
-- ---------------------------------------------------------------------------
create table if not exists moderation_reports (
  id              uuid primary key default gen_random_uuid(),
  report_type     text not null check (report_type in ('community_message', 'community', 'user_account')),
  target_id       text not null,
  reporter_id     uuid not null references profiles (id) on delete cascade,
  reason          text not null check (char_length(btrim(reason)) between 1 and 500),
  content_snippet text,
  metadata        jsonb not null default '{}'::jsonb,
  status          text not null default 'open' check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  created_at      timestamptz not null default now()
);

create index if not exists idx_moderation_reports_status_created
  on moderation_reports (status, created_at desc);

alter table moderation_reports enable row level security;

drop policy if exists moderation_reports_insert_own on moderation_reports;
create policy moderation_reports_insert_own on moderation_reports
  for insert with check (reporter_id = auth.uid());

drop policy if exists moderation_reports_read_own on moderation_reports;
create policy moderation_reports_read_own on moderation_reports
  for select using (reporter_id = auth.uid());

-- Setup Database Webhook via pg_net ke Supabase Edge Function `notify-moderation-report`
-- (Aktifkan ekstensi pg_net di Dashboard Supabase dan isi app.settings.moderation_webhook_url
-- atau buat Database Webhook di Dashboard Supabase: Table = moderation_reports, Event = INSERT,
-- Target = Edge Function `notify-moderation-report`).
create or replace function notify_developer_on_moderation_report()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text := current_setting('app.settings.moderation_webhook_url', true);
  v_secret text := current_setting('app.settings.moderation_webhook_secret', true);
begin
  if v_url is not null and length(v_url) > 0 and to_regnamespace('net') is not null then
    perform net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-hiqeo-webhook-secret', coalesce(v_secret, '')
      ),
      body := jsonb_build_object(
        'type', 'INSERT',
        'table', 'moderation_reports',
        'record', row_to_json(new)
      )
    );
  end if;
  return new;
exception when others then
  -- Jangan gagalkan penyimpanan laporan jika webhook jaringan sedang lambat
  return new;
end;
$$;

drop trigger if exists trg_moderation_reports_notify on moderation_reports;
create trigger trg_moderation_reports_notify
  after insert on moderation_reports
  for each row execute function notify_developer_on_moderation_report();

-- ---------------------------------------------------------------------------
-- 7. STORAGE BUCKET KOMUNITAS & REALTIME PUBLICATION
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('community-media', 'community-media', true)
on conflict (id) do nothing;

-- Grant eksekusi fungsi baru ke pengguna terautentikasi
revoke all on function has_full_plus_social(uuid) from public;
revoke all on function delete_group(uuid) from public;
revoke all on function leave_group(uuid) from public;
revoke all on function sync_device_public_key(text) from public;
revoke all on function delete_community(uuid) from public;
revoke all on function user_public_profile(uuid) from public;
revoke all on function leaderboard_rankings(text, text) from public;

grant execute on function has_full_plus_social(uuid) to authenticated;
grant execute on function delete_group(uuid) to authenticated;
grant execute on function leave_group(uuid) to authenticated;
grant execute on function sync_device_public_key(text) to authenticated;
grant execute on function delete_community(uuid) to authenticated;
grant execute on function user_public_profile(uuid) to authenticated;
grant execute on function leaderboard_rankings(text, text) to authenticated;
