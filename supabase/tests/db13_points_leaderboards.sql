begin;

-- DB-13 development-only verification. Every fixture write is rolled back.
-- Run only after scripts/check-dev-link.mjs confirms tfwejruvdahonacyldrg.

do $$
begin
  if exists (
    select 1 from auth.users
    where id between 'db130000-0000-4000-8000-000000000001'::uuid
      and 'db130000-0000-4000-8000-000000000005'::uuid
  ) or exists (
    select 1 from public.clothes
    where id = 'db13_fixture_leaderboard'
  ) or exists (
    select 1 from public.pending_clothes
    where id between 913000001 and 913000005
  ) then
    raise exception 'DB13_ASSERT: fixture identifiers already exist';
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
  ('db130000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'authenticated',
  'authenticated',
  'db13-fixture-' || value || '@example.invalid',
  '',
  pg_catalog.now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  pg_catalog.now(),
  pg_catalog.now()
from pg_catalog.generate_series(1, 5) as fixture(value);

update public.profiles
set username = case id
  when 'db130000-0000-4000-8000-000000000001'::uuid then '榜单测试甲'
  when 'db130000-0000-4000-8000-000000000003'::uuid then '榜单测试丙'
  when 'db130000-0000-4000-8000-000000000004'::uuid then '榜单测试丁'
  when 'db130000-0000-4000-8000-000000000005'::uuid then '榜单测试未来'
  else null
end
where id between 'db130000-0000-4000-8000-000000000001'::uuid
  and 'db130000-0000-4000-8000-000000000005'::uuid;

insert into public.clothes (id, name, category)
values ('db13_fixture_leaderboard', 'DB13 排行榜测试', 'DB13 测试分类');

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
  913000000 + value,
  pg_catalog.now() - (value || ' minutes')::interval,
  'DB13 排行榜测试',
  'DB13 测试分类',
  (913000 + value)::text,
  5,
  '{"简约":100}'::jsonb,
  'approved',
  ('db130000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid
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
  ('d1300000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'd13e0000-0000-4000-8000-000000000001'::uuid,
  'db13_fixture_leaderboard',
  ('db130000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  913000000 + value,
  'admin_arbitration',
  value,
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
    when 'future' then month_boundary.starts_at + interval '1 month 1 day'
    else month_boundary.starts_at - interval '1 day'
  end
from month_boundary
cross join (
  values
    (
      'd1310000-0000-4000-8000-000000000001'::uuid,
      'db130000-0000-4000-8000-000000000001'::uuid,
      10,
      'd1300000-0000-4000-8000-000000000001'::uuid,
      'current'
    ),
    (
      'd1310000-0000-4000-8000-000000000002'::uuid,
      'db130000-0000-4000-8000-000000000002'::uuid,
      10,
      'd1300000-0000-4000-8000-000000000002'::uuid,
      'current'
    ),
    (
      'd1310000-0000-4000-8000-000000000003'::uuid,
      'db130000-0000-4000-8000-000000000003'::uuid,
      20,
      'd1300000-0000-4000-8000-000000000003'::uuid,
      'previous'
    ),
    (
      'd1310000-0000-4000-8000-000000000004'::uuid,
      'db130000-0000-4000-8000-000000000004'::uuid,
      5,
      'd1300000-0000-4000-8000-000000000004'::uuid,
      'current'
    ),
    (
      'd1310000-0000-4000-8000-000000000005'::uuid,
      'db130000-0000-4000-8000-000000000005'::uuid,
      7,
      'd1300000-0000-4000-8000-000000000005'::uuid,
      'future'
    )
) as fixture(id, user_id, delta, source_id, period);

do $$
begin
  if pg_catalog.has_table_privilege('anon', 'public.points_leaderboard_total', 'select')
    or pg_catalog.has_table_privilege('anon', 'public.points_leaderboard_current_month', 'select') then
    raise exception 'DB13_ASSERT: anon unexpectedly has leaderboard access';
  end if;

  if not pg_catalog.has_table_privilege('authenticated', 'public.points_leaderboard_total', 'select')
    or not pg_catalog.has_table_privilege('authenticated', 'public.points_leaderboard_current_month', 'select') then
    raise exception 'DB13_ASSERT: authenticated is missing leaderboard access';
  end if;

  if pg_catalog.has_table_privilege('authenticated', 'public.points_ledger', 'select') then
    raise exception 'DB13_ASSERT: leaderboard widened base-table access';
  end if;

  if pg_catalog.has_table_privilege('authenticated', 'public.points_leaderboard_total', 'insert')
    or pg_catalog.has_table_privilege('authenticated', 'public.points_leaderboard_total', 'update')
    or pg_catalog.has_table_privilege('authenticated', 'public.points_leaderboard_total', 'delete') then
    raise exception 'DB13_ASSERT: total leaderboard is not read-only';
  end if;

  if pg_catalog.has_function_privilege('anon', 'private_db2.total_points_leaderboard()', 'execute')
    or pg_catalog.has_function_privilege('anon', 'private_db2.current_month_points_leaderboard()', 'execute') then
    raise exception 'DB13_ASSERT: anon unexpectedly has helper execution';
  end if;
end;
$$;

select pg_catalog.set_config('request.jwt.claims', '{}', true);

do $$
begin
  if (select pg_catalog.count(*) from public.points_leaderboard_total) <> 0
    or (select pg_catalog.count(*) from public.points_leaderboard_current_month) <> 0 then
    raise exception 'DB13_ASSERT: unauthenticated SQL context received leaderboard rows';
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db130000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

do $$
declare
  v_anonymous_name text;
  v_user_one_rank bigint;
  v_user_two_rank bigint;
  v_user_four_rank bigint;
begin
  if (select points from public.points_leaderboard_total where display_name = '榜单测试甲') is distinct from 10::bigint
    or (select points from public.points_leaderboard_total where display_name = '榜单测试丙') is distinct from 20::bigint
    or (select points from public.points_leaderboard_total where display_name = '榜单测试丁') is distinct from 5::bigint
    or (select points from public.points_leaderboard_total where display_name = '榜单测试未来') is distinct from 7::bigint then
    raise exception 'DB13_ASSERT: total leaderboard points mismatch';
  end if;

  v_anonymous_name := '匿名搭配师-' || pg_catalog.upper(
    pg_catalog.substr(
      pg_catalog.md5('db130000-0000-4000-8000-000000000002'::uuid::text),
      1,
      8
    )
  );

  if (select points from public.points_leaderboard_total where display_name = v_anonymous_name) is distinct from 10::bigint then
    raise exception 'DB13_ASSERT: anonymous display name or points mismatch: %', v_anonymous_name;
  end if;

  if exists (
    select 1
    from public.points_leaderboard_total as target
    where target.display_name in ('榜单测试甲', '榜单测试丙', '榜单测试丁', '榜单测试未来', v_anonymous_name)
      and target.leaderboard_rank <> (
        select 1 + pg_catalog.count(distinct higher.points)
        from public.points_leaderboard_total as higher
        where higher.points > target.points
      )
  ) then
    raise exception 'DB13_ASSERT: total leaderboard does not use dense rank';
  end if;

  select leaderboard_rank into v_user_one_rank
  from public.points_leaderboard_total
  where display_name = '榜单测试甲';

  select leaderboard_rank into v_user_two_rank
  from public.points_leaderboard_total
  where display_name = v_anonymous_name;

  if v_user_one_rank is distinct from v_user_two_rank then
    raise exception 'DB13_ASSERT: equal total points do not share one rank';
  end if;

  if (select points from public.points_leaderboard_current_month where display_name = '榜单测试甲') is distinct from 10::bigint
    or (select points from public.points_leaderboard_current_month where display_name = v_anonymous_name) is distinct from 10::bigint
    or (select points from public.points_leaderboard_current_month where display_name = '榜单测试丁') is distinct from 5::bigint then
    raise exception 'DB13_ASSERT: current-month leaderboard points mismatch';
  end if;

  if exists (
    select 1
    from public.points_leaderboard_current_month as target
    where target.display_name in ('榜单测试甲', '榜单测试丁', v_anonymous_name)
      and target.leaderboard_rank <> (
        select 1 + pg_catalog.count(distinct higher.points)
        from public.points_leaderboard_current_month as higher
        where higher.points > target.points
      )
  ) then
    raise exception 'DB13_ASSERT: current-month leaderboard does not use dense rank';
  end if;

  select leaderboard_rank into v_user_one_rank
  from public.points_leaderboard_current_month
  where display_name = '榜单测试甲';

  select leaderboard_rank into v_user_two_rank
  from public.points_leaderboard_current_month
  where display_name = v_anonymous_name;

  select leaderboard_rank into v_user_four_rank
  from public.points_leaderboard_current_month
  where display_name = '榜单测试丁';

  if v_user_one_rank is distinct from v_user_two_rank
    or v_user_four_rank <= v_user_one_rank then
    raise exception 'DB13_ASSERT: current-month tie ordering mismatch';
  end if;

  if (select pg_catalog.count(*) from public.points_leaderboard_total where is_current_user) <> 1
    or (select pg_catalog.count(*) from public.points_leaderboard_current_month where is_current_user) <> 1 then
    raise exception 'DB13_ASSERT: current-user marker mismatch';
  end if;

  if exists (
    select 1
    from public.points_leaderboard_current_month
    where display_name in ('榜单测试丙', '榜单测试未来')
  ) then
    raise exception 'DB13_ASSERT: previous-month or future user leaked into current month';
  end if;
end;
$$;

select 'passed' as db13_points_leaderboards;

rollback;
