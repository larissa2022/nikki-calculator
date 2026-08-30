begin;

-- DB-21 / 社区共治 V2.1：普通任期管理员以多人共签处理套装、永久驳回与任期治理；
-- 超级管理员保留单独执行权。所有事实只经受控 RPC 写入，历史不删除。
create table public.community_admin_actions (
  id uuid primary key default extensions.gen_random_uuid(),
  action_type text not null check (action_type in (
    'suit_approve',
    'suit_reject',
    'suit_create',
    'jury_permanent_reject',
    'jury_reopen',
    'manual_term_create',
    'term_end',
    'candidate_exclusion_create',
    'candidate_exclusion_revoke'
  )),
  target_key text not null check (nullif(pg_catalog.btrim(target_key), '') is not null),
  target_user_id uuid references auth.users (id) on delete set null,
  target_record_id uuid,
  proposal_key text not null,
  payload jsonb not null check (
    pg_catalog.jsonb_typeof(payload) = 'object'
    and payload <> '{}'::jsonb
  ),
  reason text not null check (nullif(pg_catalog.btrim(reason), '') is not null),
  required_signatures smallint not null check (required_signatures in (1, 2, 3)),
  status text not null default 'proposed' check (
    status in ('proposed', 'executed', 'superseded', 'cancelled')
  ),
  proposed_by uuid references auth.users (id) on delete set null,
  executed_by uuid references auth.users (id) on delete set null,
  corrects_action_id uuid references public.community_admin_actions (id) on delete restrict,
  result jsonb,
  created_at timestamptz not null default pg_catalog.now(),
  expires_at timestamptz not null default (pg_catalog.now() + interval '7 days'),
  executed_at timestamptz,
  constraint community_admin_actions_period_check check (expires_at > created_at),
  constraint community_admin_actions_execution_check check (
    (status = 'executed' and executed_at is not null and result is not null)
    or (status <> 'executed' and executed_at is null)
  ),
  constraint community_admin_actions_threshold_check check (
    (action_type in ('suit_approve', 'suit_reject', 'jury_permanent_reject', 'jury_reopen') and required_signatures in (1, 2))
    or (action_type in ('manual_term_create', 'term_end', 'candidate_exclusion_create', 'candidate_exclusion_revoke') and required_signatures in (1, 3))
    or (action_type = 'suit_create' and required_signatures = 1)
  )
);

create unique index community_admin_actions_active_proposal_key
  on public.community_admin_actions (action_type, target_key, proposal_key)
  where status = 'proposed';

create index community_admin_actions_target_status_idx
  on public.community_admin_actions (target_key, status, created_at desc);

create index community_admin_actions_target_user_idx
  on public.community_admin_actions (target_user_id)
  where target_user_id is not null;

create index community_admin_actions_target_record_idx
  on public.community_admin_actions (target_record_id)
  where target_record_id is not null;

create index community_admin_actions_proposed_by_idx
  on public.community_admin_actions (proposed_by)
  where proposed_by is not null;

create index community_admin_actions_executed_by_idx
  on public.community_admin_actions (executed_by)
  where executed_by is not null;

create index community_admin_actions_corrects_idx
  on public.community_admin_actions (corrects_action_id)
  where corrects_action_id is not null;

create table public.community_admin_action_signatures (
  action_id uuid not null references public.community_admin_actions (id) on delete restrict,
  signer_user_id uuid not null references auth.users (id) on delete restrict,
  admin_term_id uuid references public.admin_terms (id) on delete restrict,
  signature_source text not null check (signature_source in ('ordinary_admin', 'super_admin')),
  signed_at timestamptz not null default pg_catalog.now(),
  primary key (action_id, signer_user_id),
  constraint community_admin_action_signature_term_check check (
    (signature_source = 'ordinary_admin' and admin_term_id is not null)
    or (signature_source = 'super_admin' and admin_term_id is null)
  )
);

create index community_admin_action_signatures_signer_idx
  on public.community_admin_action_signatures (signer_user_id, signed_at desc);

create index community_admin_action_signatures_term_idx
  on public.community_admin_action_signatures (admin_term_id)
  where admin_term_id is not null;

alter table public.community_admin_actions enable row level security;
alter table public.community_admin_actions force row level security;
alter table public.community_admin_action_signatures enable row level security;
alter table public.community_admin_action_signatures force row level security;

revoke all on table public.community_admin_actions
  from public, anon, authenticated, service_role;
revoke all on table public.community_admin_action_signatures
  from public, anon, authenticated, service_role;

alter table public.jury_admin_decisions
  add column community_action_id uuid references public.community_admin_actions (id) on delete restrict;

create unique index jury_admin_decisions_community_action_key
  on public.jury_admin_decisions (community_action_id)
  where community_action_id is not null;

