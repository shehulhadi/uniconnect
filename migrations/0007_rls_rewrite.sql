-- ============================================================
-- Migration 0007 — RLS rewrite: permission + scope aware
-- Every policy now flows through has_permission_in_scope().
-- ============================================================

-- ---------- Helpers used only by policies ----------

create or replace function public.profile_scope(p_user_id uuid)
returns table (scope_type text, scope_id uuid)
language sql stable security definer set search_path = public
as $$
  select
    case
      when p.department_id is not null then 'department'
      when p.institution_id is not null then 'institution'
      else 'self'
    end,
    coalesce(p.department_id, p.institution_id, p.id)
  from public.profiles p
  where p.id = p_user_id;
$$;
grant execute on function public.profile_scope(uuid) to authenticated;

create or replace function public.community_scope(p_community_id uuid)
returns table (scope_type text, scope_id uuid)
language sql stable security definer set search_path = public
as $$
  select
    case
      when c.course_id     is not null then 'course'
      when c.programme_id  is not null then 'programme'
      when c.level_id      is not null then 'level'
      when c.department_id is not null then 'department'
      when c.faculty_id    is not null then 'faculty'
      else 'institution'
    end,
    coalesce(c.course_id, c.programme_id, c.level_id, c.department_id, c.faculty_id, c.institution_id)
  from public.communities c
  where c.id = p_community_id;
$$;
grant execute on function public.community_scope(uuid) to authenticated;

-- Legacy shim: keep is_admin() defined but it now delegates to RBAC.
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$ select public.has_permission('users.manage'); $$;

-- ============================================================
-- institutions
-- ============================================================
drop policy if exists institutions_select on public.institutions;
create policy institutions_select on public.institutions
  for select to authenticated using (true);

drop policy if exists institutions_admin_write on public.institutions;
drop policy if exists institutions_platform_manage on public.institutions;
create policy institutions_platform_manage on public.institutions
  for all to authenticated
  using (public.has_permission('platform.institutions.manage'))
  with check (public.has_permission('platform.institutions.manage'));

-- ============================================================
-- academic structure: faculties, departments, programmes,
-- academic_sessions, levels, courses, programme_courses,
-- course_assignments
-- ============================================================

-- faculties
drop policy if exists faculties_select on public.faculties;
drop policy if exists faculties_admin_write on public.faculties;
create policy faculties_select on public.faculties
  for select to authenticated
  using (public.same_institution(institution_id));
create policy faculties_insert on public.faculties
  for insert to authenticated
  with check (public.has_permission_in_scope('faculty.manage', 'institution', institution_id));
create policy faculties_update on public.faculties
  for update to authenticated
  using (public.has_permission_in_scope('faculty.manage', 'faculty', id))
  with check (public.has_permission_in_scope('faculty.manage', 'faculty', id));
create policy faculties_delete on public.faculties
  for delete to authenticated
  using (public.has_permission_in_scope('faculty.manage', 'faculty', id));

-- departments
drop policy if exists departments_select on public.departments;
drop policy if exists departments_admin_write on public.departments;
create policy departments_select on public.departments
  for select to authenticated
  using (
    exists (select 1 from public.faculties f
            where f.id = departments.faculty_id
              and public.same_institution(f.institution_id))
  );
create policy departments_insert on public.departments
  for insert to authenticated
  with check (
    exists (select 1 from public.faculties f
            where f.id = departments.faculty_id
              and public.has_permission_in_scope('department.manage', 'faculty', f.id))
  );
create policy departments_update on public.departments
  for update to authenticated
  using (public.has_permission_in_scope('department.manage', 'department', id))
  with check (public.has_permission_in_scope('department.manage', 'department', id));
create policy departments_delete on public.departments
  for delete to authenticated
  using (public.has_permission_in_scope('department.manage', 'department', id));

-- programmes
drop policy if exists programmes_select on public.programmes;
drop policy if exists programmes_admin_write on public.programmes;
create policy programmes_select on public.programmes
  for select to authenticated
  using (
    exists (
      select 1 from public.departments d
      join public.faculties f on f.id = d.faculty_id
      where d.id = programmes.department_id
        and public.same_institution(f.institution_id)
    )
  );
