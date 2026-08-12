begin;

-- DB-19 development-only fixture. Every write is rolled back.
-- Run only after scripts/check-dev-link.mjs confirms tfwejruvdahonacyldrg.

do $$
begin
  if exists (
    select 1 from auth.users where email like 'db19-fixture-%@example.invalid'
  ) then
    raise exception 'DB19_ASSERT: fixture identifiers already exist';
  end if;
end;
$$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  ('db190000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'authenticated', 'authenticated',
  'db19-fixture-' || value || '@example.invalid', '', pg_catalog.now(),
  '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
  pg_catalog.now(), pg_catalog.now()
from pg_catalog.generate_series(1, 5) as fixture(value);

update public.profiles
set username = 'DB19 体验测试 ' || right(id::text, 2)
where id between 'db190000-0000-4000-8000-000000000001'::uuid
  and 'db190000-0000-4000-8000-000000000005'::uuid;

insert into public.clothes (id, name, category, game_id, stars, scores)
values
  ('db19_permanent_lv4', 'DB19 永久 Lv4 载体', 'DB19 测试', '919001', '5', '{"simple":100}'::jsonb),
  ('db19_experience_bonus', 'DB19 体验奖励载体', 'DB19 测试', '919002', '5', '{"simple":100}'::jsonb),
  ('db19_jury', 'DB19 体验票权载体', 'DB19 测试', '919003', '5', '{"simple":100}'::jsonb);

insert into public.pending_clothes (
  id, created_at, name, category, game_id, stars, scores, status, submitted_by
)
values
  (
    919000001,
    pg_catalog.now(),
    'DB19 永久 Lv4 载体', 'DB19 测试', '919001', 5,
    '{"simple":100}'::jsonb, 'approved',
    'db190000-0000-4000-8000-000000000002'::uuid
  ),
  (
    919000002,
    pg_catalog.now(),
    'DB19 体验奖励载体', 'DB19 测试', '919002', 5,
    '{"simple":100}'::jsonb, 'approved',
    'db190000-0000-4000-8000-000000000001'::uuid
  );

insert into public.clothing_contributions (
  id, event_id, clothes_id, user_id, source_pending_id,
  contribution_type, contribution_rank, source_created_at
)
values
  (
    'db190000-0000-4000-8000-000000000101'::uuid,
    'db190000-0000-4000-8000-000000000111'::uuid,
    'db19_permanent_lv4',
    'db190000-0000-4000-8000-000000000002'::uuid,
    919000001, 'admin_arbitration', 1, pg_catalog.now()
  ),
  (
    'db190000-0000-4000-8000-000000000102'::uuid,
    'db190000-0000-4000-8000-000000000112'::uuid,
    'db19_experience_bonus',
    'db190000-0000-4000-8000-000000000001'::uuid,
    919000002, 'admin_arbitration', 1, pg_catalog.now()
  );

do $$
declare
  v_service_month date := (
    pg_catalog.date_trunc('month', pg_catalog.timezone('Asia/Shanghai', pg_catalog.now()))
    + interval '30 months'
  )::date;
  v_source_month date := (v_service_month - interval '1 month')::date;
begin
  -- 永久 Lv4 在体验资格授予前由正常积分流水达到门槛。
  insert into public.points_ledger (
    id, user_id, delta, source_type, source_id, occurred_at
  ) values (
    'db190000-0000-4000-8000-000000000121'::uuid,
    'db190000-0000-4000-8000-000000000002'::uuid,
    10000,
    'clothing_contribution',
    'db190000-0000-4000-8000-000000000101'::uuid,
    v_source_month::timestamp at time zone 'Asia/Shanghai' + interval '15 days'
  );

  insert into private_db2.points_leaderboard_months (
    month_start, frozen_at, row_count
  ) values (
    v_source_month,
    v_service_month::timestamp at time zone 'Asia/Shanghai' + interval '5 minutes',
    4
  );

  insert into private_db2.points_leaderboard_monthly_snapshots (
    month_start, user_id, points, leaderboard_rank, frozen_at
  ) values
    (
      v_source_month, 'db190000-0000-4000-8000-000000000001'::uuid,
      100, 1, v_service_month::timestamp at time zone 'Asia/Shanghai' + interval '5 minutes'
    ),
    (
      v_source_month, 'db190000-0000-4000-8000-000000000002'::uuid,
      100, 1, v_service_month::timestamp at time zone 'Asia/Shanghai' + interval '5 minutes'
    ),
    (
      v_source_month, 'db190000-0000-4000-8000-000000000003'::uuid,
      100, 1, v_service_month::timestamp at time zone 'Asia/Shanghai' + interval '5 minutes'
    ),
    (
      v_source_month, 'db190000-0000-4000-8000-000000000004'::uuid,
      90, 2, v_service_month::timestamp at time zone 'Asia/Shanghai' + interval '5 minutes'
    );
end;
$$;

delete from public.profiles
where id = 'db190000-0000-4000-8000-000000000003'::uuid;
delete from auth.users
where id = 'db190000-0000-4000-8000-000000000003'::uuid;

do $$
declare
  v_service_month date := (
    pg_catalog.date_trunc('month', pg_catalog.timezone('Asia/Shanghai', pg_catalog.now()))
    + interval '30 months'
  )::date;
  v_run_at timestamptz := v_service_month::timestamp at time zone 'Asia/Shanghai'
    + interval '5 minutes';
  v_first jsonb;
  v_second jsonb;
begin
  v_first := private_db2.refresh_monthly_lv4_experiences(v_run_at);
  v_second := private_db2.refresh_monthly_lv4_experiences(v_run_at);

  if (v_first->>'granted_count')::integer <> 2
    or (v_first->>'active_count')::integer <> 2
    or (v_second->>'granted_count')::integer <> 0 then
    raise exception 'DB19_ASSERT: tied-first grant or idempotency mismatch: %, %', v_first, v_second;
  end if;

  if (select pg_catalog.count(*) from private_db2.monthly_lv4_experience_terms
      where service_month = v_service_month) <> 2
    or exists (
      select 1 from private_db2.monthly_lv4_experience_terms
      where service_month = v_service_month
        and user_id in (
          'db190000-0000-4000-8000-000000000003'::uuid,
          'db190000-0000-4000-8000-000000000004'::uuid
        )
    ) then
    raise exception 'DB19_ASSERT: deleted or rank-two account received experience';
  end if;

  if private_db2.active_monthly_lv4_experience_id(
      'db190000-0000-4000-8000-000000000001'::uuid,
      v_service_month::timestamp at time zone 'Asia/Shanghai'
    ) is null
    or private_db2.active_monthly_lv4_experience_id(
      'db190000-0000-4000-8000-000000000001'::uuid,
      (v_service_month + interval '1 month')::timestamp at time zone 'Asia/Shanghai'
    ) is not null then
    raise exception 'DB19_ASSERT: exact Beijing-time experience window mismatch';
  end if;
end;
$$;

-- 审计资格不得伪造来源月、冻结积分、名次或用户与快照的绑定。
do $$
declare
  v_service_month date := (
    pg_catalog.date_trunc('month', pg_catalog.timezone('Asia/Shanghai', pg_catalog.now()))
    + interval '42 months'
  )::date;
  v_denied boolean := false;
  v_snapshot_id bigint;
begin
  select snapshot.id into v_snapshot_id
  from private_db2.points_leaderboard_monthly_snapshots as snapshot
  where snapshot.user_id = 'db190000-0000-4000-8000-000000000001'::uuid
  order by snapshot.month_start desc
  limit 1;

  begin
    insert into private_db2.monthly_lv4_experience_terms (
      service_month, source_month, source_snapshot_id, user_id,
      frozen_points, leaderboard_rank, starts_at, scheduled_end_at, granted_at
    ) values (
      v_service_month,
      (v_service_month - interval '1 month')::date,
      v_snapshot_id,
      'db190000-0000-4000-8000-000000000001'::uuid,
      100,
      1,
      v_service_month::timestamp at time zone 'Asia/Shanghai',
      (v_service_month + interval '1 month')::timestamp at time zone 'Asia/Shanghai',
      v_service_month::timestamp at time zone 'Asia/Shanghai' + interval '5 minutes'
    );
  exception when foreign_key_violation then
    v_denied := true;
  end;

  if not v_denied then
    raise exception 'DB19_ASSERT: mismatched source snapshot audit was accepted';
  end if;
end;
$$;

-- 另外使用当前自然月窗口验证用户可见 RPC 与投票；来源仍绑定真实的上月冻结标记。
do $$
declare
  v_service_month date := pg_catalog.date_trunc(
    'month', pg_catalog.timezone('Asia/Shanghai', pg_catalog.now())
  )::date;
  v_source_month date := (v_service_month - interval '1 month')::date;
  v_frozen_at timestamptz;
begin
  select frozen_month.frozen_at into v_frozen_at
  from private_db2.points_leaderboard_months as frozen_month
  where frozen_month.month_start = v_source_month;

  if v_frozen_at is null then
    raise exception 'DB19_ASSERT: current previous month is not frozen';
  end if;

  insert into private_db2.points_leaderboard_monthly_snapshots (
    month_start, user_id, points, leaderboard_rank, frozen_at
  ) values
    (
      v_source_month, 'db190000-0000-4000-8000-000000000001'::uuid,
      100, 1, v_frozen_at
    ),
    (
      v_source_month, 'db190000-0000-4000-8000-000000000002'::uuid,
      100, 1, v_frozen_at
    );

  insert into private_db2.monthly_lv4_experience_terms (
    service_month, source_month, source_snapshot_id, user_id,
    frozen_points, leaderboard_rank, starts_at, scheduled_end_at, granted_at
  )
  select
    v_service_month,
    v_source_month,
    snapshot.id,
    snapshot.user_id,
    snapshot.points,
    snapshot.leaderboard_rank,
    v_service_month::timestamp at time zone 'Asia/Shanghai',
    (v_service_month + interval '1 month')::timestamp at time zone 'Asia/Shanghai',
    pg_catalog.now()
  from private_db2.points_leaderboard_monthly_snapshots as snapshot
  where snapshot.month_start = v_source_month
    and snapshot.user_id in (
      'db190000-0000-4000-8000-000000000001'::uuid,
      'db190000-0000-4000-8000-000000000002'::uuid
    );
end;
$$;

-- 体验用户的成功业务结算冻结为 Lv4，追加 +5；累计等级仍为 Lv0。
do $$
declare
  v_service_month date := (
    pg_catalog.date_trunc('month', pg_catalog.timezone('Asia/Shanghai', pg_catalog.now()))
    + interval '30 months'
  )::date;
begin
  insert into public.points_ledger (
    id, user_id, delta, source_type, source_id, occurred_at
  ) values (
    'db190000-0000-4000-8000-000000000122'::uuid,
    'db190000-0000-4000-8000-000000000001'::uuid,
    10,
    'clothing_contribution',
    'db190000-0000-4000-8000-000000000102'::uuid,
    v_service_month::timestamp at time zone 'Asia/Shanghai' + interval '1 day'
  );
end;
$$;

do $$
begin
  if not exists (
    select 1
    from public.points_ledger as bonus
    where bonus.bonus_of = 'db190000-0000-4000-8000-000000000122'::uuid
      and bonus.source_type = 'level_bonus'
      and bonus.level_snapshot = 4
      and bonus.delta = 5
  ) or private_db2.level_for_points((
    select coalesce(pg_catalog.sum(ledger.delta), 0)
    from public.points_ledger as ledger
    where ledger.user_id = 'db190000-0000-4000-8000-000000000001'::uuid
      and ledger.status = 'awarded'
  )) <> 0 then
    raise exception 'DB19_ASSERT: temporary +5 bonus or cumulative level isolation mismatch';
  end if;
end;
$$;

insert into public.re_review_items (
  id, reason, status, clothes_id, payload, submitted_by
) values (
  'db190000-0000-4000-8000-000000000201'::uuid,
  'missing_suit', 'voting', 'db19_jury',
  '{"name":"DB19 体验票权载体","category":"DB19 测试","game_id":"919003","needs_suit_review":true}'::jsonb,
  'db190000-0000-4000-8000-000000000005'::uuid
);

insert into public.re_review_candidates (
  id, re_review_item_id, payload, submitted_by, status
) values (
  'db190000-0000-4000-8000-000000000202'::uuid,
  'db190000-0000-4000-8000-000000000201'::uuid,
  '{"suit_id":null}'::jsonb,
  'db190000-0000-4000-8000-000000000005'::uuid,
  'voting'
);

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db190000-0000-4000-8000-000000000001","role":"authenticated"}', true
);
set local role authenticated;

