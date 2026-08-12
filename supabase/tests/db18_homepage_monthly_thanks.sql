begin;

-- DB-18 development-only verification. Every fixture write is rolled back.
-- Run only after scripts/check-dev-link.mjs confirms tfwejruvdahonacyldrg.

do $$
begin
  if exists (
    select 1 from auth.users where email like 'db18-fixture-%@example.invalid'
  ) then
    raise exception 'DB18_ASSERT: fixture identifiers already exist';
  end if;
end;
$$;

delete from private_db2.admin_rotation_candidates
where service_month = pg_catalog.date_trunc(
  'month', pg_catalog.timezone('Asia/Shanghai', pg_catalog.now())
)::date;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  ('db180000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'authenticated', 'authenticated',
  'db18-fixture-' || value || '@example.invalid', '', pg_catalog.now(),
  '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
  pg_catalog.now(), pg_catalog.now()
from pg_catalog.generate_series(1, 12) as fixture(value);

update public.profiles
set username = case
  when id = 'db180000-0000-4000-8000-000000000011'::uuid then null
  else '首页鸣谢测试 ' || right(id::text, 2)
end
where id between 'db180000-0000-4000-8000-000000000001'::uuid
  and 'db180000-0000-4000-8000-000000000012'::uuid;

insert into private_db2.admin_rotation_candidates (
  service_month, source_month, user_id, frozen_points,
  qualifying_action_count, tie_break_at, candidate_order,
  eligibility_status, skip_reason, level_at_snapshot
)
select
  target.service_month,
  (target.service_month - interval '1 month')::date,
  ('db180000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  1000 - value,
  case when value = 12 then 4 else 5 end,
  target.service_month::timestamp at time zone 'Asia/Shanghai' + (value || ' minutes')::interval,
  value,
  'skipped',
  'DB18 fixture does not grant admin eligibility',
  0
from pg_catalog.generate_series(1, 12) as fixture(value)
cross join lateral (
  select pg_catalog.date_trunc(
    'month', pg_catalog.timezone('Asia/Shanghai', pg_catalog.now())
  )::date as service_month
) as target;

delete from public.profiles
where id = 'db180000-0000-4000-8000-000000000002'::uuid;

delete from auth.users
where id = 'db180000-0000-4000-8000-000000000002'::uuid;

update public.profiles
set username = '首页鸣谢测试 01·新名称'
where id = 'db180000-0000-4000-8000-000000000001'::uuid;

do $$
begin
  if not pg_catalog.has_table_privilege(
    'anon', 'public.homepage_monthly_thanks', 'select'
  ) or not pg_catalog.has_table_privilege(
    'authenticated', 'public.homepage_monthly_thanks', 'select'
  ) then
    raise exception 'DB18_ASSERT: public read grants are missing';
  end if;

  if pg_catalog.has_table_privilege(
    'anon', 'public.homepage_monthly_thanks', 'insert'
  ) or pg_catalog.has_table_privilege(
    'authenticated', 'public.homepage_monthly_thanks', 'update'
  ) or pg_catalog.has_table_privilege(
    'service_role', 'public.homepage_monthly_thanks', 'select'
  ) then
    raise exception 'DB18_ASSERT: homepage thanks grants are broader than intended';
  end if;

  if pg_catalog.has_table_privilege(
    'anon', 'private_db2.admin_rotation_candidates', 'select'
  ) or pg_catalog.has_table_privilege(
    'authenticated', 'auth.users', 'select'
  ) then
    raise exception 'DB18_ASSERT: private source tables became readable';
  end if;

  if not pg_catalog.has_function_privilege(
    'anon', 'private_db2.homepage_monthly_thanks()', 'execute'
  ) or pg_catalog.has_function_privilege(
    'service_role', 'private_db2.homepage_monthly_thanks()', 'execute'
  ) then
    raise exception 'DB18_ASSERT: function execute grants mismatch';
  end if;
end;
$$;

set local role anon;

do $$
declare
  v_expected_month date := (
    pg_catalog.date_trunc(
      'month', pg_catalog.timezone('Asia/Shanghai', pg_catalog.now())
    ) - interval '1 month'
  )::date;
begin
  if (select pg_catalog.count(*) from public.homepage_monthly_thanks) <> 10 then
    raise exception 'DB18_ASSERT: public result must contain exactly ten rows';
  end if;

  if (select pg_catalog.min(month_start) from public.homepage_monthly_thanks)
    is distinct from v_expected_month
    or (select pg_catalog.max(month_start) from public.homepage_monthly_thanks)
      is distinct from v_expected_month then
    raise exception 'DB18_ASSERT: source month mismatch';
  end if;

  if (select display_name from public.homepage_monthly_thanks where display_order = 1)
    is distinct from '首页鸣谢测试 01·新名称' then
    raise exception 'DB18_ASSERT: current public name or ordering mismatch';
  end if;

  if exists (
    select 1 from public.homepage_monthly_thanks
    where display_name in ('首页鸣谢测试 02', '首页鸣谢测试 12')
  ) then
    raise exception 'DB18_ASSERT: deleted or under-threshold user leaked';
  end if;

  if not exists (
    select 1 from public.homepage_monthly_thanks
    where display_name like '匿名搭配师-%'
  ) then
    raise exception 'DB18_ASSERT: missing-name pseudonym fallback was not used';
  end if;
end;
$$;

reset role;
rollback;

do $$
begin
  if exists (
    select 1 from auth.users where email like 'db18-fixture-%@example.invalid'
  ) then
    raise exception 'DB18_ASSERT: fixture residue remains after rollback';
  end if;
end;
$$;

select 'passed' as db18_homepage_monthly_thanks;
