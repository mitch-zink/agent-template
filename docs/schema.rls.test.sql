-- RLS checks for docs/schema.sql. Not a migration.
-- scripts/check-rls.sh loads the schema, then this file, on a scratch database.
-- Proves: ownerless+private is denied, ownerless+org is allowed, owned+private is owner-only.

do $$
begin
  if current_database() not like 'agent_kit_rls_%' then
    raise exception 'refusing to load fixtures outside the check-rls scratch database (current: %)', current_database();
  end if;
end $$;

grant usage on schema public to authenticated;
grant select, update on public.agents, public.agent_versions to authenticated;

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222'),
  ('33333333-3333-3333-3333-333333333333'),
  ('44444444-4444-4444-4444-444444444444');

insert into public.agents (id, owner_id, team, slug, visibility) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', null, null, 'ownerless-private', 'private'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', null, null, 'ownerless-org', 'org'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', '11111111-1111-1111-1111-111111111111', null, 'owned-private', 'private'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4', '11111111-1111-1111-1111-111111111111', null, 'owned-org', 'org'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa5', '22222222-2222-2222-2222-222222222222', null, 'stranger-private', 'private'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa6', null, 'billing', 'ownerless-team-billing', 'team'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa7', null, 'other', 'ownerless-team-other', 'team'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa8', null, 'billing', 'ownerless-private-billing', 'private'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa9', null, null, 'archived-org', 'org'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa10', '44444444-4444-4444-4444-444444444444', null, 'doomed-private', 'private');

update public.agents set archived_at = now() where slug = 'archived-org';

insert into public.agent_versions (id, agent_id, n, name, instructions_md, tools, model) values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 1, 'private template', 'SECRET_PRIVATE_INSTRUCTIONS', '["mail.send"]', 'hidden-model'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 1, 'org template', 'ORG_INSTRUCTIONS', '[]', 'org-model'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb3', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', 1, 'owned', 'OWNED_SECRET', '[]', 'owned-model'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb8', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa8', 1, 'private on team', 'PRIVATE_ON_TEAM', '[]', 'team-model');

update public.agents a
set current_version_id = v.id
from public.agent_versions v
where v.agent_id = a.id and v.n = 1;

create or replace function public.rls_test_become(p_uid uuid, p_role text)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, false);
  perform set_config('request.jwt.claim.role', 'authenticated', false);
  perform set_config(
    'request.jwt.claims',
    json_build_object('app_metadata', json_build_object('role', p_role))::text,
    false);
end $$;

create or replace function public.rls_test_assert_agent(p_slug text, p_expect boolean)
returns void language plpgsql as $$
declare got boolean;
begin
  select exists(select 1 from public.agents a where a.slug = p_slug) into got;
  if got is distinct from p_expect then
    raise exception 'agents.% readable=% expected %', p_slug, got, p_expect;
  end if;
end $$;

create or replace function public.rls_test_assert_instructions(p_text text, p_expect boolean)
returns void language plpgsql as $$
declare got boolean;
begin
  select exists(select 1 from public.agent_versions v where v.instructions_md = p_text) into got;
  if got is distinct from p_expect then
    raise exception 'instructions % readable=% expected %', p_text, got, p_expect;
  end if;
end $$;

-- The turn route loads the agent and its current version in one read.
create or replace function public.rls_test_assert_turn(p_slug text, p_expect boolean)
returns void language plpgsql as $$
declare got boolean;
begin
  select exists(
    select 1
    from public.agents a
    join public.agent_versions v
      on v.id = a.current_version_id and v.agent_id = a.id
    where a.slug = p_slug
  ) into got;
  if got is distinct from p_expect then
    raise exception 'turn load % readable=% expected %', p_slug, got, p_expect;
  end if;
end $$;

grant execute on function
  public.rls_test_assert_agent(text, boolean),
  public.rls_test_assert_instructions(text, boolean),
  public.rls_test_assert_turn(text, boolean)
to authenticated;

