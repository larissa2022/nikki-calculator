begin;

-- DB-6 missing-suit integration verification. Every fixture write is rolled back.
-- Run only against local Supabase or the explicitly authorized development project.

do $$
begin
  if exists (
    select 1
    from auth.users
    where id between 'db600000-0000-4000-8000-000000000001'::uuid
      and 'db600000-0000-4000-8000-000000000007'::uuid
  ) or exists (
    select 1 from public.clothes where name like 'DB6 接入测试%'
  ) or exists (
    select 1 from public.pending_clothes where name like 'DB6 接入测试%'
  ) then
    raise exception 'DB6_INTEGRATION_ASSERT: fixture identifiers already exist';
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
  ('db600000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'authenticated',
  'authenticated',
  'db6-integration-' || value || '@example.invalid',
  '',
  pg_catalog.now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  pg_catalog.now(),
  pg_catalog.now()
from pg_catalog.generate_series(1, 7) as fixture(value);

update public.profiles
set role = 'admin', role_level = 1
where id = 'db600000-0000-4000-8000-000000000007'::uuid;

insert into public.suits (id, name)
values (
  'db600000-0000-4000-8000-000000000098'::uuid,
  'DB6 接入测试社区候选套装'
);

select pg_catalog.set_config('request.jwt.claims', '{}', true);

do $$
declare
  v_denied boolean := false;
begin
  begin
    perform public.submit_clothing_contribution(
      'DB6 接入测试匿名拒绝',
      '960000',
      'DB6 测试分类',
      5,
      '{"简约":100}'::jsonb,
      null,
      null,
      null,
      true
    );
  exception when others then
    v_denied := true;
  end;

  if not v_denied
    or exists (select 1 from public.pending_clothes where name = 'DB6 接入测试匿名拒绝') then
    raise exception 'DB6_INTEGRATION_ASSERT: anonymous request was not denied atomically';
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db600000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

do $$
declare
  v_result jsonb;
begin
  v_result := public.submit_clothing_contribution(
    'DB6 接入测试纯散件',
    '960001',
    'DB6 测试分类',
    4,
    '{"简约":80}'::jsonb,
    null,
    null,
    null
  );

  if v_result->>'auto_approved' <> 'false'
    or not exists (
      select 1
      from public.pending_clothes
      where id = (v_result->>'pending_id')::bigint
        and not needs_suit_review
    )
    or exists (select 1 from public.re_review_items where payload->>'name' = 'DB6 接入测试纯散件') then
    raise exception 'DB6_INTEGRATION_ASSERT: standalone item semantics changed: %', v_result;
  end if;
end;
$$;

do $$
declare
  v_rejected boolean := false;
begin
  begin
    perform public.submit_clothing_contribution(
      'DB6 接入测试冲突状态',
      '960002',
      'DB6 测试分类',
      5,
      '{"简约":100}'::jsonb,
      '00000000-0000-4000-8000-000000000001'::uuid,
      null,
      null,
      true
    );
  exception when others then
    v_rejected := true;
  end;

  if not v_rejected
    or exists (select 1 from public.pending_clothes where name = 'DB6 接入测试冲突状态') then
    raise exception 'DB6_INTEGRATION_ASSERT: conflicting review flag was not rejected';
  end if;
end;
$$;

do $$
declare
  v_index integer;
  v_user_id uuid;
  v_result jsonb;
begin
  for v_index in 1..5 loop
    v_user_id := ('db600000-0000-4000-8000-' || pg_catalog.lpad(v_index::text, 12, '0'))::uuid;
    perform pg_catalog.set_config(
      'request.jwt.claims',
      pg_catalog.jsonb_build_object('sub', v_user_id, 'role', 'authenticated')::text,
      true
    );

    v_result := public.submit_clothing_contribution(
      'DB6 接入测试自动建项',
      '960003',
      'DB6 测试分类',
      5,
      '{"简约":100,"活泼":200}'::jsonb,
      null,
      null,
      'DB6 标签',
      true
    );

    if (v_result->>'auto_approved')::boolean is distinct from (v_index = 5) then
      raise exception 'DB6_INTEGRATION_ASSERT: submission % result mismatch: %', v_index, v_result;
    end if;

    if v_index = 5 and (v_result->>'re_review_item_id') is null then
      raise exception 'DB6_INTEGRATION_ASSERT: fifth submission did not return review item: %', v_result;
    end if;
  end loop;
end;
$$;

do $$
declare
  v_clothes_id text;
  v_item_id uuid;
  v_result jsonb;
  v_points_count integer;
  v_points_total integer;
begin
  select clothes.id
    into v_clothes_id
  from public.clothes as clothes
  where clothes.name = 'DB6 接入测试自动建项';

  select item.id
    into v_item_id
  from public.re_review_items as item
  where item.clothes_id = v_clothes_id
    and item.reason = 'missing_suit';

  select pg_catalog.count(*), coalesce(pg_catalog.sum(ledger.delta), 0)
    into v_points_count, v_points_total
  from public.points_ledger as ledger
  join public.clothing_contributions as contribution
    on contribution.id = ledger.source_id
  where contribution.clothes_id = v_clothes_id;

  if v_clothes_id is null
    or v_item_id is null
    or not exists (
      select 1
      from public.re_review_items
      where id = v_item_id
        and status = 'pending'
        and payload->>'name' = 'DB6 接入测试自动建项'
        and payload->>'needs_suit_review' = 'true'
    )
    or (select pg_catalog.count(*) from public.re_review_item_sources where re_review_item_id = v_item_id) <> 5
    or (select pg_catalog.count(*) from public.pending_clothes where name = 'DB6 接入测试自动建项' and needs_suit_review and status = 'approved') <> 5
    or (select pg_catalog.count(*) from public.clothing_contributions where clothes_id = v_clothes_id and contribution_type = 'auto_entry') <> 5
    or v_points_count <> 5
    or v_points_total <> 50
    or (select pg_catalog.count(*) from public.user_wardrobes where coalesce(owned_clothes, '[]'::jsonb) @> pg_catalog.jsonb_build_array(v_clothes_id)) <> 5 then
    raise exception 'DB6_INTEGRATION_ASSERT: automatic entry facts are incomplete';
  end if;

  perform pg_catalog.set_config(
    'request.jwt.claims',
    '{"sub":"db600000-0000-4000-8000-000000000005","role":"authenticated"}',
    true
  );

  v_result := public.submit_clothing_contribution(
    'DB6 接入测试自动建项',
    '960003',
    'DB6 测试分类',
    5,
    '{"简约":100,"活泼":200}'::jsonb,
    null,
    null,
    'DB6 标签',
    true
  );

  if v_result->>'auto_approved' <> 'true'
    or (v_result->>'re_review_item_id')::uuid <> v_item_id
    or (select pg_catalog.count(*) from public.re_review_items where clothes_id = v_clothes_id and reason = 'missing_suit') <> 1
    or (select pg_catalog.count(*) from public.re_review_item_sources where re_review_item_id = v_item_id) <> 5 then
    raise exception 'DB6_INTEGRATION_ASSERT: completed retry was not idempotent: %', v_result;
  end if;
end;
$$;

select pg_catalog.set_config(
  'db6.source_item_id',
  (
    select item.id::text
    from public.re_review_items as item
    join public.clothes as clothes on clothes.id = item.clothes_id
    where clothes.name = 'DB6 接入测试自动建项'
  ),
  true
);

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db600000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

set local role authenticated;

do $$
declare
  v_item_id uuid;
  v_denied boolean := false;
begin
  v_item_id := pg_catalog.current_setting('db6.source_item_id')::uuid;

  if exists (select 1 from public.re_review_items where id = v_item_id) then
    raise exception 'DB6_INTEGRATION_ASSERT: source user can read own review item';
  end if;

  begin
    perform public.submit_jury_candidate(
      v_item_id,
      '{"suit_id":"db600000-0000-4000-8000-000000000098"}'::jsonb
    );
  exception when others then
    v_denied := sqlstate = '42501';
  end;

  if not v_denied then
    raise exception 'DB6_INTEGRATION_ASSERT: source user candidate was not denied';
  end if;
end;
$$;

reset role;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db600000-0000-4000-8000-000000000006","role":"authenticated"}',
  true
);

