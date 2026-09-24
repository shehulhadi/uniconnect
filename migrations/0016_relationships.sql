-- ============================================================
-- Migration 0016 — User relationships (friends, follows, blocks)
-- One table for all directional relationships between users.
-- ============================================================

create table if not exists public.user_relationships (
  id uuid primary key default gen_random_uuid(),
  from_user_id uuid not null references public.profiles(id) on delete cascade,
  to_user_id   uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('follow','friend_request','friend','block')),
  accepted_at timestamptz,
  created_at  timestamptz not null default now(),
  check (from_user_id <> to_user_id),
  check (kind <> 'friend' or from_user_id < to_user_id)
);

create unique index if not exists ur_follow_unique
  on public.user_relationships(from_user_id, to_user_id) where kind = 'follow';
create unique index if not exists ur_request_unique
  on public.user_relationships(from_user_id, to_user_id) where kind = 'friend_request';
create unique index if not exists ur_block_unique
  on public.user_relationships(from_user_id, to_user_id) where kind = 'block';
create unique index if not exists ur_friend_unique
  on public.user_relationships(from_user_id, to_user_id) where kind = 'friend';

create index if not exists ur_from_idx on public.user_relationships(from_user_id);
create index if not exists ur_to_idx   on public.user_relationships(to_user_id);

alter table public.user_relationships enable row level security;

drop policy if exists ur_select on public.user_relationships;
create policy ur_select on public.user_relationships
  for select to authenticated
  using (
    from_user_id = auth.uid()
    or (to_user_id = auth.uid() and kind <> 'block')
  );

-- All writes go through RPCs. No direct insert/update/delete policy.

grant select on public.user_relationships to authenticated;

-- ============================================================
-- RPCs
-- ============================================================

-- Friend request (auto-accepts if the other person already requested)
create or replace function public.send_friend_request(p_to_user uuid)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  me uuid := auth.uid();
  v_inst uuid; v_other_inst uuid;
  v_id uuid;
begin
  if me is null then raise exception 'not authenticated'; end if;
  if p_to_user = me then raise exception 'cannot friend yourself'; end if;

  select institution_id into v_inst       from public.profiles where id = me;
  select institution_id into v_other_inst from public.profiles where id = p_to_user;
  if v_inst is null or v_other_inst is null or v_inst <> v_other_inst then
    raise exception 'user is not at your institution';
  end if;

  -- Already friends?
  if exists (
    select 1 from public.user_relationships
    where kind = 'friend'
      and ((from_user_id = me and to_user_id = p_to_user)
        or (from_user_id = p_to_user and to_user_id = me))
  ) then raise exception 'already friends'; end if;

  -- Blocked by them?
  if exists (
    select 1 from public.user_relationships
    where kind = 'block' and from_user_id = p_to_user and to_user_id = me
  ) then raise exception 'cannot send request'; end if;

  -- They already asked me: accept.
  select id into v_id from public.user_relationships
    where kind = 'friend_request' and from_user_id = p_to_user and to_user_id = me;
  if v_id is not null then
    perform public.respond_friend_request(v_id, true);
    return v_id;
  end if;

  -- Already asked them: return existing id.
  select id into v_id from public.user_relationships
    where kind = 'friend_request' and from_user_id = me and to_user_id = p_to_user;
  if v_id is not null then return v_id; end if;

  insert into public.user_relationships (from_user_id, to_user_id, kind)
  values (me, p_to_user, 'friend_request')
  returning id into v_id;
  return v_id;
end;
$$;
grant execute on function public.send_friend_request(uuid) to authenticated;

-- Accept or decline a friend request
create or replace function public.respond_friend_request(p_request_id uuid, p_accept boolean)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  me uuid := auth.uid();
  r record;
  lo uuid; hi uuid;
begin
  if me is null then raise exception 'not authenticated'; end if;

  select * into r from public.user_relationships
    where id = p_request_id and kind = 'friend_request';
  if r.id is null then raise exception 'request not found'; end if;
  if r.to_user_id <> me and r.from_user_id <> me then raise exception 'not authorized'; end if;

  if p_accept then
    lo := least(r.from_user_id, r.to_user_id);
    hi := greatest(r.from_user_id, r.to_user_id);

    insert into public.user_relationships (from_user_id, to_user_id, kind, accepted_at)
    values (lo, hi, 'friend', now())
    on conflict do nothing;

    -- Drop any redundant follows
    delete from public.user_relationships
     where kind = 'follow'
       and ((from_user_id = r.from_user_id and to_user_id = r.to_user_id)
         or (from_user_id = r.to_user_id   and to_user_id = r.from_user_id));
  end if;

  delete from public.user_relationships where id = p_request_id;
end;
$$;
grant execute on function public.respond_friend_request(uuid, boolean) to authenticated;

