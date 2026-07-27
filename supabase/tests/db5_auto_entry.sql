begin;

-- DB-5 development-only verification. Every fixture write is rolled back.
-- Run only after scripts/check-dev-link.mjs confirms tfwejruvdahonacyldrg.

do $$
begin
  if exists (
    select 1
    from auth.users
    where id between 'db500000-0000-4000-8000-000000000001'::uuid
      and 'db500000-0000-4000-8000-000000000007'::uuid
  ) or exists (
    select 1
    from public.clothes
    where name like 'DB5 测试%'
  ) or exists (
    select 1
    from public.pending_clothes
    where name like 'DB5 测试%'
  ) or exists (
    select 1
    from public.pending_suits
    where name like 'DB5 测试%'
  ) then
    raise exception 'DB5_ASSERT: fixture identifiers already exist';
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
  ('db500000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'authenticated',
  'authenticated',
  'db5-fixture-' || value || '@example.invalid',
  '',
  pg_catalog.now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  pg_catalog.now(),
  pg_catalog.now()
from pg_catalog.generate_series(1, 7) as fixture(value);

select pg_catalog.set_config('request.jwt.claims', '{}', true);

do $$
declare
  v_denied boolean := false;
begin
  begin
    perform public.submit_clothing_contribution(
      'DB5 测试匿名拒绝',
      '950000',
      'DB5 测试分类',
      5,
      '{"简约":100,"活泼":200}'::jsonb,
      null,
      'DB5 测试临时套装',
      'DB5 标签'
    );
  exception when others then
    v_denied := pg_catalog.strpos(sqlerrm, '需要登录') > 0;
  end;

  if not v_denied
    or exists (select 1 from public.pending_clothes where name = 'DB5 测试匿名拒绝') then
    raise exception 'DB5_ASSERT: anonymous request was not denied atomically';
  end if;
end;
$$;

do $$
declare
  v_index integer;
  v_user_id uuid;
  v_result jsonb;
begin
  for v_index in 1..4 loop
    v_user_id := ('db500000-0000-4000-8000-' || pg_catalog.lpad(v_index::text, 12, '0'))::uuid;
    perform pg_catalog.set_config(
      'request.jwt.claims',
      pg_catalog.jsonb_build_object('sub', v_user_id, 'role', 'authenticated')::text,
      true
    );

    v_result := public.submit_clothing_contribution(
      'DB5 测试自动入库',
      '950001',
      'DB5 测试分类',
      5,
      '{"简约":100,"活泼":200}'::jsonb,
      null,
      'DB5 测试临时套装',
      'DB5 标签'
    );

    if v_result->>'auto_approved' <> 'false'
      or (v_result->>'pending_id') is null then
      raise exception 'DB5_ASSERT: submission % unexpectedly auto-approved: %', v_index, v_result;
    end if;
  end loop;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db500000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

do $$
declare
  v_existing_pending_id bigint;
  v_result jsonb;
begin
  select id
    into v_existing_pending_id
  from public.pending_clothes
  where name = 'DB5 测试自动入库'
    and submitted_by = 'db500000-0000-4000-8000-000000000001'::uuid;

  v_result := public.submit_clothing_contribution(
    'DB5 测试自动入库',
    '950001',
    'DB5 测试分类',
    5,
    '{"简约":100,"活泼":200}'::jsonb,
    null,
    'DB5 测试临时套装',
    'DB5 标签'
  );

  if v_result->>'auto_approved' <> 'false'
    or (v_result->>'pending_id')::bigint <> v_existing_pending_id
    or (select pg_catalog.count(*) from public.pending_clothes where name = 'DB5 测试自动入库') <> 4
    or (select pg_catalog.count(*) from public.pending_suits where name = 'DB5 测试临时套装') <> 4 then
    raise exception 'DB5_ASSERT: duplicate submission was not idempotent: %', v_result;
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db500000-0000-4000-8000-000000000005","role":"authenticated"}',
  true
);

do $$
declare
  v_result jsonb;
begin
  v_result := public.submit_clothing_contribution(
    'DB5 测试自动入库',
    '950001',
    'DB5 测试分类',
    5,
    '{"简约":100,"活泼":200}'::jsonb,
    null,
    'DB5 测试临时套装',
    'DB5 标签'
  );

  if v_result->>'auto_approved' <> 'true'
    or (v_result->>'matched_pending_count')::integer <> 5
    or (v_result->>'wardrobe_updated_count')::integer <> 5 then
    raise exception 'DB5_ASSERT: fifth contributor result mismatch: %', v_result;
  end if;
end;
$$;

do $$
declare
  v_clothes_id text;
  v_source_users uuid[];
  v_points_count integer;
  v_points_total integer;
