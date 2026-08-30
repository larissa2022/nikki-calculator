begin;

-- DB-21 / 社区共治 V2.1 development-only fixture. Every write is rolled back.
-- Run only after scripts/check-dev-link.mjs confirms tfwejruvdahonacyldrg.

do $$
begin
  if exists (
    select 1 from auth.users
    where id between 'db220000-0000-4000-8000-000000000001'::uuid
      and 'db220000-0000-4000-8000-000000000008'::uuid
  ) or exists (
    select 1 from public.pending_suits where name like 'DB21 V2.1 %'
  ) or exists (
    select 1 from public.suits where name like 'DB21 V2.1 %'
  ) then
    raise exception 'DB21_V21_ASSERT: fixture identifiers already exist';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_class
    where oid = 'public.community_admin_actions'::regclass
      and relrowsecurity and relforcerowsecurity
  ) or not exists (
    select 1 from pg_catalog.pg_class
    where oid = 'public.community_admin_action_signatures'::regclass
      and relrowsecurity and relforcerowsecurity
  ) then
    raise exception 'DB21_V21_ASSERT: governance audit tables require RLS and FORCE RLS';
  end if;

  if pg_catalog.has_table_privilege('anon', 'public.community_admin_actions', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
    or pg_catalog.has_table_privilege('authenticated', 'public.community_admin_actions', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
    or pg_catalog.has_table_privilege('service_role', 'public.community_admin_actions', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
    or pg_catalog.has_table_privilege('anon', 'public.community_admin_action_signatures', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
    or pg_catalog.has_table_privilege('authenticated', 'public.community_admin_action_signatures', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
    or pg_catalog.has_table_privilege('service_role', 'public.community_admin_action_signatures', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE') then
    raise exception 'DB21_V21_ASSERT: governance audit tables escaped the RPC boundary';
  end if;

  if pg_catalog.has_function_privilege('anon', 'public.submit_admin_governance_action(text,uuid,uuid,text,timestamptz,timestamptz)', 'EXECUTE')
    or pg_catalog.has_function_privilege('anon', 'public.reopen_rejected_jury_candidate(uuid,text)', 'EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated', 'public.submit_admin_governance_action(text,uuid,uuid,text,timestamptz,timestamptz)', 'EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated', 'public.reopen_rejected_jury_candidate(uuid,text)', 'EXECUTE') then
    raise exception 'DB21_V21_ASSERT: governance RPC grants are incorrect';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname in (
        'review_pending_suit',
        'admin_reject_jury_candidate',
        'reopen_rejected_jury_candidate',
        'submit_admin_governance_action'
      )
      and procedure.prosecdef
      and procedure.proconfig = array['search_path=""']
    group by namespace.nspname
    having pg_catalog.count(*) = 4
  ) then
    raise exception 'DB21_V21_ASSERT: privileged RPCs must use empty search_path';
  end if;
end;
$$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  ('db220000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'authenticated',
  'authenticated',
  'db21-v21-' || value || '@example.invalid',
  '',
  pg_catalog.now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  pg_catalog.now(),
  pg_catalog.now()
from pg_catalog.generate_series(1, 8) as fixture(value);

update public.profiles
set
  username = case id
    when 'db220000-0000-4000-8000-000000000001'::uuid then 'DB21 V2.1 提交者'
    when 'db220000-0000-4000-8000-000000000002'::uuid then 'DB21 V2.1 管理员甲'
    when 'db220000-0000-4000-8000-000000000003'::uuid then 'DB21 V2.1 管理员乙'
    when 'db220000-0000-4000-8000-000000000004'::uuid then 'DB21 V2.1 管理员丙'
    when 'db220000-0000-4000-8000-000000000005'::uuid then 'DB21 V2.1 管理员丁'
    when 'db220000-0000-4000-8000-000000000006'::uuid then 'DB21 V2.1 站长'
    when 'db220000-0000-4000-8000-000000000007'::uuid then 'DB21 V2.1 任期目标'
    else 'DB21 V2.1 纠错候选人'
  end,
  role = case when id = 'db220000-0000-4000-8000-000000000006'::uuid then 'super_admin' else 'user' end,
  role_level = case when id = 'db220000-0000-4000-8000-000000000006'::uuid then 2 else 0 end
where id between 'db220000-0000-4000-8000-000000000001'::uuid
  and 'db220000-0000-4000-8000-000000000008'::uuid;

insert into public.admin_terms (user_id, source, reason, starts_at, scheduled_end_at)
select
  ('db220000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'manual',
  'DB21 V2.1 fixture ordinary administrator',
  pg_catalog.now() - interval '1 hour',
  pg_catalog.now() + interval '1 day'
from pg_catalog.generate_series(2, 5) as fixture(value);

set local role anon;
select pg_catalog.set_config('request.jwt.claims', '{"role":"anon"}', true);

do $$
declare
  v_denied boolean := false;
begin
  perform pg_catalog.count(*) from public.stages;
  perform pg_catalog.count(*) from public.suits;
  begin
    perform public.list_pending_suits_for_review();
  exception when others then v_denied := true;
  end;
  if not v_denied then
    raise exception 'DB21_V21_ASSERT: anonymous user opened suit review queue';
  end if;
end;
$$;

reset role;
set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db220000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',
  true
);

insert into public.pending_suits (name, submitted_by)
values
  ('DB21 V2.1 共签通过', 'db220000-0000-4000-8000-000000000001'::uuid),
  ('DB21 V2.1 共签驳回', 'db220000-0000-4000-8000-000000000001'::uuid);

do $$
declare
  v_denied boolean := false;
begin
  if (select pg_catalog.count(*) from public.pending_suits) <> 2 then
    raise exception 'DB21_V21_ASSERT: owner cannot read own pending suits';
  end if;
  begin
    perform public.review_pending_suit('DB21 V2.1 共签通过', 'approve');
  exception when others then v_denied := true;
  end;
  if not v_denied then
    raise exception 'DB21_V21_ASSERT: ordinary signed-in user reviewed a suit';
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db220000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}',
  true
);

do $$
declare
  v_capabilities jsonb;
  v_first jsonb;
  v_retry jsonb;
  v_conflict_denied boolean := false;
  v_quick_create_denied boolean := false;
begin
  v_capabilities := public.get_current_admin_capabilities();
  if not coalesce((v_capabilities->>'can_review_suits')::boolean, false)
    or not coalesce((v_capabilities->>'can_permanently_reject')::boolean, false)
    or not coalesce((v_capabilities->>'can_manage_admin_terms')::boolean, false)
    or not coalesce((v_capabilities->>'can_review_high_risk')::boolean, false) then
    raise exception 'DB21_V21_ASSERT: ordinary administrator did not receive V2.1 capabilities: %', v_capabilities;
  end if;

  if (select pg_catalog.count(*) from public.list_pending_suits_for_review() where name like 'DB21 V2.1 %') <> 2 then
    raise exception 'DB21_V21_ASSERT: ordinary administrator cannot see suit review queue';
  end if;

  v_first := public.review_pending_suit('DB21 V2.1 共签通过', 'approve');
  v_retry := public.review_pending_suit('DB21 V2.1 共签通过', 'approve');
  if v_first->>'status' <> 'awaiting_cosign'
    or (v_first->>'signature_count')::integer <> 1
    or (v_first->>'required_signatures')::integer <> 2
    or (v_retry->>'signature_count')::integer <> 1
    or exists (select 1 from public.suits where name = 'DB21 V2.1 共签通过')
    or exists (select 1 from public.pending_suits where name = 'DB21 V2.1 共签通过' and status <> 'pending') then
    raise exception 'DB21_V21_ASSERT: first suit signer changed formal state or retry duplicated signature: %, %', v_first, v_retry;
  end if;

  begin
    perform public.review_pending_suit('DB21 V2.1 共签通过', 'reject', '冲突结论');
  exception when others then v_conflict_denied := true;
  end;
  if not v_conflict_denied then
    raise exception 'DB21_V21_ASSERT: signer signed conflicting conclusions for one suit';
  end if;

  begin
    perform public.review_pending_suit('DB21 V2.1 普通管理员极速创建', 'create');
  exception when others then v_quick_create_denied := true;
  end;
  if not v_quick_create_denied then
    raise exception 'DB21_V21_ASSERT: ordinary administrator used owner-only quick create';
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db220000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":false}',
  true
);

do $$
declare
  v_result jsonb;
begin
  v_result := public.review_pending_suit('DB21 V2.1 共签通过', 'approve');
  if v_result->>'status' <> 'executed'
    or (v_result->>'required_signatures')::integer <> 2
    or (v_result->>'processed_count')::integer <> 1
    or (select pg_catalog.count(*) from public.suits where name = 'DB21 V2.1 共签通过') <> 1 then
    raise exception 'DB21_V21_ASSERT: second suit signer did not atomically execute approval: %', v_result;
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db220000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}',
  true
);
select public.review_pending_suit('DB21 V2.1 共签驳回', 'reject', '资料来源不足');

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db220000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":false}',
  true
);

