-- RLS checks for agent_kit.can_read_agent / agents_read / versions_read.
-- Requires docs/schema.sql (RLS section) loaded on a database with tests/rls/prelude.sql.
--
-- Cases:
--   ownerless + private  -> deny every non-admin, including when can_see_team is true
--   ownerless + org      -> allow any signed-in user
--   owned + private      -> owner only
--   owner deleted        -> ON DELETE SET NULL must not publish a private agent

grant usage on schema public to authenticated;
grant select on public.agents, public.agent_versions to authenticated;

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),  -- owner
  ('44444444-4444-4444-4444-444444444444');  -- deleted later, in its own transaction

insert into public.agents (id, owner_id, team, slug, visibility) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', null, null, 'ownerless-private', 'private'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', null, null, 'ownerless-org', 'org'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', '11111111-1111-1111-1111-111111111111', null, 'owned-private', 'private'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4', null, 'red', 'ownerless-private-team', 'private'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa5', null, 'red', 'ownerless-team', 'team'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa6', null, null, 'ownerless-org-archived', 'org');

update public.agents set archived_at = now() where slug = 'ownerless-org-archived';

insert into public.agent_versions (id, agent_id, n, name, instructions_md, tools, model) values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 1, 'ownerless-private', 'PRIVATE_OWNERLESS_PROMPT', '["secret_tool"]', 'secret/model'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 1, 'ownerless-org', 'ORG_TEMPLATE_PROMPT', '["org_tool"]', 'org/model'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb3', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', 1, 'owned-private', 'OWNED_PRIVATE_PROMPT', '["owned_tool"]', 'owned/model'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb4', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4', 1, 'ownerless-private-team', 'PRIVATE_TEAM_PROMPT', '[]', 'team/model'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb5', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa5', 1, 'ownerless-team', 'TEAM_TEMPLATE_PROMPT', '[]', 'team/model');

-- Fixture is actually present (superuser bypasses RLS). A missing row must not look like a deny.
do $$
begin
  if (select count(*) from public.agents) <> 6 then
    raise exception 'fixture: expected 6 agents, got %', (select count(*) from public.agents);
  end if;
  if (select count(*) from public.agent_versions where instructions_md = 'PRIVATE_OWNERLESS_PROMPT') <> 1 then
    raise exception 'fixture: private ownerless version missing';
  end if;
end $$;

create or replace function pg_temp.assume(p_sub uuid, p_role text default 'member')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_sub::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_sub::text, 'role', 'authenticated', 'app_metadata', json_build_object('role', p_role))::text,
    true);
end $$;

create or replace function pg_temp.expect_can_read(p_slug text, p_want boolean, p_label text)
returns void language plpgsql as $$
declare
  got boolean;
begin
  select agent_kit.can_read_agent(a) into got from public.agents a where a.slug = p_slug;
  if got is distinct from p_want then
    raise exception '%: can_read_agent(%) = %, want %', p_label, p_slug, got, p_want;
  end if;
end $$;

create or replace function pg_temp.expect_visible(p_slug text, p_agents int, p_versions int, p_label text)
returns void language plpgsql as $$
declare
  agents int;
  versions int;
  found_id uuid;
begin
  if current_user <> 'authenticated' then
    raise exception '%: current_user is %, want authenticated', p_label, current_user;
  end if;
  select count(*) into agents from public.agents where slug = p_slug;
  select id into found_id from public.agents where slug = p_slug;
  if found_id is null then
    versions := 0;
  else
    select count(*) into versions from public.agent_versions v where v.agent_id = found_id;
  end if;
  if agents <> p_agents or versions <> p_versions then
    raise exception '%: visible agents=% versions=% , want agents=% versions=%',
      p_label, agents, versions, p_agents, p_versions;
  end if;
end $$;

-- Versions policy, queried by primary key so a hidden parent row cannot mask a leak.
create or replace function pg_temp.expect_version_text(p_text text, p_n int, p_label text)
returns void language plpgsql as $$
declare
  got int;
begin
  select count(*) into got from public.agent_versions where instructions_md = p_text;
  if got <> p_n then
    raise exception '%: versions with % = %, want %', p_label, p_text, got, p_n;
  end if;
end $$;

-- ---------------------------------------------------------------- predicate
-- These calls run as the table owner, who bypasses RLS, so they check the
-- helper's return value itself. The policy section below is what a signed-in
-- user can SELECT. Shipped can_see_team stub: a null team is visible, a named team is not.