create policy programmes_insert on public.programmes
  for insert to authenticated
  with check (public.has_permission_in_scope('programme.manage', 'department', department_id));
create policy programmes_update on public.programmes
  for update to authenticated
  using (public.has_permission_in_scope('programme.manage', 'programme', id))
  with check (public.has_permission_in_scope('programme.manage', 'programme', id));
create policy programmes_delete on public.programmes
  for delete to authenticated
  using (public.has_permission_in_scope('programme.manage', 'programme', id));

-- academic_sessions
drop policy if exists academic_sessions_select on public.academic_sessions;
drop policy if exists academic_sessions_admin_write on public.academic_sessions;
create policy academic_sessions_select on public.academic_sessions
  for select to authenticated
  using (public.same_institution(institution_id));
create policy academic_sessions_insert on public.academic_sessions
  for insert to authenticated
  with check (public.has_permission_in_scope('session.manage', 'institution', institution_id));
create policy academic_sessions_update on public.academic_sessions
  for update to authenticated
  using (public.has_permission_in_scope('session.manage', 'institution', institution_id))
  with check (public.has_permission_in_scope('session.manage', 'institution', institution_id));
create policy academic_sessions_delete on public.academic_sessions
  for delete to authenticated
  using (public.has_permission_in_scope('session.manage', 'institution', institution_id));

-- levels
drop policy if exists levels_select on public.levels;
drop policy if exists levels_admin_write on public.levels;
create policy levels_select on public.levels
  for select to authenticated
  using (public.same_institution(institution_id));
create policy levels_insert on public.levels
  for insert to authenticated
  with check (public.has_permission_in_scope('level.manage', 'institution', institution_id));
create policy levels_update on public.levels
  for update to authenticated
  using (public.has_permission_in_scope('level.manage', 'institution', institution_id))
  with check (public.has_permission_in_scope('level.manage', 'institution', institution_id));
create policy levels_delete on public.levels
  for delete to authenticated
  using (public.has_permission_in_scope('level.manage', 'institution', institution_id));

-- courses
drop policy if exists courses_select on public.courses;
drop policy if exists courses_admin_write on public.courses;
create policy courses_select on public.courses
  for select to authenticated
  using (public.same_institution(institution_id));
create policy courses_insert on public.courses
  for insert to authenticated
  with check (public.has_permission_in_scope('course.create', 'institution', institution_id));
create policy courses_update on public.courses
  for update to authenticated
  using (
    public.has_permission_in_scope('course.manage', 'course', id)
    or public.has_permission_in_scope('course.manage', 'institution', institution_id)
  )
  with check (
    public.has_permission_in_scope('course.manage', 'course', id)
    or public.has_permission_in_scope('course.manage', 'institution', institution_id)
  );
create policy courses_delete on public.courses
  for delete to authenticated
  using (public.has_permission_in_scope('course.manage', 'institution', institution_id));

-- programme_courses
drop policy if exists programme_courses_select on public.programme_courses;
drop policy if exists programme_courses_admin_write on public.programme_courses;
create policy programme_courses_select on public.programme_courses
  for select to authenticated
  using (
    exists (
      select 1 from public.programmes p
      join public.departments d on d.id = p.department_id
      join public.faculties   f on f.id = d.faculty_id
      where p.id = programme_courses.programme_id
        and public.same_institution(f.institution_id)
    )
  );
create policy programme_courses_write on public.programme_courses
  for all to authenticated
  using (public.has_permission_in_scope('programme.manage', 'programme', programme_id))
  with check (public.has_permission_in_scope('programme.manage', 'programme', programme_id));

-- course_assignments
drop policy if exists course_assignments_select on public.course_assignments;
drop policy if exists course_assignments_admin_write on public.course_assignments;
create policy course_assignments_select on public.course_assignments
  for select to authenticated
  using (
    lecturer_id = auth.uid()
    or exists (
      select 1 from public.courses c
      where c.id = course_assignments.course_id
        and public.same_institution(c.institution_id)
    )
  );
