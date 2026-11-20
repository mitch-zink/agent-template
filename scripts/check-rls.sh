#!/usr/bin/env bash
# Load docs/schema.sql on stock Postgres and run docs/schema.rls.test.sql.
# pg_cron, pg_net and Supabase auth are stubbed; the policies under test are the real ones.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
db="agent_kit_rls_$$"

if [[ "$(id -un)" == "postgres" ]]; then
  psqlq() { psql "$@"; }
else
  psqlq() { sudo -u postgres psql "$@"; }
fi

cleanup() {
  psqlq -d postgres -v ON_ERROR_STOP=1 -c \
    "select pg_terminate_backend(pid) from pg_stat_activity where datname = '${db}' and pid <> pg_backend_pid();" \
    >/dev/null 2>&1 || true
  psqlq -d postgres -v ON_ERROR_STOP=1 -c "drop database if exists ${db};" >/dev/null 2>&1 || true
}
trap cleanup EXIT

psqlq -d postgres -v ON_ERROR_STOP=1 -c "drop database if exists ${db};" >/dev/null
psqlq -d postgres -v ON_ERROR_STOP=1 -c "create database ${db};" >/dev/null

psqlq -d "$db" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
create schema if not exists auth;
create table auth.users (id uuid primary key);
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create or replace function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb) $$;
create or replace function auth.role() returns text language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), current_user) $$;
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if;
end $$;
create schema if not exists cron;
create schema if not exists vault;
create table vault.decrypted_secrets (name text, decrypted_secret text);
create or replace function cron.schedule(job_name text, schedule text, command text)
returns bigint language sql as $$ select 1::bigint $$;
SQL

sed -e '/^create extension if not exists pg_cron;$/d' \
    -e '/^create extension if not exists pg_net;$/d' \
    "$root/docs/schema.sql" \
  | psqlq -d "$db" -v ON_ERROR_STOP=1 -f - >/dev/null

psqlq -d "$db" -v ON_ERROR_STOP=1 -f "$root/docs/schema.rls.test.sql" >/dev/null
echo "rls ok"
