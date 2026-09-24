-- ============================================================
-- Migration 0004 — RBAC seed
--
-- Seeds:
--   role_definitions        — the 9 canonical roles
--   permission_definitions  — 49 atomic permissions
--   role_permissions        — the role→permission mapping
--
-- Idempotent. Re-running will not duplicate rows.
-- ============================================================

-- ---------- 1. Roles ----------
insert into public.role_definitions (name, description, tier, is_system) values
  ('SUPER_ADMIN',      'Platform operator. Manages institutions and platform security.', 'platform',    true),
  ('UNIVERSITY_ADMIN', 'Manages a single institution end to end.',                       'institution', true),
  ('FACULTY_ADMIN',    'Administers a faculty and everything under it.',                 'faculty',     true),
  ('HOD',              'Heads a department.',                                            'department',  true),
  ('LECTURER',         'Teaches assigned courses.',                                      'course',      true),
  ('STAFF',            'Non-teaching institutional staff. Permissions are modular.',     'institution', true),
  ('LEADERSHIP',       'Institutional leadership (VC, Registrar, Dean, etc.).',          'institution', true),
  ('STUDENT',          'Currently enrolled student.',                                    'self',        true),
  ('ALUMNI',           'Graduated former student.',                                      'self',        true)
on conflict (name) do nothing;

-- ---------- 2. Permissions ----------
insert into public.permission_definitions (name, description, category) values
  ('platform.institutions.manage', 'Create, suspend, or delete institutions',       'platform'),
  ('platform.security.manage',     'Configure platform security',                   'platform'),
  ('platform.maintenance',         'Platform-level maintenance operations',         'platform'),

  ('users.read',                   'Read user records within scope',                'users'),
  ('users.manage',                 'Update user records within scope',              'users'),
  ('users.suspend',                'Suspend or restore user accounts',              'users'),

  ('roles.read',                   'View role assignments',                         'roles'),
  ('roles.assign',                 'Assign roles at authorised scopes',             'roles'),
  ('roles.revoke',                 'Revoke role assignments',                       'roles'),

  ('verification.read',            'View verification requests',                    'verification'),
  ('verification.review',          'Review verification requests',                  'verification'),
  ('verification.approve',         'Approve verification',                          'verification'),
  ('verification.reject',          'Reject verification',                           'verification'),

  ('academic_structure.read',      'View faculties, departments, programmes',       'academic'),
  ('academic_structure.manage',    'Create or modify academic structure',           'academic'),
  ('faculty.manage',               'Manage faculties',                              'academic'),
  ('department.manage',            'Manage departments',                            'academic'),
  ('programme.manage',             'Manage programmes',                             'academic'),
  ('level.manage',                 'Manage levels',                                 'academic'),
  ('session.manage',               'Manage academic sessions',                      'academic'),

  ('course.read',                  'View courses',                                  'course'),
  ('course.create',                'Create courses',                                'course'),
  ('course.manage',                'Modify courses',                                'course'),
  ('course.assign_lecturer',       'Assign lecturers to courses',                   'course'),

  ('materials.read',               'View course materials',                         'materials'),
  ('materials.create',             'Upload course materials',                       'materials'),
  ('materials.manage',             'Edit or delete course materials',               'materials'),
  ('materials.publish',            'Publish course materials',                      'materials'),

  ('assignments.read',             'View assignments',                              'assignments'),
  ('assignments.create',           'Create assignments or submit own work',         'assignments'),
  ('assignments.manage',           'Edit or delete assignments',                    'assignments'),
  ('assignments.grade',            'Grade assignment submissions',                  'assignments'),

  ('announcements.read',           'View announcements',                            'announcements'),
  ('announcements.create',         'Draft announcements within scope',              'announcements'),
  ('announcements.publish',        'Publish announcements',                         'announcements'),
  ('announcements.manage',         'Edit or delete any announcement in scope',      'announcements'),

  ('community.create',             'Create interest communities',                   'communities'),
  ('community.manage',             'Manage any community in scope',                 'communities'),
  ('community.moderate',           'Moderate community content',                    'communities'),

  ('enrollment.read',              'View enrollment records in scope',              'enrollment'),
  ('enrollment.manage',            'Manage enrollment records',                     'enrollment'),

  ('student_records.read',         'View student academic records',                 'records'),
  ('student_records.manage',       'Modify student academic records',               'records'),

  ('reports.read',                 'View reports within scope',                     'reports'),
  ('settings.read',                'View settings',                                 'settings'),
  ('settings.manage',              'Modify settings within scope',                  'settings'),
  ('audit_logs.read',              'View audit logs within scope',                  'audit'),

  ('profile.read_self',            'View own profile',                              'self'),
  ('profile.update_self',          'Update own profile',                            'self')