create policy course_assignments_write on public.course_assignments
  for all to authenticated
  using (
    public.has_permission_in_scope('course.assign_lecturer', 'course', course_id)
    or public.has_permission_in_scope('course.assign_lecturer', 'institution',
         (select institution_id from public.courses where id = course_id))
  )
  with check (
    public.has_permission_in_scope('course.assign_lecturer', 'course', course_id)
    or public.has_permission_in_scope('course.assign_lecturer', 'institution',
         (select institution_id from public.courses where id = course_id))
  );

-- ============================================================
-- profiles
-- ============================================================
drop policy if exists profiles_select on public.profiles;
drop policy if exists profiles_update_self on public.profiles;
drop policy if exists profiles_admin_write on public.profiles;

create policy profiles_select on public.profiles
  for select to authenticated
  using (
    id = auth.uid()
    or public.same_institution(institution_id)
    or exists (
      select 1 from public.profile_scope(profiles.id) s
      where public.has_permission_in_scope('users.read', s.scope_type, s.scope_id)
    )
  );

-- Self-update cannot escalate role or change institution (existing rule kept).
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (
    id = auth.uid()
    and role = public.current_role()
    and institution_id is not distinct from public.current_institution()
  );

create policy profiles_admin_update on public.profiles
  for update to authenticated
  using (
    exists (
      select 1 from public.profile_scope(profiles.id) s
      where public.has_permission_in_scope('users.manage', s.scope_type, s.scope_id)
    )
  )
  with check (
    exists (
      select 1 from public.profile_scope(profiles.id) s
      where public.has_permission_in_scope('users.manage', s.scope_type, s.scope_id)
    )
  );

-- ============================================================
-- announcements
-- ============================================================
drop policy if exists announcements_select on public.announcements;
drop policy if exists announcements_insert on public.announcements;
drop policy if exists announcements_update on public.announcements;
drop policy if exists announcements_delete on public.announcements;

create policy announcements_select on public.announcements
  for select to authenticated
  using (public.has_permission_in_scope('announcements.read', 'institution', institution_id));

create policy announcements_insert on public.announcements
  for insert to authenticated
  with check (
    author_id = auth.uid()
    and public.has_permission_in_scope('announcements.create', 'institution', institution_id)
  );

create policy announcements_update on public.announcements
  for update to authenticated
  using (
    public.has_permission_in_scope('announcements.manage', 'institution', institution_id)
    or (author_id = auth.uid()
        and public.has_permission_in_scope('announcements.create', 'institution', institution_id))
  )
  with check (
    public.has_permission_in_scope('announcements.manage', 'institution', institution_id)
    or (author_id = auth.uid()
        and public.has_permission_in_scope('announcements.create', 'institution', institution_id))
  );

create policy announcements_delete on public.announcements
  for delete to authenticated
  using (public.has_permission_in_scope('announcements.manage', 'institution', institution_id));

-- ============================================================
-- materials
-- ============================================================
drop policy if exists materials_select on public.materials;
drop policy if exists materials_insert on public.materials;
drop policy if exists materials_update on public.materials;
drop policy if exists materials_delete on public.materials;

create policy materials_select on public.materials
  for select to authenticated
  using (public.has_permission_in_scope('materials.read', 'institution', institution_id));

create policy materials_insert on public.materials
  for insert to authenticated
  with check (
    uploader_id = auth.uid()
    and public.has_permission_in_scope('materials.create', 'institution', institution_id)
  );

create policy materials_update on public.materials
  for update to authenticated
  using (
    public.has_permission_in_scope('materials.manage', 'institution', institution_id)
    or (uploader_id = auth.uid()
        and public.has_permission_in_scope('materials.create', 'institution', institution_id))
  )
  with check (
    public.has_permission_in_scope('materials.manage', 'institution', institution_id)
    or (uploader_id = auth.uid()
        and public.has_permission_in_scope('materials.create', 'institution', institution_id))
  );