do $$
declare v_denied boolean := false;
begin
  begin
    perform public.cast_jury_vote(
      'db190000-0000-4000-8000-000000000202'::uuid,
      'approve',
      '体验资格不应开放复核意见'
    );
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'DB19_ASSERT: experience incorrectly granted review-note capability';
  end if;
end;
$$;

select public.cast_jury_vote(
  'db190000-0000-4000-8000-000000000202'::uuid,
  'approve',
  null
);

do $$
declare
  v_benefits jsonb := public.get_my_level_benefits();
  v_admin jsonb := public.get_current_admin_capabilities();
begin
  if (v_benefits->>'level')::integer <> 0
    or (v_benefits->>'bonus_per_event')::integer <> 5
    or (v_benefits->>'vote_weight')::integer <> 3
    or (v_benefits->>'admin_candidate_eligible')::boolean is not false
    or (v_benefits->>'can_submit_review_note')::boolean is not false
    or pg_catalog.jsonb_typeof(v_benefits->'governance_stats') <> 'object'
    or (v_benefits->'monthly_lv4_experience'->>'temporarily_applied')::boolean is not true
    or (v_admin->>'can_review_low_risk')::boolean is not false
    or (v_admin->>'can_manage_admin_terms')::boolean is not false then
    raise exception 'DB19_ASSERT: three-benefit or admin isolation mismatch: %, %', v_benefits, v_admin;
  end if;
