-- ============================================================================
-- Migrasi 004: RLS Keanggotaan Grup, Realtime (group_members, invitations,
--              group_key_blobs), RPC Detail Anggota, & Deduplikasi Chat
-- Proyek: Hiqeo (Supabase Postgres + Realtime)
--
-- AMAN DIJALANKAN ULANG (idempoten). Jalankan di Supabase SQL Editor setelah
-- migrasi 001–003.
-- ============================================================================

-- 1. Pastikan fungsi helper `public.is_group_member(gid uuid)` tersedia
--    sebagai SECURITY DEFINER agar evaluasi RLS pada `group_members` tidak
--    menyebabkan rekursi tak terbatas.
create or replace function public.is_group_member(gid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1
      from public.group_members gm
     where gm.group_id = gid
       and gm.user_id = auth.uid()
  );
$$;

revoke all on function public.is_group_member(uuid) from public;
grant execute on function public.is_group_member(uuid) to authenticated;

-- 2. Audit & perbaiki kebijakan RLS SELECT pada `public.group_members`
--    Semua anggota dalam grup yang sama WAJIB dapat membaca seluruh baris
--    keanggotaan pada grup tersebut (bukan hanya `user_id = auth.uid()`),
--    agar jumlah anggota akurat & Supabase Realtime bekerja untuk semua anggota.
alter table public.group_members enable row level security;

drop policy if exists group_members_self_read on public.group_members;
drop policy if exists group_members_select_own on public.group_members;
drop policy if exists "Users can view their own group memberships" on public.group_members;
drop policy if exists members_group_read on public.group_members;

create policy members_group_read
  on public.group_members
  for select
  to authenticated
  using (public.is_group_member(group_id));

-- Pastikan RLS SELECT pada `public.invitations` mengizinkan pengundang dan
-- penerima membaca undangan terkait (dibutuhkan untuk Realtime undangan masuk).
alter table public.invitations enable row level security;

drop policy if exists invitations_party_read on public.invitations;
create policy invitations_party_read
  on public.invitations
  for select
  to authenticated
  using (inviter_id = auth.uid() or invitee_id = auth.uid());

-- Pastikan RLS SELECT pada `public.group_key_blobs` mengizinkan anggota
-- menerima notifikasi Realtime saat pemilik menerbitkan kunci grup untuknya.
alter table public.group_key_blobs enable row level security;

drop policy if exists keyblobs_self_read on public.group_key_blobs;
create policy keyblobs_self_read
  on public.group_key_blobs
  for select
  to authenticated
  using (user_id = auth.uid());

-- 3. RPC `public.group_members_detail(p_group_id uuid)` untuk fitur "Info anggota"
--    Mengembalikan profil lengkap anggota (nama, @username, avatar_url, peran,
--    kunci publik, waktu bergabung) hanya bila pemanggil adalah anggota grup.
create or replace function public.group_members_detail(p_group_id uuid)
returns table (
  user_id uuid,
  username text,
  full_name text,
  avatar_url text,
  role text,
  public_key text,
  joined_at timestamptz
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
      m.joined_at
    from public.group_members m
    join public.profiles p on p.id = m.user_id
    where m.group_id = p_group_id
    order by
      case when m.role = 'owner' then 0 else 1 end asc,
      m.joined_at asc;
end;
$$;

revoke all on function public.group_members_detail(uuid) from public;
grant execute on function public.group_members_detail(uuid) to authenticated;

-- 4. Guard idempotensi `group_messages`: pertahankan `id` dan `created_at`
--    lama saat upsert ulang dengan `(group_id, client_id)` yang sama, sehingga
--    klien bisa mengirim `id = client_msg_id` secara aman tanpa bentrok.
create or replace function public.guard_group_messages_e2ee_upsert()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.id := old.id;
  new.created_at := old.created_at;
  new.voice_path := coalesce(nullif(btrim(new.voice_path), ''), old.voice_path);
  return new;
end;
$$;

drop trigger if exists trg_group_messages_e2ee_upsert on public.group_messages;
create trigger trg_group_messages_e2ee_upsert
  before update on public.group_messages
  for each row
  execute function public.guard_group_messages_e2ee_upsert();

-- 5. Aktifkan REPLICA IDENTITY FULL & daftarkan tabel ke publikasi Supabase Realtime
--    agar perubahan jumlah anggota, undangan masuk, dan distribusi kunci grup
--    diterima perangkat secara realtime.
alter table public.group_members   replica identity full;
alter table public.invitations     replica identity full;
alter table public.group_key_blobs replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'group_members'
    ) then
      alter publication supabase_realtime add table public.group_members;
    end if;

    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'invitations'
    ) then
      alter publication supabase_realtime add table public.invitations;
    end if;

    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'group_key_blobs'
    ) then
      alter publication supabase_realtime add table public.group_key_blobs;
    end if;
  end if;
end;
$$;