do $$
declare
  v_result jsonb;
begin
  v_result := public.review_pending_suit('DB21 V2.1 共签驳回', 'reject', '资料来源不足');
  if v_result->>'status' <> 'executed'
    or (v_result->>'processed_count')::integer <> 1
    or exists (select 1 from public.suits where name = 'DB21 V2.1 共签驳回') then
    raise exception 'DB21_V21_ASSERT: two-person suit rejection failed: %', v_result;
  end if;
end;
$$;

-- Three distinct ordinary administrators must agree before a governance action executes.
select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db220000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}',
  true
);

do $$
declare
  v_first jsonb;
  v_self_denied boolean := false;
begin
  v_first := public.submit_admin_governance_action(
    'manual_term_create',
    'db220000-0000-4000-8000-000000000007'::uuid,
    null,
    '补充社区值守任期',
    null,
    pg_catalog.now() + interval '2 days'
  );
  if v_first->>'status' <> 'awaiting_cosign'
    or (v_first->>'signature_count')::integer <> 1
    or (v_first->>'required_signatures')::integer <> 3 then
    raise exception 'DB21_V21_ASSERT: first governance signer changed term state: %', v_first;
  end if;

  begin
    perform public.submit_admin_governance_action(
      'manual_term_create',
      'db220000-0000-4000-8000-000000000002'::uuid,
      null,
      '普通管理员尝试处理自己',
      null,
      pg_catalog.now() + interval '2 days'
    );
  exception when others then v_self_denied := true;
  end;
  if not v_self_denied then
    raise exception 'DB21_V21_ASSERT: ordinary administrator governed own term';
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db220000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":false}',
  true
);
select public.submit_admin_governance_action(
  'manual_term_create',
  'db220000-0000-4000-8000-000000000007'::uuid,
  null,
  '补充社区值守任期',
  null,
  pg_catalog.now() + interval '2 days'
);

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db220000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":false}',
  true
);

