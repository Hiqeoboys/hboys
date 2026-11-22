-- Security hardening migration: full RLS coverage, privilege-escalation guards,
-- IDOR & consent protections, and fail-closed webhook/SECURITY DEFINER checks.

-- Ensure profile entitlement/moderation columns exist before installing triggers.
alter table if exists public.profiles
  add column if not exists full_name text,
  add column if not exists avatar_url text,
  add column if not exists fcm_token text,
  add column if not exists is_plus boolean not null default false,
  add column if not exists plus_plan_id text,
  add column if not exists plus_expires_at timestamptz,
  add column if not exists username_changed_at timestamptz;

-- 1. Enable Row Level Security on every public table.
do $$
declare
  v_tbl text;
begin
  foreach v_tbl in array array[
    'profiles',
    'groups',
    'group_members',
    'invitations',
    'group_key_blobs',
    'group_messages',
    'member_locations',
    'group_hike_prep',
    'last_known_locations',
    'communities',
    'community_members',
    'community_messages',
    'friendships',
    'hike_sessions',
    'cloud_session_backups',
    'sos_events',
    'sos_dispatch_log',
    'emergency_contacts',
    'moderation_reports',
    'user_fcm_tokens',
    'blocked_terms'
  ] loop
    if to_regclass(format('public.%I', v_tbl)) is not null then
      execute format('alter table public.%I enable row level security', v_tbl);
    end if;
  end loop;
end;
$$;

-- 2. Prevent privilege escalation on public.profiles.
revoke update on table public.profiles from anon, authenticated;
grant update (fcm_token, full_name) on table public.profiles to authenticated;

drop policy if exists profiles_self_write on public.profiles;
drop policy if exists profiles_self_update on public.profiles;
drop policy if exists profiles_self_update_fcm_token on public.profiles;
drop policy if exists profiles_self_update_safe on public.profiles;
create policy profiles_self_update_safe
  on public.profiles
  for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create or replace function public.guard_profile_sensitive_columns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('postgres', 'service_role', 'supabase_admin') then
    if new.id is distinct from old.id
       or new.is_plus is distinct from old.is_plus
       or new.plus_plan_id is distinct from old.plus_plan_id
       or new.plus_expires_at is distinct from old.plus_expires_at
       or new.created_at is distinct from old.created_at
       or (to_jsonb(new) ->> 'email') is distinct from (to_jsonb(old) ->> 'email') then
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
  before update on public.profiles
  for each row
  execute function public.guard_profile_sensitive_columns();

revoke all on function public.guard_profile_sensitive_columns() from public, anon;

-- 3. Prevent IDOR and consent bypass on public.friendships.
do $$
begin
  if to_regclass('public.friendships') is not null then
    drop policy if exists friendships_insert_plus on public.friendships;
    drop policy if exists friendships_insert_auth on public.friendships;
    create policy friendships_insert_auth
      on public.friendships
      for insert
      to authenticated
      with check (
        requester_id = auth.uid()
        and addressee_id <> auth.uid()
        and status = 'pending'
      );

    drop policy if exists friendships_party_update on public.friendships;
    drop policy if exists friendships_addressee_respond on public.friendships;
    create policy friendships_addressee_respond
      on public.friendships
      for update
      to authenticated
      using (addressee_id = auth.uid() and status = 'pending')
      with check (addressee_id = auth.uid() and status in ('accepted', 'rejected'));
  end if;
end;
$$;

create or replace function public.guard_friendships_immutable()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('postgres', 'service_role', 'supabase_admin') then
    if new.requester_id is distinct from old.requester_id
       or new.addressee_id is distinct from old.addressee_id then
      raise exception 'FRIENDSHIP_PARTIES_IMMUTABLE'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

do $$
begin
  if to_regclass('public.friendships') is not null then
    drop trigger if exists trg_guard_friendships_immutable on public.friendships;
    create trigger trg_guard_friendships_immutable
      before update on public.friendships
      for each row
      execute function public.guard_friendships_immutable();
  end if;
end;
$$;

revoke all on function public.guard_friendships_immutable() from public, anon;

-- 4. Prevent role escalation in communities & sender spoofing in community_messages.
do $$
begin
  if to_regclass('public.community_members') is not null then
    drop policy if exists community_members_join on public.community_members;
    create policy community_members_join
      on public.community_members
      for insert
      to authenticated
      with check (
        user_id = auth.uid()
        and (
          role = 'member'
          or (
            role = 'owner'
            and exists (
              select 1
              from public.communities c
              where c.id = community_members.community_id
                and c.owner_id = auth.uid()
            )
          )
        )
      );
  end if;
