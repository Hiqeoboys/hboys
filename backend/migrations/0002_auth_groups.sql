-- Autentikasi profil, direktori kunci, undangan, dan kunci grup.
-- Status: DRAFT, BELUM DIJALANKAN. Tidak ada PostgreSQL/Supabase di mesin ini.
-- Wajib diuji di staging sebelum dipakai; lihat docs/security_review.md.
--
-- Semua penulisan profil, grup, anggota, undangan, dan blob kunci dilakukan
-- lewat fungsi security definer di bawah. Klien tidak diberi policy INSERT/
-- UPDATE/DELETE langsung. Setiap fungsi memeriksa auth.uid() sendiri.

-- ---------------------------------------------------------------------------
-- Kunci publik perangkat tidak boleh berubah tanpa menghapus blob kunci grup
-- lama milik pengguna. Profil hanya boleh diubah lewat register_profile.
-- ---------------------------------------------------------------------------
drop policy if exists profiles_self_write on profiles;

-- ---------------------------------------------------------------------------
-- Profil dan direktori kunci
-- ---------------------------------------------------------------------------
create or replace function register_profile(
  p_username text,
  p_public_key text
)
returns table (id uuid, username text, public_key text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_username citext;
  v_existing profiles%rowtype;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  v_username := lower(btrim(coalesce(p_username, '')))::citext;
  if v_username !~ '^[a-z0-9_.]{3,20}$' then
    raise exception 'USERNAME_INVALID';
  end if;

  -- X25519 public key: 32 byte, base64 standar 44 karakter.
  if p_public_key is null
     or length(p_public_key) <> 44
     or p_public_key !~ '^[A-Za-z0-9+/]{43}=$'
     or length(decode(p_public_key, 'base64')) <> 32 then
    raise exception 'PUBLIC_KEY_INVALID';
  end if;

  select * into v_existing from profiles p where p.id = v_uid;

  if found then
    if v_existing.username <> v_username then
      raise exception 'USERNAME_IMMUTABLE';
    end if;
    if v_existing.public_key <> p_public_key then
      update profiles p set public_key = p_public_key where p.id = v_uid;
      -- Perangkat baru tidak bisa membuka kunci lama. Hapus blob lama agar
      -- anggota melihat status "menunggu pemilik" alih-alih gagal dekripsi.
      delete from group_key_blobs b where b.user_id = v_uid;
      -- Bila pengguna pemilik grup, versi dinaikkan agar pemilik membuat kunci
      -- baru untuk versi baru, bukan diam-diam menimpa kunci versi yang sama.
      update groups g
      set key_version = g.key_version + 1
      where g.owner_id = v_uid;
    end if;
  else
    insert into profiles (id, username, public_key)
    values (v_uid, v_username, p_public_key);
  end if;

  return query
    select p.id, p.username::text, p.public_key
    from profiles p
    where p.id = v_uid;
exception
  when unique_violation then
    raise exception 'USERNAME_TAKEN';
end;
$$;

create or replace function lookup_user(p_username text)
returns table (id uuid, username text, public_key text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_username citext;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if not exists (select 1 from profiles p where p.id = v_uid) then
    raise exception 'PROFILE_REQUIRED';
  end if;

  v_username := lower(btrim(coalesce(p_username, '')))::citext;
  if v_username !~ '^[a-z0-9_.]{3,20}$' then
    return;
  end if;

  return query
    select p.id, p.username::text, p.public_key
    from profiles p
    where p.username = v_username;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grup dan anggota
-- ---------------------------------------------------------------------------
create or replace function create_group(
  p_name text,
  p_mountain text default null
)
returns table (
  id uuid,
  name text,
  owner_id uuid,
  mountain text,
  key_version integer,
  created_at timestamptz,
  role text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_group groups%rowtype;
  v_mountain text;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if not exists (select 1 from profiles p where p.id = v_uid) then
    raise exception 'PROFILE_REQUIRED';
  end if;
  if p_name is null or char_length(btrim(p_name)) not between 1 and 60 then
    raise exception 'GROUP_NAME_INVALID';
  end if;

  v_mountain := nullif(btrim(coalesce(p_mountain, '')), '');
  if v_mountain is not null and char_length(v_mountain) > 80 then
    raise exception 'GROUP_NAME_INVALID';
  end if;

  insert into groups (name, owner_id, mountain)
  values (btrim(p_name), v_uid, v_mountain)
  returning * into v_group;

  insert into group_members (group_id, user_id, role)
  values (v_group.id, v_uid, 'owner');

  return query
    select g.id, g.name, g.owner_id, g.mountain, g.key_version,
           g.created_at, 'owner'::text
    from groups g
    where g.id = v_group.id;
end;
$$;

create or replace function invite_user(
  p_group_id uuid,
  p_username text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_username citext;
  v_invitee uuid;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if not exists (select 1 from profiles p where p.id = v_uid) then
    raise exception 'PROFILE_REQUIRED';
  end if;

  select g.owner_id into v_owner from groups g where g.id = p_group_id;
  if not found then
    raise exception 'GROUP_NOT_FOUND';
  end if;
  if v_owner <> v_uid then
    raise exception 'OWNER_REQUIRED';
  end if;

  v_username := lower(btrim(coalesce(p_username, '')))::citext;
  select p.id into v_invitee from profiles p where p.username = v_username;
  if not found then
    raise exception 'USER_NOT_FOUND';
  end if;

  if exists (
    select 1 from group_members m
    where m.group_id = p_group_id and m.user_id = v_invitee
  ) then
    raise exception 'ALREADY_MEMBER';
  end if;

  -- Undangan kedaluwarsa tidak boleh memblokir undangan baru lewat
  -- partial unique index one_pending_invite.
  update invitations i
  set status = 'expired', responded_at = now()
  where i.group_id = p_group_id
    and i.invitee_id = v_invitee
    and i.status = 'pending'
    and i.expires_at <= now();

  begin
    insert into invitations (group_id, inviter_id, invitee_id)
    values (p_group_id, v_uid, v_invitee);
  exception
    when unique_violation then
      raise exception 'INVITE_PENDING';
  end;
end;
$$;

create or replace function my_groups()
returns table (
  id uuid,
  name text,
  owner_id uuid,
  mountain text,
  key_version integer,
  created_at timestamptz,
  role text
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
    raise exception 'AUTH_REQUIRED';
  end if;
  if not exists (select 1 from profiles p where p.id = v_uid) then
    raise exception 'PROFILE_REQUIRED';
  end if;

  return query
    select g.id, g.name, g.owner_id, g.mountain, g.key_version,
           g.created_at, m.role
    from group_members m
    join groups g on g.id = m.group_id
    where m.user_id = v_uid
    order by m.joined_at asc;
end;
$$;

create or replace function my_pending_invitations()
returns table (
  id uuid,
  group_id uuid,
  group_name text,
  inviter_username text,
  created_at timestamptz,
  expires_at timestamptz
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
    raise exception 'AUTH_REQUIRED';
  end if;

  return query
    select i.id, i.group_id, g.name, inviter.username::text,
           i.created_at, i.expires_at
    from invitations i
    join groups g on g.id = i.group_id
    join profiles inviter on inviter.id = i.inviter_id
    where i.invitee_id = v_uid
      and i.status = 'pending'
      and i.expires_at > now()
    order by i.created_at desc;
end;
$$;

create or replace function respond_invitation(
  p_invitation_id uuid,
  p_accept boolean
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_invitation invitations%rowtype;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select * into v_invitation
  from invitations i
  where i.id = p_invitation_id
  for update;

  if not found then
    raise exception 'INVITATION_NOT_FOUND';
  end if;
  if v_invitation.invitee_id <> v_uid then
    raise exception 'NOT_INVITEE';
  end if;
  if v_invitation.status <> 'pending' then
    raise exception 'INVITATION_NOT_PENDING';
  end if;

  if v_invitation.expires_at <= now() then
    update invitations i
    set status = 'expired', responded_at = now()
    where i.id = p_invitation_id;
    return 'expired';
  end if;

  if p_accept then
    insert into group_members (group_id, user_id, role)
    values (v_invitation.group_id, v_uid, 'member')
    on conflict (group_id, user_id) do nothing;

    update invitations i
    set status = 'accepted', responded_at = now()
    where i.id = p_invitation_id;
    return 'accepted';
  end if;

  update invitations i
  set status = 'rejected', responded_at = now()
  where i.id = p_invitation_id;
  return 'rejected';
end;
$$;

create or replace function group_members_directory(p_group_id uuid)
returns table (
  user_id uuid,
  username text,
  role text,
  public_key text,
  joined_at timestamptz
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
    raise exception 'AUTH_REQUIRED';
  end if;
  if not exists (select 1 from profiles p where p.id = v_uid) then
    raise exception 'PROFILE_REQUIRED';
  end if;
  if not exists (
    select 1 from group_members m
    where m.group_id = p_group_id and m.user_id = v_uid
  ) then
    raise exception 'NOT_MEMBER';
  end if;

  return query
    select m.user_id, p.username::text, m.role, p.public_key, m.joined_at
    from group_members m
    join profiles p on p.id = m.user_id
    where m.group_id = p_group_id
    order by m.joined_at asc;
end;
$$;

-- ---------------------------------------------------------------------------
-- Kunci grup (server hanya menyimpan blob terenkripsi)
-- ---------------------------------------------------------------------------
create or replace function publish_group_keys(
  p_group_id uuid,
  p_key_version integer,
  p_wrapped_keys jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_version integer;
  v_count integer;
  v_distinct integer;
  v_member_count integer;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if not exists (select 1 from profiles p where p.id = v_uid) then
    raise exception 'PROFILE_REQUIRED';
  end if;

  select g.key_version into v_version
  from groups g
  where g.id = p_group_id
  for update;

  if not found then
    raise exception 'GROUP_NOT_FOUND';
  end if;
  if not exists (
    select 1 from group_members m
    where m.group_id = p_group_id and m.user_id = v_uid and m.role = 'owner'
  ) then
    raise exception 'OWNER_REQUIRED';
  end if;
  if p_key_version is null or p_key_version <> v_version then
    raise exception 'KEY_VERSION_INVALID';
  end if;

  if p_wrapped_keys is null or jsonb_typeof(p_wrapped_keys) <> 'array' then
    raise exception 'MISSING_MEMBER_KEY';
  end if;

  -- Validasi bentuk data sebelum cast ke uuid agar input rusak tidak menjadi
  -- error 500. Server tidak dapat memeriksa isi kriptografis blob.
  if exists (
    select 1
    from jsonb_array_elements(p_wrapped_keys) elem
    where jsonb_typeof(elem) <> 'object'
       or (elem->>'user_id') is null
       or (elem->>'user_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or (elem->>'wrapped_key') is null
       or char_length(elem->>'wrapped_key') not between 64 and 4096
       or char_length(elem->>'wrapped_key') % 4 <> 0
       or (elem->>'wrapped_key') !~ '^[A-Za-z0-9+/]+={0,2}$'
  ) then
    raise exception 'MISSING_MEMBER_KEY';
  end if;

  select count(*), count(distinct lower(elem->>'user_id'))
  into v_count, v_distinct
  from jsonb_array_elements(p_wrapped_keys) elem;

  if v_count <> v_distinct then
    raise exception 'RECIPIENT_NOT_MEMBER';
  end if;

  select count(*) into v_member_count
  from group_members m
  where m.group_id = p_group_id;

  if v_count <> v_member_count then
    if exists (
      select 1
      from jsonb_array_elements(p_wrapped_keys) elem
      where not exists (
        select 1 from group_members m
        where m.group_id = p_group_id
          and m.user_id = (elem->>'user_id')::uuid
      )
    ) then
      raise exception 'RECIPIENT_NOT_MEMBER';
    end if;
    raise exception 'MISSING_MEMBER_KEY';
  end if;

  insert into group_key_blobs (group_id, user_id, key_version, wrapped_key)
  select
    p_group_id,
    (elem->>'user_id')::uuid,
    p_key_version,
    elem->>'wrapped_key'
  from jsonb_array_elements(p_wrapped_keys) elem
  on conflict (group_id, user_id, key_version)
  do update set wrapped_key = excluded.wrapped_key, created_at = now();
end;
$$;

create or replace function remove_group_member(
  p_group_id uuid,
  p_user_id uuid
)
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
    raise exception 'GROUP_NOT_FOUND';
  end if;
  if v_owner <> v_uid then
    raise exception 'OWNER_REQUIRED';
  end if;
  if p_user_id = v_owner then
    raise exception 'OWNER_IMMUTABLE';
  end if;
  if not exists (
    select 1 from group_members m
    where m.group_id = p_group_id and m.user_id = p_user_id
  ) then
    raise exception 'NOT_MEMBER';
  end if;

  delete from group_members m
  where m.group_id = p_group_id and m.user_id = p_user_id;

  delete from group_key_blobs b
  where b.group_id = p_group_id and b.user_id = p_user_id;

  -- Naikkan versi agar pemilik wajib membagikan kunci baru ke anggota tersisa.
  update groups g
  set key_version = g.key_version + 1
  where g.id = p_group_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Hak eksekusi: hanya pengguna terautentikasi. Fungsi tetap memeriksa
-- kepemilikan/keanggotaan; grant ini bukan pengganti pemeriksaan tersebut.
-- ---------------------------------------------------------------------------
revoke all on function register_profile(text, text) from public;
revoke all on function lookup_user(text) from public;
revoke all on function create_group(text, text) from public;
revoke all on function invite_user(uuid, text) from public;
revoke all on function my_groups() from public;
revoke all on function my_pending_invitations() from public;
revoke all on function respond_invitation(uuid, boolean) from public;
revoke all on function group_members_directory(uuid) from public;
revoke all on function publish_group_keys(uuid, integer, jsonb) from public;
revoke all on function remove_group_member(uuid, uuid) from public;

grant execute on function register_profile(text, text) to authenticated;
grant execute on function lookup_user(text) to authenticated;
grant execute on function create_group(text, text) to authenticated;
grant execute on function invite_user(uuid, text) to authenticated;
grant execute on function my_groups() to authenticated;
grant execute on function my_pending_invitations() to authenticated;
grant execute on function respond_invitation(uuid, boolean) to authenticated;
grant execute on function group_members_directory(uuid) to authenticated;
grant execute on function publish_group_keys(uuid, integer, jsonb) to authenticated;
grant execute on function remove_group_member(uuid, uuid) to authenticated;
