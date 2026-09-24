-- ============================================================
-- Migration 0009b — MAU dev seed
-- Session, levels (100–500), BSc CS programme, courses, curriculum.
-- Idempotent.
-- ============================================================

insert into public.academic_sessions (institution_id, name, start_date, end_date, is_current)
select id, '2026/2027', '2026-09-01', '2027-08-31', true
from public.institutions where slug = 'mau'
on conflict (institution_id, name) do nothing;

update public.institutions
set current_session_id = (
  select id from public.academic_sessions
  where institution_id = institutions.id and is_current = true
  limit 1
)
where slug = 'mau';

insert into public.levels (institution_id, ordinal, display_name)
select i.id, x.ord, x.name
from public.institutions i
cross join (values
  (100, '100 Level'),
  (200, '200 Level'),
  (300, '300 Level'),
  (400, '400 Level'),
  (500, '500 Level')
) as x(ord, name)
where i.slug = 'mau'
on conflict (institution_id, ordinal) do nothing;

insert into public.programmes (department_id, name, code, duration_years)
select d.id, 'BSc Computer Science', 'BSC-CS', 4
from public.departments d
join public.faculties f on f.id = d.faculty_id
join public.institutions i on i.id = f.institution_id
where i.slug = 'mau' and d.code = 'CSC'
on conflict (department_id, name) do nothing;

insert into public.courses (institution_id, department_id, code, title, credits, level_ordinal, semester)
select i.id, d.id, x.code, x.title, x.credits, x.level, x.sem
from public.institutions i
join public.faculties   f on f.institution_id = i.id
join public.departments d on d.faculty_id = f.id
cross join (values
  ('CSC 101', 'Introduction to Computer Science',   3::smallint, 100::smallint, 1::smallint),
  ('CSC 102', 'Computer Hardware Fundamentals',     3,           100,           2),
  ('CSC 201', 'Programming I',                       3,           200,           1),
  ('CSC 202', 'Programming II',                      3,           200,           2),
  ('CSC 301', 'Data Structures',                     3,           300,           1),
  ('CSC 302', 'Algorithms',                          3,           300,           2),
  ('CSC 305', 'Database Systems',                    3,           300,           1),
  ('CSC 307', 'Computer Networks',                   3,           300,           2),
  ('CSC 309', 'Operating Systems',                   3,           300,           1),
  ('CSC 401', 'Software Engineering',                3,           400,           1),
  ('CSC 403', 'Artificial Intelligence',             3,           400,           2)
) as x(code, title, credits, level, sem)
where i.slug = 'mau' and d.code = 'CSC'
on conflict (institution_id, code) do nothing;

insert into public.programme_courses (programme_id, level_ordinal, semester, course_id, is_required)
select p.id, c.level_ordinal, c.semester, c.id, true
from public.programmes p
join public.departments d on d.id = p.department_id
join public.faculties   f on f.id = d.faculty_id
join public.courses     c on c.institution_id = f.institution_id and c.department_id = d.id
where p.code = 'BSC-CS'
  and c.level_ordinal in (200, 300, 400)
on conflict (programme_id, level_ordinal, semester, course_id) do nothing;