create function private_db2.sign_community_admin_action(
  p_action_type text,
  p_target_key text,
  p_target_user_id uuid,
  p_target_record_id uuid,
  p_payload jsonb,
  p_reason text,
  p_ordinary_threshold smallint,
  p_corrects_action_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_super boolean := false;
  v_term public.admin_terms%rowtype;
  v_action public.community_admin_actions%rowtype;
  v_proposal_key text;
  v_signature_count integer := 0;
  v_required smallint;
begin
  if coalesce((select auth.jwt())->>'role', '') not in ('authenticated', 'service_role')
    or coalesce((select auth.jwt())->>'is_anonymous', 'false') = 'true'
    or v_actor is null then
    raise exception using errcode = '42501', message = '需要真实登录后才能参与管理员共签';
  end if;

  v_super := public.is_super_admin();
  if not v_super then
    select * into v_term
    from private_db2.current_admin_term(v_actor, pg_catalog.now());
    if v_term.id is null then
      raise exception using errcode = '42501', message = '当前账号没有有效普通管理员任期';
    end if;
    if p_target_user_id is not null and p_target_user_id = v_actor then
      raise exception using errcode = '42501', message = '普通管理员不能处理自己的任期或候选排除';
    end if;
  end if;

  if p_ordinary_threshold not in (2, 3)
    or nullif(pg_catalog.btrim(coalesce(p_target_key, '')), '') is null
    or pg_catalog.jsonb_typeof(p_payload) <> 'object'
    or p_payload = '{}'::jsonb
    or nullif(pg_catalog.btrim(coalesce(p_reason, '')), '') is null then
    raise exception using errcode = '22023', message = '共签事项、目标、内容、原因和门槛必须完整';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('V21:community:' || p_target_key, 0)
  );

  update public.community_admin_actions
  set status = 'cancelled'
  where target_key = p_target_key
    and status = 'proposed'
    and expires_at <= pg_catalog.now();

  v_required := case when v_super then 1 else p_ordinary_threshold end;
  v_proposal_key := pg_catalog.md5(
    p_action_type || E'\n' || p_target_key || E'\n'
    || p_payload::text || E'\n' || pg_catalog.btrim(p_reason)
  );

  select action.* into v_action
  from public.community_admin_actions as action
  where action.action_type = p_action_type
    and action.target_key = p_target_key
    and action.proposal_key = v_proposal_key
    and action.status = 'executed'
  order by action.executed_at desc, action.id
  limit 1;

  if v_action.id is not null then
    return pg_catalog.jsonb_build_object(
      'action_id', v_action.id,
      'already_executed', true,
      'ready', false,
      'is_super_admin', v_super,
      'result', v_action.result
    );
  end if;

  select action.* into v_action
  from public.community_admin_actions as action
  where action.action_type = p_action_type
    and action.target_key = p_target_key
    and action.proposal_key = v_proposal_key
    and action.status = 'proposed'
    and action.expires_at > pg_catalog.now()
  for update;

  if v_action.id is null then
    insert into public.community_admin_actions (
      action_type,
      target_key,
      target_user_id,
      target_record_id,
      proposal_key,
      payload,
      reason,
      required_signatures,
      proposed_by,
      corrects_action_id
    ) values (
      p_action_type,
      p_target_key,
      p_target_user_id,
      p_target_record_id,
      v_proposal_key,
      p_payload,
      pg_catalog.btrim(p_reason),
      v_required,
      v_actor,
      p_corrects_action_id
    ) returning * into v_action;
  elsif v_super and v_action.required_signatures <> 1 then
    update public.community_admin_actions
    set required_signatures = 1
    where id = v_action.id
    returning * into v_action;
  end if;

  if not v_super and exists (
    select 1
    from public.community_admin_action_signatures as signature
    join public.community_admin_actions as other_action
      on other_action.id = signature.action_id
    where signature.signer_user_id = v_actor
      and other_action.target_key = p_target_key
      and other_action.status = 'proposed'
      and other_action.expires_at > pg_catalog.now()
      and other_action.id <> v_action.id
  ) then
    raise exception using errcode = '42501', message = '不能同时共签同一目标的冲突结论';
  end if;

  insert into public.community_admin_action_signatures (
    action_id,
    signer_user_id,
    admin_term_id,
    signature_source
  ) values (
    v_action.id,
    v_actor,
    case when v_super then null else v_term.id end,
    case when v_super then 'super_admin' else 'ordinary_admin' end
  )
  on conflict (action_id, signer_user_id) do update
  set admin_term_id = excluded.admin_term_id,
      signature_source = excluded.signature_source,
      signed_at = pg_catalog.now();

  select pg_catalog.count(*)::integer into v_signature_count
  from public.community_admin_action_signatures as signature
  left join public.admin_terms as term on term.id = signature.admin_term_id
  where signature.action_id = v_action.id
    and (
      signature.signature_source = 'super_admin'
      or (
        signature.signature_source = 'ordinary_admin'
        and term.status = 'active'
        and term.starts_at <= pg_catalog.now()
        and term.scheduled_end_at > pg_catalog.now()
      )
    );

  return pg_catalog.jsonb_build_object(
    'action_id', v_action.id,
    'already_executed', false,
    'ready', v_super or v_signature_count >= v_action.required_signatures,
    'is_super_admin', v_super,
    'actor_id', v_actor,
    'term_id', case when v_super then null else v_term.id end,
    'signature_count', v_signature_count,
    'required_signatures', v_action.required_signatures
  );
end;
$$;

create function private_db2.finish_community_admin_action(
  p_action_id uuid,
  p_result jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_action public.community_admin_actions%rowtype;
begin
  update public.community_admin_actions
  set status = 'executed',
      executed_by = v_actor,
      executed_at = pg_catalog.now(),
      result = p_result
  where id = p_action_id
    and status = 'proposed'
  returning * into v_action;

  if v_action.id is null then
    raise exception using errcode = '40001', message = '共签事项已被其他请求处理，请刷新后重试';
  end if;

  update public.community_admin_actions
  set status = 'superseded'
  where target_key = v_action.target_key
    and status = 'proposed'
    and id <> v_action.id;

  return p_result || pg_catalog.jsonb_build_object(
    'action_id', v_action.id,
    'status', 'executed',
    'required_signatures', v_action.required_signatures
  );
end;
$$;

create or replace function public.get_current_admin_capabilities()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_term public.admin_terms%rowtype;
  v_super boolean;
begin
  if v_user_id is null
    or coalesce((select auth.jwt())->>'is_anonymous', 'false') = 'true' then
    raise exception using errcode = '42501', message = '请先登录';
  end if;

  select exists (
    select 1 from public.profiles as profile
    where profile.id = v_user_id
      and (profile.role_level = 2 or profile.role = 'super_admin')
  ) into v_super;

  select * into v_term from private_db2.current_admin_term(v_user_id);

  return pg_catalog.jsonb_build_object(
    'is_super_admin', v_super,
    'can_review_low_risk', v_super or v_term.id is not null,
    'can_review_suits', v_super or v_term.id is not null,
    'can_permanently_reject', v_super or v_term.id is not null,
    'can_manage_admin_terms', v_super or v_term.id is not null,
    'can_review_high_risk', v_super or v_term.id is not null,
    'term_id', v_term.id,
    'term_source', v_term.source,
    'term_ends_at', v_term.scheduled_end_at,
    'show_grant_notice', v_term.id is not null and v_term.created_at >= pg_catalog.now() - interval '7 days'
  );
end;
$$;

drop function public.list_pending_suits_for_review();

create function public.list_pending_suits_for_review()
returns table (
  name text,
  request_count bigint,
  first_created_at timestamptz,
  approve_signature_count integer,
  reject_signature_count integer,
  approve_reason text,
  reject_reason text,
  my_decision text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
begin
  if coalesce((select auth.jwt())->>'role', '') not in ('authenticated', 'service_role')
    or coalesce((select auth.jwt())->>'is_anonymous', 'false') = 'true'
    or v_actor is null
    or (
      not public.is_super_admin()
      and not private_db2.is_effective_ordinary_admin(v_actor, pg_catalog.now())
    ) then
    raise exception using errcode = '42501', message = '仅当前管理员可查看套装审核队列';
  end if;

  return query
  with pending_names as (
    select
      pending.name,
      pg_catalog.count(*)::bigint as request_count,
      pg_catalog.min(pending.created_at) as first_created_at
    from public.pending_suits as pending
    where pending.status = 'pending'
    group by pending.name
  ), active_actions as (
    select
      action.id,
      action.action_type,
      action.target_key,
      action.reason,
      coalesce((
        select pg_catalog.count(*)::integer
        from public.community_admin_action_signatures as signature
        left join public.admin_terms as term on term.id = signature.admin_term_id
        where signature.action_id = action.id
          and (
            signature.signature_source = 'super_admin'
            or (
              signature.signature_source = 'ordinary_admin'
              and term.status = 'active'
              and term.starts_at <= pg_catalog.now()
              and term.scheduled_end_at > pg_catalog.now()
            )
          )
      ), 0) as signature_count,
      exists (
        select 1
        from public.community_admin_action_signatures as mine
        where mine.action_id = action.id
          and mine.signer_user_id = v_actor
      ) as signed_by_me
    from public.community_admin_actions as action
    where action.status = 'proposed'
      and action.expires_at > pg_catalog.now()
      and action.action_type in ('suit_approve', 'suit_reject')
  )
  select
    pending_name.name,
    pending_name.request_count,
    pending_name.first_created_at,
    coalesce(pg_catalog.max(active.signature_count) filter (
      where active.action_type = 'suit_approve'
    ), 0)::integer as approve_signature_count,
    coalesce(pg_catalog.max(active.signature_count) filter (
      where active.action_type = 'suit_reject'
    ), 0)::integer as reject_signature_count,
    pg_catalog.max(active.reason) filter (
      where active.action_type = 'suit_approve'
    ) as approve_reason,
    pg_catalog.max(active.reason) filter (
      where active.action_type = 'suit_reject'
    ) as reject_reason,
    case
      when pg_catalog.bool_or(active.signed_by_me and active.action_type = 'suit_approve') then 'approve'
      when pg_catalog.bool_or(active.signed_by_me and active.action_type = 'suit_reject') then 'reject'
      else null
    end as my_decision
  from pending_names as pending_name
  left join active_actions as active
    on active.target_key = 'suit:' || pending_name.name
  group by pending_name.name, pending_name.request_count, pending_name.first_created_at
  order by pending_name.request_count desc, pending_name.first_created_at, pending_name.name;
end;
$$;

drop function public.review_pending_suit(text, text);

create function public.review_pending_suit(
  p_name text,
  p_decision text,
  p_reason text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_name text := pg_catalog.btrim(coalesce(p_name, ''));
  v_decision text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_decision, '')));
  v_action_type text;
  v_reason text;
  v_target_key text;
  v_signing jsonb;
  v_payload jsonb;
  v_pending_ids jsonb := '[]'::jsonb;
  v_suit_id uuid;
  v_pending_count bigint := 0;
  v_approved_count bigint := 0;
  v_rejected_count bigint := 0;
  v_processed_count bigint := 0;
  v_suit_existed boolean := false;
  v_result jsonb;
