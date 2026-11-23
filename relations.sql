-- Every table and view in the exposed schemas, with its real row count.
-- Run as the database owner (postgres), not as anon.
select
  n.nspname,
  c.relname,
  case c.relkind when 'v' then 'view' when 'm' then 'mview'
                 when 'f' then 'foreign' else 'table' end,
  (xpath('/row/n/text()',
     query_to_xml(format('select count(*) as n from %I.%I', n.nspname, c.relname),
                  false, true, '')))[1]::text
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = any (string_to_array(:'schemas', ','))
  and c.relkind in ('r', 'p', 'v', 'm', 'f')
  and not c.relispartition
order by 1, 2;