set local role authenticated;

do $$
declare
  v_item_id uuid;
begin
  select item.id
    into v_item_id
  from public.re_review_items as item
  join public.clothes as clothes on clothes.id = item.clothes_id
  where clothes.name = 'DB6 接入测试自动建项';

  if not exists (select 1 from public.re_review_items where id = v_item_id) then
    raise exception 'DB6_INTEGRATION_ASSERT: unrelated community user cannot read open item';
  end if;

  perform public.submit_jury_candidate(
    v_item_id,
    '{"suit_id":"db600000-0000-4000-8000-000000000098"}'::jsonb
  );
end;
$$;

reset role;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db600000-0000-4000-8000-000000000007","role":"authenticated"}',
  true
);

insert into public.pending_clothes (
  id, created_at, name, category, game_id, stars, scores, tags, status, submitted_by, needs_suit_review
)
values (
  960000011,
  '2026-07-26 03:00:00+00',
  'DB6 接入测试管理员建项',
  'DB6 测试分类',
  '960004',
  4,
  '{"简约":70}'::jsonb,
  null,
  'pending',
  'db600000-0000-4000-8000-000000000002'::uuid,
  true
);

do $$
declare
  v_result jsonb;
begin
  v_result := public.approve_pending_clothes_arbitration(
    'db6_integration_admin_01',
    'DB6 接入测试管理员建项',
    '960004',
    'DB6 测试分类',
    4,
    '{"简约":70}'::jsonb,
    null,
    null,
    null,
    array[960000011]::bigint[],
    true
  );

  if v_result->>'already_completed' <> 'false'
    or (v_result->>'re_review_item_id') is null
    or not exists (
      select 1
      from public.re_review_items
      where id = (v_result->>'re_review_item_id')::uuid
        and clothes_id = 'db6_integration_admin_01'
        and status = 'pending'
    )
    or (select pg_catalog.count(*) from public.re_review_item_sources where re_review_item_id = (v_result->>'re_review_item_id')::uuid) <> 1 then
    raise exception 'DB6_INTEGRATION_ASSERT: admin arbitration did not create review facts: %', v_result;
  end if;
