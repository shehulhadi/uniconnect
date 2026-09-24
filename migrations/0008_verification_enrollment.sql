-- ============================================================
-- Migration 0008 — Verification + Enrollment engine
--
-- Adds:
--   verification_requests
--   enrollments
--   course_enrollments
--
-- RPCs:
--   submit_verification()  — user submits academic identity for review
--   run_enrollment()       — idempotent engine that turns verified
--                            academic identity into membership
--
-- All writes go through security definer functions. Authenticated
-- users have no direct INSERT policy on these tables.
-- ============================================================

-- ---------- 1. verification_requests ----------
create table if not exists public.verification_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  institution_id uuid not null references public.institutions(id) on delete cascade,
  method text not null default 'email',
  submitted_data jsonb not null default '{}'::jsonb,
  status text not null default 'pending'
    check (status in ('pending','verified','needs_review','rejected')),
  decided_by uuid references public.profiles(id) on delete set null,
  decided_at timestamptz,
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists verification_requests_user_idx
  on public.verification_requests(user_id, created_at desc);
create index if not exists verification_requests_status_idx
  on public.verification_requests(institution_id, status, created_at desc);

alter table public.verification_requests enable row level security;

drop policy if exists verification_select on public.verification_requests;
create policy verification_select on public.verification_requests
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.has_permission_in_scope('verification.read', 'institution', institution_id)
  );

-- No direct insert/update/delete policy — writes go through submit_verification()
-- and the admin RPC that approves/rejects.

grant select on public.verification_requests to authenticated;

-- ---------- 2. enrollments ----------
create table if not exists public.enrollments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  institution_id uuid not null references public.institutions(id) on delete cascade,
  faculty_id uuid references public.faculties(id) on delete set null,
  department_id uuid references public.departments(id) on delete set null,
  programme_id uuid references public.programmes(id) on delete set null,
  level_id uuid references public.levels(id) on delete set null,
  session_id uuid references public.academic_sessions(id) on delete set null,
  status text not null default 'active'
    check (status in ('active','completed','suspended')),
  source text not null default 'auto'
    check (source in ('auto','admin')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, institution_id, session_id)
);

create index if not exists enrollments_user_idx
  on public.enrollments(user_id, status);
create index if not exists enrollments_inst_idx
  on public.enrollments(institution_id, session_id);

alter table public.enrollments enable row level security;

drop policy if exists enrollments_select on public.enrollments;
create policy enrollments_select on public.enrollments
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.has_permission_in_scope('enrollment.read', 'institution', institution_id)
  );

grant select on public.enrollments to authenticated;

-- ---------- 3. course_enrollments ----------
create table if not exists public.course_enrollments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  course_id uuid not null references public.courses(id) on delete cascade,
  session_id uuid not null references public.academic_sessions(id) on delete cascade,
  role text not null default 'student' check (role in ('student','lecturer')),
  status text not null default 'active' check (status in ('active','completed','dropped')),
  source text not null default 'auto' check (source in ('auto','admin')),
  created_at timestamptz not null default now(),
  unique (user_id, course_id, session_id)
);

create index if not exists course_enrollments_user_idx
  on public.course_enrollments(user_id, session_id, status);
create index if not exists course_enrollments_course_idx
  on public.course_enrollments(course_id, session_id, status);

alter table public.course_enrollments enable row level security;

drop policy if exists course_enrollments_select on public.course_enrollments;
create policy course_enrollments_select on public.course_enrollments
  for select to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.courses c
      where c.id = course_enrollments.course_id
        and public.has_permission_in_scope('enrollment.read', 'institution', c.institution_id)
    )
    or exists (
      select 1 from public.courses c
      where c.id = course_enrollments.course_id
        and public.has_permission_in_scope('course.manage', 'course', c.id)
    )
  );

grant select on public.course_enrollments to authenticated;