begin
  select id
    into v_clothes_id
  from public.clothes
  where name = 'DB5 测试自动入库'
    and category = 'DB5 测试分类';

  if v_clothes_id is null then
    raise exception 'DB5_ASSERT: auto-approved clothes row missing';
  end if;

  select pg_catalog.array_agg(user_id order by contribution_rank)
    into v_source_users
  from public.clothing_contributions
  where clothes_id = v_clothes_id
    and contribution_type = 'auto_entry';

  if v_source_users is distinct from array[
    'db500000-0000-4000-8000-000000000001'::uuid,
    'db500000-0000-4000-8000-000000000002'::uuid,
    'db500000-0000-4000-8000-000000000003'::uuid,
    'db500000-0000-4000-8000-000000000004'::uuid,
    'db500000-0000-4000-8000-000000000005'::uuid
  ] then
    raise exception 'DB5_ASSERT: stable top-five users mismatch: %', v_source_users;
  end if;

  select pg_catalog.count(*)::integer, coalesce(pg_catalog.sum(ledger.delta), 0)::integer
    into v_points_count, v_points_total
  from public.points_ledger as ledger
  join public.clothing_contributions as contribution
    on contribution.id = ledger.source_id
  where contribution.clothes_id = v_clothes_id;

  if v_points_count <> 5 or v_points_total <> 50 then
    raise exception 'DB5_ASSERT: points facts mismatch: count %, total %', v_points_count, v_points_total;
  end if;

  if (select pg_catalog.count(*) from public.pending_clothes where name = 'DB5 测试自动入库' and status = 'approved') <> 5 then
    raise exception 'DB5_ASSERT: matching pending sources were not preserved as approved';
  end if;

  if exists (select 1 from public.pending_clothes where name = 'DB5 测试自动入库' and status <> 'approved') then
    raise exception 'DB5_ASSERT: auto-entry left a matching pending source unfinished';
  end if;

  if (select pg_catalog.count(*) from public.user_wardrobes where user_id between 'db500000-0000-4000-8000-000000000001'::uuid and 'db500000-0000-4000-8000-000000000005'::uuid and coalesce(owned_clothes, '[]'::jsonb) @> pg_catalog.jsonb_build_array(v_clothes_id)) <> 5 then
    raise exception 'DB5_ASSERT: wardrobe writeback mismatch';
  end if;

  if (select pg_catalog.count(*) from public.clothing_contributors_public where clothes_id = v_clothes_id) <> 3 then
    raise exception 'DB5_ASSERT: DB-2 public contributor view mismatch';
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db500000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

do $$
declare
  v_points bigint;
begin
  select total_points into v_points from public.user_points_summary;
  if v_points <> 10 then
    raise exception 'DB5_ASSERT: DB-2 points summary mismatch: %', v_points;
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db500000-0000-4000-8000-000000000005","role":"authenticated"}',
  true
);

do $$
declare
  v_result jsonb;
  v_clothes_id text;
begin
  select id into v_clothes_id
  from public.clothes
  where name = 'DB5 测试自动入库'
    and category = 'DB5 测试分类';

  v_result := public.submit_clothing_contribution(
    'DB5 测试自动入库',
    '950001',
    'DB5 测试分类',
    5,
    '{"简约":100,"活泼":200}'::jsonb,
    null,
    'DB5 测试临时套装',
    'DB5 标签'
  );

  if v_result->>'auto_approved' <> 'true'
    or v_result->>'clothes_id' <> v_clothes_id
    or (select pg_catalog.count(*) from public.pending_clothes where name = 'DB5 测试自动入库') <> 5
    or (select pg_catalog.count(*) from public.clothing_contributions where clothes_id = v_clothes_id) <> 5
    or (select pg_catalog.count(*) from public.points_ledger as ledger join public.clothing_contributions as contribution on contribution.id = ledger.source_id where contribution.clothes_id = v_clothes_id) <> 5 then
    raise exception 'DB5_ASSERT: retry after completed auto-entry was not idempotent: %', v_result;
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db500000-0000-4000-8000-000000000006","role":"authenticated"}',
  true
);

do $$
declare
  v_rejected boolean := false;
begin
  begin
    perform public.submit_clothing_contribution(
      'DB5 测试冲突候选',
      '950001',
      'DB5 测试分类',
      5,
      '{"简约":100,"活泼":200}'::jsonb,
      null,
      'DB5 测试临时套装',
      'DB5 标签'
    );
  exception when others then
    v_rejected := pg_catalog.strpos(sqlerrm, '数据与本次提交不一致') > 0;
  end;

  if not v_rejected
    or exists (select 1 from public.pending_clothes where name = 'DB5 测试冲突候选') then
    raise exception 'DB5_ASSERT: conflicting candidate was not rejected atomically';
  end if;
end;
$$;

do $$
declare
  v_result jsonb;