end;
$$;

insert into public.clothes (
  id, name, category, game_id, stars, scores, suit_id, temp_suit_name, tags
)
values (
  'db6_integration_existing_01',
  'DB6 接入测试已有服装',
  'DB6 测试分类',
  '960007',
  '4',
  '{"简约":65}'::jsonb,
  null,
  null,
  null
);

insert into public.pending_clothes (
  id, created_at, name, category, game_id, stars, scores, tags, status, submitted_by, needs_suit_review
)
values (
  960000013,
  '2026-07-26 03:05:00+00',
  'DB6 接入测试已有服装',
  'DB6 测试分类',
  '960007',
  4,
  '{"简约":65}'::jsonb,
  'DB6 补全标签',
  'pending',
  'db600000-0000-4000-8000-000000000002'::uuid,
  true
);

do $$
declare
  v_result jsonb;
  v_retry jsonb;
  v_item_id uuid;
begin
  v_result := public.complete_existing_clothes_from_pending(
    'db6_integration_existing_01',
    'DB6 接入测试已有服装',
    '960007',
    'DB6 测试分类',
    4,
    '{"简约":65}'::jsonb,
    null,
    null,
    'DB6 补全标签',
    array[960000013]::bigint[]
  );

  v_item_id := (v_result->>'re_review_item_id')::uuid;

  if v_result->>'already_completed' <> 'false'
    or v_item_id is null
    or not exists (
      select 1
      from public.re_review_items
      where id = v_item_id
        and clothes_id = 'db6_integration_existing_01'
        and status = 'pending'
    )
    or (select pg_catalog.count(*) from public.re_review_item_sources where re_review_item_id = v_item_id) <> 1 then
    raise exception 'DB6_INTEGRATION_ASSERT: existing clothes completion did not create review facts: %', v_result;
  end if;

  v_retry := public.complete_existing_clothes_from_pending(
    'db6_integration_existing_01',
    'DB6 接入测试已有服装',
    '960007',
    'DB6 测试分类',
    4,
    '{"简约":65}'::jsonb,
    null,
    null,
    'DB6 补全标签',
    array[960000013]::bigint[]
  );

  if v_retry->>'already_completed' <> 'true'
    or (v_retry->>'re_review_item_id')::uuid <> v_item_id
    or (select pg_catalog.count(*) from public.re_review_items where clothes_id = 'db6_integration_existing_01' and reason = 'missing_suit') <> 1
    or (select pg_catalog.count(*) from public.re_review_item_sources where re_review_item_id = v_item_id) <> 1 then
    raise exception 'DB6_INTEGRATION_ASSERT: existing clothes retry was not idempotent: %', v_retry;
  end if;