begin
  if v_name = '' then
    raise exception using errcode = '22023', message = '套装名称不能为空';
  end if;
  if v_decision not in ('approve', 'reject', 'create') then
    raise exception using errcode = '22023', message = '套装操作必须是 approve、reject 或 create';
  end if;
  if v_decision = 'create' and not public.is_super_admin() then
    raise exception using errcode = '42501', message = '无待审来源的极速创建仅保留给站长';
  end if;

  v_target_key := 'suit:' || v_name;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('V21:community:' || v_target_key, 0)
  );

  select
    pg_catalog.count(*) filter (where pending.status = 'pending'),
    pg_catalog.count(*) filter (where pending.status = 'approved'),
    pg_catalog.count(*) filter (where pending.status = 'rejected'),
    coalesce(
      pg_catalog.jsonb_agg(pg_catalog.to_jsonb(pending.id) order by pending.id)
        filter (where pending.status = 'pending'),
      '[]'::jsonb
    )
  into v_pending_count, v_approved_count, v_rejected_count, v_pending_ids
  from public.pending_suits as pending
  where pending.name = v_name;

  select suit.id into v_suit_id
  from public.suits as suit
  where suit.name = v_name;
  v_suit_existed := found;

  if v_decision = 'approve' and v_pending_count = 0 then
    if v_approved_count > 0 and v_suit_id is not null then
      return pg_catalog.jsonb_build_object(
        'name', v_name,
        'decision', 'approved',
        'suit_id', v_suit_id,
        'processed_count', 0,
        'idempotent', true,
        'status', 'executed'
      );
    end if;
    if v_rejected_count > 0 then
      raise exception using errcode = '40001', message = '该名称已有驳回记录，请先由用户重新提交后再审核';
    end if;
    raise exception using errcode = 'P0002', message = '没有可批准的待审核套装申请';
  end if;

  if v_decision = 'reject' and v_pending_count = 0 then
    if v_rejected_count > 0 and v_approved_count = 0 then
      return pg_catalog.jsonb_build_object(
        'name', v_name,
        'decision', 'rejected',
        'suit_id', null,
        'processed_count', 0,
        'idempotent', true,
        'status', 'executed'
      );
    end if;
    if v_approved_count > 0 then
      raise exception using errcode = '40001', message = '该套装申请已批准，不能直接改为驳回；请发起纠错';
    end if;
    raise exception using errcode = 'P0002', message = '没有可驳回的待审核套装申请';
  end if;

  if v_decision = 'create' and v_pending_count = 0
    and (v_approved_count > 0 or v_rejected_count > 0) then
    raise exception using errcode = '40001', message = '该名称已有审核历史，不能使用极速创建';
  end if;

  v_action_type := case v_decision
    when 'approve' then 'suit_approve'
    when 'reject' then 'suit_reject'
    else 'suit_create'
  end;

  v_reason := nullif(pg_catalog.btrim(coalesce(p_reason, '')), '');
  if v_reason is null and v_decision = 'reject' then
    select action.reason into v_reason
    from public.community_admin_actions as action
    where action.action_type = 'suit_reject'
      and action.target_key = v_target_key
      and action.status = 'proposed'
      and action.expires_at > pg_catalog.now()
    order by action.created_at, action.id
    limit 1;
  end if;
  if v_reason is null then
    v_reason := case v_decision
      when 'approve' then '确认套装申请符合正式入库条件'
      when 'create' then '站长在服装仲裁中受控创建正式套装'
      else null
    end;
  end if;
  if v_reason is null then
    raise exception using errcode = '22023', message = '驳回套装必须填写原因';
  end if;

  v_payload := pg_catalog.jsonb_build_object(
    'name', v_name,
    'decision', v_decision,
    'pending_ids', v_pending_ids
  );

  v_signing := private_db2.sign_community_admin_action(
    v_action_type,
    v_target_key,
    null::uuid,
    null::uuid,
    v_payload,
    v_reason,
    2::smallint,
    null::uuid
  );

  if coalesce((v_signing->>'already_executed')::boolean, false) then
    return coalesce(v_signing->'result', '{}'::jsonb)
      || pg_catalog.jsonb_build_object('idempotent', true);
  end if;

  if not coalesce((v_signing->>'ready')::boolean, false) then
    return pg_catalog.jsonb_build_object(
      'name', v_name,
      'decision', v_decision,
      'status', 'awaiting_cosign',
      'action_id', v_signing->>'action_id',
      'signature_count', (v_signing->>'signature_count')::integer,
      'required_signatures', (v_signing->>'required_signatures')::integer,
      'idempotent', false
    );
  end if;

  if v_decision in ('approve', 'create') then
    if v_suit_id is null then
      insert into public.suits (name)
      values (v_name)
      on conflict (name) do nothing
      returning id into v_suit_id;

      if v_suit_id is null then
        select suit.id into strict v_suit_id
        from public.suits as suit
        where suit.name = v_name;
      end if;
    end if;

    update public.pending_suits
    set status = 'approved'
    where name = v_name and status = 'pending';
    get diagnostics v_processed_count = row_count;

    v_result := pg_catalog.jsonb_build_object(
      'name', v_name,
      'decision', 'approved',
      'suit_id', v_suit_id,
      'processed_count', v_processed_count,
      'idempotent', v_suit_existed and v_processed_count = 0
    );
  else
    update public.pending_suits
    set status = 'rejected'
    where name = v_name and status = 'pending';
    get diagnostics v_processed_count = row_count;

    if v_processed_count = 0 then
      raise exception using errcode = '40001', message = '套装申请状态已变化，请刷新后重试';
    end if;

    v_result := pg_catalog.jsonb_build_object(
      'name', v_name,
      'decision', 'rejected',
      'suit_id', null,
      'processed_count', v_processed_count,
      'idempotent', false
    );
  end if;

  return private_db2.finish_community_admin_action(
    (v_signing->>'action_id')::uuid,
    v_result
  );
