begin;

-- DB-15 development-only fixture. Every write is rolled back.
-- Run only after scripts/check-dev-link.mjs confirms tfwejruvdahonacyldrg.

do $$
begin
  if exists (
    select 1 from auth.users where email like 'db15-fixture-%@example.invalid'
  ) or exists (
    select 1 from public.pending_clothes where id between 915000001 and 915999999
  ) then
    raise exception 'DB15_ASSERT: fixture identifiers already exist';
  end if;
end;
$$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  ('db150000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'authenticated', 'authenticated',
  'db15-fixture-' || value || '@example.invalid', '', pg_catalog.now(),
  '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
  pg_catalog.now(), pg_catalog.now()
from pg_catalog.generate_series(1, 11) as fixture(value)
union all
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  ('db150000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'authenticated', 'authenticated',
  'db15-fixture-' || value || '@example.invalid', '', pg_catalog.now(),
  '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
  pg_catalog.now(), pg_catalog.now()
from (values (21), (22), (23), (24), (25), (26), (27), (90), (99)) as fixture(value);

update public.profiles
set username = 'DB15 用户 ' || right(id::text, 2)
where email like 'db15-fixture-%@example.invalid';

update public.profiles
set role = 'super_admin', role_level = 2
where id in (
  'db150000-0000-4000-8000-000000000001'::uuid,
  'db150000-0000-4000-8000-000000000099'::uuid
);

insert into public.clothes (id, name, category, game_id, stars, scores)
select
  'db15_rotation_fixture_' || user_no || '_' || action_no,
  'DB15 轮换流水载体 ' || user_no || '-' || action_no,
  'DB15 测试', (159900 + user_no * 10 + action_no)::text, '5',
  '{"simple":100}'::jsonb
from pg_catalog.generate_series(1, 11) as users(user_no)
cross join pg_catalog.generate_series(1, 5) as events(action_no)
where not (user_no = 4 and action_no = 5);

with source_month as (
  select (
    pg_catalog.date_trunc('month', pg_catalog.timezone('Asia/Shanghai', pg_catalog.now()))
    - interval '1 month'
  )::date as month_start
), actions as (
  select user_no, action_no
  from pg_catalog.generate_series(1, 11) as users(user_no)
  cross join pg_catalog.generate_series(1, 5) as events(action_no)
  where not (user_no = 4 and action_no = 5)
), pending_rows as (
  insert into public.pending_clothes (
    id, created_at, name, category, game_id, stars, scores, status, submitted_by
  )
  select
    915100000 + user_no * 10 + action_no,
    source_month.month_start::timestamp at time zone 'Asia/Shanghai'
      + (action_no || ' days')::interval + (user_no || ' minutes')::interval,
    'DB15 轮换行为', 'DB15 测试', (15000 + user_no)::text, 5,
    '{"simple":100}'::jsonb, 'approved',
    ('db150000-0000-4000-8000-' || pg_catalog.lpad(user_no::text, 12, '0'))::uuid
  from actions cross join source_month
  returning id, submitted_by, created_at
), contributions as (
  insert into public.clothing_contributions (
    id, event_id, clothes_id, user_id, source_pending_id,
    contribution_type, contribution_rank, source_created_at
  )
  select
    (pg_catalog.substr(h.hash,1,8)||'-'||pg_catalog.substr(h.hash,9,4)||'-'||pg_catalog.substr(h.hash,13,4)||'-'||pg_catalog.substr(h.hash,17,4)||'-'||pg_catalog.substr(h.hash,21,12))::uuid,
    (pg_catalog.substr(e.hash,1,8)||'-'||pg_catalog.substr(e.hash,9,4)||'-'||pg_catalog.substr(e.hash,13,4)||'-'||pg_catalog.substr(e.hash,17,4)||'-'||pg_catalog.substr(e.hash,21,12))::uuid,
    'db15_rotation_fixture_' || ((pending_rows.id - 915100000) / 10)::text
      || '_' || ((pending_rows.id - 915100000) % 10)::text,
    pending_rows.submitted_by, pending_rows.id,
    'admin_arbitration', 1, pending_rows.created_at
  from pending_rows
  cross join lateral (select pg_catalog.md5('db15-contribution-' || pending_rows.id) as hash) h
  cross join lateral (select pg_catalog.md5('db15-event-' || pending_rows.id) as hash) e
  returning id, user_id, source_created_at
)
insert into public.points_ledger (id, user_id, delta, source_type, source_id, occurred_at)
select
  (pg_catalog.substr(h.hash,1,8)||'-'||pg_catalog.substr(h.hash,9,4)||'-'||pg_catalog.substr(h.hash,13,4)||'-'||pg_catalog.substr(h.hash,17,4)||'-'||pg_catalog.substr(h.hash,21,12))::uuid,
  contributions.user_id, 400, 'clothing_contribution', contributions.id,
  contributions.source_created_at
from contributions
cross join lateral (select pg_catalog.md5('db15-ledger-' || contributions.id::text) as hash) h;

do $$
declare
  v_service_month date := pg_catalog.date_trunc(
    'month', pg_catalog.timezone('Asia/Shanghai', pg_catalog.now())
  )::date;
  v_source_month date := (v_service_month - interval '1 month')::date;
begin
  delete from private_db2.points_leaderboard_months where month_start = v_source_month;
  delete from private_db2.admin_rotation_candidates where service_month = v_service_month;
  delete from public.admin_terms where service_month = v_service_month;

  insert into private_db2.points_leaderboard_months (month_start, frozen_at, row_count)
  values (v_source_month, pg_catalog.now(), 11);

  insert into private_db2.points_leaderboard_monthly_snapshots (
    month_start, user_id, points, leaderboard_rank, frozen_at
  )
  select
    v_source_month,
    ('db150000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
    case value
      when 1 then 200 when 2 then 190 when 3 then 180 when 4 then 170
      when 5 then 100 when 6 then 100 when 7 then 100
      when 8 then 90 when 9 then 80 when 10 then 70 else 60
    end,
    value,
    pg_catalog.now()
  from pg_catalog.generate_series(1, 11) as fixture(value);

  insert into public.admin_terms (
    user_id, source, reason, starts_at, scheduled_end_at
  ) values (
    'db150000-0000-4000-8000-000000000002'::uuid,
    'manual', 'fixture existing manual', pg_catalog.now() - interval '1 day',
    pg_catalog.now() + interval '7 days'
  );

  insert into public.admin_candidate_exclusions (
    user_id, reason, starts_at, ends_at, created_by
  ) values (
    'db150000-0000-4000-8000-000000000003'::uuid,
    'fixture explicit exclusion', pg_catalog.now() - interval '1 day',
    pg_catalog.now() + interval '7 days',
    'db150000-0000-4000-8000-000000000099'::uuid
  );
end;
$$;

do $$
declare
  v_service_month date := (
    pg_catalog.date_trunc('month', pg_catalog.timezone('Asia/Shanghai', pg_catalog.now()))
    + interval '2 months'
  )::date;
  v_source_month date := (
    pg_catalog.date_trunc('month', pg_catalog.timezone('Asia/Shanghai', pg_catalog.now()))
    + interval '1 month'
  )::date;
begin
  insert into private_db2.admin_rotation_candidates (
    service_month, source_month, user_id, frozen_points,
    qualifying_action_count, tie_break_at, candidate_order,
    eligibility_status, skip_reason, level_at_snapshot
  )
  select
    v_service_month, v_source_month,
    ('db150000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
    10, 5, pg_catalog.now(), value - 4, 'eligible', null, 2
  from pg_catalog.generate_series(5, 7) as fixture(value);

  if private_db2.fill_monthly_admin_vacancies(v_service_month) <> 3 then
    raise exception 'DB15_ASSERT: fewer than five eligible users must leave empty seats';
  end if;
  if (select count(*) from public.admin_terms where source = 'monthly' and service_month = v_service_month) <> 3 then
    raise exception 'DB15_ASSERT: shortage must not lower the threshold or invent candidates';
  end if;

  insert into public.admin_terms (
    user_id, source, reason, starts_at, scheduled_end_at
  ) values (
    'db150000-0000-4000-8000-000000000027'::uuid,
    'manual', 'fixture expired term', pg_catalog.now() - interval '2 days',
    pg_catalog.now() - interval '1 day'
  );
  if private_db2.is_effective_ordinary_admin('db150000-0000-4000-8000-000000000027'::uuid) then
    raise exception 'DB15_ASSERT: expired term must not grant capability';
  end if;

  begin
    insert into public.admin_terms (
      user_id, source, reason, starts_at, scheduled_end_at
    ) values (
      'db150000-0000-4000-8000-000000000026'::uuid,
      'manual', 'fixture invalid duration', pg_catalog.now(),
      pg_catalog.now() + interval '32 days'
    );
    raise exception 'DB15_ASSERT: manual term longer than 31 days was accepted';
  exception when check_violation then null;
  end;
end;
$$;

do $$
declare
  v_service_month date := pg_catalog.date_trunc(
    'month', pg_catalog.timezone('Asia/Shanghai', pg_catalog.now())
  )::date;
  v_run_at timestamptz;
  v_result jsonb;
begin
  v_run_at := v_service_month::timestamp at time zone 'Asia/Shanghai' + interval '10 minutes';
  v_result := private_db2.rotate_monthly_admins_if_due(v_run_at);

  if (v_result->>'status') <> 'completed' then
    raise exception 'DB15_ASSERT: rotation did not complete: %', v_result;
  end if;
  if (select count(*) from public.admin_terms where source = 'monthly' and service_month = v_service_month and status = 'active') <> 5 then
    raise exception 'DB15_ASSERT: monthly seats must equal five';
  end if;
  if exists (
    select 1 from public.admin_terms
    where source = 'monthly' and service_month = v_service_month
      and user_id in (
        'db150000-0000-4000-8000-000000000001'::uuid,
        'db150000-0000-4000-8000-000000000002'::uuid,
        'db150000-0000-4000-8000-000000000003'::uuid,
        'db150000-0000-4000-8000-000000000004'::uuid
      )
  ) then
    raise exception 'DB15_ASSERT: super/manual/excluded/under-threshold candidate received a seat: %', (
      select pg_catalog.array_agg(user_id order by user_id)
      from public.admin_terms
      where source = 'monthly' and service_month = v_service_month
        and user_id in (
          'db150000-0000-4000-8000-000000000001'::uuid,
          'db150000-0000-4000-8000-000000000002'::uuid,
          'db150000-0000-4000-8000-000000000003'::uuid,
          'db150000-0000-4000-8000-000000000004'::uuid
        )
    );
  end if;
  if exists (
    select 1
    from private_db2.admin_rotation_candidates
    where service_month = v_service_month
      and eligibility_status = 'eligible'
      and level_at_snapshot < 2
  ) or (
    select level_at_snapshot
    from private_db2.admin_rotation_candidates
    where service_month = v_service_month
      and user_id = 'db150000-0000-4000-8000-000000000004'::uuid
  ) >= 2 then
    raise exception 'DB15_ASSERT: Lv2 candidate boundary was not frozen correctly';
  end if;
  if (select candidate_order from private_db2.admin_rotation_candidates where service_month = v_service_month and user_id = 'db150000-0000-4000-8000-000000000005'::uuid)
    >= (select candidate_order from private_db2.admin_rotation_candidates where service_month = v_service_month and user_id = 'db150000-0000-4000-8000-000000000006'::uuid) then
    raise exception 'DB15_ASSERT: earlier last action must win a complete tie';
  end if;

  perform private_db2.rotate_monthly_admins_if_due(v_run_at);
  if (select count(*) from public.admin_terms where source = 'monthly' and service_month = v_service_month) <> 5 then
    raise exception 'DB15_ASSERT: repeated rotation must be idempotent';
  end if;

  update public.admin_terms
  set status = 'revoked', ended_at = pg_catalog.now(), end_reason = 'fixture vacancy'
  where id = (
    select id from public.admin_terms
    where source = 'monthly' and service_month = v_service_month and status = 'active'
    order by candidate_order limit 1
  );
  if private_db2.fill_monthly_admin_vacancies(v_service_month) <> 1 then
    raise exception 'DB15_ASSERT: revocation must fill exactly one vacancy';
  end if;
  if (select count(*) from public.admin_terms where source = 'monthly' and service_month = v_service_month and status = 'active') <> 5 then
    raise exception 'DB15_ASSERT: vacancy fill did not restore five seats';
  end if;
end;
$$;

do $$
declare
  v_next_month date := (
    pg_catalog.date_trunc('month', pg_catalog.timezone('Asia/Shanghai', pg_catalog.now()))
    + interval '1 month'
  )::date;
  v_result jsonb;
begin
  delete from private_db2.points_leaderboard_months
  where month_start = (v_next_month - interval '1 month')::date;
  v_result := private_db2.rotate_monthly_admins_if_due(
    v_next_month::timestamp at time zone 'Asia/Shanghai' + interval '10 minutes'
  );
  if (v_result->>'status') <> 'leaderboard_not_frozen' or (v_result->>'granted')::integer <> 0 then
    raise exception 'DB15_ASSERT: missing frozen leaderboard must fail closed';
  end if;
end;
$$;

insert into public.admin_terms (
  user_id, source, reason, starts_at, scheduled_end_at
) values (
  'db150000-0000-4000-8000-000000000090'::uuid,
  'manual', 'fixture low-risk reviewer', pg_catalog.now() - interval '1 hour',
  pg_catalog.now() + interval '7 days'
);

with rows(group_no, supporter_no, name, game_id, stars) as (
  values
    (1,21,'DB15 多数通过','1501',5), (1,22,'DB15 多数通过','1501',5),
    (1,23,'DB15 多数通过','1501',5), (1,24,'DB15 多数通过','1501',5),
    (1,25,'DB15 多数通过','1501',5), (1,26,'DB15 少数意见','1501',4),
    (2,21,'DB15 多数驳回','1502',5), (2,22,'DB15 多数驳回','1502',5),
    (2,23,'DB15 多数驳回','1502',5), (2,24,'DB15 多数驳回','1502',5),
    (2,25,'DB15 多数驳回','1502',5), (2,26,'DB15 驳回少数','1502',4),
    (3,21,'DB15 人数不足','1503',5), (3,22,'DB15 人数不足','1503',5),
    (3,23,'DB15 人数不足','1503',5),
    (4,21,'DB15 自审冲突','1504',5), (4,22,'DB15 自审冲突','1504',5),
    (4,23,'DB15 自审冲突','1504',5), (4,24,'DB15 自审冲突','1504',5),
    (4,90,'DB15 自审冲突','1504',5),
    (5,21,'DB15 正式库已有','1505',5), (5,22,'DB15 正式库已有','1505',5),
    (5,23,'DB15 正式库已有','1505',5), (5,24,'DB15 正式库已有','1505',5),
    (5,25,'DB15 正式库已有','1505',5)
)
insert into public.pending_clothes (
  id, name, category, game_id, stars, scores, tags, status, submitted_by
)
select
  915200000 + group_no * 100 + supporter_no,
  name, 'DB15 审核分类', game_id, stars,
  case when stars = 5 then '{"simple":100,"gorgeous":0}'::jsonb else '{"simple":80,"gorgeous":0}'::jsonb end,
  'fixture', 'pending',
  ('db150000-0000-4000-8000-' || pg_catalog.lpad(supporter_no::text, 12, '0'))::uuid
from rows;

insert into public.clothes (id, name, category, game_id, stars, scores)
values ('db15_formal_exists', 'DB15 正式库已有', 'DB15 审核分类', '1505', '5', '{"simple":100,"gorgeous":0}'::jsonb);

select pg_catalog.set_config(
  'request.jwt.claims',
  pg_catalog.json_build_object(
    'sub', 'db150000-0000-4000-8000-000000000090',
    'role', 'authenticated'
  )::text,
  true
);
set local role authenticated;

do $$
declare v_candidates jsonb;
begin
  v_candidates := public.list_low_risk_clothes_review_candidates();
  if pg_catalog.jsonb_array_length(v_candidates) <> 2 then
    raise exception 'DB15_ASSERT: only approve/reject majority groups should be visible: %', v_candidates;
  end if;
  if not exists (
    select 1 from pg_catalog.jsonb_array_elements(v_candidates) item
    where item->>'game_id' = '1501'
      and (item->>'supporter_count')::integer = 5
      and (item->>'minority_count')::integer = 1
  ) then
    raise exception 'DB15_ASSERT: five-person majority with minority dissent missing';
  end if;
end;
$$;

select public.review_low_risk_clothes_candidate(915200121, 'approved', null);
select public.review_low_risk_clothes_candidate(915200121, 'approved', null);

reset role;

do $$
begin
  if not exists (select 1 from public.clothes where game_id = '1501' and category = 'DB15 审核分类') then
    raise exception 'DB15_ASSERT: approved majority did not enter formal library';
  end if;
  if (select count(*) from public.pending_clothes where id between 915200121 and 915200125 and status = 'approved') <> 5 then
    raise exception 'DB15_ASSERT: adopted majority was not approved atomically';
  end if;
  if (select status from public.pending_clothes where id = 915200126) <> 'pending' then
    raise exception 'DB15_ASSERT: minority dissent must remain pending';
  end if;
  if (select count(*) from public.clothing_contributions where source_pending_id between 915200121 and 915200125) <> 5 then
    raise exception 'DB15_ASSERT: contribution facts missing after approval';
  end if;
  if (select count(*) from public.points_ledger where source_id in (
    select id from public.clothing_contributions where source_pending_id between 915200121 and 915200125
  )) <> 5 then
    raise exception 'DB15_ASSERT: points ledger facts missing after approval';
  end if;
  if (
    select count(*)
    from public.admin_review_decisions as decision
    join public.admin_review_decision_sources as source on source.decision_id = decision.id
    where source.pending_id = 915200121 and decision.action = 'approved'
  ) <> 1 then
    raise exception 'DB15_ASSERT: repeated approval must not append a second decision';
  end if;
end;
$$;

set local role authenticated;

select public.review_low_risk_clothes_candidate(915200221, 'rejected', '资料字段需要重新核对');

reset role;

do $$
begin
  if (select count(*) from public.pending_clothes where id between 915200221 and 915200225 and status = 'rejected') <> 5 then
    raise exception 'DB15_ASSERT: adopted majority was not reversibly rejected';
  end if;
  if (select status from public.pending_clothes where id = 915200226) <> 'pending' then
    raise exception 'DB15_ASSERT: rejected group minority must remain pending';
  end if;
  if not exists (
    select 1 from public.admin_review_decisions
    where action = 'rejected' and reason = '资料字段需要重新核对'
  ) then
    raise exception 'DB15_ASSERT: rejection reason audit missing';
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  pg_catalog.json_build_object(
    'sub', 'db150000-0000-4000-8000-000000000021',
    'role', 'authenticated'
  )::text,
  true
);
set local role authenticated;

do $$
begin
  if not exists (
    select 1 from public.get_my_rejected_clothing_submissions()
    where pending_id = 915200221 and reason = '资料字段需要重新核对' and can_resubmit
  ) then
    raise exception 'DB15_ASSERT: submitter cannot read rejection reason and resubmit guidance';
  end if;
  begin
    perform public.list_low_risk_clothes_review_candidates();
    raise exception 'DB15_ASSERT: ordinary user unexpectedly received review capability';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
select pg_catalog.set_config('request.jwt.claims', '{}', true);

do $$
begin
  if has_table_privilege('anon', 'public.admin_terms', 'select')
    or has_table_privilege('authenticated', 'public.admin_terms', 'insert')
    or has_table_privilege('service_role', 'public.admin_review_decisions', 'update') then
    raise exception 'DB15_ASSERT: privileged tables expose direct client access';
  end if;
  if has_function_privilege('anon', 'public.get_current_admin_capabilities()', 'execute') then
    raise exception 'DB15_ASSERT: anon can execute authenticated capability RPC';
  end if;
  if (
    select count(*) from pg_catalog.pg_proc as proc
    join pg_catalog.pg_namespace as ns on ns.oid = proc.pronamespace
    where ns.nspname = 'private_db2'
      and proc.proname in ('rotate_monthly_admins_if_due', 'fill_monthly_admin_vacancies')
      and pg_catalog.array_to_string(proc.proconfig, ',') = 'search_path=""'
  ) <> 2 then
    raise exception 'DB15_ASSERT: privileged rotation functions must use empty search_path';
  end if;
end;
$$;

rollback;