begin
  v_result := public.submit_clothing_contribution(
    'DB5 测试无套装保留',
    '950002',
    'DB5 测试分类',
    4,
    '{"简约":80}'::jsonb,
    null,
    null,
    null
  );

  if v_result->>'auto_approved' <> 'false'
    or not exists (select 1 from public.pending_clothes where name = 'DB5 测试无套装保留' and status = 'pending')
    or exists (select 1 from public.clothes where name = 'DB5 测试无套装保留')
    or exists (
      select 1
      from public.re_review_items
      where payload->>'name' = 'DB5 测试无套装保留'
    ) then
    raise exception 'DB5_ASSERT: no-suit narrow-scope behavior mismatch: %', v_result;
  end if;
end;
$$;

do $$
declare
  v_index integer;
  v_user_id uuid;
  v_result jsonb;
begin
  for v_index in 1..4 loop
    v_user_id := ('db500000-0000-4000-8000-' || pg_catalog.lpad(v_index::text, 12, '0'))::uuid;
    perform pg_catalog.set_config(
      'request.jwt.claims',
      pg_catalog.jsonb_build_object('sub', v_user_id, 'role', 'authenticated')::text,
      true
    );

    v_result := public.submit_clothing_contribution(
      'DB5 测试事务回滚',
      '950003',
      'DB5 测试分类',
      4,
      '{"简约":70}'::jsonb,
      null,
      'DB5 测试事务套装',
      null
    );

    if v_result->>'auto_approved' <> 'false' then
      raise exception 'DB5_ASSERT: rollback fixture submission % unexpectedly auto-approved', v_index;
    end if;
  end loop;
end;
$$;

create function pg_temp.db5_force_points_failure()
returns trigger
language plpgsql
as $$
begin
  if new.user_id = 'db500000-0000-4000-8000-000000000001'::uuid then
    raise exception 'DB5_EXPECTED_POINTS_FAILURE';
  end if;
  return new;
end;
$$;

create trigger db5_force_points_failure
before insert on public.points_ledger
for each row execute function pg_temp.db5_force_points_failure();

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db500000-0000-4000-8000-000000000005","role":"authenticated"}',
  true
);

do $$
declare
  v_failed boolean := false;
begin
  begin
    perform public.submit_clothing_contribution(
      'DB5 测试事务回滚',
      '950003',
      'DB5 测试分类',
      4,
      '{"简约":70}'::jsonb,
      null,
      'DB5 测试事务套装',
      null
    );
  exception when others then
    v_failed := pg_catalog.strpos(sqlerrm, 'DB5_EXPECTED_POINTS_FAILURE') > 0;
  end;

  if not v_failed
    or (select pg_catalog.count(*) from public.pending_clothes where name = 'DB5 测试事务回滚') <> 4
    or exists (select 1 from public.clothes where name = 'DB5 测试事务回滚')
    or exists (select 1 from public.clothing_contributions as contribution join public.clothes as clothes on clothes.id = contribution.clothes_id where clothes.name = 'DB5 测试事务回滚') then
    raise exception 'DB5_ASSERT: induced points failure left a partial write';
  end if;
end;
$$;

drop trigger db5_force_points_failure on public.points_ledger;

do $$
declare
  v_signature text := 'public.submit_clothing_contribution(text,text,text,integer,jsonb,uuid,text,text,boolean)';
  v_definition text;
  v_config text[];
begin
  select pg_catalog.pg_get_functiondef(proc.oid), proc.proconfig
    into v_definition, v_config
  from pg_catalog.pg_proc as proc
  join pg_catalog.pg_namespace as namespace on namespace.oid = proc.pronamespace
  where namespace.nspname = 'public'
    and proc.proname = 'submit_clothing_contribution';

  if has_function_privilege('anon', v_signature, 'EXECUTE')
    or not has_function_privilege('authenticated', v_signature, 'EXECUTE')
    or not has_function_privilege('service_role', v_signature, 'EXECUTE')
    or coalesce(pg_catalog.array_to_string(v_config, ','), '') not like '%search_path=%'
    or pg_catalog.strpos(v_definition, 'pg_advisory_xact_lock') = 0 then
    raise exception 'DB5_ASSERT: RPC security or serialization definition mismatch';
  end if;

  if has_table_privilege('anon', 'public.clothing_contributions', 'SELECT,INSERT,UPDATE,DELETE')
    or has_table_privilege('authenticated', 'public.clothing_contributions', 'SELECT,INSERT,UPDATE,DELETE')
    or has_table_privilege('anon', 'public.points_ledger', 'SELECT,INSERT,UPDATE,DELETE')
    or has_table_privilege('authenticated', 'public.points_ledger', 'SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'DB5_ASSERT: DB-1 direct table privileges widened';
  end if;
end;
$$;

select pg_catalog.jsonb_build_object(
  'status', 'passed',
  'distinct_contributors', 5,
  'points_each', 10,
  'points_total', 50,
  'sources_preserved', true,
  'duplicate_pending_idempotent', true,
  'completed_retry_idempotent', true,
  'business_key_lock_present', true,
  'conflict_rejected', true,
  'no_suit_stays_pending', true,
  'transaction_rollback', true,
  'db2_views_verified', true,
  'fixture_rollback_pending', true
) as db5_verification;

rollback;
