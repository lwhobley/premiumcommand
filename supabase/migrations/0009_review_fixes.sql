-- CUTX Premium Command: fixes from the code review.
-- 1. A member list for managers who deploy staff, so roster positions can be linked to real accounts.
-- 2. The person who delivered a food batch cannot also confirm its receipt.

-- Names only, no emails. Needs deploy_staff or manage_configuration.
create or replace function public.list_venue_members(p_venue uuid)
returns table (user_id uuid, display_name text)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not (public.has_permission(p_venue, 'deploy_staff') or public.has_permission(p_venue, 'manage_configuration')) then
    raise exception 'Not authorized to list people' using errcode = '42501';
  end if;

  return query
  select m.user_id, coalesce(p.display_name, u.email::text, 'Team member')
    from venue_memberships m
    join auth.users u on u.id = m.user_id
    left join user_profiles p on p.id = m.user_id
   where m.venue_id = p_venue and m.status = 'active'
   order by coalesce(p.display_name, u.email::text);
end;
$$;

revoke execute on function public.list_venue_members(uuid) from public, anon;
grant execute on function public.list_venue_members(uuid) to authenticated;

create or replace function public.advance_culinary_batch(
  p_batch uuid,
  p_to text,
  p_expected_version integer,
  p_receiver text default ''
)
returns culinary_batches
language plpgsql security definer set search_path = public
as $$
declare
  b culinary_batches%rowtype;
  previous text;
  order_list text[] := array['planned','in_production','ready','collected','delivered','received'];
  fi integer;
  ti integer;
  allowed boolean;
begin
  select * into b from culinary_batches where id = p_batch for update;
  if not found then raise exception 'Batch not found' using errcode = 'P0002'; end if;
  if b.version <> p_expected_version then
    raise exception 'Conflict: this batch changed. Refresh and try again.' using errcode = '40001';
  end if;

  fi := array_position(order_list, b.state);
  ti := array_position(order_list, p_to);
  if ti is null or ti <> fi + 1 then
    raise exception 'Batch moves one step at a time (% to % is not allowed)', b.state, p_to;
  end if;

  allowed := case p_to
    when 'in_production' then public.has_permission(b.venue_id, 'view_culinary')
    when 'ready' then public.has_permission(b.venue_id, 'view_culinary')
    when 'collected' then public.has_permission(b.venue_id, 'manage_requests')
    when 'delivered' then public.has_permission(b.venue_id, 'manage_requests')
    when 'received' then public.has_permission(b.venue_id, 'update_tasks')
    else false
  end;
  if not allowed then
    raise exception 'Not authorized for this handoff step' using errcode = '42501';
  end if;
  if p_to = 'received' and length(trim(coalesce(p_receiver, ''))) = 0 then
    raise exception 'Record who received the delivery';
  end if;

  -- Receipt is an independent confirmation. The person who delivered cannot give it.
  if p_to = 'received' and exists (
    select 1 from culinary_batch_history h
     where h.batch_id = b.id and h.to_state = 'delivered' and h.actor_id = auth.uid()
  ) then
    raise exception 'The person who delivered this batch cannot confirm its receipt' using errcode = '42501';
  end if;

  previous := b.state;
  update culinary_batches set
    state = p_to,
    ready_at = case when p_to = 'ready' then now() else ready_at end,
    collected_at = case when p_to = 'collected' then now() else collected_at end,
    delivered_at = case when p_to = 'delivered' then now() else delivered_at end,
    received_at = case when p_to = 'received' then now() else received_at end,
    received_by = case when p_to = 'received' then p_receiver else received_by end,
    version = version + 1
  where id = b.id
  returning * into b;

  insert into culinary_batch_history (batch_id, venue_id, from_state, to_state)
  values (b.id, b.venue_id, previous, p_to);
  return b;
end;
$$;