end;
$$;

reset role;

do $$
begin
  if (select vote_weight from public.jury_votes
      where candidate_id = 'db190000-0000-4000-8000-000000000202'::uuid
        and user_id = 'db190000-0000-4000-8000-000000000001'::uuid) <> 3 then
    raise exception 'DB19_ASSERT: experience vote was not frozen at weight three';
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db190000-0000-4000-8000-000000000002","role":"authenticated"}', true
);
set local role authenticated;

do $$
declare v_benefits jsonb := public.get_my_level_benefits();
begin
  if (v_benefits->>'level')::integer <> 4
    or (v_benefits->'monthly_lv4_experience'->>'temporarily_applied')::boolean is not false then
    raise exception 'DB19_ASSERT: permanent Lv4 experience audit mismatch: %', v_benefits;
  end if;
end;
$$;

reset role;

-- 到期窗口先自然失效；下月刷新只补记回收审计。永久 Lv4 不受回收影响。
do $$
declare
  v_service_month date := (
    pg_catalog.date_trunc('month', pg_catalog.timezone('Asia/Shanghai', pg_catalog.now()))
    + interval '30 months'
  )::date;
  v_next_month date := (v_service_month + interval '1 month')::date;
  v_result jsonb;
begin
  v_result := private_db2.refresh_monthly_lv4_experiences(
    v_next_month::timestamp at time zone 'Asia/Shanghai' + interval '5 minutes'
  );

  if (v_result->>'status') <> 'source_not_frozen'
    or (v_result->>'reclaimed_count')::integer <> 4
    or exists (
      select 1 from private_db2.monthly_lv4_experience_terms
      where reclaimed_at is null
        and user_id in (
          'db190000-0000-4000-8000-000000000001'::uuid,
          'db190000-0000-4000-8000-000000000002'::uuid
        )
    ) then
    raise exception 'DB19_ASSERT: month-end reclaim audit mismatch: %', v_result;
  end if;
  if private_db2.level_for_points((
    select coalesce(pg_catalog.sum(ledger.delta), 0)
    from public.points_ledger as ledger
    where ledger.user_id = 'db190000-0000-4000-8000-000000000002'::uuid
      and ledger.status = 'awarded'
  )) <> 4 then
    raise exception 'DB19_ASSERT: permanent cumulative Lv4 changed during reclaim';
  end if;
