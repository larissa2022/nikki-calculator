begin;

-- DB-16 development-only fixture. Every write is rolled back.
-- Run only after scripts/check-dev-link.mjs confirms tfwejruvdahonacyldrg.

do $$
begin
  if exists (
    select 1 from auth.users where email like 'db16-fixture-%@example.invalid'
  ) or exists (
    select 1 from public.pending_clothes where id between 916000001 and 916999999
  ) then
    raise exception 'DB16_ASSERT: fixture identifiers already exist';
  end if;
end;
$$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  ('db160000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'authenticated', 'authenticated',
  'db16-fixture-' || value || '@example.invalid', '', pg_catalog.now(),
  '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
  pg_catalog.now(), pg_catalog.now()
from pg_catalog.generate_series(1, 6) as fixture(value);

update public.profiles
set username = 'DB16 公开名称 ' || right(id::text, 2)
where id between 'db160000-0000-4000-8000-000000000001'::uuid
  and 'db160000-0000-4000-8000-000000000006'::uuid;

insert into public.clothes (id, name, category, game_id, stars, scores)
select
  'db16_level_fixture_' || user_no || '_' || phase,
  'DB16 等级流水载体 ' || user_no || '-' || phase,
  'DB16 测试', (916000 + user_no * 10 + phase)::text, '5',
  '{"simple":100}'::jsonb
from pg_catalog.generate_series(2, 6) as users(user_no)
cross join pg_catalog.generate_series(1, 2) as phases(phase);

insert into public.clothes (id, name, category, game_id, stars, scores)
values (
  'db16_jury_fixture', 'DB16 加权陪审载体', 'DB16 测试', '916099', '5',
  '{"simple":100}'::jsonb
);

with source as (
  select user_no, phase,
    916000000 + user_no * 10 + phase as pending_id,
    ('db160000-0000-4000-8000-' || pg_catalog.lpad(user_no::text, 12, '0'))::uuid as user_id
  from pg_catalog.generate_series(2, 6) as users(user_no)
  cross join pg_catalog.generate_series(1, 2) as phases(phase)
), pending_rows as (
  insert into public.pending_clothes (
    id, created_at, name, category, game_id, stars, scores, status, submitted_by
  )
  select pending_id,
    pg_catalog.now() - interval '1 day' + (user_no * 10 + phase) * interval '1 second',
    'DB16 等级流水载体', 'DB16 测试', pending_id::text, 5,
    '{"simple":100}'::jsonb, 'approved', user_id
  from source
  returning id, submitted_by, created_at
)
insert into public.clothing_contributions (
  id, event_id, clothes_id, user_id, source_pending_id,
  contribution_type, contribution_rank, source_created_at
)
select
  (pg_catalog.substr(ids.contribution_hash, 1, 8) || '-' ||
    pg_catalog.substr(ids.contribution_hash, 9, 4) || '-' ||
    pg_catalog.substr(ids.contribution_hash, 13, 4) || '-' ||
    pg_catalog.substr(ids.contribution_hash, 17, 4) || '-' ||
    pg_catalog.substr(ids.contribution_hash, 21, 12))::uuid,
  (pg_catalog.substr(ids.event_hash, 1, 8) || '-' ||
    pg_catalog.substr(ids.event_hash, 9, 4) || '-' ||
    pg_catalog.substr(ids.event_hash, 13, 4) || '-' ||
    pg_catalog.substr(ids.event_hash, 17, 4) || '-' ||
    pg_catalog.substr(ids.event_hash, 21, 12))::uuid,
  'db16_level_fixture_' || ((pending_rows.id - 916000000) / 10)::text || '_' ||
    ((pending_rows.id - 916000000) % 10)::text,
  pending_rows.submitted_by, pending_rows.id, 'admin_arbitration', 1,
  pending_rows.created_at
from pending_rows
cross join lateral (
  select
    pg_catalog.md5('db16-contribution-' || pending_rows.id) as contribution_hash,
    pg_catalog.md5('db16-event-' || pending_rows.id) as event_hash
) as ids;

-- 第一次只建立各等级门槛，发生前均为 Lv0，因此不得追补等级奖励。
insert into public.points_ledger (
  id, user_id, delta, source_type, source_id, occurred_at
)
select
  (pg_catalog.substr(ids.ledger_hash, 1, 8) || '-' ||
    pg_catalog.substr(ids.ledger_hash, 9, 4) || '-' ||
    pg_catalog.substr(ids.ledger_hash, 13, 4) || '-' ||
    pg_catalog.substr(ids.ledger_hash, 17, 4) || '-' ||
    pg_catalog.substr(ids.ledger_hash, 21, 12))::uuid,
  contribution.user_id,
  case right(contribution.clothes_id, 3)
    when '2_1' then 1
    when '3_1' then 500
    when '4_1' then 2000
    when '5_1' then 5000
    when '6_1' then 10000
  end,
  'clothing_contribution', contribution.id, contribution.source_created_at
from public.clothing_contributions as contribution
cross join lateral (
  select pg_catalog.md5('db16-ledger-' || contribution.id::text) as ledger_hash
) as ids
where contribution.source_pending_id between 916000021 and 916000061
  and contribution.source_pending_id % 10 = 1;

-- 第二次按事件发生前等级产生 0/1/2/3/5 分的独立奖励流水。
insert into public.points_ledger (
  id, user_id, delta, source_type, source_id, occurred_at
)
select
  (pg_catalog.substr(ids.ledger_hash, 1, 8) || '-' ||
    pg_catalog.substr(ids.ledger_hash, 9, 4) || '-' ||
    pg_catalog.substr(ids.ledger_hash, 13, 4) || '-' ||
    pg_catalog.substr(ids.ledger_hash, 17, 4) || '-' ||
    pg_catalog.substr(ids.ledger_hash, 21, 12))::uuid,
  contribution.user_id, 10, 'clothing_contribution', contribution.id,
  contribution.source_created_at
from public.clothing_contributions as contribution
cross join lateral (
  select pg_catalog.md5('db16-ledger-' || contribution.id::text) as ledger_hash
) as ids
where contribution.source_pending_id between 916000022 and 916000062
  and contribution.source_pending_id % 10 = 2;

do $$
declare
  v_expected integer[] := array[0, 1, 2, 3, 5];
  v_actual integer[];
begin
  select array_agg(coalesce(bonus.delta, 0) order by right(base.clothes_id, 3))
  into v_actual
  from public.clothing_contributions as base
  join public.points_ledger as base_ledger on base_ledger.source_id = base.id
  left join public.points_ledger as bonus on bonus.bonus_of = base_ledger.id
  where base.source_pending_id between 916000022 and 916000062
    and base.source_pending_id % 10 = 2;

  if v_actual is distinct from v_expected then
    raise exception 'DB16_ASSERT: level bonus matrix mismatch: %', v_actual;
  end if;

  if exists (
    select 1 from public.points_ledger
    where source_type = 'level_bonus' and level_snapshot not between 1 and 4
  ) then
    raise exception 'DB16_ASSERT: bonus snapshot is invalid';
  end if;
end;
$$;

-- 同一基础流水重试不得重复奖励，也不得污染并发积分缓存。
insert into public.points_ledger (
  id, user_id, delta, source_type, source_id, occurred_at
)
select extensions.gen_random_uuid(), contribution.user_id, 10,
  'clothing_contribution', contribution.id, contribution.source_created_at
from public.clothing_contributions as contribution
where contribution.source_pending_id = 916000042
on conflict (source_id) where source_id is not null do nothing;

do $$
begin
  if (
    select pg_catalog.count(*)
    from public.points_ledger as bonus
    join public.points_ledger as base on base.id = bonus.bonus_of
    join public.clothing_contributions as contribution on contribution.id = base.source_id
    where contribution.source_pending_id = 916000042
  ) <> 1 then
    raise exception 'DB16_ASSERT: idempotent retry duplicated level bonus';
  end if;

  if exists (
    select 1
    from private_db2.user_points_state as state
    left join lateral (
      select coalesce(pg_catalog.sum(ledger.delta), 0)::bigint as total_points
      from public.points_ledger as ledger
      where ledger.user_id = state.user_id and ledger.status = 'awarded'
    ) as authority on true
    where state.user_id between 'db160000-0000-4000-8000-000000000002'::uuid
      and 'db160000-0000-4000-8000-000000000006'::uuid
      and state.total_points <> authority.total_points
  ) then
    raise exception 'DB16_ASSERT: points cache diverged after idempotent retry';
  end if;
end;
$$;

-- Lv4 基础流水扣回时必须同步追加对应的 -5 奖励扣回流水。
insert into public.points_ledger (
  user_id, delta, source_type, reversal_of, occurred_at
)
select base.user_id, -base.delta, 'reversal', base.id, pg_catalog.now()
from public.points_ledger as base
join public.clothing_contributions as contribution on contribution.id = base.source_id
where contribution.source_pending_id = 916000062;

do $$
begin
  if (
    select coalesce(pg_catalog.sum(delta), 0)
    from public.points_ledger
    where user_id = 'db160000-0000-4000-8000-000000000006'::uuid
  ) <> 10000 then
    raise exception 'DB16_ASSERT: base and bonus reversal did not restore Lv4 total';
  end if;

  if not exists (
    select 1
    from public.points_ledger as bonus_reversal
    join public.points_ledger as bonus on bonus.id = bonus_reversal.reversal_of
    where bonus.source_type = 'level_bonus'
      and bonus_reversal.source_type = 'reversal'
      and bonus_reversal.delta = -5
      and bonus.user_id = 'db160000-0000-4000-8000-000000000006'::uuid
  ) then
    raise exception 'DB16_ASSERT: level bonus reversal is missing';
  end if;
end;
$$;

-- Lv2 只是月度候选资格门槛，不直接授予权限；Lv1 即使行为数满足也必须跳过。
do $$
declare
  v_service_month date := (
    pg_catalog.date_trunc('month', pg_catalog.timezone('Asia/Shanghai', pg_catalog.now()))
    + interval '18 months'
  )::date;
  v_source_month date := (
    pg_catalog.date_trunc('month', pg_catalog.timezone('Asia/Shanghai', pg_catalog.now()))
    + interval '17 months'
  )::date;
begin
  insert into private_db2.admin_rotation_candidates (
    service_month, source_month, user_id, frozen_points,
    qualifying_action_count, tie_break_at, candidate_order,
    eligibility_status, skip_reason, level_at_snapshot
  ) values
    (
      v_service_month, v_source_month,
      'db160000-0000-4000-8000-000000000003'::uuid,
      511, 5, pg_catalog.now(), 1, 'eligible', null, 1
    ),
    (
      v_service_month, v_source_month,
      'db160000-0000-4000-8000-000000000004'::uuid,
      2012, 5, pg_catalog.now(), 2, 'eligible', null, 2
    );

  if private_db2.fill_monthly_admin_vacancies(v_service_month) <> 1 then
    raise exception 'DB16_ASSERT: Lv2 candidate boundary did not grant exactly one future term';
  end if;
  if exists (
    select 1 from public.admin_terms
    where service_month = v_service_month
      and user_id = 'db160000-0000-4000-8000-000000000003'::uuid
  ) or not exists (
    select 1 from public.admin_terms
    where service_month = v_service_month
      and user_id = 'db160000-0000-4000-8000-000000000004'::uuid
  ) then
    raise exception 'DB16_ASSERT: Lv1/Lv2 candidate selection mismatch';
  end if;
  if private_db2.is_effective_ordinary_admin(
    'db160000-0000-4000-8000-000000000004'::uuid
  ) then
    raise exception 'DB16_ASSERT: future Lv2 term granted current admin capability';
  end if;
end;
$$;

insert into public.re_review_items (
  id, reason, status, clothes_id, payload, submitted_by
) values (
  'db160000-0000-4000-8000-000000000080'::uuid,
  'missing_suit', 'voting', 'db16_jury_fixture',
  '{"name":"DB16 加权陪审载体","category":"DB16 测试","game_id":"916099","needs_suit_review":true}'::jsonb,
  'db160000-0000-4000-8000-000000000001'::uuid
);

insert into public.re_review_candidates (
  id, re_review_item_id, payload, submitted_by, status
) values (
  'db160000-0000-4000-8000-000000000081'::uuid,
  'db160000-0000-4000-8000-000000000080'::uuid,
  '{"suit_id":null}'::jsonb,
  'db160000-0000-4000-8000-000000000001'::uuid,
  'voting'
);

-- Lv1 不得提交复核意见。
select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db160000-0000-4000-8000-000000000003","role":"authenticated"}', true
);
set local role authenticated;