-- Shipped can_see_team stub: null team passes, a named team does not.
select public.rls_test_become('22222222-2222-2222-2222-222222222222', 'member');
set role authenticated;
select public.rls_test_assert_agent('ownerless-private', false);
select public.rls_test_assert_instructions('SECRET_PRIVATE_INSTRUCTIONS', false);
select public.rls_test_assert_turn('ownerless-private', false);
select public.rls_test_assert_agent('ownerless-org', true);
select public.rls_test_assert_instructions('ORG_INSTRUCTIONS', true);
select public.rls_test_assert_turn('ownerless-org', true);
select public.rls_test_assert_agent('owned-private', false);
select public.rls_test_assert_instructions('OWNED_SECRET', false);
select public.rls_test_assert_agent('owned-org', true);
select public.rls_test_assert_agent('stranger-private', true);
select public.rls_test_assert_agent('archived-org', false);
reset role;

select public.rls_test_become('11111111-1111-1111-1111-111111111111', 'member');
set role authenticated;
select public.rls_test_assert_agent('owned-private', true);
select public.rls_test_assert_instructions('OWNED_SECRET', true);
select public.rls_test_assert_agent('stranger-private', false);
select public.rls_test_assert_agent('ownerless-private', false);
reset role;

select public.rls_test_become('33333333-3333-3333-3333-333333333333', 'admin');
set role authenticated;
select public.rls_test_assert_agent('ownerless-private', true);
select public.rls_test_assert_agent('archived-org', false);
reset role;

-- Host hook: team members can see team 'billing'. Private still does not follow.
create or replace function agent_kit.can_see_team(team text)
returns boolean language sql stable security definer set search_path = '' as $$
  select team = 'billing'
$$;

select public.rls_test_become('22222222-2222-2222-2222-222222222222', 'member');
set role authenticated;
select public.rls_test_assert_agent('ownerless-team-billing', true);
select public.rls_test_assert_agent('ownerless-team-other', false);
select public.rls_test_assert_agent('ownerless-private-billing', false);
select public.rls_test_assert_instructions('PRIVATE_ON_TEAM', false);
select public.rls_test_assert_agent('ownerless-org', true);
reset role;

-- An admin clearing owner_id must not publish a private agent.
select public.rls_test_become('33333333-3333-3333-3333-333333333333', 'admin');
set role authenticated;
update public.agents set owner_id = null where slug = 'owned-private';
reset role;

select public.rls_test_become('22222222-2222-2222-2222-222222222222', 'member');
set role authenticated;
select public.rls_test_assert_agent('owned-private', false);
select public.rls_test_assert_instructions('OWNED_SECRET', false);
reset role;

select public.rls_test_become('33333333-3333-3333-3333-333333333333', 'admin');
set role authenticated;
select public.rls_test_assert_agent('owned-private', true);
reset role;

-- Deleting the owner must not null owner_id. No other FK references this user.
do $$
declare def text;
begin
  select pg_get_constraintdef(oid) into def
  from pg_constraint
  where conname = 'agents_owner_id_fkey';
  if def not like '%ON DELETE RESTRICT%' then
    raise exception 'agents.owner_id is "%", expected ON DELETE RESTRICT', def;
  end if;
  begin
    delete from auth.users where id = '44444444-4444-4444-4444-444444444444';
    raise exception 'deleting an owner cleared owner_id or removed the agent';
  exception
    when foreign_key_violation then
      null;
  end;
end $$;

do $$
declare oid uuid;
begin
  select owner_id into oid from public.agents where slug = 'doomed-private';
  if oid is distinct from '44444444-4444-4444-4444-444444444444'::uuid then
    raise exception 'doomed-private owner_id became %', oid;
  end if;
end $$;

select public.rls_test_become('22222222-2222-2222-2222-222222222222', 'member');
set role authenticated;
select public.rls_test_assert_agent('doomed-private', false);
reset role;

drop function public.rls_test_become(uuid, text);
drop function public.rls_test_assert_agent(text, boolean);
drop function public.rls_test_assert_instructions(text, boolean);
drop function public.rls_test_assert_turn(text, boolean);
