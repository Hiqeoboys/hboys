-- Wave 1 Corrective Migration:
-- 1. Eliminate SQL 42501 ("Direct deletion from storage tables is not allowed")
--    by removing triggers/functions that directly DELETE FROM storage.objects.
-- 2. Fix E2EE group key distribution race conditions so any key-holding member
--    can forward missing group key blobs, add group_members_missing_key RPC,
--    and optimize RLS, indexes, and Realtime publications.

-- ----------------------------------------------------------------------------
-- 1. Drop storage.objects trigger on groups (prevents 42501 during delete_group
--    and delete_my_account cascades)
-- ----------------------------------------------------------------------------
drop trigger if exists trg_groups_cleanup_voice on public.groups;
drop function if exists public.trg_cleanup_group_voice_objects() cascade;

-- ----------------------------------------------------------------------------
-- 2. Replace delete_group without touching storage.objects directly
-- ----------------------------------------------------------------------------
drop function if exists public.delete_group(uuid);

create function public.delete_group(p_group_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_group public.groups%rowtype;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  if p_group_id is null then
    return false;
  end if;

  select * into v_group
  from public.groups g
  where g.id = p_group_id
  for update;

  if not found then
    return false;
  end if;

  if v_group.owner_id <> v_uid and not exists (
    select 1
    from public.group_members gm
    where gm.group_id = p_group_id
      and gm.user_id = v_uid
      and gm.role = 'owner'
  ) then
    raise exception 'OWNER_REQUIRED' using errcode = '42501';
  end if;

  delete from public.groups
  where id = p_group_id;

  return true;
end;
$$;

revoke all on function public.delete_group(uuid) from public, anon;
grant execute on function public.delete_group(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. Replace soft_delete_group_message without touching storage.objects
--    (Storage/R2 deletion happens client-side / Edge Function via Storage API)
-- ----------------------------------------------------------------------------
create or replace function public.soft_delete_group_message(
  p_group_id uuid,
  p_client_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.group_messages%rowtype;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  if not public.is_group_member(p_group_id) then
    raise exception 'NOT_MEMBER' using errcode = '42501';
  end if;

  select * into v_row
  from public.group_messages gm
  where gm.group_id = p_group_id
    and (gm.client_id = p_client_id or gm.id = p_client_id)
  for update;

  if not found then
    return false;
  end if;

  if v_row.sender_id <> v_uid then
    raise exception 'FORBIDDEN_DELETE_MESSAGE' using errcode = '42501';
  end if;

  update public.group_messages
  set is_deleted = true,
      deleted_at = coalesce(deleted_at, now()),
      ciphertext = '',
      nonce = '',
      voice_path = null
  where id = v_row.id;

  return true;
end;
$$;

revoke all on function public.soft_delete_group_message(uuid, uuid) from public, anon;
grant execute on function public.soft_delete_group_message(uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 4. Replace cleanup_expired_group_voice without touching storage.objects
-- ----------------------------------------------------------------------------
drop function if exists public.cleanup_expired_group_voice();

create function public.cleanup_expired_group_voice()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cleared integer := 0;
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'group_messages'
      and column_name = 'voice_path'
  ) then
    update public.group_messages
    set voice_path = null
    where voice_path is not null
      and created_at < now() - interval '30 days';
    get diagnostics v_cleared = row_count;
  end if;

  return v_cleared;
end;
$$;

revoke all on function public.cleanup_expired_group_voice() from public, anon;

-- ----------------------------------------------------------------------------
-- 5. Update publish_group_keys: allow owner OR any existing key holder to
--    distribute missing wrapped keys for active members without failing on
--    concurrent joins/leaves or requiring full-roster resubmission
-- ----------------------------------------------------------------------------
create or replace function public.publish_group_keys(
  p_group_id uuid,
  p_key_version integer,
  p_wrapped_keys jsonb
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_version integer;
  v_owner_id uuid;
  v_is_owner boolean := false;
  v_has_key boolean := false;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = v_uid and p.username is not null
  ) then
    raise exception 'PROFILE_REQUIRED' using errcode = '42501';
  end if;

  select g.key_version, g.owner_id
  into v_version, v_owner_id
  from public.groups g
  where g.id = p_group_id
  for share;

  if not found then
    raise exception 'GROUP_NOT_FOUND';
  end if;

  if p_key_version is null or p_key_version <> v_version then
    raise exception 'KEY_VERSION_INVALID';
  end if;

  if not exists (
    select 1
    from public.group_members m
    where m.group_id = p_group_id and m.user_id = v_uid
  ) then
    raise exception 'NOT_MEMBER' using errcode = '42501';
  end if;

  v_is_owner := (v_owner_id = v_uid) or exists (
    select 1
    from public.group_members m
    where m.group_id = p_group_id
      and m.user_id = v_uid
      and m.role = 'owner'
  );

  v_has_key := exists (
    select 1
    from public.group_key_blobs kb
    where kb.group_id = p_group_id
      and kb.user_id = v_uid
      and kb.key_version = p_key_version
  );

  if not v_is_owner and not v_has_key then
    raise exception 'KEY_HOLDER_REQUIRED' using errcode = '42501';
  end if;

  if p_wrapped_keys is null or jsonb_typeof(p_wrapped_keys) <> 'array' then
    raise exception 'MISSING_MEMBER_KEY';
  end if;

  if jsonb_array_length(p_wrapped_keys) = 0 then
    return;
  end if;

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
    raise exception 'INVALID_WRAPPED_KEY';
  end if;

  if v_is_owner then
    insert into public.group_key_blobs (group_id, user_id, key_version, wrapped_key)
    select distinct on (gm.user_id)
      p_group_id,
      gm.user_id,
      p_key_version,
      elem->>'wrapped_key'
    from jsonb_array_elements(p_wrapped_keys) elem
    join public.group_members gm
      on gm.group_id = p_group_id
     and gm.user_id = (elem->>'user_id')::uuid
    order by gm.user_id
    on conflict (group_id, user_id, key_version) do update
      set wrapped_key = excluded.wrapped_key;
  else
    -- Non-owner key holders can only fill missing key blobs, never overwrite
    insert into public.group_key_blobs (group_id, user_id, key_version, wrapped_key)
    select distinct on (gm.user_id)
      p_group_id,
      gm.user_id,
      p_key_version,
      elem->>'wrapped_key'
    from jsonb_array_elements(p_wrapped_keys) elem
    join public.group_members gm
      on gm.group_id = p_group_id
     and gm.user_id = (elem->>'user_id')::uuid
    order by gm.user_id
    on conflict (group_id, user_id, key_version) do nothing;
  end if;
end;
$$;

revoke all on function public.publish_group_keys(uuid, integer, jsonb) from public, anon;
grant execute on function public.publish_group_keys(uuid, integer, jsonb) to authenticated;

-- ----------------------------------------------------------------------------
-- 6. New RPC: group_members_missing_key
--    Returns active group members with a registered public_key who still lack
--    a wrapped key blob for the active/requested key_version.
-- ----------------------------------------------------------------------------
create or replace function public.group_members_missing_key(
  p_group_id uuid,
  p_key_version integer default null
)
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
  v_version integer;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  if not exists (
    select 1
    from public.group_members m
    where m.group_id = p_group_id and m.user_id = v_uid
  ) then
    raise exception 'NOT_MEMBER' using errcode = '42501';
  end if;

  select coalesce(p_key_version, g.key_version)
  into v_version
  from public.groups g
  where g.id = p_group_id;

  if v_version is null then
    return;
  end if;

  return query
    select
      m.user_id,
      p.username::text,
      m.role,
      p.public_key,
      m.joined_at
    from public.group_members m
    join public.profiles p on p.id = m.user_id
    where m.group_id = p_group_id
      and p.public_key is not null
      and btrim(p.public_key) <> ''
      and not exists (
        select 1
        from public.group_key_blobs kb
        where kb.group_id = p_group_id
          and kb.user_id = m.user_id
          and kb.key_version = v_version
      )
    order by m.joined_at asc;
end;
$$;

revoke all on function public.group_members_missing_key(uuid, integer) from public, anon;
grant execute on function public.group_members_missing_key(uuid, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- 7. Indexes, RLS initPlan optimization, and Realtime publications
-- ----------------------------------------------------------------------------
create index if not exists idx_group_key_blobs_user_group_ver
  on public.group_key_blobs (user_id, group_id, key_version);

create index if not exists idx_group_key_blobs_group_ver_user
  on public.group_key_blobs (group_id, key_version, user_id);

create index if not exists idx_group_members_user_group
  on public.group_members (user_id, group_id);

create index if not exists idx_group_messages_group_created_desc
  on public.group_messages (group_id, created_at desc);

drop policy if exists keyblobs_self_read on public.group_key_blobs;
create policy keyblobs_self_read on public.group_key_blobs
  for select using (user_id = (select auth.uid()));

drop policy if exists invitations_party_read on public.invitations;
create policy invitations_party_read on public.invitations
  for select using (
    inviter_id = (select auth.uid()) or invitee_id = (select auth.uid())
  );

alter table if exists public.group_members   replica identity full;
alter table if exists public.group_key_blobs replica identity full;
alter table if exists public.invitations     replica identity full;

do $$
declare
  v_table text;
  v_tables text[] := array[
    'group_members',
    'group_key_blobs',
    'invitations',
    'group_messages',
    'member_locations'
  ];
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach v_table in array v_tables loop
      if exists (
        select 1
        from information_schema.tables
        where table_schema = 'public' and table_name = v_table
      ) and not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = v_table
      ) then
        execute format('alter publication supabase_realtime add table public.%I', v_table);
      end if;
    end loop;
  end if;
end
$$;
