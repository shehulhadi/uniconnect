-- ============================================================
-- Migration 0003 — RBAC schema
--
-- Creates the authorization primitives:
--   role_definitions        — what roles exist (SUPER_ADMIN, LECTURER, …)
--   permission_definitions  — atomic actions (materials.manage, …)
--   role_permissions        — role × permission mapping
--   user_role_assignments   — user × role × scope (the heart of the model)
--   audit_logs              — immutable trail of sensitive actions
--
-- No rows are inserted here. No policies are attached here.
-- Seed, helpers, and RLS come in later migrations.
-- ============================================================

-- ---------- 1. role_definitions ----------
create table if not exists public.role_definitions (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text not null default '',
  -- tier: broadest scope this role is ever allowed to hold.
  -- Used as a sanity check when assigning (a LECTURER should never be
  -- assigned at institution scope). Not used for permission inheritance.
  tier text not null default 'self',
  is_system boolean not null default false,
  created_at timestamptz not null default now()
);

do $$
begin
  if not exists (select 1 from pg_constraint where conname='role_definitions_tier_check') then
    alter table public.role_definitions add constraint role_definitions_tier_check
      check (tier in ('platform','institution','faculty','department','course','community','self'));
  end if;
  if not exists (select 1 from pg_constraint where conname='role_definitions_name_check') then
    alter table public.role_definitions add constraint role_definitions_name_check
      check (name in (
        'SUPER_ADMIN','UNIVERSITY_ADMIN','FACULTY_ADMIN','HOD','LECTURER',
        'STAFF','LEADERSHIP','STUDENT','ALUMNI'
      ));
  end if;
end $$;

-- ---------- 2. permission_definitions ----------
create table if not exists public.permission_definitions (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text not null default '',
  category text not null default 'general',
  created_at timestamptz not null default now()
);

create index if not exists permission_definitions_category_idx
  on public.permission_definitions(category);

-- ---------- 3. role_permissions ----------
create table if not exists public.role_permissions (
  role_id uuid not null references public.role_definitions(id) on delete cascade,
  permission_id uuid not null references public.permission_definitions(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (role_id, permission_id)
);

create index if not exists role_permissions_perm_idx
  on public.role_permissions(permission_id);

-- ---------- 4. user_role_assignments ----------
create table if not exists public.user_role_assignments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  role_id uuid not null references public.role_definitions(id) on delete restrict,
  scope_type text not null,
  -- scope_id is NULL only for scope_type in ('platform','self').
  scope_id uuid,
  assigned_by uuid references public.profiles(id) on delete set null,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  revoked_at timestamptz,

  check (scope_type in ('platform','institution','faculty','department','programme','course','community','self')),
  check (
    (scope_type in ('platform','self') and scope_id is null)
    or (scope_type not in ('platform','self') and scope_id is not null)
  ),
  check (status in ('active','revoked','expired')),
  check (expires_at is null or expires_at > created_at)
);

-- At most one *active* assignment of the same role at the same scope per user.
-- Historical rows (status revoked/expired) remain for the audit trail.
create unique index if not exists user_role_assignments_active_unique
  on public.user_role_assignments (user_id, role_id, scope_type, coalesce(scope_id, '00000000-0000-0000-0000-000000000000'::uuid))
  where status = 'active';

create index if not exists user_role_assignments_user_idx
  on public.user_role_assignments(user_id) where status = 'active';

create index if not exists user_role_assignments_scope_idx
  on public.user_role_assignments(scope_type, scope_id) where status = 'active';

-- ---------- 5. audit_logs ----------
create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references public.profiles(id) on delete set null,
  action text not null,
  target_type text,
  target_id uuid,
  scope_type text,
  scope_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists audit_logs_actor_idx
  on public.audit_logs(actor_user_id, created_at desc);

create index if not exists audit_logs_target_idx
  on public.audit_logs(target_type, target_id, created_at desc);

create index if not exists audit_logs_created_idx
  on public.audit_logs(created_at desc);

-- ---------- 6. Enable RLS ----------
alter table public.role_definitions        enable row level security;
alter table public.permission_definitions  enable row level security;
alter table public.role_permissions        enable row level security;
alter table public.user_role_assignments   enable row level security;
alter table public.audit_logs              enable row level security;

-- ---------- 7. Interim RLS: read-only, self-scoped ----------
-- These are intentionally restrictive. Real permission-aware policies
-- arrive in migration 0007. Between now and then, admins work through
-- the SQL Editor (which bypasses RLS) and the app keeps working because
-- nothing yet reads from these tables.

drop policy if exists role_definitions_read on public.role_definitions;
create policy role_definitions_read on public.role_definitions
  for select to authenticated using (true);

drop policy if exists permission_definitions_read on public.permission_definitions;
create policy permission_definitions_read on public.permission_definitions
  for select to authenticated using (true);

drop policy if exists role_permissions_read on public.role_permissions;
create policy role_permissions_read on public.role_permissions
  for select to authenticated using (true);

drop policy if exists user_role_assignments_read_self on public.user_role_assignments;
create policy user_role_assignments_read_self on public.user_role_assignments
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists audit_logs_read_self on public.audit_logs;
create policy audit_logs_read_self on public.audit_logs
  for select to authenticated
  using (actor_user_id = auth.uid());

-- No INSERT / UPDATE / DELETE policies exist for authenticated users on
-- any of these tables. Writes happen only through security definer
-- functions (added later) or by superusers in the SQL Editor.

-- ---------- 8. Grants ----------
grant select on public.role_definitions       to authenticated;
grant select on public.permission_definitions to authenticated;
grant select on public.role_permissions       to authenticated;
grant select on public.user_role_assignments  to authenticated;
grant select on public.audit_logs             to authenticated;