do $$
declare v_denied boolean := false;
begin
  begin
    perform public.cast_jury_vote(
      'db160000-0000-4000-8000-000000000081'::uuid,
      'reject', 'Lv1 不应被接受的复核意见'
    );
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'DB16_ASSERT: Lv1 review note was accepted';
  end if;
end;
$$;

reset role;
select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db160000-0000-4000-8000-000000000004","role":"authenticated"}', true
);
set local role authenticated;
select public.cast_jury_vote(
  'db160000-0000-4000-8000-000000000081'::uuid,
  'reject', '字段仍需来源复核'
);

reset role;
select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db160000-0000-4000-8000-000000000005","role":"authenticated"}', true
);
set local role authenticated;
select public.cast_jury_vote(
  'db160000-0000-4000-8000-000000000081'::uuid,
  'reject', null
);

reset role;
select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db160000-0000-4000-8000-000000000006","role":"authenticated"}', true
);
set local role authenticated;
select public.cast_jury_vote(
  'db160000-0000-4000-8000-000000000081'::uuid,
  'reject', '达到三人反对边界'
);

reset role;

do $$
begin
  if (
    select array_agg(vote_weight order by user_id)
    from public.jury_votes
    where candidate_id = 'db160000-0000-4000-8000-000000000081'::uuid
  ) is distinct from array[2, 2, 3]::smallint[] then
    raise exception 'DB16_ASSERT: weighted jury snapshot mismatch';
  end if;

  if (
    select status from public.re_review_candidates
    where id = 'db160000-0000-4000-8000-000000000081'::uuid
  ) <> 'returned' or (
    select status from public.re_review_items
    where id = 'db160000-0000-4000-8000-000000000080'::uuid
  ) <> 'pending' then
    raise exception 'DB16_ASSERT: three distinct weighted rejects did not return to review';
  end if;

  if (
    select pg_catalog.count(*) from public.points_ledger
    where source_type = 'level_bonus'
      and bonus_of in (
        select id from public.points_ledger where source_type = 'jury_vote'
      )
  ) <> 0 then
    raise exception 'DB16_ASSERT: jury +1 incorrectly received a level bonus';
  end if;
