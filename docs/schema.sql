-- Agent Kit schema (reference). Postgres 15+ on Supabase.
-- Every table in `public` has RLS on. Privileged helpers live in the unexposed `agent_kit` schema.
-- The host app overrides agent_kit.can_see_team() to mirror its own access rules.

create schema if not exists agent_kit;
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ---------------------------------------------------------------- host hook
-- Default: an agent with no team is visible per its visibility flag; team agents need the host's rule.
create or replace function agent_kit.can_see_team(team text)
returns boolean language sql stable security definer set search_path = '' as $$
  select team is null  -- host replaces this body, e.g. `select public.user_in_team(team)`
$$;

create or replace function agent_kit.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((auth.jwt() -> 'app_metadata' ->> 'role') in ('admin', 'platform_admin'), false)
$$;

-- ---------------------------------------------------------------- agents
create table public.agents (
  id                 uuid primary key default gen_random_uuid(),
  owner_id           uuid references auth.users(id) on delete set null,  -- null = system / template agent
  team               text,
  slug               text not null,
  visibility         text not null default 'private' check (visibility in ('private', 'team', 'org')),
  current_version_id uuid,
  archived_at        timestamptz,
  created_at         timestamptz not null default now(),
  unique (owner_id, slug)
);

create table public.agent_versions (
  id               uuid primary key default gen_random_uuid(),
  agent_id         uuid not null references public.agents(id) on delete cascade,
  n                int  not null,
  name             text not null,
  avatar_url       text,
  instructions_md  text not null default '',
  tools            jsonb not null default '[]',   -- [{server_id, tool, approval?: 'approved'}]; server_id must be in the host's registry, never a URL
  model            text not null,
  model_fallbacks  text[] not null default '{}',
  budget_run_usd   numeric(10,4) not null default 0.50,
  budget_day_usd   numeric(10,4) not null default 5.00,
  bootstrap_md     text,
  created_by       uuid references auth.users(id),
  created_at       timestamptz not null default now(),
  unique (agent_id, n),
  unique (id, agent_id)              -- target of the composite FK below
);