-- ---------- 4. Internal helper: ensure an auto community exists ----------
create or replace function public.ensure_auto_community(
  p_institution_id uuid,
  p_kind text,
  p_name text,
  p_faculty_id uuid default null,
  p_department_id uuid default null,
  p_programme_id uuid default null,
  p_level_id uuid default null,
  p_course_id uuid default null,
  p_session_id uuid default null
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid;
  v_match_column text;
  v_match_value uuid;
begin
  -- Find by the specific entity column for this kind
  case p_kind
    when 'institution' then v_match_column := 'institution_id'; v_match_value := p_institution_id;
    when 'faculty'     then v_match_column := 'faculty_id';     v_match_value := p_faculty_id;
    when 'department'  then v_match_column := 'department_id';  v_match_value := p_department_id;
    when 'programme'   then v_match_column := 'programme_id';   v_match_value := p_programme_id;
    when 'level'       then v_match_column := 'level_id';       v_match_value := p_level_id;
    when 'course'      then v_match_column := 'course_id';      v_match_value := p_course_id;
    else raise exception 'unknown community kind: %', p_kind;
  end case;

  execute format(
    'select id from public.communities where kind = %L and %I = $1 limit 1',
    p_kind, v_match_column
  ) into v_id using v_match_value;

  if v_id is not null then
    return v_id;
  end if;

  insert into public.communities (
    institution_id, name, kind, membership_mode,
    faculty_id, department_id, programme_id, level_id, course_id, session_id
  ) values (
    p_institution_id, p_name, p_kind, 'auto',
    p_faculty_id, p_department_id, p_programme_id, p_level_id, p_course_id, p_session_id
  )
  returning id into v_id;

  return v_id;
end;
$$;
grant execute on function public.ensure_auto_community(uuid, text, text, uuid, uuid, uuid, uuid, uuid, uuid) to authenticated;

-- ---------- 5. RPC: submit_verification ----------
create or replace function public.submit_verification()
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_profile record;
  v_method text;
  v_req_id uuid;
begin
  if v_user is null then raise exception 'not authenticated'; end if;

  select id, institution_id, faculty_id, department_id, programme_id,
         level_id, session_id, matric_no, full_name
    into v_profile
    from public.profiles
    where id = v_user;

  if v_profile.institution_id is null then
    raise exception 'institution not set on profile';
  end if;
  if v_profile.faculty_id is null or v_profile.department_id is null
     or v_profile.programme_id is null or v_profile.level_id is null
     or v_profile.session_id is null then
    raise exception 'academic identity incomplete';
  end if;

  select coalesce(verification_method, 'email')
    into v_method
    from public.institutions where id = v_profile.institution_id;

  -- Prevent duplicate open requests
  select id into v_req_id
    from public.verification_requests
    where user_id = v_user
      and status in ('pending','needs_review')
    limit 1;

  if v_req_id is not null then
    return v_req_id;
  end if;

  insert into public.verification_requests (
    user_id, institution_id, method, submitted_data, status
  ) values (
    v_user,
    v_profile.institution_id,
    v_method,
    jsonb_build_object(
      'full_name',      v_profile.full_name,
      'faculty_id',     v_profile.faculty_id,
      'department_id',  v_profile.department_id,
      'programme_id',   v_profile.programme_id,
      'level_id',       v_profile.level_id,
      'session_id',     v_profile.session_id,
      'matric_no',      v_profile.matric_no
    ),
    'pending'
  )
  returning id into v_req_id;

  update public.profiles
    set verification_status = 'pending',
        registration_step   = 'verification'
    where id = v_user;

  return v_req_id;
end;
$$;
grant execute on function public.submit_verification() to authenticated;

-- ---------- 6. RPC: approve_verification (admin-only) ----------
create or replace function public.approve_verification(
  p_request_id uuid,
  p_decision text,           -- 'verified' | 'rejected' | 'needs_review'
  p_notes text default null
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_req record;
begin
  if p_decision not in ('verified','rejected','needs_review') then
    raise exception 'invalid decision';
  end if;

  select * into v_req
    from public.verification_requests where id = p_request_id;
  if v_req.id is null then
    raise exception 'request not found';
  end if;

  if not public.has_permission_in_scope('verification.approve', 'institution', v_req.institution_id)
     and not public.has_permission_in_scope('verification.review', 'institution', v_req.institution_id) then
    raise exception 'not authorized';
  end if;

  update public.verification_requests
    set status     = p_decision,
        decided_by = v_actor,
        decided_at = now(),
        notes      = coalesce(p_notes, notes)
    where id = p_request_id;

  update public.profiles
    set verification_status = p_decision,
        registration_step   = case
          when p_decision = 'verified' then 'enrollment'
          else 'verification'
        end
    where id = v_req.user_id;

  insert into public.audit_logs (actor_user_id, action, target_type, target_id,
                                  scope_type, scope_id, metadata)
  values (
    v_actor, 'verification.' || p_decision,
    'verification_request', p_request_id,
    'institution', v_req.institution_id,
    jsonb_build_object('user_id', v_req.user_id, 'notes', p_notes)
  );
end;
$$;
grant execute on function public.approve_verification(uuid, text, text) to authenticated;

-- ---------- 7. RPC: run_enrollment ----------
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

  -- ---------- 7a. Upsert the enrollments row ----------
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

  -- ---------- 7b. Course enrollments from the curriculum ----------
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

    -- Every course gets its own auto community
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

  -- ---------- 7c. Auto communities: institution / faculty / department / programme / level ----------
  for v_community_id in
    select public.ensure_auto_community(
      p_institution_id, 'institution', v_inst.name
    )
    union all
    select public.ensure_auto_community(
      p_institution_id, 'faculty', v_fac.name, p_faculty_id := v_fac.id
    )
    union all
    select public.ensure_auto_community(
      p_institution_id, 'department', v_dept.name, p_faculty_id := v_fac.id, p_department_id := v_dept.id
    )
    union all
    select public.ensure_auto_community(
      p_institution_id, 'programme', v_prog.name, p_faculty_id := v_fac.id,
        p_department_id := v_dept.id, p_programme_id := v_prog.id
    )
    union all
    select public.ensure_auto_community(
      p_institution_id, 'level', v_level.display_name,
        p_faculty_id := v_fac.id, p_department_id := v_dept.id,
        p_programme_id := v_prog.id, p_level_id := v_level.id
    )
  loop
    insert into public.community_members (community_id, user_id, role, source)
    values (v_community_id, v_user, 'member', 'auto')
    on conflict do nothing;

    if found then
      v_new_communities := v_new_communities + 1;
    end if;
  end loop;

  -- ---------- 7d. Advance registration ----------
  update public.profiles
    set registration_step = 'complete',
        onboarded_at      = coalesce(onboarded_at, now())
    where id = v_user;

  -- ---------- 7e. Audit ----------
  insert into public.audit_logs (actor_user_id, action, target_type, target_id,
                                  scope_type, scope_id, metadata)
  values (
    v_user, 'enrollment.run', 'user', v_user,
    'institution', v_profile.institution_id,
    jsonb_build_object(
      'enrollment_id', v_enrollment_id,
      'new_courses',   v_new_courses,
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
