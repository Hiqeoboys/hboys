-- ============================================================================
-- Migration: Add `fcm_token` column to `public.profiles` + self-only RLS
-- ============================================================================
-- 1. Adds `fcm_token text` to `public.profiles` for instant FCM HTTP v1 lookup
--    and automatic cleanup when FCM returns UNREGISTERED.
-- 2. Grants column-scoped `UPDATE (fcm_token)` on `public.profiles` to
--    `authenticated` with RLS `id = auth.uid()` so signed-in users can update
--    their own `fcm_token` (or set it to NULL on logout) WITHOUT exposing
--    sensitive columns (`is_plus`, `public_key`, `username`) to direct writes.
-- ============================================================================

alter table public.profiles
  add column if not exists fcm_token text;

create index if not exists idx_profiles_fcm_token_present
  on public.profiles (id)
  where fcm_token is not null;

-- Protect sensitive columns while allowing self-update of `fcm_token` only.
revoke update on table public.profiles from authenticated;
grant update (fcm_token) on table public.profiles to authenticated;

drop policy if exists profiles_self_update_fcm_token on public.profiles;
create policy profiles_self_update_fcm_token on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());