end;
$$;

create or replace function public.fill_community_message_sender()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_avatar text;
begin
  select
    coalesce(
      nullif(btrim(p.full_name), ''),
      nullif(btrim(p.username::text), ''),
      'Pendaki'
    ),
    p.avatar_url
  into v_name, v_avatar
  from public.profiles p
  where p.id = new.sender_id;

  -- Overwrite client-supplied sender metadata whenever a server profile exists.
  if found then
    new.sender_name := v_name;
    new.sender_avatar := v_avatar;
  elsif new.sender_name is null or btrim(new.sender_name) = '' then
    new.sender_name := 'Pendaki';
  end if;
  return new;
end;
$$;

do $$
begin
  if to_regclass('public.community_messages') is not null then
    drop trigger if exists trg_community_messages_fill_sender on public.community_messages;
    create trigger trg_community_messages_fill_sender
      before insert on public.community_messages
      for each row
      execute function public.fill_community_message_sender();
  end if;
end;
$$;

revoke all on function public.fill_community_message_sender() from public, anon;

do $$
begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists community_media_auth_insert on storage.objects;
    create policy community_media_auth_insert
      on storage.objects
      for insert
      to authenticated
      with check (
        bucket_id = 'community-media'
        and coalesce(owner, auth.uid()) = auth.uid()
      );
  end if;
end;
$$;

-- 5. Enforce active group membership (anti-IDOR) on group_messages, member_locations, group_hike_prep.
do $$
begin
  if to_regclass('public.group_messages') is not null then
    drop policy if exists group_messages_member_select on public.group_messages;
    drop policy if exists group_messages_member_insert on public.group_messages;
    drop policy if exists group_messages_member_update on public.group_messages;
    drop policy if exists group_messages_select_member on public.group_messages;
    drop policy if exists group_messages_insert_member on public.group_messages;
    drop policy if exists group_messages_update_own on public.group_messages;
    drop policy if exists group_messages_delete_own on public.group_messages;

    create policy group_messages_select_member
      on public.group_messages
      for select
      to authenticated
      using (public.is_group_member(group_id));

    create policy group_messages_insert_member
      on public.group_messages
      for insert
      to authenticated
      with check (
        sender_id = auth.uid()
        and public.is_group_member(group_id)
      );

    create policy group_messages_update_own
      on public.group_messages
      for update
      to authenticated
      using (
        sender_id = auth.uid()
        and public.is_group_member(group_id)
      )
      with check (
        sender_id = auth.uid()
        and public.is_group_member(group_id)
      );

    create policy group_messages_delete_own
      on public.group_messages
      for delete
      to authenticated
      using (
        sender_id = auth.uid()
        and public.is_group_member(group_id)
      );
  end if;

  if to_regclass('public.member_locations') is not null then
    drop policy if exists member_locations_member_select on public.member_locations;
    drop policy if exists member_locations_member_insert on public.member_locations;
    drop policy if exists member_locations_member_update on public.member_locations;
    drop policy if exists member_locations_select_member on public.member_locations;
    drop policy if exists member_locations_insert_own on public.member_locations;
    drop policy if exists member_locations_update_own on public.member_locations;
    drop policy if exists member_locations_delete_own on public.member_locations;

    create policy member_locations_select_member
      on public.member_locations
      for select
      to authenticated
      using (public.is_group_member(group_id));

    create policy member_locations_insert_own
      on public.member_locations
      for insert
      to authenticated
      with check (
        user_id = auth.uid()
        and public.is_group_member(group_id)
      );

    create policy member_locations_update_own
      on public.member_locations
      for update
      to authenticated
      using (
        user_id = auth.uid()
        and public.is_group_member(group_id)
      )
      with check (
        user_id = auth.uid()
        and public.is_group_member(group_id)
      );

    create policy member_locations_delete_own
      on public.member_locations
      for delete
      to authenticated
      using (user_id = auth.uid());
  end if;

  if to_regclass('public.group_hike_prep') is not null then
    drop policy if exists group_hike_prep_member_all on public.group_hike_prep;
    drop policy if exists group_hike_prep_member_select on public.group_hike_prep;
    drop policy if exists group_hike_prep_member_insert on public.group_hike_prep;
    drop policy if exists group_hike_prep_member_update on public.group_hike_prep;
    drop policy if exists group_hike_prep_member_delete on public.group_hike_prep;

    create policy group_hike_prep_member_select
      on public.group_hike_prep
      for select
      to authenticated
      using (public.is_group_member(group_id));

    create policy group_hike_prep_member_insert
      on public.group_hike_prep
      for insert
      to authenticated
      with check (
        organizer_user_id = auth.uid()
        and public.is_group_member(group_id)
      );

    create policy group_hike_prep_member_update
      on public.group_hike_prep
      for update
      to authenticated
      using (public.is_group_member(group_id))
      with check (public.is_group_member(group_id));

    create policy group_hike_prep_member_delete
      on public.group_hike_prep
      for delete
      to authenticated
      using (public.is_group_member(group_id));
  end if;
