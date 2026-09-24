-- ============================================================
-- Migration 0001 — Academic structure
-- Adds: academic_sessions, levels, courses, programme_courses, course_assignments
-- Adds columns: institutions.verification_method/student_id_pattern/current_session_id
--               profiles.level_id/session_id/registration_step/verification_status
-- Constraints: unique (institution_id, matric_no) and (institution_id, staff_no)
-- Updates handle_new_user() so new signups start at step 'account'
-- ============================================================

-- ---------- 1. Academic sessions ----------
create table if not exists public.academic_sessions (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  name text not null,
  start_date date,
  end_date date,
  is_current boolean not null default false,
  created_at timestamptz not null default now(),
  unique (institution_id, name)
);
create index if not exists academic_sessions_inst_current_idx
  on public.academic_sessions(institution_id, is_current);

-- ---------- 2. Levels ----------
create table if not exists public.levels (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  ordinal smallint not null check (ordinal between 1 and 999),
  display_name text not null,
  created_at timestamptz not null default now(),
  unique (institution_id, ordinal)
);

-- ---------- 3. Courses ----------
create table if not exists public.courses (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  department_id uuid references public.departments(id) on delete set null,
  code text not null,
  title text not null,
  credits smallint check (credits is null or credits between 0 and 20),
  level_ordinal smallint,
  semester smallint check (semester in (1,2)),
  created_at timestamptz not null default now(),
  unique (institution_id, code)
);
create index if not exists courses_inst_idx on public.courses(institution_id);
create index if not exists courses_dept_idx on public.courses(department_id);

-- ---------- 4. Programme courses (curriculum matrix) ----------
create table if not exists public.programme_courses (
  id uuid primary key default gen_random_uuid(),
  programme_id uuid not null references public.programmes(id) on delete cascade,
  level_ordinal smallint not null,
  semester smallint not null check (semester in (1,2)),
  course_id uuid not null references public.courses(id) on delete cascade,
  is_required boolean not null default true,
  created_at timestamptz not null default now(),
  unique (programme_id, level_ordinal, semester, course_id)
);
create index if not exists programme_courses_prog_idx
  on public.programme_courses(programme_id, level_ordinal, semester);

-- ---------- 5. Course assignments ----------
create table if not exists public.course_assignments (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  lecturer_id uuid not null references public.profiles(id) on delete cascade,
  session_id uuid not null references public.academic_sessions(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (course_id, session_id)
);
create index if not exists course_assignments_lect_idx
  on public.course_assignments(lecturer_id, session_id);

-- ---------- 6. New columns on institutions ----------
alter table public.institutions
  add column if not exists verification_method text not null default 'email',
  add column if not exists student_id_pattern text,
  add column if not exists current_session_id uuid references public.academic_sessions(id) on delete set null;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'institutions_verification_method_check'
  ) then
    alter table public.institutions
      add constraint institutions_verification_method_check
      check (verification_method in ('email','student_id','admin_review','database_match','hybrid'));
  end if;
end $$;

-- ---------- 7. New columns on profiles ----------
alter table public.profiles
  add column if not exists level_id uuid references public.levels(id) on delete set null,
  add column if not exists session_id uuid references public.academic_sessions(id) on delete set null,
  add column if not exists registration_step text not null default 'complete',
  add column if not exists verification_status text not null default 'verified';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_registration_step_check'
  ) then
    alter table public.profiles
      add constraint profiles_registration_step_check
      check (registration_step in ('account','institution','academic','verification','enrollment','complete'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'profiles_verification_status_check'
  ) then
    alter table public.profiles
      add constraint profiles_verification_status_check
      check (verification_status in ('unverified','pending','verified','needs_review','rejected'));
  end if;
end $$;

-- ---------- 8. Unique student / staff IDs per institution ----------
create unique index if not exists profiles_matric_unique
  on public.profiles (institution_id, matric_no)
  where matric_no is not null and institution_id is not null;

create unique index if not exists profiles_staff_unique
  on public.profiles (institution_id, staff_no)
  where staff_no is not null and institution_id is not null;

-- ---------- 9. Update handle_new_user to start new signups at 'account' ----------
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (
    id, email, full_name, registration_step, verification_status
  )
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    'account',
    'unverified'
  );
  return new;
end;
$$;

-- ---------- 10. RLS ----------
alter table public.academic_sessions  enable row level security;
alter table public.levels             enable row level security;
alter table public.courses            enable row level security;
alter table public.programme_courses  enable row level security;
alter table public.course_assignments enable row level security;

drop policy if exists academic_sessions_select on public.academic_sessions;
create policy academic_sessions_select on public.academic_sessions
  for select to authenticated
  using (public.is_admin() or public.same_institution(institution_id));

drop policy if exists academic_sessions_admin_write on public.academic_sessions;
create policy academic_sessions_admin_write on public.academic_sessions
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists levels_select on public.levels;
create policy levels_select on public.levels
  for select to authenticated
  using (public.is_admin() or public.same_institution(institution_id));

drop policy if exists levels_admin_write on public.levels;
create policy levels_admin_write on public.levels
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists courses_select on public.courses;
create policy courses_select on public.courses
  for select to authenticated
  using (public.is_admin() or public.same_institution(institution_id));

drop policy if exists courses_admin_write on public.courses;
create policy courses_admin_write on public.courses
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists programme_courses_select on public.programme_courses;
create policy programme_courses_select on public.programme_courses
  for select to authenticated
  using (
    public.is_admin()
    or exists (
      select 1
      from public.programmes p
      join public.departments d on d.id = p.department_id
      join public.faculties f on f.id = d.faculty_id
      where p.id = programme_courses.programme_id
        and public.same_institution(f.institution_id)
    )
  );

drop policy if exists programme_courses_admin_write on public.programme_courses;
create policy programme_courses_admin_write on public.programme_courses
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists course_assignments_select on public.course_assignments;
create policy course_assignments_select on public.course_assignments
  for select to authenticated
  using (
    public.is_admin()
    or exists (
      select 1 from public.courses c
      where c.id = course_assignments.course_id
        and public.same_institution(c.institution_id)
    )
  );

drop policy if exists course_assignments_admin_write on public.course_assignments;
create policy course_assignments_admin_write on public.course_assignments
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------- 11. Grants ----------
grant select, insert, update, delete on public.academic_sessions  to authenticated;
grant select, insert, update, delete on public.levels             to authenticated;
grant select, insert, update, delete on public.courses            to authenticated;
grant select, insert, update, delete on public.programme_courses  to authenticated;
grant select, insert, update, delete on public.course_assignments to authenticated;
