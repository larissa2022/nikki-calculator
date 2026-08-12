begin;

-- DB-20 development-only verification. Every fixture write is rolled back.
-- Run only after scripts/check-dev-link.mjs confirms tfwejruvdahonacyldrg.

do $$
begin
  if exists (
    select 1 from auth.users
    where id between 'db200000-0000-4000-8000-000000000001'::uuid
      and 'db200000-0000-4000-8000-000000000003'::uuid
  ) or exists (
    select 1 from public.feature_requests
    where title like 'DB20 %'
  ) then
    raise exception 'DB20_ASSERT: fixture identifiers already exist';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_class
    where oid = 'public.feature_requests'::regclass and relrowsecurity and relforcerowsecurity
  ) or not exists (
    select 1 from pg_catalog.pg_class
    where oid = 'public.feature_request_likes'::regclass and relrowsecurity and relforcerowsecurity
  ) or not exists (
    select 1 from pg_catalog.pg_class
    where oid = 'public.feature_request_events'::regclass and relrowsecurity and relforcerowsecurity
  ) then
    raise exception 'DB20_ASSERT: RLS and FORCE RLS are required';
  end if;

  if pg_catalog.has_table_privilege('anon', 'public.feature_requests', 'SELECT,INSERT,UPDATE,DELETE')
    or pg_catalog.has_table_privilege('authenticated', 'public.feature_requests', 'SELECT,INSERT,UPDATE,DELETE')
    or pg_catalog.has_table_privilege('authenticated', 'public.feature_request_likes', 'SELECT,INSERT,UPDATE,DELETE')
    or pg_catalog.has_table_privilege('authenticated', 'public.feature_request_events', 'SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'DB20_ASSERT: client obtained direct fact-table access';
  end if;

  if not pg_catalog.has_function_privilege('anon', 'public.list_feature_requests(text,integer,integer)', 'EXECUTE')
    or pg_catalog.has_function_privilege('anon', 'public.submit_feature_request(text,text)', 'EXECUTE')
    or pg_catalog.has_function_privilege('anon', 'public.set_feature_request_like(uuid,boolean)', 'EXECUTE')
    or pg_catalog.has_function_privilege('anon', 'public.withdraw_feature_request(uuid)', 'EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated', 'public.submit_feature_request(text,text)', 'EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated', 'public.set_feature_request_like(uuid,boolean)', 'EXECUTE') then
    raise exception 'DB20_ASSERT: RPC grants are incorrect';
  end if;
end;
$$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  ('db200000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'authenticated',
  'authenticated',
  'db20-feature-' || value || '@example.invalid',
  '',
  pg_catalog.now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  pg_catalog.now(),
  pg_catalog.now()
from pg_catalog.generate_series(1, 3) as fixture(value);

update public.profiles
set
  username = case id
    when 'db200000-0000-4000-8000-000000000001'::uuid then '建议测试甲'
    when 'db200000-0000-4000-8000-000000000002'::uuid then '建议测试乙'
    else '建议测试超管'
  end,
  role = case when id = 'db200000-0000-4000-8000-000000000003'::uuid then 'super_admin' else 'user' end,
  role_level = case when id = 'db200000-0000-4000-8000-000000000003'::uuid then 2 else 0 end
where id between 'db200000-0000-4000-8000-000000000001'::uuid
  and 'db200000-0000-4000-8000-000000000003'::uuid;

select pg_catalog.set_config('request.jwt.claims', '{"role":"anon"}', true);

do $$
declare
  v_denied boolean := false;
begin
  if pg_catalog.jsonb_array_length(public.list_feature_requests('pending', 100, 0)) <> 0 then
    raise exception 'DB20_ASSERT: anonymous public list should start empty';
  end if;

  begin
    perform public.submit_feature_request('DB20 匿名建议', '匿名用户不应能够提交这条优化建议');
  exception when others then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'DB20_ASSERT: anonymous submission was accepted';
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db200000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

do $$
declare
  v_first jsonb;
  v_duplicate jsonb;
  v_request_id uuid;
  v_counter integer;
  v_limit_denied boolean := false;
begin
  v_first := public.submit_feature_request(
    'DB20 增加筛选条件',
    '希望衣服列表支持按照来源和星级组合筛选。'
  );
  v_request_id := (v_first->>'request_id')::uuid;
  if coalesce((v_first->>'duplicate')::boolean, true) then
    raise exception 'DB20_ASSERT: first submission was marked duplicate';
  end if;

  v_duplicate := public.submit_feature_request(
    ' DB20   增加筛选条件 ',
    '希望衣服列表支持按照来源和星级组合筛选。'
  );
  if not coalesce((v_duplicate->>'duplicate')::boolean, false)
    or v_duplicate->>'request_id' is distinct from v_first->>'request_id'
    or (select pg_catalog.count(*) from public.feature_requests where title = 'DB20 增加筛选条件') <> 1 then
    raise exception 'DB20_ASSERT: exact duplicate was not redirected';
  end if;

  perform public.set_feature_request_like(v_request_id, true);
  perform public.set_feature_request_like(v_request_id, true);
  if private_db2.feature_request_like_count(v_request_id) <> 1 then
    raise exception 'DB20_ASSERT: repeated like was not idempotent';
  end if;
  perform public.set_feature_request_like(v_request_id, false);
  if private_db2.feature_request_like_count(v_request_id) <> 0
    or not exists (
      select 1 from public.feature_request_likes
      where feature_request_id = v_request_id and not is_active and cancelled_at is not null
    ) then
    raise exception 'DB20_ASSERT: unlike was not preserved as inactive fact';
  end if;
  perform public.set_feature_request_like(v_request_id, true);
  if (
    select pg_catalog.count(*)
    from public.feature_request_likes
    where feature_request_id = v_request_id
      and user_id = 'db200000-0000-4000-8000-000000000001'::uuid
  ) <> 2 then
    raise exception 'DB20_ASSERT: relike did not preserve the cancelled history';
  end if;

  for v_counter in 2..5 loop
    perform public.submit_feature_request(
      'DB20 每日上限测试 ' || v_counter,
      '这是用于验证北京自然日提交上限的第 ' || v_counter || ' 条不同说明。'
    );
  end loop;

  begin
    perform public.submit_feature_request(
      'DB20 每日上限测试 6',
      '这是第六条不同说明，应该被每日五条规则拒绝。'
    );
  exception when others then
    v_limit_denied := true;
  end;
  if not v_limit_denied then
    raise exception 'DB20_ASSERT: daily submission limit was not enforced';
  end if;

  if pg_catalog.jsonb_array_length(public.get_my_feature_requests()) <> 5
    or pg_catalog.jsonb_array_length(public.list_feature_requests('pending', 100, 0)) <> 5 then
    raise exception 'DB20_ASSERT: author or public list is incomplete';
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db200000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);

do $$
declare
  v_target uuid;
  v_own uuid;
  v_withdraw_denied boolean := false;
  v_admin_denied boolean := false;
begin
  select id into v_target from public.feature_requests where title = 'DB20 增加筛选条件';
  perform public.set_feature_request_like(v_target, true);

  begin
    perform public.withdraw_feature_request(v_target);
  exception when others then
    v_withdraw_denied := true;
  end;
  if not v_withdraw_denied then
    raise exception 'DB20_ASSERT: another user withdrew the request';
  end if;

  begin
    perform public.moderate_feature_request(v_target, 'plan', '越权测试', '不应成功', null);
  exception when others then
    v_admin_denied := true;
  end;
  if not v_admin_denied then
    raise exception 'DB20_ASSERT: normal user moderated the request';
  end if;

  v_own := (public.submit_feature_request(
    'DB20 可撤回建议',
    '这条建议用于验证作者只能撤回自己的待评估建议。'
  )->>'request_id')::uuid;
  perform public.withdraw_feature_request(v_own);
  if exists (
    select 1 from pg_catalog.jsonb_array_elements(public.list_feature_requests('pending', 100, 0)) as listed(item)
    where listed.item->>'request_id' = v_own::text
  ) or not exists (
    select 1 from public.feature_request_events
    where feature_request_id = v_own and event_type = 'withdrawn'
  ) then
    raise exception 'DB20_ASSERT: withdrawn request remained public or lost audit';
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db200000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);

