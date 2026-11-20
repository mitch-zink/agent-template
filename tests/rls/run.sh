#!/usr/bin/env bash
# Load docs/schema.sql (RLS section) and run the can_read_agent checks.
# Uses libpq env when a connection already works; otherwise local peer auth as postgres.
set -euo pipefail
cd "$(dirname "$0")/../.."

db=${PGDATABASE_TEST:-agent_kit_rls_test}
if [[ ! "$db" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  echo "PGDATABASE_TEST must be a plain identifier" >&2
  exit 1
fi
schema=$(mktemp)
trap 'rm -f "$schema"' EXIT

python3 - "$schema" <<'PY'
import pathlib, sys
out = pathlib.Path(sys.argv[1])
lines = pathlib.Path("docs/schema.sql").read_text().splitlines(keepends=True)
kept = []
for line in lines:
    if line.startswith("create extension if not exists pg_cron"):
        continue
    if line.startswith("create extension if not exists pg_net"):
        continue
    if line.startswith("-- ---------------------------------------------------------------- scheduler"):
        break
    kept.append(line)
out.write_text("".join(kept))
PY
chmod a+r "$schema"
grep -q 'function agent_kit.can_read_agent' "$schema"
if grep -q 'cron.schedule' "$schema"; then
  echo "schema filter included the scheduler section" >&2
  exit 1
fi

psql_base=(psql -v ON_ERROR_STOP=1 -X -q)
if ! "${psql_base[@]}" -d postgres -c 'select 1' >/dev/null 2>&1; then
  psql_base=(sudo -u postgres psql -v ON_ERROR_STOP=1 -X -q)
fi

"${psql_base[@]}" -d postgres -c "drop database if exists ${db};"
"${psql_base[@]}" -d postgres -c "create database ${db};"
"${psql_base[@]}" -d "$db" -f tests/rls/prelude.sql
"${psql_base[@]}" -d "$db" -f "$schema"
"${psql_base[@]}" -d "$db" -f tests/rls/can_read_agent.sql >/dev/null
"${psql_base[@]}" -d postgres -c "drop database if exists ${db};" >/dev/null
echo "rls ok"
