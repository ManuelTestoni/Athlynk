-- Auto-enable RLS on newly created public tables.
-- Strategy: RLS enabled, no policy → blocks PostgREST/anon Data API.
-- Django connects as table owner and bypasses RLS (unaffected).
-- Run once in Supabase SQL editor as the `postgres` role (event triggers need superuser).

create or replace function public.tg_auto_enable_rls()
  returns event_trigger
  language plpgsql
as $$
declare
  obj record;
begin
  for obj in
    select objid, object_identity
    from pg_event_trigger_ddl_commands()
    where command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      and object_type = 'table'
  loop
    -- only public schema, only ordinary/partitioned tables, skip if already on
    perform 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where c.oid = obj.objid
      and n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and not c.relrowsecurity;

    if found then
      execute format('alter table %s enable row level security', obj.object_identity);
      raise notice 'RLS enabled on %', obj.object_identity;
    end if;
  end loop;
end;
$$;

drop event trigger if exists auto_enable_rls;

create event trigger auto_enable_rls
  on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  execute function public.tg_auto_enable_rls();
