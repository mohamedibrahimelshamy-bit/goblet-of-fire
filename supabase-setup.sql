-- =================================================================
-- Goblet of Fire — Supabase setup
-- =================================================================
-- HOW TO USE:
--   1. Go to https://supabase.com and create a free project.
--   2. Open the project -> SQL Editor -> New Query.
--   3. Before running, replace the placeholder on the VERY LAST LINE
--      ('CHANGE-ME-TO-A-LONG-RANDOM-STRING') with your own admin key.
--      Pick something long — this is how you authenticate as the
--      Tournament Organizer. Treat it like a password.
--   4. Paste this entire file and click "Run".
--   5. Go to Project Settings -> API -> copy:
--        - Project URL             -> goblet.html CONFIG.supabaseUrl
--        - anon / public API key   -> goblet.html CONFIG.supabaseAnonKey
--      Then put your admin key in  -> goblet.html CONFIG.adminKey
--
-- SECURITY NOTES:
--   - The anon key is safe to expose in the browser.
--   - The admin key is ALSO in the browser, but only when visiting
--     with ?admin=1&key=XXX. Do not share that URL publicly.
--   - Names are never selectable by the public — only an aggregate
--     count, the draw time, and the final winner are readable.
-- =================================================================

-- Entries: who cast their name into the goblet
create table if not exists public.entries (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0 and length(name) <= 60),
  created_at timestamptz not null default now()
);

-- Settings: singleton row with draw time + winner + admin key
create table if not exists public.settings (
  id int primary key default 1,
  draw_at timestamptz,
  winner_name text,
  admin_key text not null,
  constraint singleton check (id = 1)
);

alter table public.entries enable row level security;
alter table public.settings enable row level security;

-- We grant NO direct access via RLS. All access goes through
-- security-definer RPC functions defined below. This keeps names
-- hidden from the public while still allowing anonymous writes.

-- ============ Public RPCs ============

-- Get aggregate status: count + draw time + winner (if drawn).
-- Names themselves are never returned here.
create or replace function public.goblet_status()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'count',       (select count(*) from public.entries),
    'draw_at',     (select draw_at     from public.settings where id = 1),
    'winner_name', (select winner_name from public.settings where id = 1)
  );
$$;

-- Cast a name into the flames. Silently deduplicates
-- (case-insensitive). Does not reveal whether the name was new.
create or replace function public.goblet_cast(p_name text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := trim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
begin
  if v_name = '' or length(v_name) > 60 then
    return;
  end if;
  if exists(select 1 from public.entries where lower(name) = lower(v_name)) then
    return;
  end if;
  insert into public.entries(name) values (v_name);
end;
$$;

grant execute on function public.goblet_status()      to anon;
grant execute on function public.goblet_cast(text)    to anon;

-- ============ Admin RPCs (gated by admin key) ============

-- Helper: raise if the supplied key does not match the stored admin key
create or replace function public._require_admin(p_key text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_key is null
     or not exists(select 1 from public.settings where id = 1 and admin_key = p_key) then
    raise exception 'unauthorized';
  end if;
end;
$$;

create or replace function public.goblet_admin_list(p_key text)
returns table (id uuid, name text, created_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._require_admin(p_key);
  return query
    select e.id, e.name, e.created_at
    from public.entries e
    order by e.created_at desc;
end;
$$;

create or replace function public.goblet_admin_remove(p_key text, p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._require_admin(p_key);
  delete from public.entries where id = p_id;
end;
$$;

create or replace function public.goblet_admin_empty(p_key text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._require_admin(p_key);
  -- `where true` satisfies Supabase's "DELETE requires a WHERE clause" guard
  delete from public.entries where true;
  update public.settings set winner_name = null where id = 1;
end;
$$;

create or replace function public.goblet_admin_set_draw_time(p_key text, p_draw_at timestamptz)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._require_admin(p_key);
  update public.settings set draw_at = p_draw_at, winner_name = null where id = 1;
end;
$$;

-- Draws a winner, records it, returns the name.
create or replace function public.goblet_admin_draw(p_key text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_winner text;
begin
  perform public._require_admin(p_key);
  select name into v_winner from public.entries order by random() limit 1;
  if v_winner is null then
    raise exception 'no entries';
  end if;
  update public.settings set winner_name = v_winner where id = 1;
  return v_winner;
end;
$$;

grant execute on function public.goblet_admin_list(text)                      to anon;
grant execute on function public.goblet_admin_remove(text, uuid)              to anon;
grant execute on function public.goblet_admin_empty(text)                     to anon;
grant execute on function public.goblet_admin_set_draw_time(text, timestamptz) to anon;
grant execute on function public.goblet_admin_draw(text)                      to anon;

-- ============ Seed settings ============
-- IMPORTANT: change the value below to your own long random admin key
-- BEFORE running this script.
insert into public.settings (id, admin_key)
values (1, 'CHANGE-ME-TO-A-LONG-RANDOM-STRING')
on conflict (id) do nothing;
