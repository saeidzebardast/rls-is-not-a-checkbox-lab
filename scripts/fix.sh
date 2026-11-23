#!/usr/bin/env bash
set -euo pipefail
# Apply every fixes/*.sql file to the local DB, in order.
# Needs DB_URL from: eval "$(supabase status -o env)"
if [[ -z "${DB_URL:-}" ]]; then
  eval "$(supabase status -o env)"
fi
shopt -s nullglob
files=(fixes/*.sql)
if (( ${#files[@]} == 0 )); then
  echo "no fixes/*.sql files" >&2
  exit 1
fi
for f in "${files[@]}"; do
  echo "applying $f"
  psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$f"
done