create policy materials_delete on public.materials
  for delete to authenticated
  using (
    public.has_permission_in_scope('materials.manage', 'institution', institution_id)
    or uploader_id = auth.uid()
  );

-- ============================================================
-- communities / members / messages
-- ============================================================
drop policy if exists communities_select on public.communities;
drop policy if exists communities_insert on public.communities;
drop policy if exists communities_update on public.communities;
drop policy if exists communities_delete on public.communities;

create policy communities_select on public.communities
  for select to authenticated
  using (
    -- Interest communities in your institution
    (kind = 'interest' and public.same_institution(institution_id))
    -- Academic communities you belong to
    or exists (
      select 1 from public.community_members cm
      where cm.community_id = communities.id and cm.user_id = auth.uid()
    )
    -- Admins who manage this scope
    or exists (
      select 1 from public.community_scope(communities.id) s
      where public.has_permission_in_scope('community.manage', s.scope_type, s.scope_id)
    )
  );

create policy communities_insert on public.communities
  for insert to authenticated
  with check (
    kind = 'interest'
    and membership_mode = 'open'
    and created_by = auth.uid()
    and public.has_permission_in_scope('community.create', 'institution', institution_id)
  );

create policy communities_update on public.communities
  for update to authenticated
  using (
    (created_by = auth.uid() and kind = 'interest')
    or exists (
      select 1 from public.community_scope(communities.id) s
      where public.has_permission_in_scope('community.manage', s.scope_type, s.scope_id)
    )
  )
  with check (
    (created_by = auth.uid() and kind = 'interest' and membership_mode = 'open')
    or exists (
      select 1 from public.community_scope(communities.id) s
      where public.has_permission_in_scope('community.manage', s.scope_type, s.scope_id)
    )
  );

create policy communities_delete on public.communities
  for delete to authenticated
  using (
    (created_by = auth.uid() and kind = 'interest')
    or exists (
      select 1 from public.community_scope(communities.id) s
      where public.has_permission_in_scope('community.manage', s.scope_type, s.scope_id)
    )
  );

drop policy if exists community_members_select on public.community_members;
drop policy if exists community_members_join   on public.community_members;
drop policy if exists community_members_leave  on public.community_members;

create policy community_members_select on public.community_members
  for select to authenticated
  using (
    exists (
      select 1 from public.communities c
      where c.id = community_members.community_id
        and public.same_institution(c.institution_id)
    )
  );

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

create policy community_members_leave on public.community_members
  for delete to authenticated
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists community_messages_select on public.community_messages;
drop policy if exists community_messages_insert on public.community_messages;
drop policy if exists community_messages_delete on public.community_messages;

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

-- ============================================================
-- RBAC metadata tables (upgrade from interim policies in 0003)
-- ============================================================
drop policy if exists user_role_assignments_read_self on public.user_role_assignments;
create policy user_role_assignments_select on public.user_role_assignments
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.has_permission_in_scope('roles.read',
         case when scope_type = 'platform' then 'platform'
              when scope_type = 'self' then 'self'
              else scope_type end,
         coalesce(scope_id, user_id))
  );

drop policy if exists audit_logs_read_self on public.audit_logs;
create policy audit_logs_select on public.audit_logs
  for select to authenticated
  using (
    actor_user_id = auth.uid()
    or public.has_permission_in_scope('audit_logs.read',
         coalesce(scope_type, 'platform'),
         scope_id)
    or public.is_platform_admin()
  );

-- ============================================================
-- storage.objects — materials bucket
-- ============================================================
do $$
begin
  if exists (select 1 from pg_policies
             where schemaname='storage' and tablename='objects'
               and policyname='materials_read') then
    drop policy materials_read on storage.objects;
  end if;
  if exists (select 1 from pg_policies
             where schemaname='storage' and tablename='objects'
               and policyname='materials_upload') then
    drop policy materials_upload on storage.objects;
  end if;
  if exists (select 1 from pg_policies
             where schemaname='storage' and tablename='objects'
               and policyname='materials_delete_own') then
    drop policy materials_delete_own on storage.objects;
  end if;