on conflict (name) do nothing;

-- ---------- 3. Role → permission mappings ----------
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from (values
  -- =========================================================
  -- STUDENT
  -- =========================================================
  ('STUDENT', 'course.read'),
  ('STUDENT', 'materials.read'),
  ('STUDENT', 'assignments.read'),
  ('STUDENT', 'assignments.create'),
  ('STUDENT', 'announcements.read'),
  ('STUDENT', 'community.create'),
  ('STUDENT', 'community.moderate'),
  ('STUDENT', 'enrollment.read'),
  ('STUDENT', 'profile.read_self'),
  ('STUDENT', 'profile.update_self'),

  -- =========================================================
  -- ALUMNI
  -- =========================================================
  ('ALUMNI', 'announcements.read'),
  ('ALUMNI', 'community.create'),
  ('ALUMNI', 'profile.read_self'),
  ('ALUMNI', 'profile.update_self'),

  -- =========================================================
  -- LECTURER
  -- =========================================================
  ('LECTURER', 'users.read'),
  ('LECTURER', 'course.read'),
  ('LECTURER', 'course.manage'),
  ('LECTURER', 'materials.read'),
  ('LECTURER', 'materials.create'),
  ('LECTURER', 'materials.manage'),
  ('LECTURER', 'materials.publish'),
  ('LECTURER', 'assignments.read'),
  ('LECTURER', 'assignments.create'),
  ('LECTURER', 'assignments.manage'),
  ('LECTURER', 'assignments.grade'),
  ('LECTURER', 'announcements.read'),
  ('LECTURER', 'announcements.create'),
  ('LECTURER', 'community.moderate'),
  ('LECTURER', 'reports.read'),
  ('LECTURER', 'profile.read_self'),
  ('LECTURER', 'profile.update_self'),

  -- =========================================================
  -- HOD
  -- =========================================================
  ('HOD', 'users.read'),
  ('HOD', 'verification.read'),
  ('HOD', 'verification.review'),
  ('HOD', 'academic_structure.read'),
  ('HOD', 'course.read'),
  ('HOD', 'course.create'),
  ('HOD', 'materials.read'),
  ('HOD', 'materials.manage'),
  ('HOD', 'assignments.read'),
  ('HOD', 'announcements.read'),
  ('HOD', 'announcements.create'),
  ('HOD', 'announcements.publish'),
  ('HOD', 'community.create'),
  ('HOD', 'community.moderate'),
  ('HOD', 'enrollment.read'),
  ('HOD', 'student_records.read'),
  ('HOD', 'reports.read'),
  ('HOD', 'profile.read_self'),
  ('HOD', 'profile.update_self'),

  -- =========================================================
  -- FACULTY_ADMIN
  -- =========================================================
  ('FACULTY_ADMIN', 'users.read'),
  ('FACULTY_ADMIN', 'verification.read'),
  ('FACULTY_ADMIN', 'verification.review'),
  ('FACULTY_ADMIN', 'academic_structure.read'),
  ('FACULTY_ADMIN', 'department.manage'),
  ('FACULTY_ADMIN', 'programme.manage'),
  ('FACULTY_ADMIN', 'course.read'),
  ('FACULTY_ADMIN', 'course.create'),
  ('FACULTY_ADMIN', 'course.manage'),
  ('FACULTY_ADMIN', 'materials.read'),
  ('FACULTY_ADMIN', 'materials.manage'),
  ('FACULTY_ADMIN', 'materials.publish'),
  ('FACULTY_ADMIN', 'announcements.read'),
  ('FACULTY_ADMIN', 'announcements.create'),
  ('FACULTY_ADMIN', 'announcements.publish'),
  ('FACULTY_ADMIN', 'community.create'),
  ('FACULTY_ADMIN', 'community.manage'),
  ('FACULTY_ADMIN', 'community.moderate'),
  ('FACULTY_ADMIN', 'enrollment.read'),
  ('FACULTY_ADMIN', 'student_records.read'),
  ('FACULTY_ADMIN', 'reports.read'),
  ('FACULTY_ADMIN', 'profile.read_self'),
  ('FACULTY_ADMIN', 'profile.update_self'),

  -- =========================================================
  -- UNIVERSITY_ADMIN
  -- =========================================================
  ('UNIVERSITY_ADMIN', 'users.read'),
  ('UNIVERSITY_ADMIN', 'users.manage'),
  ('UNIVERSITY_ADMIN', 'users.suspend'),
  ('UNIVERSITY_ADMIN', 'roles.read'),
  ('UNIVERSITY_ADMIN', 'roles.assign'),
  ('UNIVERSITY_ADMIN', 'roles.revoke'),
  ('UNIVERSITY_ADMIN', 'verification.read'),
  ('UNIVERSITY_ADMIN', 'verification.review'),
  ('UNIVERSITY_ADMIN', 'verification.approve'),
  ('UNIVERSITY_ADMIN', 'verification.reject'),
  ('UNIVERSITY_ADMIN', 'academic_structure.read'),
  ('UNIVERSITY_ADMIN', 'academic_structure.manage'),
  ('UNIVERSITY_ADMIN', 'faculty.manage'),
  ('UNIVERSITY_ADMIN', 'department.manage'),
  ('UNIVERSITY_ADMIN', 'programme.manage'),
  ('UNIVERSITY_ADMIN', 'level.manage'),
  ('UNIVERSITY_ADMIN', 'session.manage'),
  ('UNIVERSITY_ADMIN', 'course.read'),
  ('UNIVERSITY_ADMIN', 'course.create'),
  ('UNIVERSITY_ADMIN', 'course.manage'),
  ('UNIVERSITY_ADMIN', 'course.assign_lecturer'),
  ('UNIVERSITY_ADMIN', 'materials.read'),
  ('UNIVERSITY_ADMIN', 'materials.create'),
  ('UNIVERSITY_ADMIN', 'materials.manage'),
  ('UNIVERSITY_ADMIN', 'materials.publish'),
  ('UNIVERSITY_ADMIN', 'assignments.read'),
  ('UNIVERSITY_ADMIN', 'assignments.manage'),
  ('UNIVERSITY_ADMIN', 'announcements.read'),
  ('UNIVERSITY_ADMIN', 'announcements.create'),
  ('UNIVERSITY_ADMIN', 'announcements.publish'),
  ('UNIVERSITY_ADMIN', 'announcements.manage'),
  ('UNIVERSITY_ADMIN', 'community.create'),
  ('UNIVERSITY_ADMIN', 'community.manage'),
  ('UNIVERSITY_ADMIN', 'community.moderate'),
  ('UNIVERSITY_ADMIN', 'enrollment.read'),
  ('UNIVERSITY_ADMIN', 'enrollment.manage'),
  ('UNIVERSITY_ADMIN', 'student_records.read'),
  ('UNIVERSITY_ADMIN', 'student_records.manage'),
  ('UNIVERSITY_ADMIN', 'reports.read'),
  ('UNIVERSITY_ADMIN', 'settings.read'),
  ('UNIVERSITY_ADMIN', 'settings.manage'),
  ('UNIVERSITY_ADMIN', 'audit_logs.read'),
  ('UNIVERSITY_ADMIN', 'profile.read_self'),
  ('UNIVERSITY_ADMIN', 'profile.update_self'),

  -- =========================================================
  -- LEADERSHIP
  -- =========================================================
  ('LEADERSHIP', 'users.read'),
  ('LEADERSHIP', 'academic_structure.read'),
  ('LEADERSHIP', 'course.read'),
  ('LEADERSHIP', 'materials.read'),
  ('LEADERSHIP', 'announcements.read'),
  ('LEADERSHIP', 'announcements.create'),
  ('LEADERSHIP', 'announcements.publish'),
  ('LEADERSHIP', 'reports.read'),
  ('LEADERSHIP', 'audit_logs.read'),
  ('LEADERSHIP', 'settings.read'),
  ('LEADERSHIP', 'profile.read_self'),
  ('LEADERSHIP', 'profile.update_self'),

  -- =========================================================
  -- STAFF  (modular baseline — additional function-specific
  --         permissions come from additional scoped assignments)
  -- =========================================================
  ('STAFF', 'users.read'),
  ('STAFF', 'academic_structure.read'),
  ('STAFF', 'announcements.read'),
  ('STAFF', 'community.create'),
  ('STAFF', 'reports.read'),
  ('STAFF', 'profile.read_self'),
  ('STAFF', 'profile.update_self')
) as m(role, permission)
join public.role_definitions        r on r.name = m.role
join public.permission_definitions  p on p.name = m.permission
on conflict do nothing;

-- ---------- 4. SUPER_ADMIN gets every permission ----------
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.role_definitions r
cross join public.permission_definitions p
where r.name = 'SUPER_ADMIN'
on conflict do nothing;
