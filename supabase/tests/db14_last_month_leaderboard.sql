begin;

-- DB-14 development-only verification. Every fixture write is rolled back.
-- Run only after scripts/check-dev-link.mjs confirms tfwejruvdahonacyldrg.

do $$
begin
  if exists (
    select 1
    from auth.users
    where id between 'db140000-0000-4000-8000-000000000001'::uuid
      and 'db140000-0000-4000-8000-000000000004'::uuid
  ) or exists (
    select 1
    from public.clothes
    where id = 'db14_fixture_leaderboard'
  ) or exists (
    select 1
    from public.pending_clothes
    where id between 914000001 and 914000005
  ) then
    raise exception 'DB14_ASSERT: fixture identifiers already exist';
  end if;
end;
$$;

delete from private_db2.points_leaderboard_months
where month_start = (
  pg_catalog.date_trunc(
    'month',
    pg_catalog.timezone('Asia/Shanghai', pg_catalog.now())
  ) - interval '1 month'
)::date;

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
  ('db140000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'authenticated',
  'authenticated',
  'db14-fixture-' || value || '@example.invalid',
  '',
  pg_catalog.now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  pg_catalog.now(),
  pg_catalog.now()
from pg_catalog.generate_series(1, 4) as fixture(value);

update public.profiles
set username = case id
  when 'db140000-0000-4000-8000-000000000001'::uuid then '上月榜测试甲'
  when 'db140000-0000-4000-8000-000000000003'::uuid then '上月榜测试丙'
  when 'db140000-0000-4000-8000-000000000004'::uuid then '上月榜测试迟到'
  else null
end
where id between 'db140000-0000-4000-8000-000000000001'::uuid
  and 'db140000-0000-4000-8000-000000000004'::uuid;

insert into public.clothes (id, name, category)
values ('db14_fixture_leaderboard', 'DB14 上月榜测试', 'DB14 测试分类');

insert into public.pending_clothes (
  id,
  created_at,
  name,
  category,
  game_id,
  stars,
  scores,
  status,
  submitted_by
)
select
  914000000 + value,
  pg_catalog.now() - (value || ' minutes')::interval,
  'DB14 上月榜测试',
  'DB14 测试分类',
  (914000 + value)::text,
  5,
  '{"简约":100}'::jsonb,
  'approved',
  case
    when value = 5 then 'db140000-0000-4000-8000-000000000004'::uuid
    else ('db140000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid
  end
from pg_catalog.generate_series(1, 5) as fixture(value);

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
select
  ('d1400000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  case
    when value = 5 then 'd14e0000-0000-4000-8000-000000000002'::uuid
    else 'd14e0000-0000-4000-8000-000000000001'::uuid
  end,
  'db14_fixture_leaderboard',
  case
    when value = 5 then 'db140000-0000-4000-8000-000000000004'::uuid
    else ('db140000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid
  end,
  914000000 + value,
  case when value = 5 then 'existing_field_completion' else 'admin_arbitration' end,
  case when value = 5 then 1 else value end,
  pg_catalog.now() - (value || ' minutes')::interval
from pg_catalog.generate_series(1, 5) as fixture(value);

with month_boundary as (
  select (
    pg_catalog.date_trunc(
      'month',
      pg_catalog.timezone('Asia/Shanghai', pg_catalog.now())
    ) at time zone 'Asia/Shanghai'
  ) as starts_at
)
insert into public.points_ledger (
  id,
  user_id,
  delta,
  source_type,
  source_id,
  occurred_at
)
select
  fixture.id,
  fixture.user_id,
  fixture.delta,
  'clothing_contribution',
  fixture.source_id,
  case fixture.period
    when 'current' then month_boundary.starts_at + interval '1 day'
    else month_boundary.starts_at - interval '1 day'
  end
from month_boundary
cross join (
  values
    (
      'd1410000-0000-4000-8000-000000000001'::uuid,
      'db140000-0000-4000-8000-000000000001'::uuid,
      10,
      'd1400000-0000-4000-8000-000000000001'::uuid,
      'previous'
    ),
    (
      'd1410000-0000-4000-8000-000000000002'::uuid,
      'db140000-0000-4000-8000-000000000002'::uuid,
      10,
      'd1400000-0000-4000-8000-000000000002'::uuid,
      'previous'
    ),
    (
      'd1410000-0000-4000-8000-000000000003'::uuid,
      'db140000-0000-4000-8000-000000000003'::uuid,
      5,
      'd1400000-0000-4000-8000-000000000003'::uuid,
      'previous'
    ),
    (
      'd1410000-0000-4000-8000-000000000004'::uuid,
      'db140000-0000-4000-8000-000000000004'::uuid,
      100,
      'd1400000-0000-4000-8000-000000000004'::uuid,
      'current'
    )
) as fixture(id, user_id, delta, source_id, period);

do $$
declare
  v_previous_month date := (
    pg_catalog.date_trunc(
      'month',
      pg_catalog.timezone('Asia/Shanghai', pg_catalog.now())
    ) - interval '1 month'
  )::date;
begin
  if private_db2.freeze_points_leaderboard_month(v_previous_month) <> 3 then
    raise exception 'DB14_ASSERT: initial freeze row count mismatch';
  end if;
end;
$$;

with month_boundary as (
  select (
    pg_catalog.date_trunc(
      'month',
      pg_catalog.timezone('Asia/Shanghai', pg_catalog.now())
    ) at time zone 'Asia/Shanghai'
  ) as starts_at
)
insert into public.points_ledger (
  id,
  user_id,
  delta,
  source_type,
  source_id,
  occurred_at
)
select
  'd1410000-0000-4000-8000-000000000005'::uuid,
  'db140000-0000-4000-8000-000000000004'::uuid,
  50,
  'clothing_contribution',
  'd1400000-0000-4000-8000-000000000005'::uuid,
  month_boundary.starts_at - interval '1 day'
from month_boundary;

update public.profiles
set username = '上月榜测试甲·新名称'
where id = 'db140000-0000-4000-8000-000000000001'::uuid;

delete from public.profiles
where id = 'db140000-0000-4000-8000-000000000002'::uuid;

update private_db2.points_leaderboard_monthly_snapshots
set user_id = null
where user_id = 'db140000-0000-4000-8000-000000000002'::uuid;

do $$
declare
  v_beijing_month_start timestamp := pg_catalog.date_trunc(
    'month',
    pg_catalog.timezone('Asia/Shanghai', pg_catalog.now())
  );
  v_previous_month date := (v_beijing_month_start - interval '1 month')::date;
begin
  if private_db2.freeze_points_leaderboard_month(v_previous_month) <> 3 then
    raise exception 'DB14_ASSERT: repeated freeze is not idempotent';
  end if;

  if private_db2.freeze_previous_month_if_due(
    (v_beijing_month_start + interval '5 minutes') at time zone 'Asia/Shanghai'
  ) <> 3 then
    raise exception 'DB14_ASSERT: day-one cron entrypoint did not freeze previous month';
  end if;

  if private_db2.freeze_previous_month_if_due(
    (v_beijing_month_start + interval '1 day 5 minutes') at time zone 'Asia/Shanghai'
  ) <> 0 then
    raise exception 'DB14_ASSERT: non-day-one cron entrypoint was not a no-op';
  end if;

  begin
    perform private_db2.freeze_points_leaderboard_month(
      v_beijing_month_start::date
    );
    raise exception 'DB14_ASSERT: current month freeze unexpectedly succeeded';
  exception
    when sqlstate '22023' then null;
  end;
end;
$$;

do $$
begin
  if pg_catalog.has_table_privilege(
    'anon',
    'public.points_leaderboard_last_month',
    'select'
  ) then
    raise exception 'DB14_ASSERT: anon unexpectedly has last-month access';
  end if;

  if not pg_catalog.has_table_privilege(
    'authenticated',
    'public.points_leaderboard_last_month',
    'select'
  ) then
    raise exception 'DB14_ASSERT: authenticated is missing last-month access';
  end if;

  if pg_catalog.has_table_privilege(
    'authenticated',
    'private_db2.points_leaderboard_months',
    'select'
  ) or pg_catalog.has_table_privilege(
    'authenticated',
    'private_db2.points_leaderboard_monthly_snapshots',
    'select'
  ) then
    raise exception 'DB14_ASSERT: authenticated can read private snapshots';
  end if;

  if pg_catalog.has_function_privilege(
    'authenticated',
    'private_db2.freeze_points_leaderboard_month(date)',
    'execute'
  ) or pg_catalog.has_function_privilege(
    'authenticated',
    'private_db2.freeze_previous_month_if_due(timestamptz)',
    'execute'
  ) then
    raise exception 'DB14_ASSERT: authenticated can execute freeze functions';
  end if;

  if pg_catalog.has_table_privilege(
    'authenticated',
    'public.points_leaderboard_last_month',
    'insert'
  ) or pg_catalog.has_table_privilege(
    'authenticated',
    'public.points_leaderboard_last_month',
    'update'
  ) or pg_catalog.has_table_privilege(
    'authenticated',
    'public.points_leaderboard_last_month',
    'delete'
  ) then
    raise exception 'DB14_ASSERT: last-month view is not read-only';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class
    where oid = 'private_db2.points_leaderboard_months'::regclass
      and relrowsecurity
      and relforcerowsecurity
  ) or not exists (
    select 1
    from pg_catalog.pg_class
    where oid = 'private_db2.points_leaderboard_monthly_snapshots'::regclass
      and relrowsecurity
      and relforcerowsecurity
  ) then
    raise exception 'DB14_ASSERT: private snapshot RLS is not forced';
  end if;

  if (
    select pg_catalog.count(*)
    from cron.job
    where jobname = 'db14-freeze-previous-month-leaderboard'
      and schedule = '5 16 * * *'
      and command = 'select private_db2.freeze_previous_month_if_due();'
  ) <> 1 then
    raise exception 'DB14_ASSERT: cron job definition mismatch';
  end if;
end;
$$;

select pg_catalog.set_config('request.jwt.claims', '{}', true);

do $$
begin
  if (select pg_catalog.count(*) from public.points_leaderboard_last_month) <> 0 then
    raise exception 'DB14_ASSERT: unauthenticated SQL context received rows';
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db140000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

do $$
declare
  v_previous_month date := (
    pg_catalog.date_trunc(
      'month',
      pg_catalog.timezone('Asia/Shanghai', pg_catalog.now())
    ) - interval '1 month'
  )::date;
begin
  if (
    select row_count
    from private_db2.points_leaderboard_months
    where month_start = v_previous_month
  ) is distinct from 3::bigint then
    raise exception 'DB14_ASSERT: freeze marker row count mismatch';
  end if;

  if (
    select pg_catalog.count(*)
    from private_db2.points_leaderboard_monthly_snapshots
    where month_start = v_previous_month
  ) <> 3 then
    raise exception 'DB14_ASSERT: frozen snapshot row count mismatch';
  end if;

  if (
    select points
    from public.points_leaderboard_last_month
    where display_name = '上月榜测试甲·新名称'
  ) is distinct from 10::bigint then
    raise exception 'DB14_ASSERT: current display name or frozen points mismatch';
  end if;

  if (
    select points
    from public.points_leaderboard_last_month
    where display_name = '已注销用户'
  ) is distinct from 10::bigint then
    raise exception 'DB14_ASSERT: deleted-user display or frozen points mismatch';
  end if;

  if (
    select leaderboard_rank
    from public.points_leaderboard_last_month
    where display_name = '上月榜测试甲·新名称'
  ) is distinct from 1::bigint or (
    select leaderboard_rank
    from public.points_leaderboard_last_month
    where display_name = '已注销用户'
  ) is distinct from 1::bigint or (
    select leaderboard_rank
    from public.points_leaderboard_last_month
    where display_name = '上月榜测试丙'
  ) is distinct from 2::bigint then
    raise exception 'DB14_ASSERT: dense rank mismatch';
  end if;

  if (
    select points
    from public.points_leaderboard_last_month
    where display_name = '上月榜测试丙'
  ) is distinct from 5::bigint then
    raise exception 'DB14_ASSERT: late previous-month entry changed frozen points';
  end if;

  if exists (
    select 1
    from public.points_leaderboard_last_month
    where display_name = '上月榜测试迟到'
  ) then
    raise exception 'DB14_ASSERT: current or late entry leaked into frozen result';
  end if;

  if (
    select pg_catalog.count(*)
    from public.points_leaderboard_last_month
    where is_current_user
  ) <> 1 then
    raise exception 'DB14_ASSERT: current-user marker mismatch';
  end if;
end;
$$;

rollback;

do $$
begin
  if exists (
    select 1
    from auth.users
    where id between 'db140000-0000-4000-8000-000000000001'::uuid
      and 'db140000-0000-4000-8000-000000000004'::uuid
  ) or exists (
    select 1
    from public.clothes
    where id = 'db14_fixture_leaderboard'
  ) or exists (
    select 1
    from public.pending_clothes
    where id between 914000001 and 914000005
  ) then
    raise exception 'DB14_ASSERT: fixture residue remains after rollback';
  end if;
end;
$$;

select 'passed' as db14_last_month_leaderboard;
