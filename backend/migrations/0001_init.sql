-- Skema awal (contoh untuk PostgreSQL/Supabase). Sesuaikan jika memakai Firebase.
-- Prinsip: server TIDAK menyimpan kunci grup dalam bentuk terbuka dan tidak membaca isi pesan.
-- Status: DRAFT, belum dijalankan. Uji di lingkungan staging dan tinjau kebijakan akses.

create extension if not exists citext;
create extension if not exists pgcrypto;

-- Profil publik pengguna. Username unik dan dicari dengan kecocokan PERSIS.
create table profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  username    citext not null unique check (username ~ '^[a-z0-9_.]{3,20}$'),
  public_key  text   not null,            -- kunci publik perangkat (base64)
  created_at  timestamptz not null default now()
);

create table groups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 60),
  owner_id    uuid not null references profiles (id),
  mountain    text,
  key_version integer not null default 1,
  created_at  timestamptz not null default now()
);

create table group_members (
  group_id  uuid not null references groups (id) on delete cascade,
  user_id   uuid not null references profiles (id) on delete cascade,
  role      text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create type invitation_status as enum ('pending', 'accepted', 'rejected', 'expired', 'cancelled');

create table invitations (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references groups (id) on delete cascade,
  inviter_id  uuid not null references profiles (id) on delete cascade,
  invitee_id  uuid not null references profiles (id) on delete cascade,
  status      invitation_status not null default 'pending',
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default (now() + interval '7 days'),
  responded_at timestamptz,
  -- satu undangan pending per (grup, orang)
  constraint no_self_invite check (inviter_id <> invitee_id)
);
create unique index one_pending_invite on invitations (group_id, invitee_id) where status = 'pending';

-- Kunci grup terenkripsi untuk tiap anggota (server hanya menyimpan blob).
create table group_key_blobs (
  group_id    uuid not null references groups (id) on delete cascade,
  user_id     uuid not null references profiles (id) on delete cascade,
  key_version integer not null,
  wrapped_key text not null,              -- dienkripsi dengan kunci publik anggota
  created_at  timestamptz not null default now(),
  primary key (group_id, user_id, key_version)
);

create table emergency_contacts (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references profiles (id) on delete cascade,
  name            text not null,
  phone_e164      text not null check (phone_e164 ~ '^\+[0-9]{8,15}$'),
  channel         text not null default 'sms' check (channel in ('sms', 'whatsapp')),
  consent_status  text not null default 'pending' check (consent_status in ('pending', 'granted', 'revoked')),
  consent_at      timestamptz,
  created_at      timestamptz not null default now()
);

-- SOS: idempoten lewat id yang dibuat di perangkat (dikirim ulang berkali-kali).
create table sos_events (
  id           uuid primary key,          -- dibuat di perangkat
  author_id    uuid not null references profiles (id),
  group_id     uuid references groups (id),
  category     smallint not null,
  lat          double precision not null check (lat between -90 and 90),
  lon          double precision not null check (lon between -180 and 180),
  accuracy_m   integer,
  battery_pct  smallint check (battery_pct between 0 and 100),
  created_at   timestamptz not null,      -- waktu di perangkat (UTC)
  received_at  timestamptz not null default now(),
  signature    text,                      -- tanda tangan perangkat (base64)
  status       text not null default 'active' check (status in ('active', 'cancelled', 'resolved')),
  cancelled_at timestamptz
);
create index sos_active on sos_events (status, received_at desc);

create table sos_dispatch_log (
  id          bigserial primary key,
  sos_id      uuid not null references sos_events (id) on delete cascade,
  target_kind text not null check (target_kind in ('emergency_contact', 'group_member')),
  target_ref  uuid not null,
  channel     text not null,
  status      text not null check (status in ('queued', 'sent', 'delivered', 'failed')),
  attempted_at timestamptz not null default now(),
  detail      text
);

create table last_known_locations (
  user_id     uuid primary key references profiles (id) on delete cascade,
  lat         double precision not null,
  lon         double precision not null,
  accuracy_m  integer,
  battery_pct smallint,
  recorded_at timestamptz not null,       -- waktu di perangkat
  received_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Keamanan baris (RLS). Contoh Supabase; tinjau SETIAP kebijakan sebelum produksi.
-- ---------------------------------------------------------------------------
alter table profiles             enable row level security;
alter table groups               enable row level security;
alter table group_members        enable row level security;
alter table invitations          enable row level security;
alter table group_key_blobs      enable row level security;
alter table emergency_contacts   enable row level security;
alter table sos_events           enable row level security;
alter table sos_dispatch_log     enable row level security;
alter table last_known_locations enable row level security;

create or replace function is_group_member(gid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from group_members where group_id = gid and user_id = auth.uid());
$$;

-- Profil: baca diri sendiri. Pencarian username lain dilakukan lewat fungsi server
-- (invite_user) yang mensyaratkan kecocokan persis, bukan lewat SELECT bebas.
create policy profiles_self_read on profiles for select using (id = auth.uid());
create policy profiles_self_write on profiles for update using (id = auth.uid());

create policy groups_member_read on groups for select using (is_group_member(id));
create policy members_group_read on group_members for select using (is_group_member(group_id));

create policy invitations_party_read on invitations for select
  using (inviter_id = auth.uid() or invitee_id = auth.uid());
-- Perubahan status undangan HANYA lewat fungsi server (respond_invitation).

create policy keyblobs_self_read on group_key_blobs for select using (user_id = auth.uid());

create policy contacts_owner_all on emergency_contacts for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy sos_author_or_group_read on sos_events for select
  using (author_id = auth.uid() or (group_id is not null and is_group_member(group_id)));
-- Penulisan SOS lewat fungsi ingest_sos (validasi tanda tangan + deduplikasi).

create policy last_known_group_read on last_known_locations for select
  using (user_id = auth.uid() or exists (
    select 1 from group_members me
    join group_members other on other.group_id = me.group_id
    where me.user_id = auth.uid() and other.user_id = last_known_locations.user_id
  ));
