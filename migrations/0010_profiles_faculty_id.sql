-- ============================================================
-- Migration 0010 — Add faculty_id to profiles
-- Denormalised for query convenience; derivable via department_id.
-- ============================================================

alter table public.profiles
  add column if not exists faculty_id uuid references public.faculties(id) on delete set null;

create index if not exists profiles_faculty_idx on public.profiles(faculty_id);