end;
$$;

create or replace function public.admin_reject_jury_candidate(
  p_candidate_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_super boolean := public.is_super_admin();
  v_candidate public.re_review_candidates%rowtype;
  v_item public.re_review_items%rowtype;
  v_existing_decision public.jury_admin_decisions%rowtype;
  v_reason text := nullif(pg_catalog.btrim(coalesce(p_reason, '')), '');
  v_target_key text := 'jury:' || coalesce(p_candidate_id::text, '');
  v_signing jsonb;
  v_result jsonb;
begin
  if v_actor is null
    or coalesce((select auth.jwt())->>'is_anonymous', 'false') = 'true' then
    raise exception using errcode = '42501', message = '需要登录后才能执行管理员终审';
  end if;
  if v_reason is null then
    raise exception using errcode = '22023', message = '永久驳回必须填写终审理由';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('V21:community:' || v_target_key, 0)
  );

  select decision.* into v_existing_decision
  from public.jury_admin_decisions as decision
  where decision.candidate_id = p_candidate_id;

  if v_existing_decision.id is not null then
    return pg_catalog.jsonb_build_object(
      'candidate_id', v_existing_decision.candidate_id,
      're_review_item_id', v_existing_decision.re_review_item_id,
      'status', 'rejected',
      'idempotent', true,
      'action_id', v_existing_decision.community_action_id
    );
  end if;

  select candidate.* into v_candidate
  from public.re_review_candidates as candidate
  where candidate.id = p_candidate_id
  for update;

  if v_candidate.id is null or v_candidate.status not in ('voting', 'returned') then
    raise exception using errcode = '55000', message = '待审核内容不存在或当前不能永久驳回';
  end if;

  select item.* into v_item
  from public.re_review_items as item
  where item.id = v_candidate.re_review_item_id
  for update;

  if v_item.id is null or v_item.status not in ('pending', 'voting', 'failed')
    or (v_candidate.status = 'voting' and v_item.status <> 'voting')
    or (v_candidate.status = 'returned' and v_item.status not in ('pending', 'failed'))
    or exists (
      select 1
      from public.re_review_candidates as active_candidate
      where active_candidate.re_review_item_id = v_item.id
        and active_candidate.status = 'voting'
        and active_candidate.id <> v_candidate.id
    ) then
    raise exception using errcode = '55000', message = '该内容已不是当前可终审轮次';
  end if;

  if not v_super and (
    v_candidate.submitted_by is not distinct from v_actor
    or v_item.submitted_by is not distinct from v_actor
    or exists (
      select 1 from public.pending_clothes as primary_source
      where primary_source.id = v_item.source_pending_id
        and primary_source.submitted_by = v_actor
    )
    or exists (
      select 1 from public.re_review_item_sources as source
      where source.re_review_item_id = v_item.id
        and source.source_user_id = v_actor
    )
    or exists (
      select 1 from public.jury_votes as vote
      where vote.candidate_id = v_candidate.id
        and vote.user_id = v_actor
    )
  ) then
    raise exception using errcode = '42501', message = '普通管理员不能终审自己提交、参与或投票过的数据';
  end if;

  v_signing := private_db2.sign_community_admin_action(
    'jury_permanent_reject',
    v_target_key,
    null::uuid,
    v_candidate.id,
    pg_catalog.jsonb_build_object(
      'candidate_id', v_candidate.id,
      're_review_item_id', v_item.id,
      'decision', 'rejected'
    ),
    v_reason,
    2::smallint,
    null::uuid
  );

  if coalesce((v_signing->>'already_executed')::boolean, false) then
    return coalesce(v_signing->'result', '{}'::jsonb)
      || pg_catalog.jsonb_build_object('idempotent', true);
  end if;

  if not coalesce((v_signing->>'ready')::boolean, false) then
    return pg_catalog.jsonb_build_object(
      'candidate_id', v_candidate.id,
      're_review_item_id', v_item.id,
      'status', 'awaiting_cosign',
      'action_id', v_signing->>'action_id',
      'signature_count', (v_signing->>'signature_count')::integer,
      'required_signatures', (v_signing->>'required_signatures')::integer,
      'idempotent', false
    );
  end if;

  if exists (
    select 1
    from public.community_admin_action_signatures as signature
    join public.community_admin_actions as action on action.id = signature.action_id
    where action.id = (v_signing->>'action_id')::uuid
      and signature.signature_source = 'ordinary_admin'
      and (
        v_candidate.submitted_by is not distinct from signature.signer_user_id
        or v_item.submitted_by is not distinct from signature.signer_user_id
        or exists (
          select 1 from public.pending_clothes as primary_source
          where primary_source.id = v_item.source_pending_id
            and primary_source.submitted_by = signature.signer_user_id
        )
        or exists (
          select 1 from public.re_review_item_sources as source
          where source.re_review_item_id = v_item.id
            and source.source_user_id = signature.signer_user_id
        )
        or exists (
          select 1 from public.jury_votes as vote
          where vote.candidate_id = v_candidate.id
            and vote.user_id = signature.signer_user_id
        )
      )
  ) then
    raise exception using errcode = '42501', message = '共签人中存在提交者、来源参与者或原投票者，不能执行永久驳回';
  end if;

  insert into public.jury_admin_decisions (
    candidate_id,
    re_review_item_id,
    admin_user_id,
    decision,
    reason,
    community_action_id
  ) values (
    v_candidate.id,
    v_item.id,
    v_actor,
    'rejected',
    v_reason,
    (v_signing->>'action_id')::uuid
  );

  update public.re_review_candidates
  set status = 'rejected', resolved_at = pg_catalog.now()
  where id = v_candidate.id;

  update public.re_review_items
  set status = 'rejected',
      resolved_by = v_actor,
      resolved_at = pg_catalog.now(),
      updated_at = pg_catalog.now()
  where id = v_item.id;

  v_result := pg_catalog.jsonb_build_object(
    'candidate_id', v_candidate.id,
    're_review_item_id', v_item.id,
    'status', 'rejected',
    'idempotent', false
  );

  return private_db2.finish_community_admin_action(
    (v_signing->>'action_id')::uuid,
    v_result
  );