end;
$$;

-- 6. Prevent consent forgery on emergency_contacts and cross-group spoofing on sos_events.
create or replace function public.guard_emergency_contacts_consent()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_new_kind text;
  v_old_kind text;
  v_new_target text;
  v_old_target text;
begin
  if current_user in ('postgres', 'service_role', 'supabase_admin') then
    return new;
  end if;

  v_new_kind := coalesce(to_jsonb(new) ->> 'contact_kind', 'phone');
  v_new_target := to_jsonb(new) ->> 'contact_user_id';

  if tg_op = 'INSERT' then
    if new.user_id is distinct from v_uid then
      raise exception 'CONTACT_OWNER_REQUIRED' using errcode = '42501';
    end if;
    if v_new_kind = 'hiqeo_account' and new.consent_status is distinct from 'pending' then
      raise exception 'CONSENT_MUST_START_PENDING' using errcode = '42501';
    end if;
    return new;
  end if;

  v_old_kind := coalesce(to_jsonb(old) ->> 'contact_kind', 'phone');
  v_old_target := to_jsonb(old) ->> 'contact_user_id';

  if old.user_id = v_uid then
    if new.user_id is distinct from old.user_id
       or v_new_target is distinct from v_old_target then
      raise exception 'CONTACT_IDENTITY_IMMUTABLE' using errcode = '42501';
    end if;
    if v_old_kind = 'hiqeo_account'
       and new.consent_status = 'granted'
       and old.consent_status is distinct from 'granted' then
      raise exception 'OWNER_CANNOT_SELF_GRANT_CONSENT' using errcode = '42501';
    end if;
    return new;
  end if;

  if v_old_target is not null and v_old_target = v_uid::text then
    if new.user_id is distinct from old.user_id
       or v_new_target is distinct from v_old_target
       or v_new_kind is distinct from v_old_kind
       or new.name is distinct from old.name
       or new.phone_e164 is distinct from old.phone_e164
       or new.channel is distinct from old.channel
       or new.consent_status not in ('granted', 'revoked') then
      raise exception 'TARGET_MAY_ONLY_RESPOND_CONSENT' using errcode = '42501';
    end if;
    return new;
  end if;

  raise exception 'FORBIDDEN_EMERGENCY_CONTACT_UPDATE' using errcode = '42501';
end;
$$;

do $$
begin
  if to_regclass('public.emergency_contacts') is not null then
    drop trigger if exists trg_guard_emergency_contacts_consent on public.emergency_contacts;
    create trigger trg_guard_emergency_contacts_consent
      before insert or update on public.emergency_contacts
      for each row
      execute function public.guard_emergency_contacts_consent();
  end if;
end;
$$;

revoke all on function public.guard_emergency_contacts_consent() from public, anon;

do $$
declare
  v_has_hiqeo_contacts boolean;
begin
  if to_regclass('public.sos_events') is not null then
    select exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'emergency_contacts'
        and column_name = 'contact_kind'
    ) into v_has_hiqeo_contacts;

    drop policy if exists sos_author_or_group_read on public.sos_events;
    if v_has_hiqeo_contacts then
      execute $pol$
        create policy sos_author_or_group_read
          on public.sos_events
          for select
          to authenticated
          using (
            author_id = auth.uid()
            or (group_id is not null and public.is_group_member(group_id))
            or exists (
              select 1
              from public.emergency_contacts ec
              where ec.user_id = sos_events.author_id
                and ec.contact_kind = 'hiqeo_account'
                and ec.contact_user_id = auth.uid()
                and ec.consent_status = 'granted'
            )
          )
      $pol$;
    else
      execute $pol$
        create policy sos_author_or_group_read
          on public.sos_events
          for select
          to authenticated
          using (
            author_id = auth.uid()
            or (group_id is not null and public.is_group_member(group_id))
          )
      $pol$;
    end if;

    drop policy if exists sos_author_insert on public.sos_events;
    create policy sos_author_insert
      on public.sos_events
      for insert
      to authenticated
      with check (
        author_id = auth.uid()
        and (group_id is null or public.is_group_member(group_id))
      );

    drop policy if exists sos_author_update on public.sos_events;
    create policy sos_author_update
      on public.sos_events
      for update
      to authenticated
      using (author_id = auth.uid())
      with check (
        author_id = auth.uid()
        and (group_id is null or public.is_group_member(group_id))
      );
  end if;
