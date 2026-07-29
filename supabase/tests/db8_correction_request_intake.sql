begin;

-- DB-8 correction-request intake verification.
-- Run only against local Supabase or the explicitly authorized development project.
-- Every fixture write is rolled back.

do $$
begin
  if exists (
    select 1
    from auth.users
    where id between 'db800000-0000-4000-8000-000000000001'::uuid
      and 'db800000-0000-4000-8000-000000000002'::uuid
  ) or exists (
    select 1
    from public.clothes
    where id = 'db8_correction_fixture'
  ) then
    raise exception 'DB8_CORRECTION_ASSERT: fixture identifiers already exist';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class as relation
    where relation.oid = 'public.correction_requests'::regclass
      and relation.relrowsecurity
  ) then
    raise exception 'DB8_CORRECTION_ASSERT: RLS is not enabled';
  end if;

  if pg_catalog.has_table_privilege(
    'authenticated',
    'public.correction_requests',
    'SELECT,INSERT,UPDATE,DELETE'
  ) then
    raise exception 'DB8_CORRECTION_ASSERT: authenticated role has direct table privileges';
  end if;

  if not pg_catalog.has_table_privilege(
    'service_role',
    'public.correction_requests',
    'SELECT'
  ) or not pg_catalog.has_table_privilege(
    'service_role',
    'public.correction_requests',
    'INSERT'
  ) or not pg_catalog.has_table_privilege(
    'service_role',
    'public.correction_requests',
    'UPDATE'
  ) then
    raise exception 'DB8_CORRECTION_ASSERT: service role is missing required table privileges';
  end if;

  if pg_catalog.has_table_privilege(
    'service_role',
    'public.correction_requests',
    'DELETE,TRUNCATE,REFERENCES,TRIGGER'
  ) then
    raise exception 'DB8_CORRECTION_ASSERT: service role has excess table privileges';
  end if;

  if pg_catalog.has_function_privilege(
    'anon',
    'public.submit_correction_request(varchar,text,jsonb)',
    'EXECUTE'
  ) or pg_catalog.has_function_privilege(
    'anon',
    'public.get_my_correction_requests()',
    'EXECUTE'
  ) then
    raise exception 'DB8_CORRECTION_ASSERT: anonymous role can execute correction RPCs';
  end if;

  if pg_catalog.has_function_privilege(
    'authenticated',
    'public.submit_correction_request(varchar,text,jsonb)',
    'EXECUTE'
  ) or not pg_catalog.has_function_privilege(
    'authenticated',
    'public.submit_correction_request_with_evidence(varchar,jsonb,text)',
    'EXECUTE'
  ) or not pg_catalog.has_function_privilege(
    'authenticated',
    'public.get_my_correction_requests()',
    'EXECUTE'
  ) then
    raise exception 'DB8_CORRECTION_ASSERT: correction RPC exposure is incorrect';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_index as index_definition
    join pg_catalog.pg_class as index_relation
      on index_relation.oid = index_definition.indexrelid
    where index_relation.relname = 'correction_requests_active_reporter_field_unique'
      and index_definition.indisunique
      and index_definition.indpred is not null
  ) then
    raise exception 'DB8_CORRECTION_ASSERT: active report partial unique index is missing';
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
  ('db800000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'authenticated',
  'authenticated',
  'db8-correction-' || value || '@example.invalid',
  '',
  pg_catalog.now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  pg_catalog.now(),
  pg_catalog.now()
from pg_catalog.generate_series(1, 2) as fixture(value);

insert into public.clothes (
  id,
  name,
  category,
  game_id,
  stars,
  scores,
  tags,
  suit_id,
  temp_suit_name
)
values (
  'db8_correction_fixture',
  'DB8 报错受理测试服装',
  '连衣裙',
  '990080',
  '5',
  '{"simple":4305,"gorgeous":0,"active":4305,"elegant":0,"cute":4305,"mature":0,"pure":4305,"sexy":0,"cool":4305,"warm":0}'::jsonb,
  null,
  null,
  null
);

select pg_catalog.set_config('request.jwt.claims', '{}', true);

do $$
declare
  v_denied boolean := false;
begin
  begin
    perform public.submit_correction_request(
      'db8_correction_fixture',
      '这里有足够长度的匿名报错说明',
      '{"name":"建议名称"}'::jsonb
    );
  exception when others then
    v_denied := true;
  end;

  if not v_denied
    or exists (
      select 1 from public.correction_requests
      where clothes_id = 'db8_correction_fixture'
    ) then
    raise exception 'DB8_CORRECTION_ASSERT: anonymous request was not denied atomically';
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db800000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

do $$
declare
  v_first jsonb;
  v_retry jsonb;
  v_second_field jsonb;
  v_history jsonb;
  v_conflict_denied boolean := false;
  v_invalid_denied boolean := false;
  v_missing_denied boolean := false;
begin
  v_first := public.submit_correction_request(
    'db8_correction_fixture',
    '游戏内名称应为“DB8 报错受理修正名称”，截图可以核对。',
    '{"name":"DB8 报错受理修正名称"}'::jsonb
  );

  if coalesce((v_first->>'idempotent')::boolean, true)
    or v_first->>'status' <> 'converted_to_re_review'
    or nullif(v_first->>'request_id', '') is null
    or nullif(v_first->>'re_review_item_id', '') is null then
    raise exception 'DB8_CORRECTION_ASSERT: first submission result is invalid';
  end if;

  v_retry := public.submit_correction_request(
    'db8_correction_fixture',
    '游戏内名称应为“DB8 报错受理修正名称”，截图可以核对。',
    '{"name":"DB8 报错受理修正名称"}'::jsonb
  );

  if not coalesce((v_retry->>'idempotent')::boolean, false)
    or v_retry->>'request_id' is distinct from v_first->>'request_id'
    or (
      select count(*)
      from public.correction_requests
      where clothes_id = 'db8_correction_fixture'
        and field_key = 'name'
    ) <> 1 then
    raise exception 'DB8_CORRECTION_ASSERT: identical retry is not idempotent';
  end if;

  begin
    perform public.submit_correction_request(
      'db8_correction_fixture',
      '这次改成另一个名称，不能覆盖已有待处理报错。',
      '{"name":"另一个名称"}'::jsonb
    );
  exception when others then
    v_conflict_denied := true;
  end;

  if not v_conflict_denied then
    raise exception 'DB8_CORRECTION_ASSERT: conflicting active report was accepted';
  end if;

  v_second_field := public.submit_correction_request(
    'db8_correction_fixture',
    '游戏内星级显示为四星，当前正式图鉴记录不一致。',
    '{"stars":"4"}'::jsonb
  );

  if coalesce((v_second_field->>'idempotent')::boolean, true)
    or (
      select count(*)
      from public.correction_requests
      where clothes_id = 'db8_correction_fixture'
        and reported_by = 'db800000-0000-4000-8000-000000000001'::uuid
    ) <> 2 then
    raise exception 'DB8_CORRECTION_ASSERT: independent field report was not created';
  end if;

  begin
    perform public.submit_correction_request(
      'db8_correction_fixture',
      '这个字段不在允许范围内，必须被数据库拒绝。',
      '{"unknown":"错误内容"}'::jsonb
    );
  exception when others then
    v_invalid_denied := true;
  end;

  if not v_invalid_denied then
    raise exception 'DB8_CORRECTION_ASSERT: invalid field was accepted';
  end if;

  begin
    perform public.submit_correction_request(
      'missing_db8_fixture',
      '这件服装并不存在，因此报错请求不能形成孤立记录。',
      '{"name":"不存在"}'::jsonb
    );
  exception when others then
    v_missing_denied := true;
  end;

  if not v_missing_denied then
    raise exception 'DB8_CORRECTION_ASSERT: missing clothes report was accepted';
  end if;

  v_history := public.get_my_correction_requests();
  if jsonb_array_length(v_history) <> 2
    or not exists (
      select 1
      from jsonb_array_elements(v_history) as history(item)
      where history.item->>'field_key' = 'name'
        and history.item->>'clothes_name' = 'DB8 报错受理测试服装'
        and history.item->>'status' = 'converted_to_re_review'
    ) then
    raise exception 'DB8_CORRECTION_ASSERT: reporter history is incomplete';
  end if;

  if exists (
    select 1
    from public.clothes
    where id = 'db8_correction_fixture'
      and (
        name is distinct from 'DB8 报错受理测试服装'
        or category is distinct from '连衣裙'
        or game_id is distinct from '990080'
        or stars is distinct from '5'
        or suit_id is not null
        or temp_suit_name is not null
      )
  ) then
    raise exception 'DB8_CORRECTION_ASSERT: intake changed formal clothes';
  end if;

  if (
    select count(*)
    from public.re_review_items
    where clothes_id = 'db8_correction_fixture'
      and status = 'pending'
  ) <> 1 or (
    select count(*)
    from public.re_review_item_sources as source
    join public.re_review_items as item on item.id = source.re_review_item_id
    where item.clothes_id = 'db8_correction_fixture'
  ) <> 2 then
    raise exception 'DB8_CORRECTION_ASSERT: intake did not route into one jury item';
  end if;

  if not exists (
    select 1
    from public.re_review_items as item
    where item.clothes_id = 'db8_correction_fixture'
      and item.status = 'pending'
      and exists (
        select 1
        from pg_catalog.jsonb_array_elements(item.payload->'issues') as issue(value)
        where issue.value->>'field' = 'name'
      )
      and exists (
        select 1
        from pg_catalog.jsonb_array_elements(item.payload->'issues') as issue(value)
        where issue.value->>'field' = 'stars'
      )
  ) then
    raise exception 'DB8_CORRECTION_ASSERT: reused jury item did not retain every reported field';
  end if;

  if exists (
    select 1
    from public.points_ledger
    where user_id = 'db800000-0000-4000-8000-000000000001'::uuid
  ) then
    raise exception 'DB8_CORRECTION_ASSERT: intake awarded points';
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db800000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);

do $$
begin
  if jsonb_array_length(public.get_my_correction_requests()) <> 0 then
    raise exception 'DB8_CORRECTION_ASSERT: another user can see reporter history';
  end if;
end;
$$;

delete from public.profiles
where id = 'db800000-0000-4000-8000-000000000001'::uuid;

delete from auth.users
where id = 'db800000-0000-4000-8000-000000000001'::uuid;

do $$
begin
  if (
    select count(*)
    from public.correction_requests
    where clothes_id = 'db8_correction_fixture'
      and reported_by is null
  ) <> 2 then
    raise exception 'DB8_CORRECTION_ASSERT: deleted reporter audit facts were not retained anonymously';
  end if;
end;
$$;

select 'db8_correction_request_intake_passed' as result;

rollback;
