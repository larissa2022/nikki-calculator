begin;

-- DB-4 development-only verification. Every fixture write is rolled back.
-- Run only after scripts/check-dev-link.mjs confirms tfwejruvdahonacyldrg.

do $$
begin
  if exists (
    select 1 from auth.users
    where id between 'db400000-0000-4000-8000-000000000001'::uuid
      and 'db400000-0000-4000-8000-000000000007'::uuid
  ) or exists (
    select 1 from public.clothes
    where id like 'db4_fixture_20260721_%'
  ) or exists (
    select 1 from public.pending_clothes
    where id between 940000001 and 940000099
  ) then
    raise exception 'DB4_ASSERT: fixture identifiers already exist';
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
  ('db400000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'authenticated',
  'authenticated',
  'db4-fixture-' || value || '@example.invalid',
  '',
  pg_catalog.now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  pg_catalog.now(),
  pg_catalog.now()
from pg_catalog.generate_series(1, 7) as fixture(value);

update public.profiles
set role = 'admin', role_level = 1
where id = 'db400000-0000-4000-8000-000000000001'::uuid;

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
  (940000001, '2026-07-21 01:01:00+00', 'DB4 管理员仲裁测试', 'DB4 测试分类', '940001', 5, '{"简约":100,"活泼":200}'::jsonb, null, null, 'DB4 标签', 'pending', 'db400000-0000-4000-8000-000000000002'),
  (940000002, '2026-07-21 01:07:00+00', 'DB4 管理员仲裁测试', 'DB4 测试分类', '940001', 5, '{"简约":100,"活泼":200}'::jsonb, null, null, 'DB4 标签', 'pending', 'db400000-0000-4000-8000-000000000002'),
  (940000003, '2026-07-21 01:02:00+00', 'DB4 管理员仲裁测试', 'DB4 测试分类', '940001', 5, '{"简约":100,"活泼":200}'::jsonb, null, null, 'DB4 标签', 'pending', 'db400000-0000-4000-8000-000000000003'),
  (940000004, '2026-07-21 01:03:00+00', 'DB4 管理员仲裁测试', 'DB4 测试分类', '940001', 5, '{"简约":100,"活泼":200}'::jsonb, null, null, 'DB4 标签', 'pending', 'db400000-0000-4000-8000-000000000004'),
  (940000005, '2026-07-21 01:04:00+00', 'DB4 管理员仲裁测试', 'DB4 测试分类', '940001', 5, '{"简约":100,"活泼":200}'::jsonb, null, null, 'DB4 标签', 'pending', 'db400000-0000-4000-8000-000000000005'),
  (940000006, '2026-07-21 01:05:00+00', 'DB4 管理员仲裁测试', 'DB4 测试分类', '940001', 5, '{"简约":100,"活泼":200}'::jsonb, null, null, 'DB4 标签', 'pending', 'db400000-0000-4000-8000-000000000006'),
  (940000007, '2026-07-21 01:06:00+00', 'DB4 管理员仲裁测试', 'DB4 测试分类', '940001', 5, '{"简约":100,"活泼":200}'::jsonb, null, null, 'DB4 标签', 'pending', 'db400000-0000-4000-8000-000000000007'),
  (940000008, '2026-07-21 01:00:00+00', 'DB4 管理员仲裁测试', 'DB4 测试分类', '940001', 5, '{"简约":100,"活泼":200}'::jsonb, null, null, 'DB4 标签', 'pending', null),
  (940000009, '2026-07-21 01:08:00+00', 'DB4 错误候选', 'DB4 测试分类', '940001', 5, '{"简约":100,"活泼":200}'::jsonb, null, null, 'DB4 标签', 'pending', 'db400000-0000-4000-8000-000000000007');

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db400000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);

do $$
declare
  v_denied boolean := false;
begin
  begin
    perform public.approve_pending_clothes_arbitration(
      'db4_fixture_20260721_01',
      'DB4 管理员仲裁测试',
      '940001',
      'DB4 测试分类',
      5,
      '{"简约":100,"活泼":200}'::jsonb,
      null,
      null,
      'DB4 标签',
      array[940000001]::bigint[]
    );
  exception when others then
    v_denied := pg_catalog.strpos(sqlerrm, '没有仲裁入库权限') > 0;
  end;

  if not v_denied then
    raise exception 'DB4_ASSERT: ordinary authenticated user was not denied';
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db400000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

do $$
declare
  v_rejected boolean := false;
begin
  begin
    perform public.approve_pending_clothes_arbitration(
      'db4_fixture_20260721_01',
      'DB4 管理员仲裁测试',
      '940001',
      'DB4 测试分类',
      5,
      '{"简约":100,"活泼":200}'::jsonb,
      null,
      null,
      'DB4 标签',
      array[940000001,940000009]::bigint[]
    );
  exception when others then
    v_rejected := pg_catalog.strpos(sqlerrm, '最终数据不一致') > 0;
  end;

  if not v_rejected
    or exists (select 1 from public.clothes where id = 'db4_fixture_20260721_01')
    or exists (select 1 from public.clothing_contributions where source_pending_id in (940000001, 940000009)) then
    raise exception 'DB4_ASSERT: mismatched candidate was not rejected atomically';
  end if;
