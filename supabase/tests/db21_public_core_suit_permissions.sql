begin;

-- DB-21 development-only fixture. Every write is rolled back.
-- Run only after scripts/check-dev-link.mjs confirms tfwejruvdahonacyldrg.

do $$
begin
  if exists (
    select 1 from auth.users
    where id between 'db210000-0000-4000-8000-000000000001'::uuid
      and 'db210000-0000-4000-8000-000000000004'::uuid
  ) or exists (
    select 1 from public.pending_suits where name like 'DB21 fixture %'
  ) or exists (
    select 1 from public.suits where name like 'DB21 fixture %'
  ) then
    raise exception 'DB21_ASSERT: fixture identifiers already exist';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_class
    where oid in ('public.stages'::regclass, 'public.suits'::regclass, 'public.pending_suits'::regclass)
      and (not relrowsecurity or not relforcerowsecurity)
  ) then
    raise exception 'DB21_ASSERT: all target tables require RLS and FORCE RLS';
  end if;

  if not pg_catalog.has_table_privilege('anon', 'public.stages', 'SELECT')
    or not pg_catalog.has_table_privilege('authenticated', 'public.stages', 'SELECT')
    or not pg_catalog.has_table_privilege('anon', 'public.suits', 'SELECT')
    or not pg_catalog.has_table_privilege('authenticated', 'public.suits', 'SELECT')
    or pg_catalog.has_table_privilege('anon', 'public.stages', 'INSERT,UPDATE,DELETE,TRUNCATE')
    or pg_catalog.has_table_privilege('authenticated', 'public.stages', 'INSERT,UPDATE,DELETE,TRUNCATE')
    or pg_catalog.has_table_privilege('anon', 'public.suits', 'INSERT,UPDATE,DELETE,TRUNCATE')
    or pg_catalog.has_table_privilege('authenticated', 'public.suits', 'INSERT,UPDATE,DELETE,TRUNCATE') then
    raise exception 'DB21_ASSERT: public core grants are not read-only';
  end if;

  if pg_catalog.has_table_privilege('anon', 'public.pending_suits', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
    or not pg_catalog.has_table_privilege('authenticated', 'public.pending_suits', 'SELECT')
    or pg_catalog.has_table_privilege('authenticated', 'public.pending_suits', 'UPDATE,DELETE,TRUNCATE')
    or not pg_catalog.has_column_privilege('authenticated', 'public.pending_suits', 'name', 'INSERT')
    or not pg_catalog.has_column_privilege('authenticated', 'public.pending_suits', 'submitted_by', 'INSERT')
    or pg_catalog.has_column_privilege('authenticated', 'public.pending_suits', 'status', 'INSERT')
    or pg_catalog.has_column_privilege('authenticated', 'public.pending_suits', 'id', 'INSERT')
    or pg_catalog.has_column_privilege('authenticated', 'public.pending_suits', 'created_at', 'INSERT') then
    raise exception 'DB21_ASSERT: pending suit grants allow anonymous or forged fields';
  end if;

  if pg_catalog.has_function_privilege('anon', 'public.list_pending_suits_for_review()', 'EXECUTE')
    or pg_catalog.has_function_privilege('anon', 'public.review_pending_suit(text,text,text)', 'EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated', 'public.list_pending_suits_for_review()', 'EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated', 'public.review_pending_suit(text,text,text)', 'EXECUTE') then
    raise exception 'DB21_ASSERT: suit review RPC grants are incorrect';
  end if;

  if not pg_catalog.has_table_privilege('service_role', 'public.stages', 'SELECT,INSERT,UPDATE,DELETE')
    or not pg_catalog.has_table_privilege('service_role', 'public.suits', 'SELECT,INSERT,UPDATE,DELETE')
    or not pg_catalog.has_table_privilege('service_role', 'public.pending_suits', 'SELECT,INSERT,UPDATE')
    or pg_catalog.has_table_privilege('service_role', 'public.pending_suits', 'DELETE,TRUNCATE') then
    raise exception 'DB21_ASSERT: service role maintenance grants are incorrect';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'review_pending_suit'
      and p.prosecdef
      and p.proconfig = array['search_path=""']
      and pg_catalog.strpos(pg_catalog.pg_get_functiondef(p.oid), 'pg_advisory_xact_lock') > 0
  ) then
    raise exception 'DB21_ASSERT: review RPC must be privileged, empty-search-path and concurrency locked';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and tablename = 'pending_suits'
      and indexname = 'idx_pending_suits_submitted_by'
      and indexdef like '%(submitted_by)%'
  ) then
    raise exception 'DB21_ASSERT: pending suit ownership lookup lacks a covering index';
  end if;
