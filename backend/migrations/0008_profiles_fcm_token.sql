-- ============================================================================
-- Migration 0008: Add `fcm_token` column to `public.profiles` + self-only RLS
-- (Mirror of supabase/migrations/20261120150000_add_profiles_fcm_token.sql)
-- ============================================================================

alter table public.profiles
  add column if not exists fcm_token text;

create index if not exists idx_profiles_fcm_token_present
  on public.profiles (id)
  where fcm_token is not null;

revoke update on table public.profiles from authenticated;
grant update (fcm_token) on table public.profiles to authenticated;

drop policy if exists profiles_self_update_fcm_token on public.profiles;
create policy profiles_self_update_fcm_token on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());
