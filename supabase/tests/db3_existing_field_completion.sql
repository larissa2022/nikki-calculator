begin;

-- DB-3 development-only verification. Every fixture write is rolled back.
-- Run only after scripts/check-dev-link.mjs confirms tfwejruvdahonacyldrg.

do $$
begin
  if exists (
    select 1 from auth.users
    where id between 'db300000-0000-4000-8000-000000000001'::uuid
      and 'db300000-0000-4000-8000-000000000007'::uuid
  ) or exists (
    select 1 from public.clothes
    where id like 'db3_fixture_20260720_%'
  ) or exists (
    select 1 from public.pending_clothes
    where id between 930000001 and 930000099
  ) then
    raise exception 'DB3_ASSERT: fixture identifiers already exist';
  end if;
end;
$$;

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  ('db300000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'authenticated',
  'authenticated',
  'db3-fixture-' || value || '@example.invalid',
  '',
  pg_catalog.now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  pg_catalog.now(),
  pg_catalog.now()
from pg_catalog.generate_series(1, 7) as fixture(value);

update public.profiles
set role = 'admin', role_level = 1
where id = 'db300000-0000-4000-8000-000000000001'::uuid;

insert into public.clothes (
  id,
  name,
  category,
  game_id,
  stars,
  scores,
  suit_id,
  temp_suit_name,
  tags
)
values (
  'db3_fixture_20260720_01',
  'DB3 正式库补全测试',
  'DB3 测试分类',
  null,
  null,
  null,
  null,
  '保留的正式库套装名',
  '保留的正式库标签'
);

insert into public.pending_clothes (
  id,
  created_at,
  name,
  category,
  game_id,
  stars,
  scores,
  suit_id,
  temp_suit_name,
  tags,
  status,
  submitted_by
)
values
  (930000001, '2026-07-20 00:01:00+00', 'DB3 正式库补全测试', 'DB3 测试分类', '930001', 5, '{"简约":100,"活泼":200}', null, null, null, 'pending', 'db300000-0000-4000-8000-000000000002'),
  (930000002, '2026-07-20 00:07:00+00', 'DB3 正式库补全测试', 'DB3 测试分类', '930001', 5, '{"简约":100,"活泼":200}', null, null, null, 'pending', 'db300000-0000-4000-8000-000000000002'),
  (930000003, '2026-07-20 00:02:00+00', 'DB3 正式库补全测试', 'DB3 测试分类', '930001', 5, '{"简约":100,"活泼":200}', null, null, null, 'pending', 'db300000-0000-4000-8000-000000000003'),
  (930000004, '2026-07-20 00:03:00+00', 'DB3 正式库补全测试', 'DB3 测试分类', '930001', 5, '{"简约":100,"活泼":200}', null, null, null, 'pending', 'db300000-0000-4000-8000-000000000004'),
  (930000005, '2026-07-20 00:04:00+00', 'DB3 正式库补全测试', 'DB3 测试分类', '930001', 5, '{"简约":100,"活泼":200}', null, null, null, 'pending', 'db300000-0000-4000-8000-000000000005'),
  (930000006, '2026-07-20 00:05:00+00', 'DB3 正式库补全测试', 'DB3 测试分类', '930001', 5, '{"简约":100,"活泼":200}', null, null, null, 'pending', 'db300000-0000-4000-8000-000000000006'),
  (930000007, '2026-07-20 00:06:00+00', 'DB3 正式库补全测试', 'DB3 测试分类', '930001', 5, '{"简约":100,"活泼":200}', null, null, null, 'pending', 'db300000-0000-4000-8000-000000000007'),
  (930000008, '2026-07-20 00:00:00+00', 'DB3 正式库补全测试', 'DB3 测试分类', '930001', 5, '{"简约":100,"活泼":200}', null, null, null, 'pending', null);

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db300000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);

do $$
declare
  v_denied boolean := false;
begin
  begin
    perform public.complete_existing_clothes_from_pending(
      'db3_fixture_20260720_01',
      'DB3 正式库补全测试',
      '930001',
      'DB3 测试分类',
      5,
      '{"简约":100,"活泼":200}'::jsonb,
      null,
      null,
      null,
      array[930000001,930000002,930000003,930000004,930000005,930000006,930000007,930000008]::bigint[]
    );
  exception when others then
    v_denied := pg_catalog.strpos(sqlerrm, '没有补全正式库权限') > 0;
  end;

  if not v_denied then
    raise exception 'DB3_ASSERT: ordinary authenticated user was not denied';
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db300000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

