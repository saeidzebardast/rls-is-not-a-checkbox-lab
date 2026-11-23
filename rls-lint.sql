-- One line per problem: level, object, problem. CI fails on any "error" line.
-- Starting point. Pass the same schemas as relations.sql, plus the allowlists:
--   -v schemas=public -v public_allow=public.plans
--   -v write_allow=anon:public.waitlist,authenticated:public.bookings
with rel as (
  select c.oid, n.nspname || '.' || c.relname as relation, c.relkind,
         c.relrowsecurity, c.reloptions
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = any (string_to_array(:'schemas', ','))
    and c.relkind in ('r', 'p', 'v', 'm', 'f')
),
reachable as (
  select * from rel
  where has_table_privilege('anon', oid, 'select,insert,update,delete')
     or has_table_privilege('authenticated', oid, 'select,insert,update,delete')
)
select 'error', relation, 'table has RLS disabled'
from reachable
where relkind in ('r', 'p') and not relrowsecurity
union all
select 'error', relation, 'view runs as its owner, set security_invoker = true'
from reachable
where relkind = 'v'
  and not exists (
    select 1 from unnest(coalesce(reloptions, '{}')) as opt
    where opt ~* '^security_invoker=(true|on|yes|1)$')
union all
select 'error', relation, 'materialized view or foreign table, RLS cannot protect it'
from reachable
where relkind in ('m', 'f')
union all
-- Write grants nobody put on the write allowlist, used or not.
select 'error', relation, format('%s can %s, not on the write allowlist',
                                 who, string_agg(priv, ', '))
from reachable,
     unnest(array['anon', 'authenticated']) as w(who),
     unnest(array['insert', 'update', 'delete']) as p(priv)
where has_table_privilege(who, oid, priv)
  and who || ':' || relation <> all (string_to_array(:'write_allow', ','))
group by relation, who
union all
-- Always-true policies: an error for anon, a warning for authenticated.
select case when roles && array['anon', 'public']::name[] then 'error' else 'warn' end,
       schemaname || '.' || tablename,
       format('policy %L is always true for %s', policyname, array_to_string(roles, ','))
from pg_policies
where schemaname = any (string_to_array(:'schemas', ','))
  and (qual = 'true' or with_check = 'true')
  and roles && array['anon', 'authenticated', 'public']::name[]
  and schemaname || '.' || tablename <> all (string_to_array(case cmd
        when 'SELECT' then :'public_allow'
        else regexp_replace(:'write_allow', '\w+:', '', 'g') end, ','))
union all
-- SECURITY DEFINER functions the API exposes at /rpc. They skip RLS.
select case when has_function_privilege('anon', p.oid, 'execute') then 'error' else 'warn' end,
       format('%s.%s(%s)', n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)),
       format('security definer function, %s can call it',
              case when has_function_privilege('anon', p.oid, 'execute')
                   then 'anon' else 'authenticated' end)
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = any (string_to_array(:'schemas', ','))
  and p.prosecdef
  and p.prorettype <> 'trigger'::regtype
  and (has_function_privilege('anon', p.oid, 'execute')
       or has_function_privilege('authenticated', p.oid, 'execute'))
order by 1, 2;