end;
$$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  ('db210000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'authenticated',
  'authenticated',
  'db21-permissions-' || value || '@example.invalid',
  '',
  pg_catalog.now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  pg_catalog.now(),
  pg_catalog.now()
from pg_catalog.generate_series(1, 4) as fixture(value);

update public.profiles
set
  username = case id
    when 'db210000-0000-4000-8000-000000000001'::uuid then 'DB21普通用户甲'
    when 'db210000-0000-4000-8000-000000000002'::uuid then 'DB21普通用户乙'
    when 'db210000-0000-4000-8000-000000000003'::uuid then 'DB21普通管理员'
    else 'DB21超级管理员'
  end,
  role = case when id = 'db210000-0000-4000-8000-000000000004'::uuid then 'super_admin' else 'user' end,
  role_level = case when id = 'db210000-0000-4000-8000-000000000004'::uuid then 2 else 0 end
where id between 'db210000-0000-4000-8000-000000000001'::uuid
  and 'db210000-0000-4000-8000-000000000004'::uuid;

insert into public.admin_terms (user_id, source, reason, starts_at, scheduled_end_at)
values (
  'db210000-0000-4000-8000-000000000003'::uuid,
  'manual',
  'DB21 fixture ordinary administrator',
  pg_catalog.now() - interval '1 hour',
  pg_catalog.now() + interval '1 day'
);

set local role anon;
select pg_catalog.set_config('request.jwt.claims', '{"role":"anon"}', true);

do $$
declare
  v_denied boolean := false;
begin
  perform pg_catalog.count(*) from public.stages;
  perform pg_catalog.count(*) from public.suits;
  begin
    insert into public.pending_suits (name, submitted_by)
    values ('DB21 fixture 匿名伪造', 'db210000-0000-4000-8000-000000000001'::uuid);
  exception when others then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'DB21_ASSERT: anonymous pending insert was accepted';
  end if;
end;
$$;

reset role;
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db210000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',
  true
);

insert into public.pending_suits (name, submitted_by)
values
  ('DB21 fixture 并发批准套装', 'db210000-0000-4000-8000-000000000001'::uuid),
  ('DB21 fixture 并发批准套装', 'db210000-0000-4000-8000-000000000001'::uuid),
  ('DB21 fixture 驳回套装', 'db210000-0000-4000-8000-000000000001'::uuid);

do $$
declare
  v_denied boolean;
begin
  if (select pg_catalog.count(*) from public.pending_suits) <> 3 then
    raise exception 'DB21_ASSERT: owner cannot read own pending records';
  end if;

  v_denied := false;
  begin
    insert into public.pending_suits (name, submitted_by)
    values ('DB21 fixture 伪造提交人', 'db210000-0000-4000-8000-000000000002'::uuid);
  exception when others then v_denied := true;
  end;
  if not v_denied then raise exception 'DB21_ASSERT: submitted_by forgery was accepted'; end if;

  v_denied := false;
  begin
    insert into public.pending_suits (name, submitted_by, status)
    values ('DB21 fixture 伪造状态', 'db210000-0000-4000-8000-000000000001'::uuid, 'approved');
  exception when others then v_denied := true;
  end;
  if not v_denied then raise exception 'DB21_ASSERT: status forgery was accepted'; end if;

  v_denied := false;
  begin
    insert into public.pending_suits (id, name, submitted_by)
    values ('db210000-0000-4000-8000-000000000099'::uuid, 'DB21 fixture 伪造 ID', 'db210000-0000-4000-8000-000000000001'::uuid);
  exception when others then v_denied := true;
  end;
  if not v_denied then raise exception 'DB21_ASSERT: id forgery was accepted'; end if;

  v_denied := false;
  begin
    insert into public.pending_suits (name, submitted_by, created_at)
    values ('DB21 fixture 伪造时间', 'db210000-0000-4000-8000-000000000001'::uuid, '2000-01-01');
  exception when others then v_denied := true;
  end;
  if not v_denied then raise exception 'DB21_ASSERT: created_at forgery was accepted'; end if;

  v_denied := false;
  begin
    update public.pending_suits set status = 'approved';
  exception when others then v_denied := true;
  end;
  if not v_denied then raise exception 'DB21_ASSERT: authenticated direct update was accepted'; end if;

  v_denied := false;
  begin
    perform public.list_pending_suits_for_review();
  exception when others then v_denied := true;
  end;
  if not v_denied then raise exception 'DB21_ASSERT: ordinary user opened review queue'; end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db210000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}',
  true
);
do $$
begin
  if (select pg_catalog.count(*) from public.pending_suits) <> 0 then
    raise exception 'DB21_ASSERT: another user can read owner pending records';
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db210000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":false}',
  true
);
do $$
declare
  v_result jsonb;
begin
  if (select pg_catalog.count(*) from public.pending_suits) <> 0 then
    raise exception 'DB21_ASSERT: ordinary administrator gained review-table visibility';
  end if;
  v_result := public.review_pending_suit('DB21 fixture 并发批准套装', 'approve');
  if v_result->>'status' <> 'awaiting_cosign'
    or (v_result->>'signature_count')::integer <> 1
    or (v_result->>'required_signatures')::integer <> 2
    or exists (select 1 from public.suits where name = 'DB21 fixture 并发批准套装')
    or exists (
      select 1 from public.pending_suits
      where name = 'DB21 fixture 并发批准套装' and status <> 'pending'
    ) then
    raise exception 'DB21_ASSERT: ordinary administrator suit review did not wait for a second signer: %', v_result;
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db210000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":false}',
  true
);