do $$
declare
  v_target uuid;
  v_duplicate uuid;
  v_not_feasible uuid;
begin
  select id into v_target from public.feature_requests where title = 'DB20 增加筛选条件';
  select id into v_duplicate from public.feature_requests where title = 'DB20 每日上限测试 2';
  select id into v_not_feasible from public.feature_requests where title = 'DB20 每日上限测试 3';

  perform public.moderate_feature_request(
    v_target,
    'plan',
    '已确认可以进入后续规划',
    '已经纳入后续版本计划。',
    null
  );
  if (select status from public.feature_requests where id = v_target) <> 'planned'
    or pg_catalog.jsonb_array_length(public.list_feature_requests('planned', 100, 0)) <> 1 then
    raise exception 'DB20_ASSERT: planned transition failed';
  end if;

  perform public.moderate_feature_request(
    v_not_feasible,
    'not_feasible',
    '当前数据来源不足',
    '当前技术条件暂时无法提供。',
    null
  );
  if pg_catalog.jsonb_array_length(public.list_feature_requests('not_feasible', 100, 0)) <> 1 then
    raise exception 'DB20_ASSERT: not-feasible transition failed';
  end if;

  perform public.moderate_feature_request(v_target, 'reopen', '重新收集使用场景', null, null);
  if (select status from public.feature_requests where id = v_target) <> 'pending'
    or (select public_response from public.feature_requests where id = v_target) is not null then
    raise exception 'DB20_ASSERT: reopen transition failed';
  end if;

  perform public.moderate_feature_request(v_duplicate, 'mark_duplicate', '内容与目标建议重复', null, v_target);
  if (select visibility from public.feature_requests where id = v_duplicate) <> 'duplicate'
    or exists (
      select 1 from pg_catalog.jsonb_array_elements(public.list_feature_requests('pending', 100, 0)) as listed(item)
      where listed.item->>'request_id' = v_duplicate::text
    ) then
    raise exception 'DB20_ASSERT: duplicate archive remained public';
  end if;

  if pg_catalog.jsonb_array_length(public.list_feature_requests_for_admin()) <> 6
    or (select pg_catalog.count(*) from public.feature_request_events) < 10 then
    raise exception 'DB20_ASSERT: admin queue or append-only events are incomplete';
  end if;
end;
$$;

delete from public.profiles where id = 'db200000-0000-4000-8000-000000000001'::uuid;
delete from auth.users where id = 'db200000-0000-4000-8000-000000000001'::uuid;

do $$
declare
  v_target uuid;
begin
  select id into v_target from public.feature_requests where title = 'DB20 增加筛选条件';
  if (select submitted_by from public.feature_requests where id = v_target) is not null
    or private_db2.feature_request_like_count(v_target) <> 2
    or not exists (
      select 1 from public.feature_request_likes
      where feature_request_id = v_target and user_id is null and is_active
    ) then
    raise exception 'DB20_ASSERT: deleted account audit or historical active like was not preserved';
  end if;
end;
$$;

select 'passed' as db20_feature_request_board;

rollback;
