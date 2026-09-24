-- ============================================================
-- Migration 0015 — User settings
-- Adds a jsonb settings column to profiles plus a definer RPC
-- that validates and merges partial updates.
-- ============================================================

alter table public.profiles
  add column if not exists settings jsonb not null default '{
    "theme": "system",
    "language": "en",
    "notifications": {
      "in_app": true,
      "email": false,
      "announcements": true,
      "materials": true,
      "messages": true
    },
    "privacy": {
      "email_visible": true,
      "phone_visible": false,
      "last_seen_visible": true
    }
  }'::jsonb;

create or replace function public.update_my_settings(p_patch jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_current jsonb;
  v_next jsonb;
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'patch must be a JSON object';
  end if;

  select settings into v_current from public.profiles where id = v_user;
  if v_current is null then v_current := '{}'::jsonb; end if;

  -- Shallow-merge top-level keys; nested objects are merged too.
  v_next := v_current;
  declare
    k text;
    v jsonb;
  begin
    for k, v in select key, value from jsonb_each(p_patch)
    loop
      if jsonb_typeof(v) = 'object' and jsonb_typeof(v_next->k) = 'object' then
        v_next := jsonb_set(v_next, array[k], (v_next->k) || v, true);
      else
        v_next := jsonb_set(v_next, array[k], v, true);
      end if;
    end loop;
  end;

  update public.profiles set settings = v_next where id = v_user;
  return v_next;
end;
$$;
grant execute on function public.update_my_settings(jsonb) to authenticated;