do $$
declare
  v_result jsonb;
begin
  v_result := public.submit_admin_governance_action(
    'manual_term_create',
    'db220000-0000-4000-8000-000000000007'::uuid,
    null,
    '补充社区值守任期',
    null,
    pg_catalog.now() + interval '2 days'
  );
  if v_result->>'status' <> 'executed'
    or (v_result->>'required_signatures')::integer <> 3 then
    raise exception 'DB21_V21_ASSERT: third governance signer did not execute action: %', v_result;
  end if;
end;
$$;

-- Permanent rejection needs two independent administrators; its signers cannot reopen it.
reset role;
insert into public.clothes (id, name, category, game_id, stars, scores)
values
  ('db21_v21_jury_ordinary', 'DB21 V2.1 普通纠错服装', 'DB21 V2.1 测试', '982201', '5', '{"简约":100}'::jsonb),
  ('db21_v21_jury_owner', 'DB21 V2.1 站长纠错服装', 'DB21 V2.1 测试', '982202', '5', '{"简约":100}'::jsonb);

insert into public.re_review_items (id, reason, status, clothes_id, payload, submitted_by)
values
  (
    'db220000-0000-4000-8000-000000000081'::uuid,
    'correction', 'voting', 'db21_v21_jury_ordinary',
    '{"name":"DB21 V2.1 普通纠错服装"}'::jsonb,
    'db220000-0000-4000-8000-000000000001'::uuid
  ),
  (
    'db220000-0000-4000-8000-000000000082'::uuid,
    'correction', 'rejected', 'db21_v21_jury_owner',
    '{"name":"DB21 V2.1 站长纠错服装"}'::jsonb,
    'db220000-0000-4000-8000-000000000001'::uuid
  );