do $$
declare
  v_first jsonb;
  v_retry jsonb;
  v_reject jsonb;
  v_reject_retry jsonb;
  v_conflict_denied boolean := false;
  v_reverse_conflict_denied boolean := false;
  v_missing_approve_denied boolean := false;
  v_quick_create jsonb;
begin
  if (
    select pg_catalog.count(*)
    from public.list_pending_suits_for_review()
    where name like 'DB21 fixture %'
  ) <> 2 then
    raise exception 'DB21_ASSERT: super administrator review queue is incomplete';
  end if;

  v_first := public.review_pending_suit('DB21 fixture 并发批准套装', 'approve');
  v_retry := public.review_pending_suit('DB21 fixture 并发批准套装', 'approve');
  if (v_first->>'processed_count')::bigint <> 2
    or coalesce((v_first->>'idempotent')::boolean, true)
    or (v_retry->>'processed_count')::bigint <> 0
    or not coalesce((v_retry->>'idempotent')::boolean, false)
    or v_first->>'suit_id' is distinct from v_retry->>'suit_id'
    or (select pg_catalog.count(*) from public.suits where name = 'DB21 fixture 并发批准套装') <> 1 then
    raise exception 'DB21_ASSERT: approval is not atomic and retry-safe';
  end if;

  v_reject := public.review_pending_suit('DB21 fixture 驳回套装', 'reject', 'fixture rejection');
  v_reject_retry := public.review_pending_suit('DB21 fixture 驳回套装', 'reject', 'fixture rejection');
  if (v_reject->>'processed_count')::bigint <> 1
    or coalesce((v_reject->>'idempotent')::boolean, true)
    or (v_reject_retry->>'processed_count')::bigint <> 0
    or not coalesce((v_reject_retry->>'idempotent')::boolean, false)
    or exists (select 1 from public.suits where name = 'DB21 fixture 驳回套装') then
    raise exception 'DB21_ASSERT: rejection is not atomic and retry-safe';
  end if;

  begin
    perform public.review_pending_suit('DB21 fixture 并发批准套装', 'reject', 'fixture conflict');
  exception when others then v_conflict_denied := true;
  end;
  if not v_conflict_denied then
    raise exception 'DB21_ASSERT: completed approval was overwritten by rejection';
  end if;

  begin
    perform public.review_pending_suit('DB21 fixture 驳回套装', 'approve');
  exception when others then v_reverse_conflict_denied := true;
  end;
  if not v_reverse_conflict_denied or exists (select 1 from public.suits where name = 'DB21 fixture 驳回套装') then
    raise exception 'DB21_ASSERT: completed rejection was overwritten by approval';
  end if;

  begin
    perform public.review_pending_suit('DB21 fixture 无待审批准', 'approve');
  exception when others then v_missing_approve_denied := true;
  end;
  if not v_missing_approve_denied then
    raise exception 'DB21_ASSERT: review approval created a suit without pending rows';
  end if;

  v_quick_create := public.review_pending_suit('DB21 fixture 受控秒建', 'create');
  if (v_quick_create->>'processed_count')::bigint <> 0
    or coalesce((v_quick_create->>'idempotent')::boolean, true)
    or (select pg_catalog.count(*) from public.suits where name = 'DB21 fixture 受控秒建') <> 1 then
    raise exception 'DB21_ASSERT: controlled quick creation failed';
  end if;

  if exists (
    select 1 from public.list_pending_suits_for_review()
    where name like 'DB21 fixture %'
  ) then
    raise exception 'DB21_ASSERT: completed rows remained in review queue';
  end if;
end;
$$;

reset role;
set local role service_role;
select pg_catalog.set_config('request.jwt.claims', '{"role":"service_role"}', true);

insert into public.stages (id, name, weights)
overriding system value
values (9223372036854775000, 'DB21 fixture service stage', '{}'::jsonb);
update public.stages set weights = '{"simple":1}'::jsonb where name = 'DB21 fixture service stage';
delete from public.stages where name = 'DB21 fixture service stage';

insert into public.suits (name) values ('DB21 fixture service suit');
update public.suits set description = 'service maintenance' where name = 'DB21 fixture service suit';
delete from public.suits where name = 'DB21 fixture service suit';

insert into public.pending_suits (name, submitted_by, status)
values ('DB21 fixture service pending', 'db210000-0000-4000-8000-000000000001'::uuid, 'pending');
update public.pending_suits set status = 'rejected' where name = 'DB21 fixture service pending';

reset role;

do $$
begin
  if (select pg_catalog.count(*) from public.suits where name like 'DB21 fixture %') <> 2
    or (select pg_catalog.count(*) from public.pending_suits where name like 'DB21 fixture %') <> 4
    or (select pg_catalog.count(*) from public.pending_suits where name = 'DB21 fixture 并发批准套装' and status = 'approved') <> 2
    or (select pg_catalog.count(*) from public.pending_suits where name in ('DB21 fixture 驳回套装', 'DB21 fixture service pending') and status = 'rejected') <> 2 then
    raise exception 'DB21_ASSERT: fixture business assertions did not complete';
  end if;
end;
$$;

rollback;