end;
$$;

insert into public.pending_clothes (
  id, created_at, name, category, game_id, stars, scores, status, submitted_by, needs_suit_review
)
values (
  960000012,
  '2026-07-26 03:10:00+00',
  'DB6 接入测试状态不一致',
  'DB6 测试分类',
  '960005',
  4,
  '{"简约":60}'::jsonb,
  'pending',
  'db600000-0000-4000-8000-000000000003'::uuid,
  true
);

do $$
declare
  v_rejected boolean := false;
begin
  begin
    perform public.approve_pending_clothes_arbitration(
      'db6_integration_admin_02',
      'DB6 接入测试状态不一致',
      '960005',
      'DB6 测试分类',
      4,
      '{"简约":60}'::jsonb,
      null,
      null,
      null,
      array[960000012]::bigint[],
      false
    );
  exception when others then
    v_rejected := true;
  end;

  if not v_rejected
    or exists (select 1 from public.clothes where id = 'db6_integration_admin_02') then
    raise exception 'DB6_INTEGRATION_ASSERT: forged admin suit status was not rejected atomically';
  end if;
end;
$$;

insert into public.suits (id, name)
values ('db600000-0000-4000-8000-000000000099'::uuid, 'DB6 接入测试正式套装');

update public.clothes
set suit_id = 'db600000-0000-4000-8000-000000000099'::uuid
where name = 'DB6 接入测试自动建项';

do $$
begin
  if not exists (
    select 1
    from public.re_review_items as item
    join public.clothes as clothes on clothes.id = item.clothes_id
    where clothes.name = 'DB6 接入测试自动建项'
      and item.reason = 'missing_suit'
      and item.status = 'approved'
      and item.resolved_at is not null
  ) then
    raise exception 'DB6_INTEGRATION_ASSERT: formal suit link did not close review item';
  end if;

  if not exists (
    select 1
    from public.re_review_items
    where clothes_id = 'db6_integration_admin_01'
      and status = 'pending'
  ) then
    raise exception 'DB6_INTEGRATION_ASSERT: unrelated review item was closed';
  end if;
end;
$$;

do $$
declare
  v_index integer;
  v_user_id uuid;
begin
  for v_index in 1..4 loop
    v_user_id := ('db600000-0000-4000-8000-' || pg_catalog.lpad(v_index::text, 12, '0'))::uuid;
    perform pg_catalog.set_config(
      'request.jwt.claims',
      pg_catalog.jsonb_build_object('sub', v_user_id, 'role', 'authenticated')::text,
      true
    );

    perform public.submit_clothing_contribution(
      'DB6 接入测试事务回滚',
      '960006',
      'DB6 测试分类',
      3,
      '{"简约":50}'::jsonb,
      null,
      null,
      null,
      true
    );
  end loop;
end;
$$;

create function pg_temp.db6_force_review_failure()
returns trigger
language plpgsql
as $$
begin
  if new.payload->>'name' = 'DB6 接入测试事务回滚' then
    raise exception 'DB6_EXPECTED_REVIEW_FAILURE';
  end if;
  return new;
end;
$$;

create trigger db6_force_review_failure
before insert on public.re_review_items
for each row execute function pg_temp.db6_force_review_failure();

