-- ============================================================
-- Migration 0012 — Identity submission RPC
-- Replaces submit_verification with a version that:
--   * checks email method against auth.users.email_confirmed_at
--   * auto-verifies when the platform already trusts the email
--   * otherwise leaves the request pending for admin review
-- Also adds onboarding_submit_identity(matric_no) that does
-- save matric → submit request → advance step in one call.
-- ============================================================

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
begin
  if v_user is null then raise exception 'not authenticated'; end if;

  select id, institution_id, faculty_id, department_id, programme_id,
         level_id, session_id, matric_no, full_name
    into v_profile
    from public.profiles where id = v_user;

  if v_profile.institution_id is null
     or v_profile.faculty_id is null or v_profile.department_id is null
     or v_profile.programme_id is null or v_profile.level_id is null
     or v_profile.session_id is null then
    raise exception 'academic identity incomplete';
  end if;

  select coalesce(verification_method, 'email')
    into v_method
    from public.institutions where id = v_profile.institution_id;

  -- Return existing open request if present
  select id into v_req_id
    from public.verification_requests
    where user_id = v_user and status in ('pending','needs_review')
    limit 1;
  if v_req_id is not null then return v_req_id; end if;

  -- Email method: auto-verify if the platform already trusts the email
  if v_method = 'email' then
    select email_confirmed_at into v_email_conf
      from auth.users where id = v_user;
    if v_email_conf is not null then
      v_initial_status := 'verified';
    end if;
  end if;

  insert into public.verification_requests (
    user_id, institution_id, method, submitted_data, status,
    decided_at
  ) values (
    v_user,
    v_profile.institution_id,
    v_method,
    jsonb_build_object(
      'full_name', v_profile.full_name,
      'faculty_id', v_profile.faculty_id,
      'department_id', v_profile.department_id,
      'programme_id', v_profile.programme_id,
      'level_id', v_profile.level_id,
      'session_id', v_profile.session_id,
      'matric_no', v_profile.matric_no
    ),
    v_initial_status,
    case when v_initial_status = 'verified' then now() else null end
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
end;
$$;
grant execute on function public.submit_verification() to authenticated;

create or replace function public.onboarding_submit_identity(p_matric_no text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_step text;
  v_matric text := nullif(btrim(coalesce(p_matric_no, '')), '');
  v_req_id uuid;
  v_status text;
begin
  if v_user is null then raise exception 'not authenticated'; end if;

  select registration_step into v_step from public.profiles where id = v_user;
  if v_step is null then raise exception 'profile not found'; end if;
  if v_step = 'complete' then raise exception 'onboarding already complete'; end if;
  if v_step <> 'verification' then raise exception 'wrong step (expected verification, got %)', v_step; end if;

  if v_matric is null then raise exception 'matric number required'; end if;

  -- Duplicate matric within institution
  if exists (
    select 1 from public.profiles p
    join public.profiles me on me.id = v_user
    where p.institution_id = me.institution_id
      and p.id <> v_user
      and lower(p.matric_no) = lower(v_matric)
  ) then
    raise exception 'this matric number is already registered';
  end if;

  update public.profiles set matric_no = v_matric where id = v_user;

  v_req_id := public.submit_verification();

  select verification_status into v_status
    from public.profiles where id = v_user;

  return jsonb_build_object(
    'request_id', v_req_id,
    'status', v_status
  );
end;
$$;
grant execute on function public.onboarding_submit_identity(text) to authenticated;
