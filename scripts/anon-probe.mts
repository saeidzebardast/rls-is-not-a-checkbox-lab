// Query every exposed relation with the public key, then optionally again
// as a brand-new user. Starting point, not a finished tool. Run it against
// a local or staging database that has seed data, never against production.
import { readFileSync } from "node:fs";

const url = process.env.SUPABASE_URL!;
const key = process.env.SUPABASE_ANON_KEY!; // publishable key or legacy anon key

const lines = (file: string) =>
  readFileSync(file, "utf8").split("\n").map((l) => l.trim())
    .filter((l) => l && !l.startsWith("#"));

const allow = new Set(lines("rls-public-allowlist.txt"));
const relations = lines("relations.tsv").map((l) => {
  const [schema, name, kind, rows] = l.split("\t");
  return { schema, name, kind, rows: Number(rows) };
});

// A user who just signed up owns no rows, so anything it can read
// that is not allowlisted belongs to somebody else.
async function signUp(): Promise<string> {
  const res = await fetch(`${url}/auth/v1/signup`, {
    method: "POST",
    headers: { apikey: key, "Content-Type": "application/json" },
    body: JSON.stringify({
      email: `probe-${crypto.randomUUID()}@example.com`,
      password: crypto.randomUUID(),
    }),
  });
  const body = (await res.json()) as { access_token?: string };
  if (!body.access_token) throw new Error(`sign-up gave no session (HTTP ${res.status})`);
  return body.access_token;
}

async function probe(who: string, token?: string): Promise<number> {
  const headers: Record<string, string> = { apikey: key };
  const bearer = token ?? (key.startsWith("eyJ") ? key : undefined); // legacy JWT key
  if (bearer) headers.Authorization = `Bearer ${bearer}`;

  let failed = 0;
  for (const r of relations) {
    const id = `${r.schema}.${r.name}`;
    const res = await fetch(
      `${url}/rest/v1/${encodeURIComponent(r.name)}?select=*&limit=1`,
      { headers: { ...headers, "Accept-Profile": r.schema } },
    );

    let ok: boolean;
    let reason: string;
    if (res.status === 401 || res.status === 403) {
      [ok, reason] = [true, "no grant"];
    } else if (res.status === 406) {
      [ok, reason] = [true, "schema not exposed"];
    } else if (res.status === 200) {
      const rows = (await res.json()) as unknown[];
      if (allow.has(id)) [ok, reason] = [true, "public (allowlisted)"];
      else if (rows.length > 0) [ok, reason] = [false, `${who} can read rows`];
      else if (r.rows === 0) [ok, reason] = [false, "table is empty, seed it"];
      else [ok, reason] = [true, "rows hidden by RLS"];
    } else {
      // 404 means the API does not know a relation the catalog lists,
      // usually a stale schema cache. Fail until someone looks.
      [ok, reason] = [false, `unexpected HTTP ${res.status}`];
    }

    if (!ok) failed++;
    console.log(`${(ok ? "ok" : "FAIL").padEnd(6)}${reason.padEnd(25)}${r.kind.padEnd(7)}${id}`);
  }
  return failed;
}

let failed = await probe("anon");
let total = relations.length;
if (process.env.PROBE_USER_JWT || process.env.PROBE_SIGN_UP) {
  console.log("\nas a new user:");
  failed += await probe("user", process.env.PROBE_USER_JWT || (await signUp()));
  total *= 2;
}

console.log(`\n${failed} of ${total} checks failed`);
process.exit(failed > 0 ? 1 : 0);