end;
$$;

create function public.reopen_rejected_jury_candidate(
  p_candidate_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_super boolean := public.is_super_admin();
  v_candidate public.re_review_candidates%rowtype;
  v_item public.re_review_items%rowtype;
  v_decision public.jury_admin_decisions%rowtype;
  v_reason text := nullif(pg_catalog.btrim(coalesce(p_reason, '')), '');
  v_target_key text := 'jury:' || coalesce(p_candidate_id::text, '');
  v_signing jsonb;
  v_result jsonb;
begin
  if v_actor is null
    or coalesce((select auth.jwt())->>'is_anonymous', 'false') = 'true' then
    raise exception using errcode = '42501', message = '需要登录后才能发起纠错';
  end if;
  if v_reason is null then
    raise exception using errcode = '22023', message = '纠错必须填写新证据或重新审理原因';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('V21:community:' || v_target_key, 0)
  );

  select candidate.* into v_candidate
  from public.re_review_candidates as candidate
  where candidate.id = p_candidate_id
  for update;

  if v_candidate.id is null or v_candidate.status <> 'rejected' then
    raise exception using errcode = '55000', message = '只有已永久驳回的候选可以重新进入审理';
  end if;

  select item.* into v_item
  from public.re_review_items as item
  where item.id = v_candidate.re_review_item_id
  for update;

  if v_item.id is null or v_item.status <> 'rejected' then
    raise exception using errcode = '55000', message = '该审核事项当前不能重新打开';
  end if;

  select decision.* into v_decision
  from public.jury_admin_decisions as decision
  where decision.candidate_id = v_candidate.id;

  if not v_super and (
    v_candidate.submitted_by is not distinct from v_actor
    or v_item.submitted_by is not distinct from v_actor
    or exists (
      select 1 from public.re_review_item_sources as source
      where source.re_review_item_id = v_item.id
        and source.source_user_id = v_actor
    )
    or exists (
      select 1 from public.jury_votes as vote
      where vote.candidate_id = v_candidate.id
        and vote.user_id = v_actor
    )
    or exists (
      select 1
      from public.community_admin_action_signatures as signature
      join public.community_admin_actions as action on action.id = signature.action_id
      where action.target_record_id = v_candidate.id
        and action.action_type = 'jury_permanent_reject'
        and signature.signer_user_id = v_actor
    )
  ) then
    raise exception using errcode = '42501', message = '原提交者、来源参与者、共签者或原轮次投票者不能参与本次纠错';
  end if;

  v_signing := private_db2.sign_community_admin_action(
    'jury_reopen',
    v_target_key,
    null::uuid,
    v_candidate.id,
    pg_catalog.jsonb_build_object(
      'candidate_id', v_candidate.id,
      're_review_item_id', v_item.id,
      'decision', 'reopen'
    ),
    v_reason,
    2::smallint,
    v_decision.community_action_id
  );

  if coalesce((v_signing->>'already_executed')::boolean, false) then
    return coalesce(v_signing->'result', '{}'::jsonb)
      || pg_catalog.jsonb_build_object('idempotent', true);
  end if;

  if not coalesce((v_signing->>'ready')::boolean, false) then
    return pg_catalog.jsonb_build_object(
      'candidate_id', v_candidate.id,
      're_review_item_id', v_item.id,
      'status', 'awaiting_cosign',
      'action_id', v_signing->>'action_id',
      'signature_count', (v_signing->>'signature_count')::integer,
      'required_signatures', (v_signing->>'required_signatures')::integer,
      'idempotent', false
    );
  end if;

  update public.re_review_items
  set status = 'pending',
      resolved_by = null,
      resolved_at = null,
      updated_at = pg_catalog.now()
  where id = v_item.id and status = 'rejected';

  if not found then
    raise exception using errcode = '40001', message = '审核事项状态已变化，请刷新后重试';
  end if;

  v_result := pg_catalog.jsonb_build_object(
    'candidate_id', v_candidate.id,
    're_review_item_id', v_item.id,
    'status', 'pending',
    'idempotent', false
  );

  return private_db2.finish_community_admin_action(
    (v_signing->>'action_id')::uuid,
    v_result
  );
end;
$$;

