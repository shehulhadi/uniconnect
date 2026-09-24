-- ============================================================
-- Migration 0002 — Communities rename + scope
--
-- Renames:
--   groups         → communities
--   group_members  → community_members   (group_id → community_id)
--   group_messages → community_messages  (group_id → community_id)
--
-- Adds to communities:
--   kind            ('interest','institution','faculty','department','programme','level','course')
--   membership_mode ('open','auto')
--   faculty_id, department_id, programme_id, level_id, course_id, session_id
--
-- Adds to community_members:
--   source          ('auto','manual','admin')
--
-- New RLS:
--   Users can only self-join communities with membership_mode='open'
--   Only admins can insert communities with kind <> 'interest'
--   Auto communities are managed exclusively by the enrollment engine
-- ============================================================

-- ---------- 1. Rename tables (guarded) ----------
do $$
begin
  if exists (select 1 from information_schema.tables
             where table_schema='public' and table_name='groups') then
    alter table public.groups rename to communities;
  end if;
  if exists (select 1 from information_schema.tables
             where table_schema='public' and table_name='group_members') then
    alter table public.group_members rename to community_members;
  end if;
  if exists (select 1 from information_schema.tables
             where table_schema='public' and table_name='group_messages') then
    alter table public.group_messages rename to community_messages;
  end if;
end $$;

-- ---------- 2. Rename columns (guarded) ----------
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='community_members'
               and column_name='group_id') then
    alter table public.community_members rename column group_id to community_id;
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='community_messages'
               and column_name='group_id') then
    alter table public.community_messages rename column group_id to community_id;
  end if;
end $$;

-- ---------- 3. New columns on communities ----------
alter table public.communities
  add column if not exists kind text not null default 'interest',
  add column if not exists membership_mode text not null default 'open',
  add column if not exists faculty_id    uuid references public.faculties(id)         on delete cascade,
  add column if not exists department_id uuid references public.departments(id)       on delete cascade,
  add column if not exists programme_id  uuid references public.programmes(id)        on delete cascade,
  add column if not exists level_id      uuid references public.levels(id)            on delete cascade,
  add column if not exists course_id     uuid references public.courses(id)           on delete cascade,
  add column if not exists session_id    uuid references public.academic_sessions(id) on delete set null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='communities_kind_check') then
    alter table public.communities add constraint communities_kind_check
      check (kind in ('interest','institution','faculty','department','programme','level','course'));
  end if;
  if not exists (select 1 from pg_constraint where conname='communities_membership_mode_check') then
    alter table public.communities add constraint communities_membership_mode_check
      check (membership_mode in ('open','auto'));
  end if;
end $$;

-- Existing rows stay as interest/open — already the default.

-- ---------- 4. source on community_members ----------
alter table public.community_members
  add column if not exists source text not null default 'manual';

do $$
begin
  if not exists (select 1 from pg_constraint where conname='community_members_source_check') then
    alter table public.community_members add constraint community_members_source_check
      check (source in ('auto','manual','admin'));
  end if;
end $$;

-- ---------- 5. Uniqueness for auto-managed communities ----------
create unique index if not exists communities_unique_institution
  on public.communities (institution_id) where kind = 'institution';
create unique index if not exists communities_unique_faculty
  on public.communities (faculty_id) where kind = 'faculty';
create unique index if not exists communities_unique_department
  on public.communities (department_id) where kind = 'department';
create unique index if not exists communities_unique_programme
  on public.communities (programme_id) where kind = 'programme';
create unique index if not exists communities_unique_level
  on public.communities (level_id) where kind = 'level';
create unique index if not exists communities_unique_course
  on public.communities (course_id) where kind = 'course';

-- ---------- 6. Rebuild RLS on communities ----------
drop policy if exists groups_select on public.communities;
drop policy if exists groups_insert on public.communities;
drop policy if exists groups_update on public.communities;
drop policy if exists groups_delete on public.communities;

create policy communities_select on public.communities
  for select to authenticated
  using (public.is_admin() or public.same_institution(institution_id));

-- Users may only create interest communities. Academic ones are the
-- exclusive product of the enrollment engine (security definer RPC).
create policy communities_insert on public.communities
  for insert to authenticated
  with check (
    kind = 'interest'
    and membership_mode = 'open'
    and created_by = auth.uid()
    and public.same_institution(institution_id)
  );

-- Creators can edit their interest community. Admin can edit anything.
create policy communities_update on public.communities
  for update to authenticated
  using (
    public.is_admin()
    or (created_by = auth.uid() and kind = 'interest')
  )
  with check (
    public.is_admin()
    or (created_by = auth.uid() and kind = 'interest' and membership_mode = 'open')
  );

create policy communities_delete on public.communities
  for delete to authenticated
  using (
    public.is_admin()
    or (created_by = auth.uid() and kind = 'interest')
  );

-- ---------- 7. Rebuild RLS on community_members ----------
drop policy if exists group_members_select on public.community_members;
drop policy if exists group_members_join   on public.community_members;
drop policy if exists group_members_leave  on public.community_members;

create policy community_members_select on public.community_members
  for select to authenticated
  using (
    exists (
      select 1 from public.communities c
      where c.id = community_members.community_id
        and public.same_institution(c.institution_id)
    )
  );

-- The core rule: you may add yourself only to an OPEN community.
-- Auto communities are populated by the enrollment engine, never by the client.
create policy community_members_join on public.community_members
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and source = 'manual'
    and exists (
      select 1 from public.communities c
      where c.id = community_members.community_id
        and c.membership_mode = 'open'
        and public.same_institution(c.institution_id)
    )
  );

-- You can remove yourself from any community (leaving an auto one is allowed
-- but the enrollment engine will put you back on next run, which is correct:
-- you can't abandon your own department).
create policy community_members_leave on public.community_members
  for delete to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- ---------- 8. Rebuild RLS on community_messages ----------
drop policy if exists group_messages_select on public.community_messages;
drop policy if exists group_messages_insert on public.community_messages;
drop policy if exists group_messages_delete on public.community_messages;

create policy community_messages_select on public.community_messages
  for select to authenticated
  using (
    exists (
      select 1 from public.community_members cm
      where cm.community_id = community_messages.community_id
        and cm.user_id = auth.uid()
    )
  );

create policy community_messages_insert on public.community_messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.community_members cm
      where cm.community_id = community_messages.community_id
        and cm.user_id = auth.uid()
    )
  );

create policy community_messages_delete on public.community_messages
  for delete to authenticated
  using (
    sender_id = auth.uid()
    or public.is_admin()
    or exists (
      select 1 from public.community_members cm
      where cm.community_id = community_messages.community_id
        and cm.user_id = auth.uid()
        and cm.role = 'moderator'
    )
  );

-- ---------- 9. Grants (idempotent) ----------
grant select, insert, update, delete on public.communities         to authenticated;
grant select, insert, delete         on public.community_members   to authenticated;
grant select, insert, delete         on public.community_messages  to authenticated;