do $$
declare
  v_result jsonb;
begin
  v_result := public.complete_existing_clothes_from_pending(
    'db3_fixture_20260720_01',
    'DB3 正式库补全测试',
    '930001',
    'DB3 测试分类',
    5,
    '{"简约":100,"活泼":200}'::jsonb,
    null,
    null,
    null,
    array[930000008,930000007,930000002,930000006,930000001,930000005,930000004,930000003]::bigint[]
  );

  if v_result->>'already_completed' <> 'false'
    or (v_result->>'approved_pending_count')::integer <> 8
    or (v_result->>'contribution_count')::integer <> 5
    or (v_result->>'points_awarded_count')::integer <> 5
    or (v_result->>'points_awarded_total')::integer <> 25
    or (v_result->>'wardrobe_updated_count')::integer <> 5 then
    raise exception 'DB3_ASSERT: first completion result mismatch: %', v_result;
  end if;
end;
$$;

do $$
declare
  v_count integer;
  v_total integer;
  v_ids bigint[];
begin
  select count(*), coalesce(sum(ledger.delta), 0)
    into v_count, v_total
  from public.points_ledger as ledger
  join public.clothing_contributions as contribution
    on contribution.id = ledger.source_id
  where contribution.clothes_id = 'db3_fixture_20260720_01';

  if v_count <> 5 or v_total <> 25 then
    raise exception 'DB3_ASSERT: points facts mismatch: count %, total %', v_count, v_total;
  end if;

  select array_agg(source_pending_id order by contribution_rank)
    into v_ids
  from public.clothing_contributions
  where clothes_id = 'db3_fixture_20260720_01';

  if v_ids is distinct from array[930000001,930000003,930000004,930000005,930000006]::bigint[] then
    raise exception 'DB3_ASSERT: stable top-five sources mismatch: %', v_ids;
  end if;

  if (select count(*) from public.pending_clothes where id between 930000001 and 930000008 and status = 'approved') <> 8 then
    raise exception 'DB3_ASSERT: pending approval count mismatch';
  end if;

  if (select count(*) from public.user_wardrobes where user_id between 'db300000-0000-4000-8000-000000000002'::uuid and 'db300000-0000-4000-8000-000000000006'::uuid and coalesce(owned_clothes, '[]'::jsonb) @> '["db3_fixture_20260720_01"]'::jsonb) <> 5 then
    raise exception 'DB3_ASSERT: top-five wardrobe writeback mismatch';
  end if;

  if exists (
    select 1 from public.user_wardrobes
    where user_id = 'db300000-0000-4000-8000-000000000007'::uuid
      and coalesce(owned_clothes, '[]'::jsonb) @> '["db3_fixture_20260720_01"]'::jsonb
  ) then
    raise exception 'DB3_ASSERT: sixth contributor received wardrobe writeback';
  end if;

  if not exists (
    select 1 from public.clothes
    where id = 'db3_fixture_20260720_01'
      and game_id = '930001'
      and stars = '5'
      and scores = '{"简约":100,"活泼":200}'::jsonb
      and temp_suit_name = '保留的正式库套装名'
      and tags = '保留的正式库标签'
  ) then
    raise exception 'DB3_ASSERT: empty fields were not filled or non-empty fields were overwritten';
  end if;
end;
$$;

update public.profiles
set role = 'super_admin', role_level = 2
where id = 'db300000-0000-4000-8000-000000000001'::uuid;

do $$
declare
  v_result jsonb;
  v_event_count integer;
  v_points_count integer;
begin
  v_result := public.complete_existing_clothes_from_pending(
    'db3_fixture_20260720_01',
    'DB3 正式库补全测试',
    '930001',
    'DB3 测试分类',
    5,
    '{"简约":100,"活泼":200}'::jsonb,
    null,
    null,
    null,
    array[930000001,930000002,930000003,930000004,930000005,930000006,930000007,930000008]::bigint[]
  );

  select count(*) into v_event_count
  from public.clothing_contributions
  where clothes_id = 'db3_fixture_20260720_01';

  select count(*) into v_points_count
  from public.points_ledger as ledger
  join public.clothing_contributions as contribution on contribution.id = ledger.source_id
  where contribution.clothes_id = 'db3_fixture_20260720_01';

  if v_result->>'already_completed' <> 'true'
    or v_event_count <> 5
    or v_points_count <> 5 then
    raise exception 'DB3_ASSERT: retry was not idempotent: %, %, %', v_result, v_event_count, v_points_count;
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db300000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);