create function public.list_rejected_jury_items_for_reopen()
returns table (
  candidate_id uuid,
  re_review_item_id uuid,
  clothes_name text,
  rejected_reason text,
  rejected_at timestamptz,
  can_reopen boolean,
  reopen_signature_count integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_super boolean := public.is_super_admin();
begin
  if v_actor is null
    or coalesce((select auth.jwt())->>'is_anonymous', 'false') = 'true'
    or (
      not v_super
      and not private_db2.is_effective_ordinary_admin(v_actor, pg_catalog.now())
    ) then
    raise exception using errcode = '42501', message = '仅当前管理员可查看纠错队列';
  end if;

  return query
  select
    candidate.id,
    item.id,
    coalesce(clothes.name, item.payload->>'name', candidate.payload->>'name', '未命名服装'),
    decision.reason,
    decision.created_at,
    v_super or not (
      candidate.submitted_by is not distinct from v_actor
      or item.submitted_by is not distinct from v_actor
      or exists (
        select 1 from public.re_review_item_sources as source
        where source.re_review_item_id = item.id
          and source.source_user_id = v_actor
      )
      or exists (
        select 1 from public.jury_votes as vote
        where vote.candidate_id = candidate.id
          and vote.user_id = v_actor
      )
      or exists (
        select 1
        from public.community_admin_action_signatures as signature
        join public.community_admin_actions as action on action.id = signature.action_id
        where action.target_record_id = candidate.id
          and action.action_type = 'jury_permanent_reject'
          and signature.signer_user_id = v_actor
      )
    ),
    coalesce((
      select pg_catalog.count(*)::integer
      from public.community_admin_actions as action
      join public.community_admin_action_signatures as signature on signature.action_id = action.id
      join public.admin_terms as term on term.id = signature.admin_term_id
      where action.action_type = 'jury_reopen'
        and action.target_record_id = candidate.id
        and action.status = 'proposed'
        and action.expires_at > pg_catalog.now()
        and term.status = 'active'
        and term.starts_at <= pg_catalog.now()
        and term.scheduled_end_at > pg_catalog.now()
    ), 0)::integer
  from public.jury_admin_decisions as decision
  join public.re_review_candidates as candidate on candidate.id = decision.candidate_id
  join public.re_review_items as item on item.id = decision.re_review_item_id
  left join public.clothes as clothes on clothes.id = item.clothes_id
  where candidate.status = 'rejected'
    and item.status = 'rejected'
  order by decision.created_at desc, candidate.id;
end;
$$;

create function private_db2.enforce_v21_candidate_reentry_eligibility()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.submitted_by is null then
    return new;
  end if;

  if exists (
    select 1
    from public.re_review_candidates as prior
    where prior.re_review_item_id = new.re_review_item_id
      and prior.id <> new.id
      and (
        prior.submitted_by = new.submitted_by
        or exists (
          select 1 from public.jury_votes as vote
          where vote.candidate_id = prior.id
            and vote.user_id = new.submitted_by
        )
        or exists (
          select 1
          from public.community_admin_actions as action
          join public.community_admin_action_signatures as signature on signature.action_id = action.id
          where action.target_record_id = prior.id
            and action.action_type in ('jury_permanent_reject', 'jury_reopen')
            and signature.signer_user_id = new.submitted_by
        )
      )
  ) then
    raise exception using errcode = '42501', message = '原候选提交者、共签者或原轮次投票者不能提交纠错后的新候选';
  end if;

  return new;
end;
$$;

create trigger enforce_v21_candidate_reentry_eligibility
before insert on public.re_review_candidates
for each row execute function private_db2.enforce_v21_candidate_reentry_eligibility();

create function private_db2.enforce_v21_jury_vote_reentry_eligibility()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item_id uuid;
begin
  select candidate.re_review_item_id into v_item_id
  from public.re_review_candidates as candidate
  where candidate.id = new.candidate_id;

  if exists (
    select 1
    from public.re_review_candidates as prior
    where prior.re_review_item_id = v_item_id
      and prior.id <> new.candidate_id
      and (
        prior.submitted_by = new.user_id
        or exists (
          select 1 from public.jury_votes as prior_vote
          where prior_vote.candidate_id = prior.id
            and prior_vote.user_id = new.user_id
        )
        or exists (
          select 1
          from public.community_admin_actions as action
          join public.community_admin_action_signatures as signature on signature.action_id = action.id
          where action.target_record_id = prior.id
            and action.action_type in ('jury_permanent_reject', 'jury_reopen')
            and signature.signer_user_id = new.user_id
        )
      )
  ) then
    raise exception using errcode = '42501', message = '原候选提交者、共签者或原轮次投票者不能参与纠错后的新一轮投票';
  end if;

  return new;
end;
$$;

create trigger enforce_v21_jury_vote_reentry_eligibility
before insert on public.jury_votes
for each row execute function private_db2.enforce_v21_jury_vote_reentry_eligibility();

create function public.submit_admin_governance_action(
  p_action_type text,
  p_target_user_id uuid default null,
  p_target_record_id uuid default null,
  p_reason text default null,
  p_starts_at timestamptz default null,
  p_ends_at timestamptz default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_action_type text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_action_type, '')));
  v_reason text := nullif(pg_catalog.btrim(coalesce(p_reason, '')), '');
  v_target_key text;
  v_target_user_id uuid := p_target_user_id;
  v_target_record_id uuid := p_target_record_id;
  v_payload jsonb;
  v_signing jsonb;
  v_result jsonb;
  v_now timestamptz := pg_catalog.now();
  v_term public.admin_terms%rowtype;
  v_current public.admin_terms%rowtype;
  v_exclusion public.admin_candidate_exclusions%rowtype;
  v_new_id uuid;