end;
$$;

do $$
begin
  if pg_catalog.has_table_privilege(
      'authenticated', 'private_db2.monthly_lv4_experience_terms', 'select,insert,update,delete'
    )
    or pg_catalog.has_table_privilege(
      'service_role', 'private_db2.monthly_lv4_experience_terms', 'select,insert,update,delete'
    )
    or pg_catalog.has_function_privilege(
      'authenticated', 'private_db2.refresh_monthly_lv4_experiences(timestamptz)', 'execute'
    )
    or pg_catalog.has_function_privilege(
      'authenticated', 'private_db2.active_monthly_lv4_experience_id(uuid,timestamptz)', 'execute'
    )
    or pg_catalog.has_function_privilege(
      'authenticated', 'private_db2.cumulative_level_benefits()', 'execute'
    ) then
    raise exception 'DB19_ASSERT: private entitlement grants are broader than intended';
  end if;
end;
$$;

select pg_catalog.jsonb_build_object(
  'status', 'passed',
  'all_tied_first_granted', true,
  'deleted_and_rank_two_skipped', true,
  'idempotent_grant', true,
  'beijing_window_and_reclaim', true,
  'temporary_bonus_plus_five', true,
  'temporary_vote_weight_three', true,
  'temporary_governance_stats', true,
  'cumulative_level_unchanged', true,
  'admin_and_candidate_isolated', true,
  'permanent_lv4_preserved', true,
  'transaction_rollback', true
);

rollback;

do $$
begin
  if exists (
    select 1 from auth.users where email like 'db19-fixture-%@example.invalid'
  ) or exists (
    select 1 from private_db2.monthly_lv4_experience_terms
    where user_id between 'db190000-0000-4000-8000-000000000001'::uuid
      and 'db190000-0000-4000-8000-000000000005'::uuid
  ) then
    raise exception 'DB19_ASSERT: fixture residue remains after rollback';
  end if;
end;
$$;

select 'passed' as db19_monthly_lv4_experience;