end;
$$;

-- 分级 RPC：Lv0 不返回流水，Lv1 返回本人流水，Lv2 开放本人记录与匿名统计。
select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db160000-0000-4000-8000-000000000002","role":"authenticated"}', true
);
set local role authenticated;
do $$
declare v_result jsonb := public.get_my_level_benefits();
begin
  if (v_result->>'level')::integer <> 0
    or v_result->'points_entries' <> 'null'::jsonb then
    raise exception 'DB16_ASSERT: Lv0 data boundary mismatch: %', v_result;
  end if;
end;
$$;

reset role;
select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db160000-0000-4000-8000-000000000003","role":"authenticated"}', true
);
set local role authenticated;
do $$
declare v_result jsonb := public.get_my_level_benefits();
begin
  if (v_result->>'level')::integer <> 1
    or pg_catalog.jsonb_typeof(v_result->'points_entries') <> 'array'
    or v_result->'contributions' <> 'null'::jsonb then
    raise exception 'DB16_ASSERT: Lv1 data boundary mismatch: %', v_result;
  end if;
end;
$$;

reset role;
select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db160000-0000-4000-8000-000000000004","role":"authenticated"}', true
);
set local role authenticated;
do $$
declare v_result jsonb := public.get_my_level_benefits();
begin
  if (v_result->>'level')::integer <> 2
    or (v_result->>'admin_candidate_eligible')::boolean is not true
    or (v_result->>'can_submit_review_note')::boolean is not true
    or pg_catalog.jsonb_typeof(v_result->'contributions') <> 'array'
    or pg_catalog.jsonb_typeof(v_result->'votes') <> 'array'
    or pg_catalog.jsonb_typeof(v_result->'community_stats') <> 'array' then
    raise exception 'DB16_ASSERT: Lv2 data boundary mismatch: %', v_result;
  end if;
