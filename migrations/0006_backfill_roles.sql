-- ============================================================
-- Migration 0006 — Backfill existing profiles.role into
-- user_role_assignments.
--
-- Mapping:
--   student           → STUDENT           @ self          (scope_id = user id)
--   alumni            → ALUMNI            @ self
--   lecturer          → LECTURER          @ institution
--   senior-lecturer   → LECTURER          @ institution
--   staff             → STAFF             @ institution
--   hod               → HOD               @ department    (requires department_id)
--   admin             → UNIVERSITY_ADMIN  @ institution
--   leadership        → LEADERSHIP        @ institution
--
-- Idempotent: skips users who already have an active assignment.
-- Idempotent + safe: skips users whose profile lacks the scope_id
-- the target role needs (e.g. lecturer with no institution_id).
-- Raises NOTICE for skipped accounts so they can be fixed manually.
-- ============================================================

do $$
declare
  r record;
  v_role_id uuid;
  v_scope_type text;
  v_scope_id uuid;
  skipped text[] := '{}';
begin
  for r in
    select p.id, p.email, p.role, p.institution_id, p.department_id
    from public.profiles p
    where not exists (
      select 1 from public.user_role_assignments ura
      where ura.user_id = p.id and ura.status = 'active'
    )
  loop
    v_role_id    := null;
    v_scope_type := null;
    v_scope_id   := null;

    case r.role
      when 'student'         then v_scope_type := 'self';         v_scope_id := r.id;
      when 'alumni'          then v_scope_type := 'self';         v_scope_id := r.id;
      when 'lecturer'        then v_scope_type := 'institution';  v_scope_id := r.institution_id;
      when 'senior-lecturer' then v_scope_type := 'institution';  v_scope_id := r.institution_id;
      when 'staff'           then v_scope_type := 'institution';  v_scope_id := r.institution_id;
      when 'admin'           then v_scope_type := 'institution';  v_scope_id := r.institution_id;
      when 'leadership'      then v_scope_type := 'institution';  v_scope_id := r.institution_id;
      when 'hod'             then v_scope_type := 'department';   v_scope_id := r.department_id;
      else
        skipped := array_append(skipped, r.email || ' (unknown role: ' || coalesce(r.role,'null') || ')');
        continue;
    end case;

    if v_scope_id is null then
      skipped := array_append(skipped, r.email || ' (role=' || r.role || '; missing scope id)');
      continue;
    end if;

    select id into v_role_id from public.role_definitions where name = case r.role
      when 'student'         then 'STUDENT'
      when 'alumni'          then 'ALUMNI'
      when 'lecturer'        then 'LECTURER'
      when 'senior-lecturer' then 'LECTURER'
      when 'staff'           then 'STAFF'
      when 'admin'           then 'UNIVERSITY_ADMIN'
      when 'leadership'      then 'LEADERSHIP'
      when 'hod'             then 'HOD'
    end;

    if v_role_id is null then
      skipped := array_append(skipped, r.email || ' (role definition not found: ' || r.role || ')');
      continue;
    end if;

    insert into public.user_role_assignments
      (user_id, role_id, scope_type, scope_id, status)
    values
      (r.id, v_role_id, v_scope_type, v_scope_id, 'active');
  end loop;

  if array_length(skipped, 1) > 0 then
    raise notice 'Skipped % profiles (missing scope id or unknown role):', array_length(skipped, 1);
    raise notice '  %', array_to_string(skipped, E'\n  ');
  end if;
end $$;
