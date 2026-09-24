-- ============================================================
-- Migration 0014 — Status enum extended, last_seen_at column
-- Adds 'busy' to the status set, tracks recency, and provides
-- a small RPC for the client to bump its own last_seen_at.
-- ============================================================

alter table public.profiles
  add column if not exists last_seen_at timestamptz;

do $$
declare cname text;
begin
  for cname in
    select conname from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%status%'
  loop
    execute format('alter table public.profiles drop constraint %I', cname);
  end loop;
end $$;

alter table public.profiles
  add constraint profiles_status_check
  check (status in ('online','away','busy','offline'));

create or replace function public.touch_my_last_seen()
returns void
language sql security definer set search_path = public
as $$ update public.profiles set last_seen_at = now() where id = auth.uid(); $$;
grant execute on function public.touch_my_last_seen() to authenticated;