begin
  if v_actor is null
    or coalesce((select auth.jwt())->>'is_anonymous', 'false') = 'true' then
    raise exception using errcode = '42501', message = '需要登录后才能参与管理员治理';
  end if;
  if v_reason is null then
    raise exception using errcode = '22023', message = '管理员治理事项必须填写原因';
  end if;
  if v_action_type not in (
    'manual_term_create',
    'term_end',
    'candidate_exclusion_create',
    'candidate_exclusion_revoke'
  ) then
    raise exception using errcode = '22023', message = '不支持的管理员治理动作';
  end if;

  if v_action_type = 'manual_term_create' then
    if v_target_user_id is null then
      raise exception using errcode = '22023', message = '手动任期必须选择目标用户';
    end if;
    if p_ends_at is null or p_ends_at <= v_now or p_ends_at > v_now + interval '31 days' then
      raise exception using errcode = '22023', message = '手动任期结束时间必须在未来 31 天内';
    end if;
    if exists (
      select 1 from public.profiles as profile
      where profile.id = v_target_user_id
        and (profile.role_level = 2 or profile.role = 'super_admin')
    ) then
      raise exception using errcode = '22023', message = '超级管理员不需要普通管理员任期';
    end if;
    select * into v_current
    from private_db2.current_admin_term(v_target_user_id, v_now);
    if v_current.source in ('manual', 'legacy_transition') then
      raise exception using errcode = '23505', message = '该用户已有有效手动或过渡任期';
    end if;
    v_target_key := 'term-user:' || v_target_user_id::text;
    v_payload := pg_catalog.jsonb_build_object(
      'action', v_action_type,
      'target_user_id', v_target_user_id,
      'ends_at', p_ends_at
    );
  elsif v_action_type = 'term_end' then
    if v_target_record_id is null then
      raise exception using errcode = '22023', message = '提前结束任期必须选择目标任期';
    end if;
    select * into v_term
    from public.admin_terms as term
    where term.id = v_target_record_id
      and term.status = 'active'
      and term.scheduled_end_at > v_now
    for update;
    if v_term.id is null then
      raise exception using errcode = 'P0002', message = '目标任期不存在或已经结束';
    end if;
    v_target_user_id := v_term.user_id;
    v_target_key := 'term:' || v_term.id::text;
    v_payload := pg_catalog.jsonb_build_object(
      'action', v_action_type,
      'term_id', v_term.id,
      'target_user_id', v_term.user_id,
      'scheduled_end_at', v_term.scheduled_end_at
    );
  elsif v_action_type = 'candidate_exclusion_create' then
    if v_target_user_id is null or p_starts_at is null or p_ends_at is null
      or p_ends_at <= p_starts_at or p_ends_at <= v_now then
      raise exception using errcode = '22023', message = '候选排除的用户、原因和有效期必须完整，结束时间必须晚于当前时间';
    end if;
    if exists (
      select 1 from public.profiles as profile
      where profile.id = v_target_user_id
        and (profile.role_level = 2 or profile.role = 'super_admin')
    ) then
      raise exception using errcode = '42501', message = '普通管理员治理不能排除超级管理员';
    end if;
    v_target_key := 'exclusion-user:' || v_target_user_id::text;
    v_payload := pg_catalog.jsonb_build_object(
      'action', v_action_type,
      'target_user_id', v_target_user_id,
      'starts_at', p_starts_at,
      'ends_at', p_ends_at
    );
  else
    if v_target_record_id is null then
      raise exception using errcode = '22023', message = '撤销候选排除必须选择目标记录';
    end if;
    select * into v_exclusion
    from public.admin_candidate_exclusions as exclusion
    where exclusion.id = v_target_record_id
      and exclusion.revoked_at is null
      and exclusion.ends_at > v_now
    for update;
    if v_exclusion.id is null then
      raise exception using errcode = 'P0002', message = '候选排除不存在、已撤销或已过期';
    end if;
    v_target_user_id := v_exclusion.user_id;
    v_target_key := 'exclusion:' || v_exclusion.id::text;
    v_payload := pg_catalog.jsonb_build_object(
      'action', v_action_type,
      'exclusion_id', v_exclusion.id,
      'target_user_id', v_exclusion.user_id,
      'ends_at', v_exclusion.ends_at
    );
  end if;

  v_signing := private_db2.sign_community_admin_action(
    v_action_type,
    v_target_key,
    v_target_user_id,
    v_target_record_id,
    v_payload,
    v_reason,
    3::smallint,
    null::uuid
  );

  if coalesce((v_signing->>'already_executed')::boolean, false) then
    return coalesce(v_signing->'result', '{}'::jsonb)
      || pg_catalog.jsonb_build_object('idempotent', true);
  end if;

  if not coalesce((v_signing->>'ready')::boolean, false) then
    return pg_catalog.jsonb_build_object(
      'action_type', v_action_type,
      'status', 'awaiting_cosign',
      'action_id', v_signing->>'action_id',
      'signature_count', (v_signing->>'signature_count')::integer,
      'required_signatures', (v_signing->>'required_signatures')::integer,
      'idempotent', false
    );
  end if;

  if v_action_type = 'manual_term_create' then
    select * into v_current
    from private_db2.current_admin_term(v_target_user_id, v_now);
    if v_current.source in ('manual', 'legacy_transition') then
      raise exception using errcode = '23505', message = '该用户已有有效手动或过渡任期';
    end if;
    if v_current.source = 'monthly' then
      update public.admin_terms
      set status = 'revoked',
          ended_at = v_now,
          ended_by = v_actor,
          end_reason = '社区共签转为独立手动任期：' || v_reason
      where id = v_current.id;
    end if;

    insert into public.admin_terms (
      user_id,
      source,
      reason,
      starts_at,
      scheduled_end_at,
      granted_by
    ) values (
      v_target_user_id,
      'manual',
      v_reason,
      v_now,
      p_ends_at,
      v_actor
    ) returning id into v_new_id;

    if v_current.source = 'monthly' then
      perform private_db2.fill_monthly_admin_vacancies(v_current.service_month);
    end if;
    v_result := pg_catalog.jsonb_build_object(
      'action_type', v_action_type,
      'term_id', v_new_id,
      'target_user_id', v_target_user_id,
      'status', 'executed',
      'idempotent', false
    );
  elsif v_action_type = 'term_end' then
    update public.admin_terms
    set status = 'revoked',
        ended_at = v_now,
        ended_by = v_actor,
        end_reason = v_reason
    where id = v_term.id
      and status = 'active'
      and scheduled_end_at > v_now;
    if not found then
      raise exception using errcode = '40001', message = '目标任期状态已变化，请刷新后重试';
    end if;
    if v_term.source = 'monthly' then
      perform private_db2.fill_monthly_admin_vacancies(v_term.service_month);
    end if;
    v_result := pg_catalog.jsonb_build_object(
      'action_type', v_action_type,
      'term_id', v_term.id,
      'target_user_id', v_term.user_id,
      'status', 'executed',
      'idempotent', false
    );
  elsif v_action_type = 'candidate_exclusion_create' then
    insert into public.admin_candidate_exclusions (
      user_id,
      reason,
      starts_at,
      ends_at,
      created_by
    ) values (
      v_target_user_id,
      v_reason,
      p_starts_at,
      p_ends_at,
      v_actor
    ) returning id into v_new_id;

    select * into v_current
    from private_db2.current_admin_term(v_target_user_id, v_now);
    if v_current.source = 'monthly' then
      update public.admin_terms
      set status = 'revoked',
          ended_at = v_now,
          ended_by = v_actor,
          end_reason = '社区共签新增候选排除：' || v_reason
      where id = v_current.id;
      perform private_db2.fill_monthly_admin_vacancies(v_current.service_month);
    end if;
    v_result := pg_catalog.jsonb_build_object(
      'action_type', v_action_type,
      'exclusion_id', v_new_id,
      'target_user_id', v_target_user_id,
      'status', 'executed',
      'idempotent', false
    );
  else
    update public.admin_candidate_exclusions
    set revoked_at = v_now,
        revoked_by = v_actor
    where id = v_exclusion.id
      and revoked_at is null
      and ends_at > v_now;
    if not found then
      raise exception using errcode = '40001', message = '候选排除状态已变化，请刷新后重试';
    end if;
    v_result := pg_catalog.jsonb_build_object(
      'action_type', v_action_type,
      'exclusion_id', v_exclusion.id,
      'target_user_id', v_exclusion.user_id,
      'status', 'executed',
      'idempotent', false
    );
  end if;

  return private_db2.finish_community_admin_action(
    (v_signing->>'action_id')::uuid,
    v_result
  );
end;
$$;

