-- ============================================================
-- Migration 0007a — Fix RLS recursion between communities and
-- community_members.
--
-- Cause: communities_select queries community_members, and
-- community_members_select queries communities. Each RLS check
-- needs the other's RLS check, which needs the other's — infinite.
--
-- Fix: cross-table membership checks move into SECURITY DEFINER
-- helpers, which bypass RLS during their own reads.
-- ============================================================

create or replace function public.is_community_member(
  p_community_id uuid, p_user_id uuid
)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.community_members
    where community_id = p_community_id and user_id = p_user_id
  );
$$;
grant execute on function public.is_community_member(uuid, uuid) to authenticated;

create or replace function public.is_community_moderator(
  p_community_id uuid, p_user_id uuid
)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.community_members
    where community_id = p_community_id
      and user_id = p_user_id
      and role = 'moderator'
  );
$$;
grant execute on function public.is_community_moderator(uuid, uuid) to authenticated;

create or replace function public.community_in_my_institution(
  p_community_id uuid
)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.communities c
    where c.id = p_community_id
      and public.same_institution(c.institution_id)
  );
$$;
grant execute on function public.community_in_my_institution(uuid) to authenticated;

create or replace function public.community_is_open(p_community_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.communities c
    where c.id = p_community_id and c.membership_mode = 'open'
  );
$$;
grant execute on function public.community_is_open(uuid) to authenticated;

-- ---------- Rewrite community policies to use the helpers ----------

drop policy if exists communities_select on public.communities;
create policy communities_select on public.communities
  for select to authenticated
  using (
    public.is_community_member(communities.id, auth.uid())
    or (kind = 'interest' and public.same_institution(institution_id))
    or exists (
      select 1 from public.community_scope(communities.id) s
      where public.has_permission_in_scope('community.manage', s.scope_type, s.scope_id)
    )
  );

drop policy if exists community_members_select on public.community_members;
create policy community_members_select on public.community_members
  for select to authenticated
  using (public.community_in_my_institution(community_members.community_id));

drop policy if exists community_members_join on public.community_members;
create policy community_members_join on public.community_members
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and source = 'manual'
    and public.community_in_my_institution(community_members.community_id)
    and public.community_is_open(community_members.community_id)
  );

drop policy if exists community_members_leave on public.community_members;
create policy community_members_leave on public.community_members
  for delete to authenticated
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists community_messages_select on public.community_messages;
create policy community_messages_select on public.community_messages
  for select to authenticated
  using (public.is_community_member(community_messages.community_id, auth.uid()));

drop policy if exists community_messages_insert on public.community_messages;
create policy community_messages_insert on public.community_messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and public.is_community_member(community_messages.community_id, auth.uid())
  );

drop policy if exists community_messages_delete on public.community_messages;
create policy community_messages_delete on public.community_messages
  for delete to authenticated
  using (
    sender_id = auth.uid()
    or public.is_admin()
    or public.is_community_moderator(community_messages.community_id, auth.uid())
  );
