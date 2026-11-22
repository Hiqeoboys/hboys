-- Wave E: Sort communities dynamically by latest activity (`last_message_at DESC NULLS LAST`,
-- fallback `created_at DESC`).

drop function if exists public.list_communities_with_meta();
create function public.list_communities_with_meta()
returns table (
  id uuid,
  name text,
  description text,
  avatar_url text,
  owner_id uuid,
  created_by uuid,
  creator_name text,
  creator_username text,
  creator_avatar_url text,
  member_count integer,
  is_joined boolean,
  created_at timestamptz,
  last_message_at timestamptz
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
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  return query
    with counts as (
      select
        cm.community_id,
        count(*)::integer as cnt,
        bool_or(cm.user_id = v_uid) as joined
      from public.community_members cm
      group by cm.community_id
    ),
    latest_msg as (
      select
        msg.community_id,
        max(msg.created_at) as last_message_at
      from public.community_messages msg
      group by msg.community_id
    )
    select
      c.id,
      c.name,
      c.description,
      c.avatar_url,
      c.owner_id,
      coalesce(c.created_by, c.owner_id) as created_by,
      coalesce(nullif(btrim(p.full_name), ''), nullif(btrim(p.username::text), ''), 'Pendaki') as creator_name,
      p.username::text as creator_username,
      p.avatar_url as creator_avatar_url,
      greatest(coalesce(cnt.cnt, 0), 0)::integer as member_count,
      coalesce(cnt.joined, false) as is_joined,
      c.created_at,
      lm.last_message_at
    from public.communities c
    left join public.profiles p on p.id = coalesce(c.created_by, c.owner_id)
    left join counts cnt on cnt.community_id = c.id
    left join latest_msg lm on lm.community_id = c.id
    order by lm.last_message_at desc nulls last, c.created_at desc;
end;
$$;

revoke all on function public.list_communities_with_meta() from public, anon;
grant execute on function public.list_communities_with_meta() to authenticated;
