-- ============================================================
-- Migration 0017 — Allow any authenticated user with
-- community.create (at any scope) to create an interest community.
-- The previous policy required institution scope, which students
-- don't have (their community.create is scoped to self).
-- ============================================================

drop policy if exists communities_insert on public.communities;

create policy communities_insert on public.communities
  for insert to authenticated
  with check (
    kind = 'interest'
    and membership_mode = 'open'
    and created_by = auth.uid()
    and public.has_permission('community.create')
  );