insert into public.re_review_candidates (id, re_review_item_id, payload, submitted_by, status, resolved_at)
values
  (
    'db220000-0000-4000-8000-000000000091'::uuid,
    'db220000-0000-4000-8000-000000000081'::uuid,
    '{"name":"DB21 V2.1 普通纠错服装"}'::jsonb,
    'db220000-0000-4000-8000-000000000008'::uuid,
    'voting', null
  ),
  (
    'db220000-0000-4000-8000-000000000092'::uuid,
    'db220000-0000-4000-8000-000000000082'::uuid,
    '{"name":"DB21 V2.1 站长纠错服装"}'::jsonb,
    'db220000-0000-4000-8000-000000000008'::uuid,
    'rejected', pg_catalog.now()
  );

insert into public.jury_admin_decisions (
  candidate_id, re_review_item_id, admin_user_id, decision, reason
) values (
  'db220000-0000-4000-8000-000000000092'::uuid,
  'db220000-0000-4000-8000-000000000082'::uuid,
  'db220000-0000-4000-8000-000000000006'::uuid,
  'rejected',
  'DB21 V2.1 fixture prior owner decision'
);

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db220000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}',
  true
);
select public.admin_reject_jury_candidate(
  'db220000-0000-4000-8000-000000000091'::uuid,
  '当前证据无法支持候选修正'
);

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db220000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":false}',
  true
);

do $$
declare
  v_result jsonb;
begin
  v_result := public.admin_reject_jury_candidate(
    'db220000-0000-4000-8000-000000000091'::uuid,
    '当前证据无法支持候选修正'
  );
  if v_result->>'status' <> 'executed' then
    raise exception 'DB21_V21_ASSERT: second permanent-rejection signer did not execute: %', v_result;
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db220000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}',
  true
);

do $$
declare
  v_denied boolean := false;
begin
  begin
    perform public.reopen_rejected_jury_candidate(
      'db220000-0000-4000-8000-000000000091'::uuid,
      '原共签人尝试重新打开'
    );
  exception when others then v_denied := true;
  end;
  if not v_denied then
    raise exception 'DB21_V21_ASSERT: prior rejection signer joined correction';
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db220000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":false}',
  true
);
select public.reopen_rejected_jury_candidate(
  'db220000-0000-4000-8000-000000000091'::uuid,
  '发现新的独立来源，需要重新审理'
);

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db220000-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":false}',
  true
);

do $$
declare
  v_result jsonb;
begin
  v_result := public.reopen_rejected_jury_candidate(
    'db220000-0000-4000-8000-000000000091'::uuid,
    '发现新的独立来源，需要重新审理'
  );
  if v_result->>'status' <> 'executed' then
    raise exception 'DB21_V21_ASSERT: independent correction did not preserve history and reopen item: %', v_result;
  end if;
end;
$$;

