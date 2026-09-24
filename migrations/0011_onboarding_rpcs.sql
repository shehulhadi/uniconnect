-- ============================================================
-- Migration 0011 — Onboarding RPCs
-- The profiles_update_self policy rightly forbids changing
-- institution_id. Onboarding needs a controlled channel to do it.
-- ============================================================

create or replace function public.onboarding_set_institution(p_institution_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_step text;
begin
  if v_user is null then raise exception 'not authenticated'; end if;

  select registration_step into v_step from public.profiles where id = v_user;
  if v_step is null then raise exception 'profile not found'; end if;
  if v_step = 'complete' then raise exception 'onboarding already complete'; end if;
  if v_step <> 'institution' then raise exception 'wrong step (expected institution, got %)', v_step; end if;

  if not exists (select 1 from public.institutions where id = p_institution_id) then
    raise exception 'invalid institution';
  end if;

  update public.profiles
    set institution_id   = p_institution_id,
        faculty_id       = null,
        department_id    = null,
        programme_id     = null,
        level_id         = null,
        session_id       = null,
        registration_step = 'academic'
    where id = v_user;
end;
$$;
grant execute on function public.onboarding_set_institution(uuid) to authenticated;

create or replace function public.onboarding_set_academic(
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
begin
  if v_user is null then raise exception 'not authenticated'; end if;

  select registration_step, institution_id into v_step, v_inst
    from public.profiles where id = v_user;
  if v_step is null then raise exception 'profile not found'; end if;
  if v_step = 'complete' then raise exception 'onboarding already complete'; end if;
  if v_step <> 'academic' then raise exception 'wrong step (expected academic, got %)', v_step; end if;
  if v_inst is null then raise exception 'institution not set'; end if;

  -- Validate the entire academic chain within the selected institution
  if not exists (
    select 1 from public.faculties
    where id = p_faculty_id and institution_id = v_inst
  ) then raise exception 'invalid faculty'; end if;

  if not exists (
    select 1 from public.departments d
    join public.faculties f on f.id = d.faculty_id
    where d.id = p_department_id and f.id = p_faculty_id
  ) then raise exception 'invalid department'; end if;

  if not exists (
    select 1 from public.programmes
    where id = p_programme_id and department_id = p_department_id
  ) then raise exception 'invalid programme'; end if;

  if not exists (
    select 1 from public.levels
    where id = p_level_id and institution_id = v_inst
  ) then raise exception 'invalid level'; end if;

  if not exists (
    select 1 from public.academic_sessions
    where id = p_session_id and institution_id = v_inst
  ) then raise exception 'invalid session'; end if;

  update public.profiles
    set faculty_id        = p_faculty_id,
        department_id     = p_department_id,
        programme_id      = p_programme_id,
        level_id          = p_level_id,
        session_id        = p_session_id,
        registration_step = 'verification'
    where id = v_user;
end;
$$;
grant execute on function public.onboarding_set_academic(uuid, uuid, uuid, uuid, uuid) to authenticated;