end;
$$;

-- 7. Harden moderation_reports, leaderboard_rankings auth, and fail-closed webhook triggers.
do $$
begin
  if to_regclass('public.moderation_reports') is not null then
    drop policy if exists moderation_reports_insert_own on public.moderation_reports;
    drop policy if exists moderation_reports_update_own on public.moderation_reports;
    drop policy if exists moderation_reports_delete_own on public.moderation_reports;

    create policy moderation_reports_insert_own
      on public.moderation_reports
      for insert
      to authenticated
      with check (
        reporter_id = auth.uid()
        and status = 'open'
      );
  end if;
end;
$$;

do $$
begin
  if to_regclass('public.hike_sessions') is not null
     and to_regprocedure('public.has_full_plus_social(uuid)') is not null then
    create or replace function public.leaderboard_rankings(
      p_metric text,
      p_period text
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
    as $fn$
    declare
      v_since timestamptz;
    begin
      if auth.uid() is null then
        raise exception 'AUTH_REQUIRED';
      end if;

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
          from public.profiles p
          join public.hike_sessions hs
            on hs.user_id = p.id
           and hs.activity_type = 'hiking'
           and hs.started_at >= v_since
          where public.has_full_plus_social(p.id)
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
    $fn$;

    revoke all on function public.leaderboard_rankings(text, text) from public, anon;
    grant execute on function public.leaderboard_rankings(text, text) to authenticated;
  end if;
end;
$$;

create or replace function public.notify_developer_on_moderation_report()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text := current_setting('app.settings.moderation_webhook_url', true);
  v_secret text := current_setting('app.settings.moderation_webhook_secret', true);
begin
  if v_url is not null and btrim(v_url) <> ''
     and v_secret is not null and btrim(v_secret) <> ''
     and to_regnamespace('net') is not null then
    perform net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', v_secret,
        'x-hiqeo-webhook-secret', v_secret
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
  return new;
end;
$$;

create or replace function public.notify_fcm_on_emergency_contact_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text := current_setting('app.settings.fcm_webhook_url', true);
  v_secret text := current_setting('app.settings.fcm_webhook_secret', true);
begin
  if new.contact_kind = 'hiqeo_account'
     and new.consent_status = 'pending'
     and v_url is not null and btrim(v_url) <> ''
     and v_secret is not null and btrim(v_secret) <> ''
     and to_regnamespace('net') is not null then
    perform net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', v_secret,
        'x-hiqeo-webhook-secret', v_secret
      ),
      body := jsonb_build_object(
        'type', 'INSERT',
        'table', 'emergency_contacts',
        'record', row_to_json(new)
      )
    );
  end if;
  return new;
exception when others then
  return new;
end;
$$;

create or replace function public.dispatch_fcm_webhook()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text := current_setting('app.settings.fcm_webhook_url', true);
  v_secret text := current_setting('app.settings.fcm_webhook_secret', true);
begin
  if v_url is null or btrim(v_url) = ''
     or v_secret is null or btrim(v_secret) = ''
     or to_regnamespace('net') is null then
    return new;
  end if;

  if tg_table_name = 'friendships' and new.status <> 'pending' then
    return new;
  end if;

  if tg_table_name = 'group_hike_prep' then
    if new.status <> 'active' then
      return new;
    end if;
    if tg_op = 'UPDATE' and old.invite_id = new.invite_id and old.status = 'active' then
      return new;
    end if;
  end if;

  if tg_table_name = 'sos_events' and new.status <> 'active' then
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
      'table', tg_table_name,
      'record', row_to_json(new)
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
  v_url text := current_setting('app.fcm_edge_url', true);
  v_secret text := current_setting('app.fcm_webhook_secret', true);
begin
  if new.status <> 'active' then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.invite_id is not distinct from new.invite_id and old.status = 'active' then
    return new;
  end if;

  if v_url is null or btrim(v_url) = ''
     or v_secret is null or btrim(v_secret) = ''
     or to_regnamespace('net') is null then
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
      'record', row_to_json(new)
    )
  );
  return new;
exception when others then
  return new;
end;
$$;

revoke all on function public.notify_developer_on_moderation_report() from public, anon;
revoke all on function public.notify_fcm_on_emergency_contact_request() from public, anon;
revoke all on function public.dispatch_fcm_webhook() from public, anon;
revoke all on function public.dispatch_group_hike_prep_fcm() from public, anon;