-- The site owner keeps solo quick-create, governance and correction powers.
select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db220000-0000-4000-8000-000000000006","role":"authenticated","is_anonymous":false}',
  true
);

do $$
declare
  v_create jsonb;
  v_governance jsonb;
  v_reopen jsonb;
begin
  v_create := public.review_pending_suit('DB21 V2.1 站长极速创建', 'create');
  if v_create->>'status' <> 'executed' then
    raise exception 'DB21_V21_ASSERT: owner quick create failed: %', v_create;
  end if;

  v_governance := public.submit_admin_governance_action(
    'candidate_exclusion_create',
    'db220000-0000-4000-8000-000000000008'::uuid,
    null,
    '站长保留单独治理权',
    pg_catalog.now(),
    pg_catalog.now() + interval '1 day'
  );
  if v_governance->>'status' <> 'executed'
    or (v_governance->>'required_signatures')::integer <> 1 then
    raise exception 'DB21_V21_ASSERT: owner solo governance failed: %', v_governance;
  end if;

  v_reopen := public.reopen_rejected_jury_candidate(
    'db220000-0000-4000-8000-000000000092'::uuid,
    '站长根据新证据纠正既有决定'
  );
  if v_reopen->>'status' <> 'executed'
    or (v_reopen->>'required_signatures')::integer <> 1 then
    raise exception 'DB21_V21_ASSERT: owner solo correction failed: %', v_reopen;
  end if;
end;
$$;

reset role;

do $$
begin
  if (select pg_catalog.count(*) from public.suits where name = 'DB21 V2.1 共签通过') <> 1
    or (select pg_catalog.count(*) from public.suits where name = 'DB21 V2.1 站长极速创建') <> 1
    or exists (select 1 from public.suits where name = 'DB21 V2.1 共签驳回')
    or (select pg_catalog.count(*) from public.pending_suits where name = 'DB21 V2.1 共签通过' and status = 'approved') <> 1
    or (select pg_catalog.count(*) from public.pending_suits where name = 'DB21 V2.1 共签驳回' and status = 'rejected') <> 1
    or (select pg_catalog.count(*) from public.admin_terms where user_id = 'db220000-0000-4000-8000-000000000007'::uuid and status = 'active') <> 1
    or not exists (
      select 1 from public.re_review_items
      where id in (
        'db220000-0000-4000-8000-000000000081'::uuid,
        'db220000-0000-4000-8000-000000000082'::uuid
      ) and status = 'pending' and resolved_by is null and resolved_at is null
      group by status
      having pg_catalog.count(*) = 2
    )
    or not exists (
      select 1 from public.re_review_candidates
      where id = 'db220000-0000-4000-8000-000000000091'::uuid and status = 'rejected'
    )
    or (select pg_catalog.count(*) from public.community_admin_actions where status = 'executed') < 7
    or exists (
      select action.id
      from public.community_admin_actions as action
      left join public.community_admin_action_signatures as signature on signature.action_id = action.id
      group by action.id, action.required_signatures, action.status
      having action.status = 'executed'
        and pg_catalog.count(signature.signer_user_id) < action.required_signatures
    )
    or not exists (
      select 1
      from public.community_admin_actions as correction
      join public.community_admin_actions as original on original.id = correction.corrects_action_id
      where correction.action_type = 'jury_reopen'
        and correction.status = 'executed'
        and original.action_type = 'jury_permanent_reject'
    ) then
    raise exception 'DB21_V21_ASSERT: final governance audit chain is incomplete';
  end if;
end;
$$;

select pg_catalog.jsonb_build_object(
  'status', 'passed',
  'ordinary_suit_threshold', 2,
  'ordinary_governance_threshold', 3,
  'owner_threshold', 1,
  'conflicting_signature_denied', true,
  'self_governance_denied', true,
  'prior_participant_correction_denied', true,
  'history_preserved', true,
  'fixture_rollback_pending', true
) as db21_community_governance_v21_verification;

rollback;
