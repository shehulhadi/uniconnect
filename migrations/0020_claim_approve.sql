-- ============================================================
-- Migration 0020 — Lecturer claim → approve flow
-- ============================================================

-- 1. Extend verification_requests
alter table public.verification_requests
  add column if not exists claimed_role text,
  add column if not exists department_id uuid references public.departments(id) on delete set null,
  add column if not exists escalated_at timestamptz,
  add column if not exists rejection_reason text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'verification_requests_claimed_role_check') then
    alter table public.verification_requests
      add constraint verification_requests_claimed_role_check
      check (claimed_role is null or claimed_role in ('student','lecturer'));
  end if;
end $$;

-- 2. onboarding_set_academic: don't create LECTURER assignment yet
create or replace function public.onboarding_set_academic(
  p_role text,
  p_faculty_id uuid,
  p_department_id uuid,
  p_programme_id uuid,
  p_level_id uuid,
  p_session_id uuid
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_step text;
  v_inst uuid;
  v_role_id uuid;
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  if p_role not in ('student','lecturer') then
    raise exception 'role must be student or lecturer';
  end if;

  select registration_step, institution_id into v_step, v_inst
    from public.profiles where id = v_user;
  if v_step is null then raise exception 'profile not found'; end if;
  if v_step = 'complete' then raise exception 'onboarding already complete'; end if;
  if v_step <> 'academic' then raise exception 'wrong step (expected academic, got %)', v_step; end if;
  if v_inst is null then raise exception 'institution not set'; end if;

  if not exists (select 1 from public.faculties where id = p_faculty_id and institution_id = v_inst)
    then raise exception 'invalid faculty'; end if;
  if not exists (select 1 from public.departments d join public.faculties f on f.id = d.faculty_id
                 where d.id = p_department_id and f.id = p_faculty_id)
    then raise exception 'invalid department'; end if;
  if not exists (select 1 from public.academic_sessions where id = p_session_id and institution_id = v_inst)
    then raise exception 'invalid session'; end if;

  if p_role = 'student' then
    if p_programme_id is null or p_level_id is null then
      raise exception 'programme and level required for students';
    end if;
    if not exists (select 1 from public.programmes where id = p_programme_id and department_id = p_department_id)
      then raise exception 'invalid programme'; end if;
    if not exists (select 1 from public.levels where id = p_level_id and institution_id = v_inst)
      then raise exception 'invalid level'; end if;
  else
    if p_programme_id is not null or p_level_id is not null then
      raise exception 'lecturers do not have programme or level';
    end if;
  end if;

  update public.profiles
    set role              = p_role,
        faculty_id        = p_faculty_id,
        department_id     = p_department_id,
        programme_id      = p_programme_id,
        level_id          = p_level_id,
        session_id        = p_session_id,
        registration_step = 'verification'
    where id = v_user;

  -- Only students get their role assignment immediately.
  -- Lecturers wait for approval.
  if p_role = 'student' then
    select id into v_role_id from public.role_definitions where name = 'STUDENT';
    if v_role_id is not null then
      insert into public.user_role_assignments (user_id, role_id, scope_type, scope_id, status)
      values (v_user, v_role_id, 'institution', v_inst, 'active')
      on conflict do nothing;
    end if;
  end if;
end;
$$;
grant execute on function public.onboarding_set_academic(text, uuid, uuid, uuid, uuid, uuid) to authenticated;

-- 3. submit_verification: route to HOD (or UNI_ADMIN fallback)
create or replace function public.submit_verification()
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_profile record;
  v_method text;
  v_req_id uuid;
  v_email_conf timestamptz;
  v_initial_status text := 'pending';
  v_approver record;
  v_hod_count int := 0;
  v_approver_names text;
begin
  if v_user is null then raise exception 'not authenticated'; end if;

  select id, institution_id, faculty_id, department_id, programme_id,
         level_id, session_id, matric_no, staff_no, role, full_name
    into v_profile from public.profiles where id = v_user;

  if v_profile.institution_id is null or v_profile.faculty_id is null
     or v_profile.department_id is null or v_profile.session_id is null then
    raise exception 'academic identity incomplete';
  end if;
  if v_profile.role = 'student' and (v_profile.programme_id is null or v_profile.level_id is null) then
    raise exception 'academic identity incomplete';
  end if;

  select coalesce(verification_method, 'email')
    into v_method from public.institutions where id = v_profile.institution_id;

  -- Students: email auto-verify as before
  if v_profile.role = 'student' then
    if v_method = 'email' then
      select email_confirmed_at into v_email_conf from auth.users where id = v_user;
      if v_email_conf is not null then v_initial_status := 'verified'; end if;
    end if;

    select id into v_req_id from public.verification_requests
      where user_id = v_user and status in ('pending','needs_review') limit 1;
    if v_req_id is not null then return v_req_id; end if;

    insert into public.verification_requests (
      user_id, institution_id, method, submitted_data, status, decided_at,
      claimed_role, department_id
    ) values (
      v_user, v_profile.institution_id, v_method,
      jsonb_build_object(
        'role', v_profile.role, 'full_name', v_profile.full_name,
        'faculty_id', v_profile.faculty_id, 'department_id', v_profile.department_id,
        'programme_id', v_profile.programme_id, 'level_id', v_profile.level_id,
        'session_id', v_profile.session_id, 'matric_no', v_profile.matric_no
      ),
      v_initial_status,
      case when v_initial_status = 'verified' then now() else null end,
      'student', v_profile.department_id
    )
    returning id into v_req_id;

    update public.profiles
      set verification_status = v_initial_status,
          registration_step = case
            when v_initial_status = 'verified' then 'enrollment'
            else 'verification'
          end
      where id = v_user;

    return v_req_id;
  end if;

  -- Lecturers: create pending request and notify approvers
  if v_profile.role = 'lecturer' then
    select id into v_req_id from public.verification_requests
      where user_id = v_user and status in ('pending','needs_review') limit 1;
    if v_req_id is not null then return v_req_id; end if;

    insert into public.verification_requests (
      user_id, institution_id, method, submitted_data, status,
      claimed_role, department_id
    ) values (
      v_user, v_profile.institution_id, 'admin_review',
      jsonb_build_object(
        'role', v_profile.role, 'full_name', v_profile.full_name,
        'faculty_id', v_profile.faculty_id, 'department_id', v_profile.department_id,
        'session_id', v_profile.session_id, 'staff_no', v_profile.staff_no
      ),
      'pending',
      'lecturer', v_profile.department_id
    )
    returning id into v_req_id;

    -- Find HODs of this department first
    select count(*) into v_hod_count from public.user_role_assignments ura
      join public.role_definitions rd on rd.id = ura.role_id
     where rd.name = 'HOD'
       and ura.status = 'active'
       and ura.scope_type = 'department'
       and ura.scope_id = v_profile.department_id;

    if v_hod_count > 0 then
      for v_approver in
        select ura.user_id from public.user_role_assignments ura
          join public.role_definitions rd on rd.id = ura.role_id
         where rd.name = 'HOD'
           and ura.status = 'active'
           and ura.scope_type = 'department'
           and ura.scope_id = v_profile.department_id
      loop
        insert into public.notifications (user_id, kind, title, body, link)
        values (
          v_approver.user_id, 'system',
          'Lecturer verification request',
          v_profile.full_name || ' has requested lecturer access to your department.',
          'approvals.html'
        );
      end loop;
    else
      for v_approver in
        select ura.user_id from public.user_role_assignments ura
          join public.role_definitions rd on rd.id = ura.role_id
         where rd.name = 'UNIVERSITY_ADMIN'
           and ura.status = 'active'
           and ura.scope_type = 'institution'
           and ura.scope_id = v_profile.institution_id
      loop
        insert into public.notifications (user_id, kind, title, body, link)
        values (
          v_approver.user_id, 'system',
          'Lecturer verification request',
          v_profile.full_name || ' has requested lecturer access (no HOD for that department).',
          'approvals.html'
        );
      end loop;
    end if;

    update public.profiles
      set verification_status = 'pending',
          registration_step = 'verification'
      where id = v_user;

    return v_req_id;
  end if;

  raise exception 'unknown role: %', v_profile.role;
end;
$$;
grant execute on function public.submit_verification() to authenticated;

-- 4. list_pending_approvals — scoped queue
create or replace function public.list_pending_approvals()
returns table (
  request_id uuid,
  user_id uuid,
  full_name text,
  email text,
  claimed_role text,
  department_id uuid,
  department_name text,
  faculty_name text,
  institution_name text,
  staff_no text,
  submitted_at timestamptz
)
language plpgsql security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_is_hod boolean := false;
  v_hod_dept uuid;
  v_is_uni boolean := false;
  v_uni_inst uuid;
begin
  if v_user is null then raise exception 'not authenticated'; end if;

  -- Caller an HOD?
  select ura.scope_id into v_hod_dept
    from public.user_role_assignments ura
    join public.role_definitions rd on rd.id = ura.role_id
   where ura.user_id = v_user
     and rd.name = 'HOD'
     and ura.status = 'active'
     and ura.scope_type = 'department'
   limit 1;
  v_is_hod := v_hod_dept is not null;

  -- Caller a University Admin?
  select ura.scope_id into v_uni_inst
    from public.user_role_assignments ura
    join public.role_definitions rd on rd.id = ura.role_id
   where ura.user_id = v_user
     and rd.name = 'UNIVERSITY_ADMIN'
     and ura.status = 'active'
     and ura.scope_type = 'institution'
   limit 1;
  v_is_uni := v_uni_inst is not null;

  return query
  select
    vr.id, p.id, p.full_name, p.email, vr.claimed_role,
    vr.department_id, d.name, f.name, i.name, p.staff_no, vr.created_at
  from public.verification_requests vr
  join public.profiles p on p.id = vr.user_id
  left join public.departments  d on d.id = vr.department_id
  left join public.faculties    f on f.id = d.faculty_id
  left join public.institutions i on i.id = vr.institution_id
  where vr.status = 'pending'
    and vr.claimed_role = 'lecturer'
    and (
      -- HOD sees their department
      (v_is_hod and vr.department_id = v_hod_dept)
      -- University Admin sees their institution ONLY IF the department has no HOD
      or (v_is_uni
          and vr.institution_id = v_uni_inst
          and not exists (
            select 1 from public.user_role_assignments ura
            join public.role_definitions rd on rd.id = ura.role_id
            where rd.name = 'HOD'
              and ura.status = 'active'
              and ura.scope_type = 'department'
              and ura.scope_id = vr.department_id
          ))
    )
  order by vr.created_at asc;
end;
$$;
grant execute on function public.list_pending_approvals() to authenticated;

-- 5. decide_verification — approve or reject
create or replace function public.decide_verification(
  p_request_id uuid,
  p_decision text,
  p_notes text default null
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_req record;
  v_user_dept uuid;
  v_user_inst uuid;
  v_role_id uuid;
  v_actor_is_hod boolean := false;
  v_actor_hod_dept uuid;
  v_actor_is_uni boolean := false;
  v_actor_uni_inst uuid;
  v_decided_status text;
begin
  if v_actor is null then raise exception 'not authenticated'; end if;
  if p_decision not in ('verified','rejected') then
    raise exception 'invalid decision';
  end if;

  select * into v_req from public.verification_requests where id = p_request_id;
  if v_req.id is null then raise exception 'request not found'; end if;
  if v_req.status not in ('pending','needs_review') then raise exception 'request already decided'; end if;

  select department_id, institution_id into v_user_dept, v_user_inst
    from public.profiles where id = v_req.user_id;

  -- Actor authorization
  select ura.scope_id into v_actor_hod_dept
    from public.user_role_assignments ura
    join public.role_definitions rd on rd.id = ura.role_id
   where ura.user_id = v_actor and rd.name = 'HOD' and ura.status = 'active'
     and ura.scope_type = 'department' limit 1;
  v_actor_is_hod := v_actor_hod_dept is not null and v_actor_hod_dept = v_user_dept;

  select ura.scope_id into v_actor_uni_inst
    from public.user_role_assignments ura
    join public.role_definitions rd on rd.id = ura.role_id
   where ura.user_id = v_actor and rd.name = 'UNIVERSITY_ADMIN' and ura.status = 'active'
     and ura.scope_type = 'institution' limit 1;
  v_actor_is_uni := v_actor_uni_inst is not null and v_actor_uni_inst = v_user_inst;

  if not (v_actor_is_hod or v_actor_is_uni) then
    raise exception 'not authorized to decide this request';
  end if;

  if p_decision = 'verified' then
    update public.verification_requests
      set status = 'verified', decided_by = v_actor, decided_at = now(),
          notes = coalesce(p_notes, notes)
      where id = p_request_id;

    update public.profiles
      set verification_status = 'verified',
          registration_step = 'enrollment'
      where id = v_req.user_id;

    select id into v_role_id from public.role_definitions where name = 'LECTURER';
    if v_role_id is not null then
      insert into public.user_role_assignments (user_id, role_id, scope_type, scope_id, status)
      values (v_req.user_id, v_role_id, 'department', v_user_dept, 'active')
      on conflict do nothing;
    end if;

    insert into public.notifications (user_id, kind, title, body, link)
    values (
      v_req.user_id, 'system',
      'Your lecturer access was approved',
      'Welcome to Matric. Your campus is ready.',
      'onboarding.html'
    );
  else
    update public.verification_requests
      set status = 'rejected', decided_by = v_actor, decided_at = now(),
          notes = coalesce(p_notes, notes),
          rejection_reason = coalesce(p_notes, 'No reason provided')
      where id = p_request_id;

    update public.profiles
      set verification_status = 'rejected',
          registration_step = 'academic'
      where id = v_req.user_id;

    insert into public.notifications (user_id, kind, title, body, link)
    values (
      v_req.user_id, 'system',
      'Your lecturer request was not approved',
      coalesce(p_notes, 'Please review your details and try again.'),
      'onboarding.html'
    );
  end if;

  insert into public.audit_logs (actor_user_id, action, target_type, target_id,
                                  scope_type, scope_id, metadata)
  values (
    v_actor, 'verification.' || p_decision,
    'verification_request', p_request_id,
    'institution', v_user_inst,
    jsonb_build_object('claimant', v_req.user_id, 'notes', p_notes)
  );
end;
$$;
grant execute on function public.decide_verification(uuid, text, text) to authenticated;