-- Unfriend
create or replace function public.unfriend(p_other_user uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not authenticated'; end if;
  delete from public.user_relationships
   where kind = 'friend'
     and ((from_user_id = me and to_user_id = p_other_user)
       or (from_user_id = p_other_user and to_user_id = me));
end;
$$;
grant execute on function public.unfriend(uuid) to authenticated;

-- Follow / unfollow
create or replace function public.follow_user(p_to_user uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  me uuid := auth.uid();
  v_inst uuid; v_other_inst uuid;
begin
  if me is null then raise exception 'not authenticated'; end if;
  if p_to_user = me then raise exception 'cannot follow yourself'; end if;

  select institution_id into v_inst       from public.profiles where id = me;
  select institution_id into v_other_inst from public.profiles where id = p_to_user;
  if v_inst is null or v_other_inst is null or v_inst <> v_other_inst then
    raise exception 'user is not at your institution';
  end if;

  if exists (
    select 1 from public.user_relationships
    where kind = 'block' and from_user_id = p_to_user and to_user_id = me
  ) then raise exception 'cannot follow'; end if;

  insert into public.user_relationships (from_user_id, to_user_id, kind)
  values (me, p_to_user, 'follow')
  on conflict do nothing;
end;
$$;
grant execute on function public.follow_user(uuid) to authenticated;

create or replace function public.unfollow_user(p_to_user uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not authenticated'; end if;
  delete from public.user_relationships
   where kind = 'follow' and from_user_id = me and to_user_id = p_to_user;
end;
$$;
grant execute on function public.unfollow_user(uuid) to authenticated;

-- Block / unblock (blocking also clears friend + follow rows)
create or replace function public.block_user(p_to_user uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not authenticated'; end if;
  if p_to_user = me then raise exception 'cannot block yourself'; end if;

  insert into public.user_relationships (from_user_id, to_user_id, kind)
  values (me, p_to_user, 'block')
  on conflict do nothing;

  delete from public.user_relationships
   where kind in ('friend','follow','friend_request')
     and ((from_user_id = me and to_user_id = p_to_user)
       or (from_user_id = p_to_user and to_user_id = me));
end;
$$;
grant execute on function public.block_user(uuid) to authenticated;

create or replace function public.unblock_user(p_to_user uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not authenticated'; end if;
  delete from public.user_relationships
   where kind = 'block' and from_user_id = me and to_user_id = p_to_user;
end;
$$;
grant execute on function public.unblock_user(uuid) to authenticated;

-- ============================================================
-- Read RPC: people at my institution with my relationship status
-- ============================================================
create or replace function public.people_directory(p_search text default null)
returns table (
  user_id uuid,
  full_name text,
  email text,
  role text,
  avatar_url text,
  status text,
  friendship text,         -- 'self','friend','request_sent','request_received','blocked_by_me','blocked_me','none'
  is_following boolean,
  follows_me boolean
)
language sql stable security definer set search_path = public
as $$
  with me_row as (select auth.uid() as id)
  select
    p.id, p.full_name, p.email, p.role, p.avatar_url, p.status,
    case
      when p.id = (select id from me_row) then 'self'
      when exists (select 1 from public.user_relationships r
                   where r.kind='block' and r.from_user_id = (select id from me_row) and r.to_user_id = p.id) then 'blocked_by_me'
      when exists (select 1 from public.user_relationships r
                   where r.kind='block' and r.from_user_id = p.id and r.to_user_id = (select id from me_row)) then 'blocked_me'
      when exists (select 1 from public.user_relationships r
                   where r.kind='friend'
                     and ((r.from_user_id = (select id from me_row) and r.to_user_id = p.id)
                       or (r.from_user_id = p.id and r.to_user_id = (select id from me_row)))) then 'friend'
      when exists (select 1 from public.user_relationships r
                   where r.kind='friend_request' and r.from_user_id = (select id from me_row) and r.to_user_id = p.id) then 'request_sent'
      when exists (select 1 from public.user_relationships r
                   where r.kind='friend_request' and r.from_user_id = p.id and r.to_user_id = (select id from me_row)) then 'request_received'
      else 'none'
    end as friendship,
    exists (select 1 from public.user_relationships r
            where r.kind='follow' and r.from_user_id = (select id from me_row) and r.to_user_id = p.id) as is_following,
    exists (select 1 from public.user_relationships r
            where r.kind='follow' and r.from_user_id = p.id and r.to_user_id = (select id from me_row)) as follows_me
  from public.profiles p
  where p.institution_id = (select institution_id from public.profiles where id = (select id from me_row))
    and p.id <> (select id from me_row)
    and (
      p_search is null
      or p.full_name ilike '%' || p_search || '%'
      or p.email     ilike '%' || p_search || '%'
    )
  order by p.full_name;
$$;
grant execute on function public.people_directory(text) to authenticated;