-- An agent can only point at one of its own versions (stops borrowing another agent's private version).
alter table public.agents
  add constraint agents_current_version_fk foreign key (current_version_id, id)
  references public.agent_versions(id, agent_id) deferrable initially deferred;

-- ---------------------------------------------------------------- routines
create table public.agent_routines (
  id           uuid primary key default gen_random_uuid(),
  agent_id     uuid not null references public.agents(id) on delete cascade,
  cron         text not null,                       -- 5-field, in `timezone`
  timezone     text not null default 'America/New_York',
  prompt       text not null,
  delivery     jsonb not null default '{}',         -- {channel: 'slack', target: '#team'} ; empty = Activity only
  enabled      boolean not null default false,
  expires_at   timestamptz,
  next_run_at  timestamptz,
  created_at   timestamptz not null default now()
);
create index agent_routines_due on public.agent_routines (next_run_at) where enabled;

-- ---------------------------------------------------------------- runs + steps
create table public.agent_runs (
  id            uuid primary key default gen_random_uuid(),
  agent_id      uuid not null references public.agents(id) on delete cascade,
  version_id    uuid not null references public.agent_versions(id),
  user_id       uuid references auth.users(id) on delete set null,
  trigger       text not null check (trigger in ('chat', 'routine', 'event')),
  routine_id    uuid references public.agent_routines(id) on delete set null,
  period_start  timestamptz,
  status        text not null default 'running'
                check (status in ('running', 'awaiting_approval', 'done', 'error', 'budget_stopped')),
  messages      jsonb not null default '[]',        -- AI SDK model messages; what a resume replays
  model_used    text,
  tokens_in     int not null default 0,
  tokens_out    int not null default 0,
  cost_usd      numeric(12,6) not null default 0,
  error         text,
  started_at    timestamptz not null default now(),
  finished_at   timestamptz
);
-- A second tick for the same routine period is a no-op.
create unique index agent_runs_routine_period on public.agent_runs (routine_id, period_start)
  where routine_id is not null;
create index agent_runs_recent on public.agent_runs (agent_id, started_at desc);

create table public.agent_steps (
  run_id         uuid not null references public.agent_runs(id) on delete cascade,
  n              int  not null,
  kind           text not null check (kind in ('model', 'tool')),
  tool_name      text,
  generation_id  text,          -- ties to the AI Gateway request log
  model_served   text,          -- after fallbacks
  latency_ms     int,
  tokens         int,
  cost_usd       numeric(12,6),
  redacted_io    jsonb,
  primary key (run_id, n)
);

-- ---------------------------------------------------------------- actions (proposed writes)
create table public.agent_actions (
  id           uuid primary key default gen_random_uuid(),
  run_id       uuid not null references public.agent_runs(id) on delete cascade,
  approval_id  text not null,                        -- AI SDK tool-approval-request id
  tool_name    text not null,
  args         jsonb not null,                       -- exact args; what runs is what the card showed
  display      jsonb not null,                       -- {verb, title, fields, body}
  status       text not null default 'pending'
               check (status in ('pending', 'approved', 'declined', 'expired', 'superseded', 'executed', 'failed')),
  decided_by   uuid references auth.users(id),
  decided_at   timestamptz,
  expires_at   timestamptz not null default now() + interval '24 hours',
  result       jsonb,
  created_at   timestamptz not null default now(),
  unique (approval_id)
);
create index agent_actions_inbox on public.agent_actions (status, created_at desc) where status = 'pending';

-- ---------------------------------------------------------------- memory
create table public.agent_memory (
  agent_id    uuid not null references public.agents(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  key         text not null,
  value       text not null check (length(value) <= 2000),
  updated_at  timestamptz not null default now(),
  primary key (agent_id, user_id, key)
);

-- ---------------------------------------------------------------- RLS
alter table public.agents         enable row level security;
alter table public.agent_versions enable row level security;
alter table public.agent_routines enable row level security;
alter table public.agent_runs     enable row level security;
alter table public.agent_steps    enable row level security;
alter table public.agent_actions  enable row level security;
alter table public.agent_memory   enable row level security;

create or replace function agent_kit.can_read_agent(a public.agents)
returns boolean language sql stable security definer set search_path = '' as $$
  select a.archived_at is null and (
       a.owner_id = auth.uid()
    or (a.visibility = 'org')
    or (a.visibility = 'team' and agent_kit.can_see_team(a.team))
    or (a.owner_id is null and agent_kit.can_see_team(a.team))
    or agent_kit.is_admin())
$$;

-- Policies run as the caller, so the caller needs to reach the helpers (the schema itself stays unexposed to the Data API).
grant usage on schema agent_kit to authenticated;
grant execute on function agent_kit.can_see_team(text), agent_kit.is_admin(), agent_kit.can_read_agent(public.agents) to authenticated;

create policy agents_read on public.agents for select to authenticated
  using (agent_kit.can_read_agent(agents));
create policy agents_insert on public.agents for insert to authenticated
  with check (owner_id = auth.uid());
create policy agents_update on public.agents for update to authenticated
  using (owner_id = auth.uid() or agent_kit.is_admin())
  with check (owner_id = auth.uid() or agent_kit.is_admin());

-- Sharing is a publish: only admins can widen visibility or move an agent to another team or owner.
create or replace function agent_kit.guard_agent_sharing()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if auth.role() = 'authenticated' and not agent_kit.is_admin() and (
       new.visibility is distinct from old.visibility and new.visibility <> 'private'
    or new.team     is distinct from old.team
    or new.owner_id is distinct from old.owner_id) then
    raise exception 'sharing an agent needs an admin';
  end if;
  return new;
end $$;
create trigger agents_guard_sharing before update on public.agents
  for each row execute function agent_kit.guard_agent_sharing();
-- New agents start private for non-admins.
create policy agents_insert_private on public.agents as restrictive for insert to authenticated
  with check (visibility = 'private' and team is null or agent_kit.is_admin());

-- Versions are append-only: no update or delete policy exists.
-- Skipping approval on a write tool is an admin decision: a shared agent would otherwise write as its viewers without asking.
create or replace function agent_kit.guard_version_tools()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if auth.role() = 'authenticated' and not agent_kit.is_admin()
     and jsonb_path_exists(new.tools, '$[*] ? (exists(@.approval))') then
    raise exception 'approval overrides need an admin';
  end if;
  return new;
end $$;
create trigger versions_guard_tools before insert on public.agent_versions
  for each row execute function agent_kit.guard_version_tools();
create policy versions_read on public.agent_versions for select to authenticated
  using (exists (select 1 from public.agents a where a.id = agent_id and agent_kit.can_read_agent(a)));
create policy versions_insert on public.agent_versions for insert to authenticated
  with check (created_by = auth.uid() and exists (
    select 1 from public.agents a where a.id = agent_id and (a.owner_id = auth.uid() or agent_kit.is_admin())));

create policy routines_owner on public.agent_routines for all to authenticated
  using (exists (select 1 from public.agents a where a.id = agent_id and a.owner_id = auth.uid()))
  with check (exists (select 1 from public.agents a where a.id = agent_id and a.owner_id = auth.uid()));

-- Runs, steps and actions are written by the server (service role) only.
create policy runs_read on public.agent_runs for select to authenticated
  using (user_id = auth.uid()
      or exists (select 1 from public.agents a where a.id = agent_id and a.owner_id = auth.uid()));
create policy steps_read on public.agent_steps for select to authenticated
  using (exists (select 1 from public.agent_runs r where r.id = run_id));   -- inherits runs_read
create policy actions_read on public.agent_actions for select to authenticated
  using (exists (select 1 from public.agent_runs r where r.id = run_id));   -- inherits runs_read

create policy memory_own on public.agent_memory for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and exists (
    select 1 from public.agents a where a.id = agent_id and agent_kit.can_read_agent(a)));

-- Views over these tables must be `with (security_invoker = true)`.

-- ---------------------------------------------------------------- scheduler
-- Store once:  select vault.create_secret('https://<your-app>.vercel.app', 'agent_kit_app_url');
--              select vault.create_secret('<random 48 hex>',            'agent_kit_tick_secret');
-- Target the production domain: preview URLs sit behind deployment protection.
select cron.schedule('agent-kit-tick', '* * * * *', $$
  select net.http_post(
    url     := (select decrypted_secret from vault.decrypted_secrets where name = 'agent_kit_app_url') || '/api/agents/tick',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-agent-kit-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'agent_kit_tick_secret')),
    body    := '{}'::jsonb)
$$);

-- Claim due routines atomically. Called by /tick with the service role only (invoker rights; RLS bypassed by that role).
create or replace function public.agent_kit_claim_due_routines(max_n int default 25)
returns setof public.agent_routines language sql security invoker set search_path = '' as $$
  select r.* from public.agent_routines r
  where r.enabled and r.next_run_at <= now() and (r.expires_at is null or r.expires_at > now())
  order by r.next_run_at
  limit max_n
  for update skip locked
$$;
revoke all on function public.agent_kit_claim_due_routines(int) from public, anon, authenticated;
grant execute on function public.agent_kit_claim_due_routines(int) to service_role;