end;
$$;

do $$
declare
  v_result jsonb;
begin
  v_result := public.approve_pending_clothes_arbitration(
    'db4_fixture_20260721_01',
    'DB4 管理员仲裁测试',
    '940001',
    'DB4 测试分类',
    5,
    '{"简约":100,"活泼":200}'::jsonb,
    null,
    null,
    'DB4 标签',
    array[940000008,940000007,940000002,940000006,940000001,940000005,940000004,940000003]::bigint[]
  );

  if v_result->>'already_completed' <> 'false'
    or (v_result->>'approved_pending_count')::integer <> 8
    or (v_result->>'contribution_count')::integer <> 5
    or (v_result->>'points_awarded_count')::integer <> 5
    or (v_result->>'points_awarded_total')::integer <> 50
    or (v_result->>'wardrobe_updated_count')::integer <> 5 then
    raise exception 'DB4_ASSERT: first arbitration result mismatch: %', v_result;
  end if;
end;
$$;

do $$
declare
  v_count integer;
  v_total integer;
  v_ids bigint[];
begin
  select pg_catalog.count(*), coalesce(pg_catalog.sum(ledger.delta), 0)
    into v_count, v_total
  from public.points_ledger as ledger
  join public.clothing_contributions as contribution
    on contribution.id = ledger.source_id
  where contribution.clothes_id = 'db4_fixture_20260721_01';

  if v_count <> 5 or v_total <> 50 then
    raise exception 'DB4_ASSERT: points facts mismatch: count %, total %', v_count, v_total;
  end if;

  select pg_catalog.array_agg(source_pending_id order by contribution_rank)
    into v_ids
  from public.clothing_contributions
  where clothes_id = 'db4_fixture_20260721_01';

  if v_ids is distinct from array[940000001,940000003,940000004,940000005,940000006]::bigint[] then
    raise exception 'DB4_ASSERT: stable top-five sources mismatch: %', v_ids;
  end if;

  if (select pg_catalog.count(*) from public.pending_clothes where id between 940000001 and 940000008 and status = 'approved') <> 8 then
    raise exception 'DB4_ASSERT: pending approval count mismatch';
  end if;

  if (select pg_catalog.count(*) from public.user_wardrobes where user_id between 'db400000-0000-4000-8000-000000000002'::uuid and 'db400000-0000-4000-8000-000000000006'::uuid and coalesce(owned_clothes, '[]'::jsonb) @> '["db4_fixture_20260721_01"]'::jsonb) <> 5 then
    raise exception 'DB4_ASSERT: top-five wardrobe writeback mismatch';
  end if;

  if exists (
    select 1 from public.user_wardrobes
    where user_id = 'db400000-0000-4000-8000-000000000007'::uuid
      and coalesce(owned_clothes, '[]'::jsonb) @> '["db4_fixture_20260721_01"]'::jsonb
  ) then
    raise exception 'DB4_ASSERT: sixth contributor received wardrobe writeback';
  end if;

  if not exists (
    select 1 from public.clothes
    where id = 'db4_fixture_20260721_01'
      and name = 'DB4 管理员仲裁测试'
      and game_id = '940001'
      and category = 'DB4 测试分类'
      and stars = '5'
      and scores = '{"简约":100,"活泼":200}'::jsonb
      and tags = 'DB4 标签'
  ) then
    raise exception 'DB4_ASSERT: clothes row mismatch';
  end if;
end;
$$;

update public.profiles
set role = 'super_admin', role_level = 2
where id = 'db400000-0000-4000-8000-000000000001'::uuid;

do $$
declare
  v_result jsonb;
  v_event_count integer;
  v_points_count integer;
begin
  v_result := public.approve_pending_clothes_arbitration(
    'db4_fixture_20260721_01',
    'DB4 管理员仲裁测试',
    '940001',
    'DB4 测试分类',
    5,
    '{"简约":100,"活泼":200}'::jsonb,
    null,
    null,
    'DB4 标签',
    array[940000001,940000002,940000003,940000004,940000005,940000006,940000007,940000008]::bigint[]
  );

  select pg_catalog.count(*) into v_event_count
  from public.clothing_contributions
  where clothes_id = 'db4_fixture_20260721_01';

  select pg_catalog.count(*) into v_points_count
  from public.points_ledger as ledger
  join public.clothing_contributions as contribution on contribution.id = ledger.source_id
  where contribution.clothes_id = 'db4_fixture_20260721_01';

  if v_result->>'already_completed' <> 'true'
    or v_event_count <> 5
    or v_points_count <> 5 then
    raise exception 'DB4_ASSERT: retry was not idempotent: %, %, %', v_result, v_event_count, v_points_count;
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db400000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);

do $$
declare
  v_points bigint;
begin
  select total_points into v_points from public.user_points_summary;
  if v_points <> 10 then
    raise exception 'DB4_ASSERT: DB-2 points summary mismatch for awarded user: %', v_points;
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db400000-0000-4000-8000-000000000007","role":"authenticated"}',
  true
);

