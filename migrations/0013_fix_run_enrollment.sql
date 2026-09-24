-- ============================================================
-- Migration 0013 — Fix run_enrollment(): ensure_auto_community calls
-- The 7c loop passed `p_institution_id` as an argument, but no such
-- variable exists in run_enrollment()'s scope. Replaced with explicit
-- v_profile.institution_id and rewritten as a sequence of direct calls
-- so no unbound name can be mistaken for a column reference.
-- ============================================================

create or replace function public.run_enrollment()
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_profile record;
  v_inst record;
  v_dept record;
  v_fac record;
  v_prog record;
  v_level record;
  v_session record;
  v_enrollment_id uuid;
  v_new_courses int := 0;
  v_new_communities int := 0;
  v_course record;
  v_community_id uuid;
  v_result jsonb;
begin
  if v_user is null then raise exception 'not authenticated'; end if;

  select * into v_profile from public.profiles where id = v_user;
  if v_profile.id is null then raise exception 'profile not found'; end if;

  if v_profile.verification_status not in ('verified') then
    raise exception 'verification not complete (status: %)', v_profile.verification_status;
  end if;

  if v_profile.institution_id is null
     or v_profile.department_id is null
     or v_profile.programme_id is null
     or v_profile.level_id is null
     or v_profile.session_id is null then
    raise exception 'academic identity incomplete';
  end if;

  select * into v_inst    from public.institutions      where id = v_profile.institution_id;
  select * into v_dept    from public.departments       where id = v_profile.department_id;
  select * into v_fac     from public.faculties         where id = v_dept.faculty_id;
  select * into v_prog    from public.programmes        where id = v_profile.programme_id;
  select * into v_level   from public.levels            where id = v_profile.level_id;
  select * into v_session from public.academic_sessions where id = v_profile.session_id;

  -- 7a. Upsert the enrollments row
  insert into public.enrollments (
    user_id, institution_id, faculty_id, department_id,
    programme_id, level_id, session_id, status, source
  ) values (
    v_user, v_profile.institution_id, v_dept.faculty_id, v_profile.department_id,
    v_profile.programme_id, v_profile.level_id, v_profile.session_id, 'active', 'auto'
  )
  on conflict (user_id, institution_id, session_id)
  do update set
    faculty_id    = excluded.faculty_id,
    department_id = excluded.department_id,
    programme_id  = excluded.programme_id,
    level_id      = excluded.level_id,
    updated_at    = now()
  returning id into v_enrollment_id;

  -- 7b. Course enrollments from the curriculum
  for v_course in
    select c.id, c.code, c.title, pc.semester
    from public.programme_courses pc
    join public.courses c on c.id = pc.course_id
    where pc.programme_id = v_profile.programme_id
      and pc.level_ordinal = v_level.ordinal
  loop
    insert into public.course_enrollments (
      user_id, course_id, session_id, role, status, source
    ) values (
      v_user, v_course.id, v_profile.session_id, 'student', 'active', 'auto'
    )
    on conflict (user_id, course_id, session_id) do nothing;

    if found then
      v_new_courses := v_new_courses + 1;
    end if;

    v_community_id := public.ensure_auto_community(
      p_institution_id := v_profile.institution_id,
      p_kind           := 'course',
      p_name           := v_course.code || ' — ' || v_course.title,
      p_department_id  := v_profile.department_id,
      p_course_id      := v_course.id,
      p_session_id     := v_profile.session_id
    );

    insert into public.community_members (community_id, user_id, role, source)
    values (v_community_id, v_user, 'member', 'auto')
    on conflict do nothing;

    if found then
      v_new_communities := v_new_communities + 1;
    end if;
  end loop;

  -- 7c. Auto academic communities, one at a time
  -- Institution
  v_community_id := public.ensure_auto_community(
    p_institution_id := v_profile.institution_id,
    p_kind           := 'institution',
    p_name           := v_inst.name
  );
  insert into public.community_members (community_id, user_id, role, source)
  values (v_community_id, v_user, 'member', 'auto')
  on conflict do nothing;
  if found then v_new_communities := v_new_communities + 1; end if;

  -- Faculty
  v_community_id := public.ensure_auto_community(
    p_institution_id := v_profile.institution_id,
    p_kind           := 'faculty',
    p_name           := v_fac.name,
    p_faculty_id     := v_fac.id
  );
  insert into public.community_members (community_id, user_id, role, source)
  values (v_community_id, v_user, 'member', 'auto')
  on conflict do nothing;
  if found then v_new_communities := v_new_communities + 1; end if;

  -- Department
  v_community_id := public.ensure_auto_community(
    p_institution_id := v_profile.institution_id,
    p_kind           := 'department',
    p_name           := v_dept.name,
    p_faculty_id     := v_fac.id,
    p_department_id  := v_dept.id
  );
  insert into public.community_members (community_id, user_id, role, source)
  values (v_community_id, v_user, 'member', 'auto')
  on conflict do nothing;
  if found then v_new_communities := v_new_communities + 1; end if;

  -- Programme
  v_community_id := public.ensure_auto_community(
    p_institution_id := v_profile.institution_id,
    p_kind           := 'programme',
    p_name           := v_prog.name,
    p_faculty_id     := v_fac.id,
    p_department_id  := v_dept.id,
    p_programme_id   := v_prog.id
  );
  insert into public.community_members (community_id, user_id, role, source)
  values (v_community_id, v_user, 'member', 'auto')
  on conflict do nothing;
  if found then v_new_communities := v_new_communities + 1; end if;

  -- Level
  v_community_id := public.ensure_auto_community(
    p_institution_id := v_profile.institution_id,
    p_kind           := 'level',
    p_name           := v_level.display_name,
    p_faculty_id     := v_fac.id,
    p_department_id  := v_dept.id,
    p_programme_id   := v_prog.id,
    p_level_id       := v_level.id
  );
  insert into public.community_members (community_id, user_id, role, source)
  values (v_community_id, v_user, 'member', 'auto')
  on conflict do nothing;
  if found then v_new_communities := v_new_communities + 1; end if;

  -- 7d. Advance registration
  update public.profiles
    set registration_step = 'complete',
        onboarded_at      = coalesce(onboarded_at, now())
    where id = v_user;

  -- 7e. Audit
  insert into public.audit_logs (actor_user_id, action, target_type, target_id,
                                  scope_type, scope_id, metadata)
  values (
    v_user, 'enrollment.run', 'user', v_user,
    'institution', v_profile.institution_id,
    jsonb_build_object(
      'enrollment_id',   v_enrollment_id,
      'new_courses',     v_new_courses,
      'new_communities', v_new_communities
    )
  );

  v_result := jsonb_build_object(
    'enrollment_id',   v_enrollment_id,
    'institution',     v_inst.name,
    'faculty',         v_fac.name,
    'department',      v_dept.name,
    'programme',       v_prog.name,
    'level',           v_level.display_name,
    'session',         v_session.name,
    'new_courses',     v_new_courses,
    'new_communities', v_new_communities,
    'already_enrolled', (v_new_courses = 0 and v_new_communities = 0)
  );

  return v_result;
end;
$$;
grant execute on function public.run_enrollment() to authenticated;
