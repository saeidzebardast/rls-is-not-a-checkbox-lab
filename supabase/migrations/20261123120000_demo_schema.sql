-- Broken demo schema from the post. Default grants for new public tables/functions
-- come from the local stack (auto_expose_new_tables defaults to true). We still
-- grant usage on auth so auth.uid() works for authenticated policies.

grant usage on schema auth to anon, authenticated;

create table clients (id int primary key, name text, email text);
create table bookings (id int primary key, client_id int, user_id uuid, starts_at timestamptz);
create table plans (id int primary key, name text, price int);
create table audit_log (id int primary key, msg text);
create table waitlist (id int primary key, email text);
create table client_notes (id int primary key, client_id int, note text);

alter table clients enable row level security;
alter table bookings enable row level security;
alter table plans enable row level security;
alter table audit_log enable row level security;
alter table waitlist enable row level security;
alter table client_notes enable row level security;

create policy "clients readable" on clients for select to anon using (true);
create policy "plans are public" on plans for select to anon using (true);
create policy "own bookings" on bookings for select to authenticated using (user_id = auth.uid());
create policy "book for yourself" on bookings for insert to authenticated with check (user_id = auth.uid());
create policy "join the waitlist" on waitlist for insert to anon with check (true);
create policy "staff read notes" on client_notes for select to authenticated using (true);

revoke all on audit_log from anon, authenticated;

create view booking_summary as
  select b.id, c.name, c.email, b.starts_at
  from bookings b
  join clients c on c.id = b.client_id;

-- tidy write grants everywhere except bookings (the leftover)
revoke insert, update, delete on clients, plans, waitlist, client_notes, booking_summary from anon, authenticated;
grant insert on waitlist to anon;

create function public.find_client(e text) returns setof clients language sql security definer
  as $$ select * from public.clients where email = e $$;

create function public.is_staff() returns boolean language sql security definer stable
  as $$ select false $$;
revoke execute on function public.is_staff() from public, anon;

create function public.handle_new_user() returns trigger language plpgsql security definer
  as $$ begin return new; end $$;

create function public.plan_count() returns bigint language sql
  as $$ select count(*) from public.plans $$;

-- Storage: bucket + seed files come from config.toml
-- ([storage.buckets.id-documents], public = false, objects_path).
-- Config is applied after migrations, so setting public here would be
-- overwritten. The leak is this broad select policy (listing works with
-- the publishable key even when the bucket is not marked public).
create policy "anon can list id-documents"
  on storage.objects for select to anon
  using (bucket_id = 'id-documents');
