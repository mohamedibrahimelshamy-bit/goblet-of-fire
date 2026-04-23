-- =================================================================
-- Goblet of Fire — migration: support multiple champions per draw
-- Run this in Supabase SQL Editor once (already-deployed projects).
-- New deployments get this via supabase-setup.sql directly.
-- =================================================================

alter table public.settings
  add column if not exists winner_names text[];

-- Migrate any existing single winner into the array form
update public.settings
   set winner_names = case when winner_name is not null then array[winner_name] else null end
 where winner_names is null
   and id = 1;

-- Status: return winner_names (array) instead of a single winner_name
create or replace function public.goblet_status()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'count',        (select count(*) from public.entries),
    'draw_at',      (select draw_at from public.settings where id = 1),
    'winner_names', (select coalesce(winner_names, '{}'::text[]) from public.settings where id = 1)
  );
$$;

-- Draw N distinct champions; stores the full list and also the first
-- one as winner_name for backward compat.
create or replace function public.goblet_admin_draw(p_key text, p_count integer default 2)
returns text[]
language plpgsql
security definer
set search_path = public
as $$
declare
  v_winners text[];
  v_count   integer;
begin
  perform public._require_admin(p_key);
  v_count := greatest(1, least(coalesce(p_count, 2), 50));
  select array_agg(name) into v_winners from (
    select name from public.entries order by random() limit v_count
  ) t;
  if v_winners is null or array_length(v_winners, 1) = 0 then
    raise exception 'no entries';
  end if;
  update public.settings
     set winner_names = v_winners,
         winner_name  = v_winners[1]
   where id = 1;
  return v_winners;
end;
$$;

-- Empty also clears the winners array
create or replace function public.goblet_admin_empty(p_key text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._require_admin(p_key);
  delete from public.entries where true;
  update public.settings
     set winner_name = null,
         winner_names = null
   where id = 1;
end;
$$;

-- Setting a new draw time also clears the previous winners
create or replace function public.goblet_admin_set_draw_time(p_key text, p_draw_at timestamptz)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._require_admin(p_key);
  update public.settings
     set draw_at = p_draw_at,
         winner_name = null,
         winner_names = null
   where id = 1;
end;
$$;

grant execute on function public.goblet_admin_draw(text, integer) to anon;