do $$
declare
  v_points bigint;
begin
  select total_points into v_points from public.user_points_summary;
  if v_points <> 0 then
    raise exception 'DB4_ASSERT: sixth user unexpectedly received points: %', v_points;
  end if;
end;
$$;

insert into public.pending_clothes (
  id, created_at, name, category, game_id, stars, scores, status, submitted_by
)
values (
  940000011,
  '2026-07-21 02:00:00+00',
  'DB4 事务回滚测试',
  'DB4 测试分类',
  '940002',
  4,
  '{"简约":80}'::jsonb,
  'pending',
  'db400000-0000-4000-8000-000000000002'::uuid
);

create function pg_temp.db4_force_points_failure()
returns trigger
language plpgsql
as $$
begin
  if new.user_id = 'db400000-0000-4000-8000-000000000002'::uuid then
    raise exception 'DB4_EXPECTED_POINTS_FAILURE';
  end if;
  return new;
end;
$$;

create trigger db4_force_points_failure
before insert on public.points_ledger
for each row execute function pg_temp.db4_force_points_failure();

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db400000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

do $$
declare
  v_failed boolean := false;
begin
  begin
    perform public.approve_pending_clothes_arbitration(
      'db4_fixture_20260721_02',
      'DB4 事务回滚测试',
      '940002',
      'DB4 测试分类',
      4,
      '{"简约":80}'::jsonb,
      null,
      null,
      null,
      array[940000011]::bigint[]
    );
  exception when others then
    v_failed := pg_catalog.strpos(sqlerrm, 'DB4_EXPECTED_POINTS_FAILURE') > 0;
  end;

  if not v_failed then
    raise exception 'DB4_ASSERT: expected points failure was not observed';
  end if;

  if exists (
    select 1 from public.clothes
    where id = 'db4_fixture_20260721_02'
  ) or exists (
    select 1 from public.pending_clothes
    where id = 940000011 and status <> 'pending'
  ) or exists (
    select 1 from public.clothing_contributions
    where clothes_id = 'db4_fixture_20260721_02'
  ) or exists (
    select 1 from public.user_wardrobes
    where user_id = 'db400000-0000-4000-8000-000000000002'::uuid
      and coalesce(owned_clothes, '[]'::jsonb) @> '["db4_fixture_20260721_02"]'::jsonb
  ) then
    raise exception 'DB4_ASSERT: induced failure left a partial write';
  end if;
end;
$$;

drop trigger db4_force_points_failure on public.points_ledger;

insert into public.pending_clothes (
  id, created_at, name, category, game_id, stars, scores, status, submitted_by
)
values (
  940000012,
  '2026-07-21 02:10:00+00',
  'DB4 不完整旧事实测试',
  'DB4 测试分类',
  '940003',
  4,
  '{"简约":70}'::jsonb,
  'approved',
  'db400000-0000-4000-8000-000000000002'::uuid
);

do $$
declare
  v_rejected boolean := false;
begin
  begin
    perform public.approve_pending_clothes_arbitration(
      'db4_fixture_20260721_03',
      'DB4 不完整旧事实测试',
      '940003',
      'DB4 测试分类',
      4,
      '{"简约":70}'::jsonb,
      null,
      null,
      null,
      array[940000012]::bigint[]
    );
  exception when others then
    v_rejected := pg_catalog.strpos(sqlerrm, '禁止自动回填') > 0;
  end;

  if not v_rejected then
    raise exception 'DB4_ASSERT: incomplete approved legacy facts were not rejected';
  end if;
end;
$$;

do $$
declare
  v_signature text := 'public.approve_pending_clothes_arbitration(text,text,text,text,integer,jsonb,uuid,text,text,bigint[])';
begin
  if has_function_privilege('anon', v_signature, 'EXECUTE')
    or not has_function_privilege('authenticated', v_signature, 'EXECUTE')
    or not has_function_privilege('service_role', v_signature, 'EXECUTE') then
    raise exception 'DB4_ASSERT: RPC execute grants mismatch';
  end if;

  if has_table_privilege('anon', 'public.clothing_contributions', 'SELECT,INSERT,UPDATE,DELETE')
    or has_table_privilege('authenticated', 'public.clothing_contributions', 'SELECT,INSERT,UPDATE,DELETE')
    or has_table_privilege('anon', 'public.points_ledger', 'SELECT,INSERT,UPDATE,DELETE')
    or has_table_privilege('authenticated', 'public.points_ledger', 'SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'DB4_ASSERT: DB-1 direct table privileges widened';
  end if;
end;
$$;

select pg_catalog.jsonb_build_object(
  'status', 'passed',
  'effective_contributors', 5,
  'points_each', 10,
  'points_total', 50,
  'approved_pending', 8,
  'server_candidate_validation', true,
  'retry_idempotent', true,
  'transaction_rollback', true,
  'legacy_backfill_denied', true,
  'ordinary_user_denied', true,
  'fixture_rollback_pending', true
) as db4_verification;

rollback;
