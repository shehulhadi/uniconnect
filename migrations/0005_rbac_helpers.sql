-- ============================================================
-- Migration 0005 — RBAC helper functions + self-scope fix
--
-- 1. Fix the scope pairing check so `self` carries scope_id = user_id.
-- 2. Add scope_ancestors(scope_type, scope_id) — the single
--    authoritative source of the scope hierarchy.
-- 3. Add has_permission / has_permission_in_scope /
--    has_role / has_role_in_scope / effective_permissions /
--    is_platform_admin.
--
-- IMPORTANT: every permission helper is SECURITY DEFINER.
-- Without that, the RLS policies on user_role_assignments and
-- communities would recurse into themselves during evaluation.
-- ============================================================

-- ---------- 1. Fix the self-scope pairing rule ----------
do $$
declare
  cname text;
begin
  for cname in
    select conname from pg_constraint
    where conrelid = 'public.user_role_assignments'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%scope_id is null%'
  loop
    execute format('alter table public.user_role_assignments drop constraint %I', cname);
  end loop;
end $$;

alter table public.user_role_assignments
  add constraint user_role_assignments_scope_pairing
  check (
    (scope_type = 'platform' and scope_id is null)
    or (scope_type <> 'platform' and scope_id is not null)
  );

-- ---------- 2. scope_ancestors ----------
-- Returns every (scope_type, scope_id) pair that a target belongs to,
-- including the target itself and terminating at ('platform', null).
create or replace function public.scope_ancestors(
  p_scope_type text,
  p_scope_id   uuid
)
returns table (scope_type text, scope_id uuid)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_inst  uuid;
  v_fac   uuid;
  v_dept  uuid;
  v_prog  uuid;
  v_level uuid;
  v_cour  uuid;
begin
  if p_scope_type = 'platform' then
    return query select 'platform'::text, null::uuid;
    return;
  end if;

  if p_scope_type = 'self' then
    return query select 'self'::text, p_scope_id;
    return;
  end if;

  -- Every entity matches itself.
  return query select p_scope_type, p_scope_id;

  if p_scope_type = 'institution' then
    null;

  elsif p_scope_type = 'level' then
    select institution_id into v_inst from public.levels where id = p_scope_id;

  elsif p_scope_type = 'faculty' then
    select institution_id into v_inst from public.faculties where id = p_scope_id;

  elsif p_scope_type = 'department' then
    select d.faculty_id, f.institution_id
      into v_fac, v_inst
      from public.departments d
      left join public.faculties f on f.id = d.faculty_id
      where d.id = p_scope_id;

  elsif p_scope_type = 'programme' then
    select d.faculty_id, f.institution_id, pr.department_id
      into v_fac, v_inst, v_dept
      from public.programmes pr
      left join public.departments d on d.id = pr.department_id
      left join public.faculties   f on f.id = d.faculty_id
      where pr.id = p_scope_id;

  elsif p_scope_type = 'course' then
    select c.institution_id, c.department_id, d.faculty_id
      into v_inst, v_dept, v_fac
      from public.courses c
      left join public.departments d on d.id = c.department_id
      where c.id = p_scope_id;

  elsif p_scope_type = 'community' then
    select cm.institution_id, cm.faculty_id, cm.department_id,
           cm.programme_id, cm.level_id, cm.course_id
      into v_inst, v_fac, v_dept, v_prog, v_level, v_cour
      from public.communities cm where cm.id = p_scope_id;
  end if;

  -- Emit ancestors narrowest → widest.
  if p_scope_type = 'community' then
    if v_cour  is not null then return query select 'course',      v_cour;  end if;
    if v_prog  is not null then return query select 'programme',   v_prog;  end if;
    if v_level is not null then return query select 'level',       v_level; end if;
    if v_dept  is not null then return query select 'department',  v_dept;  end if;
    if v_fac   is not null then return query select 'faculty',     v_fac;   end if;
    if v_inst  is not null then return query select 'institution', v_inst;  end if;
  elsif p_scope_type = 'course' then
    if v_dept  is not null then return query select 'department',  v_dept;  end if;
    if v_fac   is not null then return query select 'faculty',     v_fac;   end if;
    if v_inst  is not null then return query select 'institution', v_inst;  end if;
  elsif p_scope_type = 'programme' then
    if v_dept  is not null then return query select 'department',  v_dept;  end if;
    if v_fac   is not null then return query select 'faculty',     v_fac;   end if;
    if v_inst  is not null then return query select 'institution', v_inst;  end if;
  elsif p_scope_type = 'department' then
    if v_fac   is not null then return query select 'faculty',     v_fac;   end if;
    if v_inst  is not null then return query select 'institution', v_inst;  end if;
  elsif p_scope_type in ('faculty','level') then
    if v_inst  is not null then return query select 'institution', v_inst;  end if;
  end if;

  return query select 'platform'::text, null::uuid;
