begin;

-- DB-17 development-only fixture. Every write is rolled back.
-- Run only after scripts/check-dev-link.mjs confirms tfwejruvdahonacyldrg.

do $$
begin
  if exists (
    select 1 from auth.users where email like 'db17-fixture-%@example.invalid'
  ) or exists (
    select 1 from public.pending_clothes where id between 917000001 and 917000099
  ) or exists (
    select 1 from public.clothes where id like 'db17_%'
  ) then
    raise exception 'DB17_ASSERT: fixture identifiers already exist';
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
  ('db170000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'authenticated',
  'authenticated',
  'db17-fixture-' || value || '@example.invalid',
  '',
  pg_catalog.now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  pg_catalog.now(),
  pg_catalog.now()
from pg_catalog.generate_series(1, 4) as fixture(value);

insert into public.clothes (id, name, category, game_id, stars, scores, tags)
values
  (
    'db17_overturned_fixture',
    'DB17 old name',
    'DB17 测试',
    '917001',
    '5',
    '{"simple":100}'::jsonb,
    'legacy-tag'
  ),
  (
    'db17_missing_fixture',
    'DB17 空字段补全',
    'DB17 测试',
    '917002',
    '5',
    '{"simple":100}'::jsonb,
    null
  ),
  (
    'db17_level_carrier',
    'DB17 等级门槛载体',
    'DB17 测试',
    '917003',
    '5',
    '{"simple":100}'::jsonb,
    null
  );

insert into public.pending_clothes (
  id,
  created_at,
  name,
  category,
  game_id,
  stars,
  scores,
  tags,
  status,
  submitted_by
)
values
  (
    917000001,
    pg_catalog.now() - interval '5 minutes',
    'DB17 old name',
    'DB17 测试',
    '917001',
    5,
    '{"simple":100}'::jsonb,
    'legacy-tag',
    'approved',
    'db170000-0000-4000-8000-000000000001'::uuid
  ),
  (
    917000002,
    pg_catalog.now() - interval '4 minutes',
    'DB17 old name',
    'DB17 测试',
    '917001',
    5,
    '{"simple":100}'::jsonb,
    'legacy-tag',
    'approved',
    'db170000-0000-4000-8000-000000000002'::uuid
  ),
  (
    917000003,
    pg_catalog.now() - interval '3 minutes',
    'DB17 unrelated completion',
    'DB17 测试',
    '917001',
    5,
    '{"simple":100}'::jsonb,
    'legacy-tag',
    'approved',
    'db170000-0000-4000-8000-000000000003'::uuid
  ),
  (
    917000004,
    pg_catalog.now() - interval '2 minutes',
    'DB17 等级门槛载体',
    'DB17 测试',
    '917003',
    5,
    '{"simple":100}'::jsonb,
    null,
    'approved',
    'db170000-0000-4000-8000-000000000001'::uuid
  ),
  (
    917000005,
    pg_catalog.now() - interval '1 minute',
    'DB17 空字段补全',
    'DB17 测试',
    '917002',
    5,
    '{"simple":100}'::jsonb,
    null,
    'approved',
    'db170000-0000-4000-8000-000000000002'::uuid
  );

insert into public.clothing_contributions (
  id,
  event_id,
  clothes_id,
  user_id,
  source_pending_id,
  contribution_type,
  contribution_rank,
  source_created_at
)
values
  (
    'db170001-0000-4000-8000-000000000001'::uuid,
    'db17e001-0000-4000-8000-000000000001'::uuid,
    'db17_overturned_fixture',
    'db170000-0000-4000-8000-000000000001'::uuid,
    917000001,
    'admin_arbitration',
    1,
    pg_catalog.now() - interval '5 minutes'
  ),
  (
    'db170001-0000-4000-8000-000000000002'::uuid,
    'db17e001-0000-4000-8000-000000000001'::uuid,
    'db17_overturned_fixture',
    'db170000-0000-4000-8000-000000000002'::uuid,
    917000002,
    'admin_arbitration',
    2,
    pg_catalog.now() - interval '4 minutes'
  ),
  (
    'db170001-0000-4000-8000-000000000003'::uuid,
    'db17e001-0000-4000-8000-000000000003'::uuid,
    'db17_overturned_fixture',
    'db170000-0000-4000-8000-000000000003'::uuid,
    917000003,
    'existing_field_completion',
    1,
    pg_catalog.now() - interval '3 minutes'
  ),
  (
    'db170001-0000-4000-8000-000000000004'::uuid,
    'db17e001-0000-4000-8000-000000000004'::uuid,
    'db17_level_carrier',
    'db170000-0000-4000-8000-000000000001'::uuid,
    917000004,
    'admin_arbitration',
    1,
    pg_catalog.now() - interval '2 minutes'
  ),
  (
    'db170001-0000-4000-8000-000000000005'::uuid,
    'db17e001-0000-4000-8000-000000000005'::uuid,
    'db17_missing_fixture',
    'db170000-0000-4000-8000-000000000002'::uuid,
    917000005,
    'admin_arbitration',
    1,
    pg_catalog.now() - interval '1 minute'
  );

-- 先建立 Lv2 门槛，再发放被推翻的 +10，使其产生 +2 等级奖励。
insert into public.points_ledger (
  id,
  user_id,
  delta,
  source_type,
  source_id,
  occurred_at
)
values (
  'db170002-0000-4000-8000-000000000004'::uuid,
  'db170000-0000-4000-8000-000000000001'::uuid,
  2000,
  'clothing_contribution',
  'db170001-0000-4000-8000-000000000004'::uuid,
  pg_catalog.now() - interval '2 minutes'
);

insert into public.points_ledger (
  id,
  user_id,
  delta,
  source_type,
  source_id,
  occurred_at
)
values
  (
    'db170002-0000-4000-8000-000000000001'::uuid,
    'db170000-0000-4000-8000-000000000001'::uuid,
    10,
    'clothing_contribution',
    'db170001-0000-4000-8000-000000000001'::uuid,
    pg_catalog.now() - interval '90 seconds'
  ),
  (
    'db170002-0000-4000-8000-000000000002'::uuid,
    'db170000-0000-4000-8000-000000000002'::uuid,
    10,
    'clothing_contribution',
    'db170001-0000-4000-8000-000000000002'::uuid,
    pg_catalog.now() - interval '80 seconds'
  ),
  (
    'db170002-0000-4000-8000-000000000003'::uuid,
    'db170000-0000-4000-8000-000000000003'::uuid,
    5,
    'clothing_contribution',
    'db170001-0000-4000-8000-000000000003'::uuid,
    pg_catalog.now() - interval '70 seconds'
  ),
  (
    'db170002-0000-4000-8000-000000000005'::uuid,
    'db170000-0000-4000-8000-000000000002'::uuid,
    10,
    'clothing_contribution',
    'db170001-0000-4000-8000-000000000005'::uuid,
    pg_catalog.now() - interval '60 seconds'
  );

insert into public.correction_requests (
  id,
  clothes_id,
  reported_by,
  field_key,
  reason,
  proposed_patch,
  clothes_snapshot,
  status,
  reviewed_by,
  resolution_note,
  reviewed_at,
  accepted_patch
)
values
  (
    'db17c001-0000-4000-8000-000000000001'::uuid,
    'db17_overturned_fixture',
    'db170000-0000-4000-8000-000000000004'::uuid,
    'name',
    'DB17 验证非空旧名称被正式推翻后的精确积分扣回',
    '{"name":"DB17 new name"}'::jsonb,
    public.jury_clothes_payload('db17_overturned_fixture'),
    'reviewing',
    'db170000-0000-4000-8000-000000000004'::uuid,
    'DB17 fixture 正在结算',
    pg_catalog.now(),
    '{"name":"DB17 new name"}'::jsonb
  ),
  (
    'db17c001-0000-4000-8000-000000000002'::uuid,
    'db17_missing_fixture',
    'db170000-0000-4000-8000-000000000004'::uuid,
    'tags',
    'DB17 验证空字段补全不得扣回原贡献积分',
    '{"tags":"new-tag"}'::jsonb,
    public.jury_clothes_payload('db17_missing_fixture'),
    'reviewing',
    'db170000-0000-4000-8000-000000000004'::uuid,
    'DB17 fixture 正在结算',
    pg_catalog.now(),
    '{"tags":"new-tag"}'::jsonb
  );

update public.clothes
set name = 'DB17 new name'
where id = 'db17_overturned_fixture';

update public.correction_requests
set status = 'approved',
    resolution_note = 'DB17 fixture 已采用新名称',
    updated_at = pg_catalog.now()
where id = 'db17c001-0000-4000-8000-000000000001'::uuid;

update public.clothes
set tags = 'new-tag'
where id = 'db17_missing_fixture';

update public.correction_requests
set status = 'approved',
    resolution_note = 'DB17 fixture 已补全标签',
    updated_at = pg_catalog.now()
where id = 'db17c001-0000-4000-8000-000000000002'::uuid;

do $$
declare
  v_linked_count integer;
  v_linked_delta integer;
begin
  select pg_catalog.count(*)::integer, coalesce(pg_catalog.sum(delta), 0)::integer
  into v_linked_count, v_linked_delta
  from public.points_ledger
  where reversal_correction_request_id =
    'db17c001-0000-4000-8000-000000000001'::uuid;

  if v_linked_count <> 3 or v_linked_delta <> -22 then
    raise exception 'DB17_ASSERT: expected three linked reversals totaling -22, got % / %',
      v_linked_count, v_linked_delta;
  end if;

  if exists (
    select 1
    from public.points_ledger as reversal
    where reversal.reversal_correction_request_id =
      'db17c001-0000-4000-8000-000000000001'::uuid
      and reversal.reversal_of = 'db170002-0000-4000-8000-000000000003'::uuid
  ) then
    raise exception 'DB17_ASSERT: unrelated field-completion reward was reversed';
  end if;

  if exists (
    select 1
    from public.points_ledger
    where reversal_correction_request_id =
      'db17c001-0000-4000-8000-000000000002'::uuid
  ) then
    raise exception 'DB17_ASSERT: missing-field completion created a reversal';
  end if;

  if (
    select coalesce(pg_catalog.sum(delta), 0)
    from public.points_ledger
    where user_id = 'db170000-0000-4000-8000-000000000001'::uuid
  ) <> 2000 then
    raise exception 'DB17_ASSERT: base and level-bonus reversals did not restore user 1';
  end if;

  if (
    select coalesce(pg_catalog.sum(delta), 0)
    from public.points_ledger
    where user_id = 'db170000-0000-4000-8000-000000000002'::uuid
  ) <> 10 then
    raise exception 'DB17_ASSERT: user 2 total should retain only missing-field contribution';
  end if;

  if (
    select coalesce(pg_catalog.sum(delta), 0)
    from public.points_ledger
    where user_id = 'db170000-0000-4000-8000-000000000003'::uuid
  ) <> 5 then
    raise exception 'DB17_ASSERT: unrelated contributor total changed';
  end if;

  if (
    select pg_catalog.count(*)
    from public.points_ledger
    where id in (
      'db170002-0000-4000-8000-000000000001'::uuid,
      'db170002-0000-4000-8000-000000000002'::uuid,
      'db170002-0000-4000-8000-000000000003'::uuid
    )
  ) <> 3 then
    raise exception 'DB17_ASSERT: original positive ledgers were not preserved';
  end if;
end;
$$;

-- 模拟同一业务事实的再次结算，唯一 reversal_of 必须保持幂等。
update public.correction_requests
set status = 'reviewing',
    resolution_note = 'DB17 fixture 模拟安全重试',
    updated_at = pg_catalog.now()
where id = 'db17c001-0000-4000-8000-000000000001'::uuid;

update public.correction_requests
set status = 'approved',
    resolution_note = 'DB17 fixture 重试完成',
    updated_at = pg_catalog.now()
where id = 'db17c001-0000-4000-8000-000000000001'::uuid;

do $$
begin
  if (
    select pg_catalog.count(*)
    from public.points_ledger
    where reversal_correction_request_id =
      'db17c001-0000-4000-8000-000000000001'::uuid
  ) <> 3 then
    raise exception 'DB17_ASSERT: idempotent retry duplicated reversals';
  end if;

  if exists (
    select 1
    from private_db2.user_points_state as state
    left join lateral (
      select coalesce(pg_catalog.sum(ledger.delta), 0)::bigint as total_points
      from public.points_ledger as ledger
      where ledger.user_id = state.user_id
        and ledger.status = 'awarded'
    ) as authority on true
    where state.user_id between 'db170000-0000-4000-8000-000000000001'::uuid
      and 'db170000-0000-4000-8000-000000000004'::uuid
      and state.total_points <> authority.total_points
  ) then
    raise exception 'DB17_ASSERT: points cache diverged from append-only authority';
  end if;
end;
$$;

select 'db17_correction_point_reversals_passed' as result;

rollback;