do $$
declare
  v_points bigint;
begin
  select total_points into v_points from public.user_points_summary;
  if v_points <> 5 then
    raise exception 'DB3_ASSERT: DB-2 points summary mismatch for awarded user: %', v_points;
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db300000-0000-4000-8000-000000000007","role":"authenticated"}',
  true
);

do $$
declare
  v_points bigint;
begin
  select total_points into v_points from public.user_points_summary;
  if v_points <> 0 then
    raise exception 'DB3_ASSERT: sixth user unexpectedly received points: %', v_points;
  end if;
end;
$$;

insert into public.clothes (id, name, category)
values ('db3_fixture_20260720_02', 'DB3 事务回滚测试', 'DB3 测试分类');

insert into public.pending_clothes (
  id, created_at, name, category, game_id, stars, scores, status, submitted_by
)
values (
  930000011,
  '2026-07-20 01:00:00+00',
  'DB3 事务回滚测试',
  'DB3 测试分类',
  '930002',
  4,
  '{"简约":80}'::jsonb,
  'pending',
  'db300000-0000-4000-8000-000000000002'::uuid
);

create function pg_temp.db3_force_points_failure()
returns trigger
language plpgsql
as $$
begin
  if new.user_id = 'db300000-0000-4000-8000-000000000002'::uuid then
    raise exception 'DB3_EXPECTED_POINTS_FAILURE';
  end if;
  return new;
end;
$$;

create trigger db3_force_points_failure
before insert on public.points_ledger
for each row execute function pg_temp.db3_force_points_failure();

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db300000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

do $$
declare
  v_failed boolean := false;
begin
  begin
    perform public.complete_existing_clothes_from_pending(
      'db3_fixture_20260720_02',
      'DB3 事务回滚测试',
      '930002',
      'DB3 测试分类',
      4,
      '{"简约":80}'::jsonb,
      null,
      null,
      null,
      array[930000011]::bigint[]
    );
  exception when others then
    v_failed := pg_catalog.strpos(sqlerrm, 'DB3_EXPECTED_POINTS_FAILURE') > 0;
  end;

  if not v_failed then
    raise exception 'DB3_ASSERT: expected points failure was not observed';
  end if;

  if exists (
    select 1 from public.clothes
    where id = 'db3_fixture_20260720_02'
      and (game_id is not null or stars is not null or scores is not null)
  ) or exists (
    select 1 from public.pending_clothes
    where id = 930000011 and status <> 'pending'
  ) or exists (
    select 1 from public.clothing_contributions
    where clothes_id = 'db3_fixture_20260720_02'
  ) or exists (
    select 1 from public.user_wardrobes
    where user_id = 'db300000-0000-4000-8000-000000000002'::uuid
      and coalesce(owned_clothes, '[]'::jsonb) @> '["db3_fixture_20260720_02"]'::jsonb
  ) then
    raise exception 'DB3_ASSERT: induced failure left a partial write';
  end if;
end;
$$;

drop trigger db3_force_points_failure on public.points_ledger;

do $$
declare
  v_signature text := 'public.complete_existing_clothes_from_pending(text,text,text,text,integer,jsonb,uuid,text,text,bigint[])';
begin
  if has_function_privilege('anon', v_signature, 'EXECUTE')
    or not has_function_privilege('authenticated', v_signature, 'EXECUTE')
    or not has_function_privilege('service_role', v_signature, 'EXECUTE') then
    raise exception 'DB3_ASSERT: RPC execute grants mismatch';
  end if;

  if has_table_privilege('anon', 'public.clothing_contributions', 'SELECT,INSERT,UPDATE,DELETE')
    or has_table_privilege('authenticated', 'public.clothing_contributions', 'SELECT,INSERT,UPDATE,DELETE')
    or has_table_privilege('anon', 'public.points_ledger', 'SELECT,INSERT,UPDATE,DELETE')
    or has_table_privilege('authenticated', 'public.points_ledger', 'SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'DB3_ASSERT: DB-1 direct table privileges widened';
  end if;
end;
$$;

select jsonb_build_object(
  'status', 'passed',
  'effective_contributors', 5,
  'points_each', 5,
  'points_total', 25,
  'approved_pending', 8,
  'retry_idempotent', true,
  'transaction_rollback', true,
  'ordinary_user_denied', true,
  'fixture_rollback_pending', true
) as db3_verification;

rollback;