create or replace function public.list_admin_governance()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_result jsonb;
begin
  if v_actor is null
    or coalesce((select auth.jwt())->>'is_anonymous', 'false') = 'true'
    or (
      not public.is_super_admin()
      and not private_db2.is_effective_ordinary_admin(v_actor, pg_catalog.now())
    ) then
    raise exception using errcode = '42501', message = '仅当前管理员可查看任期治理';
  end if;

  select pg_catalog.jsonb_build_object(
    'users', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', profile.id,
        'display_name', coalesce(
          nullif(pg_catalog.btrim(profile.username), ''),
          nullif(pg_catalog.btrim(profile.nickname), ''),
          '未命名用户'
        )
      ) order by coalesce(profile.username, profile.nickname, ''), profile.id)
      from public.profiles as profile
      where not (profile.role_level = 2 or profile.role = 'super_admin')
    ), '[]'::jsonb),
    'terms', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', term.id,
        'user_id', term.user_id,
        'display_name', coalesce(nullif(pg_catalog.btrim(profile.username), ''), nullif(pg_catalog.btrim(profile.nickname), ''), '未命名用户'),
        'source', term.source,
        'service_month', term.service_month,
        'starts_at', term.starts_at,
        'scheduled_end_at', term.scheduled_end_at,
        'status', term.status,
        'reason', term.reason,
        'end_reason', term.end_reason,
        'created_at', term.created_at
      ) order by term.created_at desc)
      from public.admin_terms as term
      left join public.profiles as profile on profile.id = term.user_id
    ), '[]'::jsonb),
    'exclusions', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', exclusion.id,
        'user_id', exclusion.user_id,
        'display_name', coalesce(nullif(pg_catalog.btrim(profile.username), ''), nullif(pg_catalog.btrim(profile.nickname), ''), '未命名用户'),
        'reason', exclusion.reason,
        'starts_at', exclusion.starts_at,
        'ends_at', exclusion.ends_at,
        'revoked_at', exclusion.revoked_at
      ) order by exclusion.created_at desc)
      from public.admin_candidate_exclusions as exclusion
      left join public.profiles as profile on profile.id = exclusion.user_id
    ), '[]'::jsonb),
    'candidates', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'service_month', candidate.service_month,
        'candidate_order', candidate.candidate_order,
        'frozen_points', candidate.frozen_points,
        'qualifying_action_count', candidate.qualifying_action_count,
        'level_at_snapshot', candidate.level_at_snapshot,
        'eligibility_status', candidate.eligibility_status,
        'skip_reason', candidate.skip_reason,
        'display_name', coalesce(nullif(pg_catalog.btrim(profile.username), ''), nullif(pg_catalog.btrim(profile.nickname), ''), '已注销用户')
      ) order by candidate.service_month desc, candidate.candidate_order)
      from private_db2.admin_rotation_candidates as candidate
      left join public.profiles as profile on profile.id = candidate.user_id
    ), '[]'::jsonb),
    'decisions', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', decision.id,
        'reviewer_display_name', coalesce(nullif(pg_catalog.btrim(reviewer.username), ''), nullif(pg_catalog.btrim(reviewer.nickname), ''), '已注销管理员'),
        'term_source', term.source,
        'term_ends_at', term.scheduled_end_at,
        'action', decision.action,
        'reason', decision.reason,
        'adopted_payload', decision.adopted_payload,
        'adopted_count', pg_catalog.cardinality(decision.adopted_pending_ids),
        'source_count', pg_catalog.cardinality(decision.all_source_pending_ids),
        'created_at', decision.created_at
      ) order by decision.created_at desc)
      from public.admin_review_decisions as decision
      left join public.profiles as reviewer on reviewer.id = decision.reviewer_user_id
      left join public.admin_terms as term on term.id = decision.admin_term_id
    ), '[]'::jsonb),
    'community_actions', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', action.id,
        'action_type', action.action_type,
        'target_key', action.target_key,
        'target_user_id', action.target_user_id,
        'target_record_id', action.target_record_id,
        'payload', action.payload,
        'reason', action.reason,
        'required_signatures', action.required_signatures,
        'status', action.status,
        'created_at', action.created_at,
        'expires_at', action.expires_at,
        'executed_at', action.executed_at,
        'signed_by_me', exists (
          select 1 from public.community_admin_action_signatures as mine
          where mine.action_id = action.id and mine.signer_user_id = v_actor
        ),
        'valid_signature_count', (
          select pg_catalog.count(*)
          from public.community_admin_action_signatures as signature
          left join public.admin_terms as signer_term on signer_term.id = signature.admin_term_id
          where signature.action_id = action.id
            and (
              signature.signature_source = 'super_admin'
              or (
                signature.signature_source = 'ordinary_admin'
                and signer_term.status = 'active'
                and signer_term.starts_at <= pg_catalog.now()
                and signer_term.scheduled_end_at > pg_catalog.now()
              )
            )
        ),
        'signatures', coalesce((
          select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'display_name', coalesce(nullif(pg_catalog.btrim(signer.username), ''), nullif(pg_catalog.btrim(signer.nickname), ''), '已注销管理员'),
            'signature_source', signature.signature_source,
            'signed_at', signature.signed_at
          ) order by signature.signed_at, signature.signer_user_id)
          from public.community_admin_action_signatures as signature
          left join public.profiles as signer on signer.id = signature.signer_user_id
          where signature.action_id = action.id
        ), '[]'::jsonb)
      ) order by action.created_at desc)
      from (
        select * from public.community_admin_actions
        order by created_at desc
        limit 100
      ) as action
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function private_db2.sign_community_admin_action(text, text, uuid, uuid, jsonb, text, smallint, uuid)
  from public, anon, authenticated, service_role;
revoke all on function private_db2.finish_community_admin_action(uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private_db2.enforce_v21_candidate_reentry_eligibility()
  from public, anon, authenticated, service_role;
revoke all on function private_db2.enforce_v21_jury_vote_reentry_eligibility()
  from public, anon, authenticated, service_role;

revoke all on function public.list_pending_suits_for_review()
  from public, anon, authenticated, service_role;
grant execute on function public.list_pending_suits_for_review()
  to authenticated, service_role;

revoke all on function public.review_pending_suit(text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.review_pending_suit(text, text, text)
  to authenticated, service_role;

revoke all on function public.admin_reject_jury_candidate(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.admin_reject_jury_candidate(uuid, text)
  to authenticated, service_role;

revoke all on function public.reopen_rejected_jury_candidate(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.reopen_rejected_jury_candidate(uuid, text)
  to authenticated, service_role;

revoke all on function public.list_rejected_jury_items_for_reopen()
  from public, anon, authenticated, service_role;
grant execute on function public.list_rejected_jury_items_for_reopen()
  to authenticated, service_role;

revoke all on function public.submit_admin_governance_action(text, uuid, uuid, text, timestamptz, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.submit_admin_governance_action(text, uuid, uuid, text, timestamptz, timestamptz)
  to authenticated, service_role;

comment on table public.community_admin_actions is
  '社区共治 V2.1 不可删除提案与执行事实；套装/永久驳回 2 人、任期/排除 3 人，超级管理员可单独执行。';
comment on table public.community_admin_action_signatures is
  '社区共治 V2.1 共签事实；普通管理员记录有效任期，执行时重新计算仍有效签名。';
comment on function public.review_pending_suit(text, text, text) is
  '社区共治 V2.1 套装审核：普通管理员 2 人同结论共签，超级管理员单独执行；事务锁、原子写入与重试幂等。';
comment on function public.admin_reject_jury_candidate(uuid, text) is
  '社区共治 V2.1 永久驳回：普通管理员 2 人同结论共签，超级管理员单独执行；来源参与者和投票者不得普通共签。';
comment on function public.reopen_rejected_jury_candidate(uuid, text) is
  '社区共治 V2.1 纠错：保留原永久驳回与共签事实，普通管理员 2 人或超级管理员单独将事项重新送入既有陪审流程。';
comment on function public.submit_admin_governance_action(text, uuid, uuid, text, timestamptz, timestamptz) is
  '社区共治 V2.1 普通管理员任期与候选排除治理：普通管理员 3 人同结论共签，超级管理员单独执行。';

commit;