do $$
declare
  v_failed boolean := false;
begin
  perform pg_catalog.set_config(
    'request.jwt.claims',
    '{"sub":"db600000-0000-4000-8000-000000000005","role":"authenticated"}',
    true
  );

  begin
    perform public.submit_clothing_contribution(
      'DB6 接入测试事务回滚',
      '960006',
      'DB6 测试分类',
      3,
      '{"简约":50}'::jsonb,
      null,
      null,
      null,
      true
    );
  exception when others then
    v_failed := pg_catalog.strpos(sqlerrm, 'DB6_EXPECTED_REVIEW_FAILURE') > 0;
  end;

  if not v_failed
    or (select pg_catalog.count(*) from public.pending_clothes where name = 'DB6 接入测试事务回滚') <> 4
    or exists (select 1 from public.clothes where name = 'DB6 接入测试事务回滚')
    or exists (select 1 from public.re_review_items where payload->>'name' = 'DB6 接入测试事务回滚')
    or exists (
      select 1
      from public.clothing_contributions as contribution
      join public.clothes as clothes on clothes.id = contribution.clothes_id
      where clothes.name = 'DB6 接入测试事务回滚'
    ) then
    raise exception 'DB6_INTEGRATION_ASSERT: induced review failure left partial facts';
  end if;
end;
$$;

drop trigger db6_force_review_failure on public.re_review_items;

do $$
declare
  v_submit_signature text := 'public.submit_clothing_contribution(text,text,text,integer,jsonb,uuid,text,text,boolean)';
  v_admin_signature text := 'public.approve_pending_clothes_arbitration(text,text,text,text,integer,jsonb,uuid,text,text,bigint[],boolean)';
  v_existing_signature text := 'public.complete_existing_clothes_from_pending(text,text,text,text,integer,jsonb,uuid,text,text,bigint[])';
  v_existing_core_signature text := 'public.complete_existing_clothes_from_pending_db3_core(text,text,text,text,integer,jsonb,uuid,text,text,bigint[])';
  v_internal_signature text := 'public.ensure_missing_suit_re_review_item(text,bigint[],boolean)';
begin
  if has_function_privilege('anon', v_submit_signature, 'EXECUTE')
    or not has_function_privilege('authenticated', v_submit_signature, 'EXECUTE')
    or has_function_privilege('anon', v_admin_signature, 'EXECUTE')
    or not has_function_privilege('authenticated', v_admin_signature, 'EXECUTE')
    or has_function_privilege('anon', v_existing_signature, 'EXECUTE')
    or not has_function_privilege('authenticated', v_existing_signature, 'EXECUTE')
    or has_function_privilege('authenticated', v_existing_core_signature, 'EXECUTE')
    or has_function_privilege('anon', v_existing_core_signature, 'EXECUTE')
    or has_function_privilege('authenticated', v_internal_signature, 'EXECUTE')
    or has_function_privilege('anon', v_internal_signature, 'EXECUTE') then
    raise exception 'DB6_INTEGRATION_ASSERT: function grants mismatch';
  end if;

  if has_table_privilege('anon', 'public.re_review_items', 'SELECT,INSERT,UPDATE,DELETE')
    or has_table_privilege('anon', 'public.re_review_item_sources', 'SELECT,INSERT,UPDATE,DELETE')
    or has_table_privilege('anon', 'public.re_review_candidates', 'SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'DB6_INTEGRATION_ASSERT: anonymous DB-6 table access was widened';
  end if;
end;
$$;

select pg_catalog.jsonb_build_object(
  'status', 'passed',
  'label', '所属套装待确认',
  'standalone_preserved', true,
  'automatic_review_created', true,
  'all_sources_preserved', true,
  'source_self_review_denied', true,
  'community_candidate_allowed', true,
  'admin_review_created', true,
  'existing_clothes_review_created', true,
  'formal_suit_auto_closed', true,
  'retry_idempotent', true,
  'transaction_rollback', true,
  'fixture_rollback_pending', true
) as db6_missing_suit_verification;

rollback;