end;
$$;

reset role;
select pg_catalog.set_config('request.jwt.claims', '{}', true);
set local role anon;
do $$
declare v_denied boolean := false;
begin
  begin
    perform public.get_my_level_benefits();
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'DB16_ASSERT: anonymous level data access was allowed';
  end if;
end;
$$;

reset role;

do $$
begin
  if has_table_privilege('authenticated', 'public.points_ledger', 'SELECT,INSERT,UPDATE,DELETE')
    or has_table_privilege('authenticated', 'public.jury_votes', 'SELECT,INSERT,UPDATE,DELETE')
    or has_table_privilege('authenticated', 'private_db2.user_points_state', 'SELECT,INSERT,UPDATE,DELETE')
    or has_function_privilege('anon', 'public.get_my_level_benefits()', 'EXECUTE')
    or has_function_privilege('anon', 'public.cast_jury_vote(uuid,text,text)', 'EXECUTE') then
    raise exception 'DB16_ASSERT: grants widened beyond controlled RPCs';
  end if;

  if not exists (
    select 1 from public.clothing_contributors_public
    where clothes_id = 'db16_level_fixture_4_1'
      and display_name = 'DB16 公开名称 04'
      and contributor_level = 2
  ) then
    raise exception 'DB16_ASSERT: current public name or contributor level is missing';
  end if;
end;
$$;

select pg_catalog.jsonb_build_object(
  'status', 'passed',
  'level_boundaries', true,
  'bonus_snapshot', true,
  'bonus_idempotency', true,
  'bonus_reversal', true,
  'weighted_jury', true,
  'distinct_rejectors', true,
  'review_note_boundary', true,
  'lv2_admin_candidate_boundary', true,
  'tiered_read_rpc', true,
  'transaction_rollback', true
);

rollback;
