-- ============================================================================
-- Migration: `user_notifications` Inbox Table, Strict RLS, Realtime,
--            and Updated FCM Webhook Triggers (Mentions, Invitations, Cancels)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. `public.user_notifications` (Home Inbox — excludes regular chat messages)
-- ----------------------------------------------------------------------------
create table if not exists public.user_notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  type       text not null check (
    type in (
      'friend_request',
      'group_invitation',
      'group_ready',
      'group_hike_cancelled',
      'community_mention',
      'emergency_contact_request',
      'sos'
    )
  ),
  title      text not null,
  body       text not null,
  actor_id   uuid references public.profiles (id) on delete set null,
  target_id  text,
  room_type  text check (room_type is null or room_type in ('group', 'community')),
  room_id    uuid,
  message_id text,
  data       jsonb not null default '{}'::jsonb,
  is_read    boolean not null default false,
  read_at    timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_user_notifications_user_created
  on public.user_notifications (user_id, created_at desc);

create index if not exists idx_user_notifications_user_unread
  on public.user_notifications (user_id, created_at desc)
  where is_read = false;

create index if not exists idx_user_notifications_actor_id
  on public.user_notifications (actor_id)
  where actor_id is not null;

alter table public.user_notifications enable row level security;

revoke all on table public.user_notifications from public, anon;
grant select on table public.user_notifications to authenticated;
grant update (is_read, read_at) on table public.user_notifications to authenticated;

drop policy if exists user_notifications_self_select on public.user_notifications;
create policy user_notifications_self_select
  on public.user_notifications
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists user_notifications_self_update_read on public.user_notifications;
create policy user_notifications_self_update_read
  on public.user_notifications
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create or replace function public.sync_user_notification_read_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('postgres', 'service_role', 'supabase_admin') then
    if new.id is distinct from old.id
       or new.user_id is distinct from old.user_id
       or new.type is distinct from old.type
       or new.title is distinct from old.title
       or new.body is distinct from old.body
       or new.actor_id is distinct from old.actor_id
       or new.target_id is distinct from old.target_id
       or new.room_type is distinct from old.room_type
       or new.room_id is distinct from old.room_id
       or new.message_id is distinct from old.message_id
       or new.data is distinct from old.data
       or new.created_at is distinct from old.created_at then
      raise exception 'NOTIFICATION_CONTENT_IMMUTABLE' using errcode = '42501';
    end if;
  end if;

  if new.is_read and not old.is_read then
    new.read_at := coalesce(new.read_at, now());
  elsif not new.is_read then
    new.read_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_user_notifications_sync_read on public.user_notifications;
create trigger trg_user_notifications_sync_read
  before update on public.user_notifications
  for each row
  execute function public.sync_user_notification_read_at();

revoke all on function public.sync_user_notification_read_at() from public, anon;

create or replace function public.mark_all_notifications_read()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_count integer := 0;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  update public.user_notifications
  set is_read = true,
      read_at = now()
  where user_id = v_uid
    and is_read = false;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.mark_all_notifications_read() from public, anon;
grant execute on function public.mark_all_notifications_read() to authenticated;

alter table public.user_notifications replica identity full;
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'user_notifications'
    ) then
      alter publication supabase_realtime add table public.user_notifications;
    end if;
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. Update Webhook Dispatch Triggers (`dispatch_fcm_webhook`, `dispatch_group_hike_prep_fcm`, `invitations`)
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

do $$
begin
  if to_regclass('public.invitations') is not null then
    drop trigger if exists trg_invitations_fcm on public.invitations;
    create trigger trg_invitations_fcm
      after insert on public.invitations
      for each row
      execute function public.dispatch_fcm_webhook();
  end if;
end;
$$;
