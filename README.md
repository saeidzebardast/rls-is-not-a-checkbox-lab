# RLS Is Not a Checkbox Lab

Companion code for **[RLS Is Not a Checkbox: How AI-Built Apps Leak Data Through the Public Key](https://zebardast.com/blog/rls-is-not-a-checkbox)**.

The post shows how a Supabase app with row-level security turned on for every table can still hand out client data to anyone holding the public key. This repo lets you watch that happen on your own machine. It is a local Supabase project with a small booking app schema that has every leak from the post built in. You run the post's lint and probe against it and watch them fail. Then one SQL file of fixes turns them green.

> Only run the probe against databases you own, and preferably against a local stack like this one.

## Quick start

You need the [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started), Docker or Podman, Node 24 and `psql`.

On Podman (macOS), point the Docker API at the machine socket and clear a broken empty `CONTAINER_HOST` if you have one:

```bash
unset CONTAINER_HOST
export DOCKER_HOST=unix://$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}')
```

```bash
git clone https://github.com/saeidzebardast/rls-is-not-a-checkbox-lab && cd rls-is-not-a-checkbox-lab
make up         # supabase start: applies the broken schema and seed data
make lint       # rls-lint.sql against the exposed schema
make probe      # the probe, as anon and then as a freshly signed-up user
make advisors   # Supabase's own Security Advisor checks
make fix        # applies fixes/001_fix_everything.sql
make lint probe advisors   # same checks, now on the fixed schema
make reset      # back to the broken state
make down
```

Without `make`, the commands are the same ones the [workflow](.github/workflows/rls-probe.yml) runs. For example, the probe:

```bash
eval "$(supabase status -o env)"
psql "$DB_URL" -At -F $'\t' -v schemas=public -f relations.sql > relations.tsv
SUPABASE_URL="$API_URL" SUPABASE_ANON_KEY="${PUBLISHABLE_KEY:-$ANON_KEY}" \
  PROBE_SIGN_UP=1 node scripts/anon-probe.mts
```

Node 24 runs the TypeScript file directly. There is nothing to install.

## Layout

| Path | What |
|---|---|
| [`supabase/migrations/`](supabase/migrations) | The demo schema in its broken state |
| [`supabase/seed.sql`](supabase/seed.sql) | Seed rows for every table except `waitlist`, which stays empty on purpose |
| [`fixes/001_fix_everything.sql`](fixes/001_fix_everything.sql) | Every fix in one file, applied by [`scripts/fix.sh`](scripts/fix.sh) |
| [`rls-lint.sql`](rls-lint.sql) | The catalog lint from the post |
| [`relations.sql`](relations.sql) | Lists every table and view the API can see, with real row counts |
| [`scripts/anon-probe.mts`](scripts/anon-probe.mts) | The probe from the post |
| [`rls-public-allowlist.txt`](rls-public-allowlist.txt), [`rls-write-allowlist.txt`](rls-write-allowlist.txt) | What may be read or written on purpose |
| [`.github/workflows/rls-probe.yml`](.github/workflows/rls-probe.yml) | The post's workflow. It fails on `main`, because `main` is the broken state |
| [`.github/workflows/rls-probe-fixed.yml`](.github/workflows/rls-probe-fixed.yml) | The same workflow with the fixes applied first. It passes |

The code from the post is copied unchanged. Lab-only additions are the demo schema, seed, fixes, Makefile, Storage demo, and the fixed workflow.

## What is broken, and what catches it

| Object | What leaks | Caught by |
|---|---|---|
| `clients` | A `to anon using (true)` policy returns every client to the public key | Probe (anon pass) and lint |
| `booking_summary` | A view that runs as its owner, so it skips the table policies | Probe (both passes) and lint |
| `bookings` | Write grants for `anon` that nobody revoked | Lint only, because the probe never writes |
| `client_notes` | A `to authenticated using (true)` policy, so anyone who signs up can read it | Probe (signed-up user pass) and lint, as a warning |
| `find_client(text)` | A `security definer` function anyone can call through `/rpc` | Lint |
| `waitlist` | An empty table, where an empty answer proves nothing | Probe, until it has a seed row |
| `id-documents` bucket | A broad `select` policy on `storage.objects` for `anon` | The `curl` below. The post's lint and probe don't look at Storage. Local `supabase db advisors` (CLI 3.3.0) does not yet ship lint 0025 |

`plans` is public on purpose and sits on the allowlist. `audit_log` has no grants at all. Both pass in every run, which is how you know the probe isn't just failing on everything.

To see the Storage leak yourself:

```bash
eval "$(supabase status -o env)"
curl -sS "$API_URL/storage/v1/object/list/id-documents" \
  -H "apikey: ${PUBLISHABLE_KEY:-$ANON_KEY}" \
  -H "Authorization: Bearer ${PUBLISHABLE_KEY:-$ANON_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"prefix":"","limit":100}'
```

Before the fix the response lists `SPECIMEN-NOT-A-REAL-DOCUMENT.txt` and `specimen.png`. After `make fix` it is `[]`.

## Results

Outputs below are from a local run on CLI 3.3.0 (Podman). CI links will be filled in after the first Actions runs on `main`.

### Before the fix

```text
error	public.booking_summary	view runs as its owner, set security_invoker = true
error	public.bookings	anon can insert, update, delete, not on the write allowlist
error	public.clients	policy 'clients readable' is always true for anon
error	public.find_client(e text)	security definer function, anon can call it
warn	public.client_notes	policy 'staff read notes' is always true for authenticated
warn	public.is_staff()	security definer function, authenticated can call it
```

```text
ok    no grant                 table  public.audit_log
FAIL  anon can read rows       view   public.booking_summary
ok    rows hidden by RLS       table  public.bookings
ok    rows hidden by RLS       table  public.client_notes
FAIL  anon can read rows       table  public.clients
ok    public (allowlisted)     table  public.plans
FAIL  table is empty, seed it  table  public.waitlist

as a new user:
ok    no grant                 table  public.audit_log
FAIL  user can read rows       view   public.booking_summary
ok    rows hidden by RLS       table  public.bookings
FAIL  user can read rows       table  public.client_notes
ok    rows hidden by RLS       table  public.clients
ok    public (allowlisted)     table  public.plans
FAIL  table is empty, seed it  table  public.waitlist

6 of 14 checks failed
```

```text
ERROR	security_definer_view	View public.booking_summary is defined with the SECURITY DEFINER property
WARN	function_search_path_mutable	Function public.is_staff has a role mutable search_path
WARN	function_search_path_mutable	Function public.handle_new_user has a role mutable search_path
WARN	function_search_path_mutable	Function public.find_client has a role mutable search_path
WARN	function_search_path_mutable	Function public.plan_count has a role mutable search_path
WARN	rls_policy_always_true	waitlist policy "join the waitlist" INSERT with check (true) for anon
```

Failing workflow: [.github/workflows/rls-probe.yml](.github/workflows/rls-probe.yml) on `main` (red by design). <!-- CI run URL after first push -->

### After the fix

```text
warn	public.is_staff()	security definer function, authenticated can call it
```

```text
ok    no grant                 table  public.audit_log
ok    rows hidden by RLS       view   public.booking_summary
ok    rows hidden by RLS       table  public.bookings
ok    rows hidden by RLS       table  public.client_notes
ok    rows hidden by RLS       table  public.clients
ok    public (allowlisted)     table  public.plans
ok    rows hidden by RLS       table  public.waitlist

as a new user:
ok    no grant                 table  public.audit_log
ok    rows hidden by RLS       view   public.booking_summary
ok    rows hidden by RLS       table  public.bookings
ok    rows hidden by RLS       table  public.client_notes
ok    rows hidden by RLS       table  public.clients
ok    public (allowlisted)     table  public.plans
ok    rows hidden by RLS       table  public.waitlist

0 of 14 checks failed
```

```text
WARN	function_search_path_mutable	(is_staff, handle_new_user, find_client, plan_count)
WARN	rls_policy_always_true	waitlist INSERT with check (true) for anon — intentional allowlisted write
```

`supabase db advisors --type security --fail-on error` exits 0 after the fix. The WARNs above stay on purpose: search_path on helper functions, and the allowlisted anon insert on `waitlist`.

Passing workflow: [.github/workflows/rls-probe-fixed.yml](.github/workflows/rls-probe-fixed.yml). <!-- CI run URL after first push -->

The `is_staff()` warning stays after the fix on purpose. Helper functions used inside policies often need to be callable by signed-in users, so the lint reports it for a human to look at and doesn't fail the build.

## What the lab found beyond the article

1. `supabase status -o env` prints both `PUBLISHABLE_KEY` (`sb_publishable_…`) and legacy `ANON_KEY` (JWT). `${PUBLISHABLE_KEY:-$ANON_KEY}` works. The probe's anon pass does not need an `Authorization` header when the key is not a JWT; Kong accepts the `apikey` header alone.
2. Through Kong, a relation with no grant returns **401** for anon and **403** for a signed-in user. The probe treats both as "no grant".
3. Local `supabase db advisors` (CLI 3.3.0) reports lint 0010 on `booking_summary` and search_path / always-true WARNs. It does **not** report storage lint 0025 or definer-execute lint 0028; those newer splinter lints are not in the local SQL bundle.
4. `handle_new_user()` is not flagged by the post's lint (trigger return type). Advisors only warn on its mutable `search_path`.
5. Default grants for new `public` tables/functions are still on (`auto_expose_new_tables` defaults to true). The leftover anon write grants on `bookings` appear without copying the post's `alter default privileges` lines.
6. On Podman, `[analytics] enabled = true` fails health checks (vector expects a Docker engine socket). This lab sets analytics to false.

## License

[MIT](LICENSE)