end;
$$;

-- ---------- 3. has_permission_in_scope ----------
-- The RLS workhorse. Returns true iff the current user has an active
-- role assignment that (a) grants the named permission and (b) has a
-- scope equal to, or an ancestor of, the requested target scope.
create or replace function public.has_permission_in_scope(
  p_permission text,
  p_scope_type text,
  p_scope_id   uuid
)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.user_role_assignments ura
    join public.role_permissions        rp on rp.role_id     = ura.role_id
    join public.permission_definitions  pd on pd.id          = rp.permission_id
    where ura.user_id = auth.uid()
      and ura.status  = 'active'
      and (ura.expires_at is null or ura.expires_at > now())
      and pd.name = p_permission
      and exists (
        select 1
        from public.scope_ancestors(p_scope_type, p_scope_id) a
        where a.scope_type = ura.scope_type
          and (a.scope_id is not distinct from ura.scope_id)
      )
  );
$$;

-- ---------- 4. has_permission (unscoped) ----------
-- UX-only. Never use in RLS. Answers "does the user hold this
-- permission anywhere at all?"
create or replace function public.has_permission(p_permission text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.user_role_assignments ura
    join public.role_permissions        rp on rp.role_id = ura.role_id
    join public.permission_definitions  pd on pd.id      = rp.permission_id
    where ura.user_id = auth.uid()
      and ura.status  = 'active'
      and (ura.expires_at is null or ura.expires_at > now())
      and pd.name = p_permission
  );
$$;

-- ---------- 5. has_role / has_role_in_scope ----------
create or replace function public.has_role(p_role text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.user_role_assignments ura
    join public.role_definitions r on r.id = ura.role_id
    where ura.user_id = auth.uid()
      and ura.status  = 'active'
      and (ura.expires_at is null or ura.expires_at > now())
      and r.name = p_role
  );
$$;

create or replace function public.has_role_in_scope(
  p_role text, p_scope_type text, p_scope_id uuid
)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.user_role_assignments ura
    join public.role_definitions r on r.id = ura.role_id
    where ura.user_id = auth.uid()
      and ura.status  = 'active'
      and (ura.expires_at is null or ura.expires_at > now())
      and r.name = p_role
      and exists (
        select 1
        from public.scope_ancestors(p_scope_type, p_scope_id) a
        where a.scope_type = ura.scope_type
          and (a.scope_id is not distinct from ura.scope_id)
      )
  );
$$;

-- ---------- 6. effective_permissions ----------
-- For a session bootstrap: every (permission, scope_type, scope_id)
-- the current user holds.
create or replace function public.effective_permissions()
returns table (permission text, scope_type text, scope_id uuid)
language sql stable security definer set search_path = public
as $$
  select distinct pd.name, ura.scope_type, ura.scope_id
  from public.user_role_assignments ura
  join public.role_permissions        rp on rp.role_id = ura.role_id
  join public.permission_definitions  pd on pd.id      = rp.permission_id
  where ura.user_id = auth.uid()
    and ura.status  = 'active'
    and (ura.expires_at is null or ura.expires_at > now());
$$;

-- ---------- 7. is_platform_admin ----------
create or replace function public.is_platform_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.user_role_assignments ura
    join public.role_definitions r on r.id = ura.role_id
    where ura.user_id = auth.uid()
      and ura.status  = 'active'
      and (ura.expires_at is null or ura.expires_at > now())
      and r.name = 'SUPER_ADMIN'
      and ura.scope_type = 'platform'
  );
$$;

-- ---------- 8. Grants ----------
grant execute on function public.scope_ancestors(text, uuid)                     to authenticated;
grant execute on function public.has_permission(text)                            to authenticated;
grant execute on function public.has_permission_in_scope(text, text, uuid)       to authenticated;
grant execute on function public.has_role(text)                                  to authenticated;
grant execute on function public.has_role_in_scope(text, text, uuid)             to authenticated;
grant execute on function public.effective_permissions()                         to authenticated;
grant execute on function public.is_platform_admin()                             to authenticated;