begin;
select pg_temp.assume('22222222-2222-2222-2222-222222222222');
select pg_temp.expect_can_read('ownerless-private', false, 'stranger ownerless+private');
select pg_temp.expect_can_read('ownerless-org', true, 'stranger ownerless+org');
select pg_temp.expect_can_read('owned-private', false, 'stranger owned+private');
select pg_temp.expect_can_read('ownerless-private-team', false, 'stranger ownerless+private+team');
select pg_temp.expect_can_read('ownerless-team', false, 'stranger ownerless+team (stub hides named teams)');
select pg_temp.expect_can_read('ownerless-org-archived', false, 'stranger archived ownerless+org');
rollback;

begin;
select pg_temp.assume('11111111-1111-1111-1111-111111111111');
select pg_temp.expect_can_read('owned-private', true, 'owner owned+private');
select pg_temp.expect_can_read('ownerless-private', false, 'owner still cannot read someone else''s ownerless private');
rollback;

begin;
select pg_temp.assume('22222222-2222-2222-2222-222222222222', 'admin');
select pg_temp.expect_can_read('ownerless-private', true, 'admin ownerless+private');
rollback;

-- Host override: can_see_team() returns true for every team. Private must stay private.
begin;
create or replace function agent_kit.can_see_team(team text)
returns boolean language sql stable security definer set search_path = '' as $$
  select true
$$;

select pg_temp.assume('22222222-2222-2222-2222-222222222222');
select pg_temp.expect_can_read('ownerless-private', false, 'team-open stranger ownerless+private');
select pg_temp.expect_can_read('ownerless-private-team', false, 'team-open stranger ownerless+private+team');
select pg_temp.expect_can_read('ownerless-team', true, 'team-open stranger ownerless+team');
select pg_temp.expect_can_read('ownerless-org', true, 'team-open stranger ownerless+org');
select pg_temp.expect_can_read('owned-private', false, 'team-open stranger owned+private');
rollback;

-- ---------------------------------------------------------------- policies
-- agents_read and versions_read, as the authenticated role (RLS on).

begin;
select pg_temp.assume('22222222-2222-2222-2222-222222222222');
set local role authenticated;
select pg_temp.expect_visible('ownerless-private', 0, 0, 'policy stranger ownerless+private');
select pg_temp.expect_visible('ownerless-org', 1, 1, 'policy stranger ownerless+org');
select pg_temp.expect_visible('owned-private', 0, 0, 'policy stranger owned+private');
select pg_temp.expect_version_text('PRIVATE_OWNERLESS_PROMPT', 0, 'policy stranger private prompt');
select pg_temp.expect_version_text('ORG_TEMPLATE_PROMPT', 1, 'policy stranger org prompt');
select pg_temp.expect_version_text('OWNED_PRIVATE_PROMPT', 0, 'policy stranger owned prompt');
rollback;

begin;
select pg_temp.assume('11111111-1111-1111-1111-111111111111');
set local role authenticated;
select pg_temp.expect_visible('owned-private', 1, 1, 'policy owner owned+private');
select pg_temp.expect_visible('ownerless-private', 0, 0, 'policy owner ownerless+private');
select pg_temp.expect_version_text('OWNED_PRIVATE_PROMPT', 1, 'policy owner owned prompt');
select pg_temp.expect_version_text('PRIVATE_OWNERLESS_PROMPT', 0, 'policy owner private prompt');
rollback;

-- Deleting the owner nulls owner_id. The private row must not become readable.
begin;
insert into public.agents (id, owner_id, team, slug, visibility) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa7', '44444444-4444-4444-4444-444444444444', null, 'deleted-owner-private', 'private');
insert into public.agent_versions (id, agent_id, n, name, instructions_md, model) values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb7', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa7', 1, 'deleted-owner-private', 'DELETED_OWNER_PROMPT', 'owned/model');

delete from auth.users where id = '44444444-4444-4444-4444-444444444444';

do $$
declare
  owner uuid;
begin
  select owner_id into owner from public.agents where slug = 'deleted-owner-private';
  if owner is not null then
    raise exception 'delete owner: owner_id is %, want null', owner;
  end if;
end $$;

select pg_temp.assume('22222222-2222-2222-2222-222222222222');
select pg_temp.expect_can_read('deleted-owner-private', false, 'deleted owner predicate');
set local role authenticated;
select pg_temp.expect_visible('deleted-owner-private', 0, 0, 'policy deleted owner');
select pg_temp.expect_version_text('DELETED_OWNER_PROMPT', 0, 'policy deleted owner prompt');
rollback;
