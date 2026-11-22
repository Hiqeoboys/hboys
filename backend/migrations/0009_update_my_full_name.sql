-- ============================================================================
-- Migration 0009: Allow authenticated user to update own `full_name` safely
-- ============================================================================

grant update (full_name) on table public.profiles to authenticated;

create or replace function public.update_my_full_name(p_full_name text)
returns table (
  id uuid,
  full_name text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_name text := btrim(coalesce(p_full_name, ''));
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if v_name = '' then
    raise exception 'FULL_NAME_EMPTY';
  end if;

  if char_length(v_name) > 40 then
    raise exception 'FULL_NAME_TOO_LONG';
  end if;

  update public.profiles p
  set full_name = v_name
  where p.id = v_uid;

  return query
    select p.id, p.full_name
    from public.profiles p
    where p.id = v_uid;
end;
$$;

revoke all on function public.update_my_full_name(text) from public;
grant execute on function public.update_my_full_name(text) to authenticated;