end $$;

create policy materials_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'materials'
    and (storage.foldername(name))[1] ~ '^[0-9a-fA-F-]{36}$'
    and public.has_permission_in_scope(
      'materials.read', 'institution', ((storage.foldername(name))[1])::uuid)
  );

create policy materials_upload on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'materials'
    and (storage.foldername(name))[1] ~ '^[0-9a-fA-F-]{36}$'
    and public.has_permission_in_scope(
      'materials.create', 'institution', ((storage.foldername(name))[1])::uuid)
  );

create policy materials_delete_own on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'materials'
    and (storage.foldername(name))[1] ~ '^[0-9a-fA-F-]{36}$'
    and (
      owner = auth.uid()
      or public.has_permission_in_scope(
        'materials.manage', 'institution', ((storage.foldername(name))[1])::uuid)
    )
  );

-- ============================================================
-- Self-test: exercise the helpers against a simulated user.
-- Rolls back all temporary rows.
-- ============================================================
do $$
declare
  v_user uuid := (select id from public.profiles limit 1);
  v_other uuid := (select id from public.profiles offset 1 limit 1);
  v_inst uuid := (select id from public.institutions limit 1);
  v_role_student uuid := (select id from public.role_definitions where name='STUDENT');
  v_role_admin   uuid := (select id from public.role_definitions where name='UNIVERSITY_ADMIN');
  v_pass int := 0;
  v_fail int := 0;
  function_check boolean;
begin
  if v_user is null or v_inst is null then
    raise notice 'self-test skipped (not enough data)';
    return;
  end if;

  -- Simulate the user
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_user)::text, true);

  -- Ensure a clean state for this user
  delete from public.user_role_assignments
    where user_id = v_user
      and role_id in (v_role_student, v_role_admin);

  -- Test A: student at self scope
  insert into public.user_role_assignments
    (user_id, role_id, scope_type, scope_id, status)
  values (v_user, v_role_student, 'self', v_user, 'active');

  select public.has_permission('profile.read_self') into function_check;
  if function_check then v_pass := v_pass+1;
  else v_fail := v_fail+1; raise notice 'FAIL: student should have profile.read_self';
  end if;

  select public.has_permission('announcements.publish') into function_check;
  if not function_check then v_pass := v_pass+1;
  else v_fail := v_fail+1; raise notice 'FAIL: student should NOT have announcements.publish';
  end if;

  select public.has_permission_in_scope('users.manage', 'institution', v_inst)
    into function_check;
  if not function_check then v_pass := v_pass+1;
  else v_fail := v_fail+1; raise notice 'FAIL: student should NOT have users.manage at institution';
  end if;

  delete from public.user_role_assignments
    where user_id = v_user and role_id = v_role_student;

  -- Test B: university admin at institution scope satisfies narrow scope checks
  insert into public.user_role_assignments
    (user_id, role_id, scope_type, scope_id, status)
  values (v_user, v_role_admin, 'institution', v_inst, 'active');

  select public.has_permission_in_scope('materials.manage', 'institution', v_inst)
    into function_check;
  if function_check then v_pass := v_pass+1;
  else v_fail := v_fail+1; raise notice 'FAIL: admin should have materials.manage at institution';
  end if;

  select public.has_permission('platform.institutions.manage') into function_check;
  if not function_check then v_pass := v_pass+1;
  else v_fail := v_fail+1; raise notice 'FAIL: institution admin should NOT have platform permission';
  end if;

  select public.is_platform_admin() into function_check;
  if not function_check then v_pass := v_pass+1;
  else v_fail := v_fail+1; raise notice 'FAIL: institution admin should NOT be platform admin';
  end if;

  -- Clean up
  delete from public.user_role_assignments
    where user_id = v_user and role_id = v_role_admin;

  raise notice 'self-test: % pass, % fail', v_pass, v_fail;
end $$;
