-- ============================================================================
-- Migration 0007: SOS Event Upsert + Metadata + Group Hike Prep Re-invite FCM
-- ============================================================================
-- 1. Tambah kolom `mountain_name`, `altitude_m`, dan `message` pada `sos_events`
--    serta kebijakan RLS agar pembuat SOS dapat melakukan 1 UPSERT aman per pemicu.
-- 2. Pastikan trigger FCM `group_hike_prep` berjalan pada ajakan baru maupun
--    saat ajakan baru dibuat ulang pada grup yang sama (`invite_id` berubah),
--    tanpa mengirim spam saat anggota menekan tombol "Siap".
-- ============================================================================

alter table sos_events
  add column if not exists mountain_name text,
  add column if not exists altitude_m    double precision,
  add column if not exists message       text;

drop policy if exists sos_author_insert on sos_events;
create policy sos_author_insert on sos_events
  for insert
  with check (author_id = auth.uid());

drop policy if exists sos_author_update on sos_events;
create policy sos_author_update on sos_events
  for update
  using (author_id = auth.uid())
  with check (author_id = auth.uid());

-- Pastikan trigger group_hike_prep hanya memicu notifikasi FCM saat ajakan baru
-- dibuat (INSERT atau invite_id berubah dengan status active), bukan saat
-- anggota hanya menekan "Siap" pada ajakan yang sama.
create or replace function public.dispatch_group_hike_prep_fcm()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url    text;
  v_secret text;
begin
  if new.status <> 'active' then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.invite_id is not distinct from new.invite_id and old.status = 'active' then
    return new;
  end if;

  v_url := current_setting('app.fcm_edge_url', true);
  v_secret := current_setting('app.fcm_webhook_secret', true);
  if v_url is null or btrim(v_url) = '' then
    return new;
  end if;

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-hiqeo-webhook-secret', coalesce(v_secret, '')
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

do $$
begin
  if to_regclass('public.group_hike_prep') is not null then
    execute 'drop trigger if exists trg_group_hike_prep_fcm on public.group_hike_prep';
    execute 'create trigger trg_group_hike_prep_fcm after insert or update on public.group_hike_prep for each row execute function public.dispatch_group_hike_prep_fcm()';
  end if;
end;
$$;
