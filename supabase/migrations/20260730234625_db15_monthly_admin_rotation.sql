-- DB-15 普通管理员月度轮换第一版。
begin;

create table public.admin_terms (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  source text not null check (source in ('monthly', 'manual', 'legacy_transition')),
  service_month date,
  source_month date,
  candidate_order integer,
  frozen_points bigint,
  qualifying_action_count integer,
  reason text,
  starts_at timestamptz not null,
  scheduled_end_at timestamptz not null,
  status text not null default 'active' check (status in ('active', 'expired', 'revoked')),
  granted_by uuid references auth.users (id) on delete set null,
  ended_at timestamptz,
  ended_by uuid references auth.users (id) on delete set null,
  end_reason text,
  created_at timestamptz not null default pg_catalog.now(),
  constraint admin_terms_period_check check (scheduled_end_at > starts_at),
  constraint admin_terms_manual_duration_check check (
    source <> 'manual'
    or scheduled_end_at <= starts_at + interval '31 days'
  ),
  constraint admin_terms_reason_check check (
    source = 'monthly'
    or nullif(pg_catalog.btrim(reason), '') is not null
  ),
  constraint admin_terms_monthly_shape_check check (
    (source = 'monthly'
      and service_month is not null
      and source_month is not null
      and candidate_order is not null
      and frozen_points is not null
      and qualifying_action_count is not null)
    or
    (source <> 'monthly'
      and service_month is null
      and source_month is null
      and candidate_order is null
      and frozen_points is null
      and qualifying_action_count is null)
  )
);

create unique index admin_terms_monthly_user_key
  on public.admin_terms (service_month, user_id)
  where source = 'monthly';

create index admin_terms_user_active_idx
  on public.admin_terms (user_id, starts_at, scheduled_end_at)
  where status = 'active';

create index admin_terms_service_month_idx
  on public.admin_terms (service_month, candidate_order)
  where source = 'monthly';

create table public.admin_candidate_exclusions (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  reason text not null check (nullif(pg_catalog.btrim(reason), '') is not null),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.now(),
  revoked_at timestamptz,
  revoked_by uuid references auth.users (id) on delete set null,
  constraint admin_candidate_exclusions_period_check check (ends_at > starts_at)
);

create index admin_candidate_exclusions_active_user_idx
  on public.admin_candidate_exclusions (user_id, starts_at, ends_at)
  where revoked_at is null;

create table private_db2.admin_rotation_candidates (
  id bigint generated always as identity primary key,
  service_month date not null,
  source_month date not null,
  user_id uuid references auth.users (id) on delete set null,
  frozen_points bigint not null,
  qualifying_action_count integer not null,
  tie_break_at timestamptz not null,
  candidate_order integer not null,
  eligibility_status text not null check (eligibility_status in ('eligible', 'skipped')),
  skip_reason text,
  captured_at timestamptz not null default pg_catalog.now(),
  constraint admin_rotation_candidates_month_check check (
    service_month = (source_month + interval '1 month')::date
  ),
  constraint admin_rotation_candidates_order_check check (candidate_order >= 1),
  constraint admin_rotation_candidates_action_check check (qualifying_action_count >= 0),
  constraint admin_rotation_candidates_service_user_key unique (service_month, user_id)
);

create index admin_rotation_candidates_fill_idx
  on private_db2.admin_rotation_candidates (
    service_month,
    eligibility_status,
    candidate_order
  );

create table private_db2.admin_review_authorizations (
  transaction_id bigint not null,
  user_id uuid not null,
  term_id uuid not null references public.admin_terms (id) on delete cascade,
  created_at timestamptz not null default pg_catalog.now(),
  primary key (transaction_id, user_id)
);

create table public.admin_review_decisions (
  id uuid primary key default extensions.gen_random_uuid(),
  reviewer_user_id uuid references auth.users (id) on delete set null,
  admin_term_id uuid references public.admin_terms (id) on delete set null,
  action text not null check (action in ('approved', 'rejected')),
  reason text,
  candidate_key text not null,
  adopted_payload jsonb not null,
  adopted_pending_ids bigint[] not null,
  all_source_pending_ids bigint[] not null,
  created_at timestamptz not null default pg_catalog.now(),
  constraint admin_review_decisions_reason_check check (
    action <> 'rejected'
    or nullif(pg_catalog.btrim(reason), '') is not null
  ),
  constraint admin_review_decisions_sources_check check (
    pg_catalog.cardinality(adopted_pending_ids) >= 5
    and pg_catalog.cardinality(all_source_pending_ids) >= pg_catalog.cardinality(adopted_pending_ids)
  )
);

create index admin_review_decisions_reviewer_idx
  on public.admin_review_decisions (reviewer_user_id, created_at desc);

create table public.admin_review_decision_sources (
  decision_id uuid not null references public.admin_review_decisions (id) on delete restrict,
  pending_id bigint not null references public.pending_clothes (id) on delete restrict,
  is_adopted boolean not null,
  primary key (decision_id, pending_id)
);

create index admin_review_decision_sources_pending_idx
  on public.admin_review_decision_sources (pending_id, decision_id);

alter table public.admin_terms enable row level security;
alter table public.admin_terms force row level security;
alter table public.admin_candidate_exclusions enable row level security;
alter table public.admin_candidate_exclusions force row level security;
alter table private_db2.admin_rotation_candidates enable row level security;
alter table private_db2.admin_rotation_candidates force row level security;
alter table private_db2.admin_review_authorizations enable row level security;
alter table private_db2.admin_review_authorizations force row level security;
alter table public.admin_review_decisions enable row level security;
alter table public.admin_review_decisions force row level security;
alter table public.admin_review_decision_sources enable row level security;
alter table public.admin_review_decision_sources force row level security;

revoke all on table public.admin_terms from public, anon, authenticated, service_role;
revoke all on table public.admin_candidate_exclusions from public, anon, authenticated, service_role;
revoke all on table private_db2.admin_rotation_candidates from public, anon, authenticated, service_role;
revoke all on sequence private_db2.admin_rotation_candidates_id_seq from public, anon, authenticated, service_role;
revoke all on table private_db2.admin_review_authorizations from public, anon, authenticated, service_role;
revoke all on table public.admin_review_decisions from public, anon, authenticated, service_role;
revoke all on table public.admin_review_decision_sources from public, anon, authenticated, service_role;

create function private_db2.current_admin_term(p_user_id uuid, p_at timestamptz default pg_catalog.now())
returns public.admin_terms
language sql
stable
security definer
set search_path = ''
as $$
  select term.*
  from public.admin_terms as term
  where term.user_id = p_user_id
    and term.status = 'active'
    and term.starts_at <= p_at
    and term.scheduled_end_at > p_at
  order by
    case term.source when 'manual' then 1 when 'legacy_transition' then 2 else 3 end,
    term.scheduled_end_at desc,
    term.id
  limit 1;
$$;

create function private_db2.is_effective_ordinary_admin(p_user_id uuid, p_at timestamptz default pg_catalog.now())
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_user_id is not null and exists (
    select 1
    from public.admin_terms as term
    where term.user_id = p_user_id
      and term.status = 'active'
      and term.starts_at <= p_at
      and term.scheduled_end_at > p_at
  );
$$;

create or replace function public.is_admin_or_super_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles as profile
    where profile.id = (select auth.uid())
      and (profile.role_level = 2 or profile.role = 'super_admin')
  ) or exists (
    select 1
    from private_db2.admin_review_authorizations as authz
    where authz.transaction_id = pg_catalog.txid_current()
      and authz.user_id = (select auth.uid())
  );
$$;

create function public.get_current_admin_capabilities()
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
  if v_user_id is null then
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
    'can_manage_admin_terms', v_super,
    'can_review_high_risk', v_super,
    'term_id', v_term.id,
    'term_source', v_term.source,
    'term_ends_at', v_term.scheduled_end_at,
    'show_grant_notice', v_term.id is not null and v_term.created_at >= pg_catalog.now() - interval '7 days'
  );
end;
$$;

create function private_db2.fill_monthly_admin_vacancies(p_service_month date)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_starts_at timestamptz := p_service_month::timestamp at time zone 'Asia/Shanghai';
  v_ends_at timestamptz := (p_service_month + interval '1 month')::timestamp at time zone 'Asia/Shanghai';
  v_needed integer;
  v_inserted integer := 0;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('db15:monthly-admins:' || p_service_month::text, 0)
  );

  update public.admin_terms
  set status = 'expired', ended_at = scheduled_end_at, end_reason = '任期自然到期'
  where status = 'active' and scheduled_end_at <= pg_catalog.now();

  select greatest(5 - count(*)::integer, 0)
  into v_needed
  from public.admin_terms as term
  where term.source = 'monthly'
    and term.service_month = p_service_month
    and term.status = 'active'
    and term.starts_at <= pg_catalog.now()
    and term.scheduled_end_at > pg_catalog.now();

  if v_needed = 0 then return 0; end if;

  with available as (
    select candidate.*
    from private_db2.admin_rotation_candidates as candidate
    join auth.users as account on account.id = candidate.user_id
    left join public.profiles as profile on profile.id = candidate.user_id
    where candidate.service_month = p_service_month
      and candidate.eligibility_status = 'eligible'
      and candidate.qualifying_action_count >= 5
      and not (coalesce(profile.role_level, 0) = 2 or profile.role = 'super_admin')
      and not exists (
        select 1 from public.admin_terms as prior
        where prior.source = 'monthly'
          and prior.service_month = p_service_month
          and prior.user_id = candidate.user_id
      )
      and not exists (
        select 1 from public.admin_terms as occupied
        where occupied.user_id = candidate.user_id
          and occupied.source in ('manual', 'legacy_transition')
          and occupied.status = 'active'
          and occupied.starts_at < v_ends_at
          and occupied.scheduled_end_at > pg_catalog.now()
      )
      and not exists (
        select 1 from public.admin_candidate_exclusions as exclusion
        where exclusion.user_id = candidate.user_id
          and exclusion.revoked_at is null
          and exclusion.starts_at < v_ends_at
          and exclusion.ends_at > pg_catalog.now()
      )
    order by candidate.candidate_order
    limit v_needed
  )
  insert into public.admin_terms (
    user_id, source, service_month, source_month, candidate_order,
    frozen_points, qualifying_action_count, starts_at, scheduled_end_at
  )
  select
    available.user_id, 'monthly', available.service_month, available.source_month,
    available.candidate_order, available.frozen_points,
    available.qualifying_action_count, v_starts_at, v_ends_at
  from available
  on conflict (service_month, user_id) where source = 'monthly' do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$$;

create function private_db2.rotate_monthly_admins_if_due(p_run_at timestamptz default pg_catalog.now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_local_date date := pg_catalog.timezone('Asia/Shanghai', p_run_at)::date;
  v_service_month date;
  v_source_month date;
  v_captured integer := 0;
  v_granted integer := 0;
begin
  if extract(day from v_local_date) <> 1 then
    return pg_catalog.jsonb_build_object('status', 'not_due', 'granted', 0);
  end if;

  v_service_month := pg_catalog.date_trunc('month', v_local_date::timestamp)::date;
  v_source_month := (v_service_month - interval '1 month')::date;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('db15:monthly-admins:' || v_service_month::text, 0)
  );

  if not exists (
    select 1 from private_db2.points_leaderboard_months as month
    where month.month_start = v_source_month
  ) then
    return pg_catalog.jsonb_build_object(
      'status', 'leaderboard_not_frozen', 'service_month', v_service_month, 'granted', 0
    );
  end if;

  if not exists (
    select 1 from private_db2.admin_rotation_candidates as candidate
    where candidate.service_month = v_service_month
  ) then
    with boundary as (
      select
        v_source_month::timestamp at time zone 'Asia/Shanghai' as starts_at,
        v_service_month::timestamp at time zone 'Asia/Shanghai' as ends_at
    ),
    actions as (
      select
        ledger.user_id,
        count(*)::integer as action_count,
        max(ledger.occurred_at) as last_action_at
      from public.points_ledger as ledger
      cross join boundary
      where ledger.status = 'awarded'
        and ledger.delta > 0
        and ledger.user_id is not null
        and ledger.occurred_at >= boundary.starts_at
        and ledger.occurred_at < boundary.ends_at
      group by ledger.user_id
    ),
    source as (
      select
        snapshot.user_id,
        snapshot.points,
        coalesce(actions.action_count, 0) as action_count,
        coalesce(actions.last_action_at, snapshot.frozen_at) as last_action_at,
        profile.role,
        profile.role_level,
        account.id is not null as account_exists,
        exists (
          select 1 from public.admin_terms as term
          where term.user_id = snapshot.user_id
            and term.status = 'active'
            and term.starts_at < (v_service_month + interval '1 month')::timestamp at time zone 'Asia/Shanghai'
            and term.scheduled_end_at > v_service_month::timestamp at time zone 'Asia/Shanghai'
        ) as has_term,
        exists (
          select 1 from public.admin_candidate_exclusions as exclusion
          where exclusion.user_id = snapshot.user_id
            and exclusion.revoked_at is null
            and exclusion.starts_at < (v_service_month + interval '1 month')::timestamp at time zone 'Asia/Shanghai'
            and exclusion.ends_at > v_service_month::timestamp at time zone 'Asia/Shanghai'
        ) as excluded
      from private_db2.points_leaderboard_monthly_snapshots as snapshot
      left join actions on actions.user_id = snapshot.user_id
      left join auth.users as account on account.id = snapshot.user_id
      left join public.profiles as profile on profile.id = snapshot.user_id
      where snapshot.month_start = v_source_month
        and snapshot.user_id is not null
    ),
    ranked as (
      select source.*,
        row_number() over (
          order by source.points desc, source.action_count desc,
            source.last_action_at asc, source.user_id asc
        )::integer as candidate_order
      from source
    )
    insert into private_db2.admin_rotation_candidates (
      service_month, source_month, user_id, frozen_points,
      qualifying_action_count, tie_break_at, candidate_order,
      eligibility_status, skip_reason
    )
    select
      v_service_month, v_source_month, ranked.user_id, ranked.points,
      ranked.action_count, ranked.last_action_at, ranked.candidate_order,
      case when ranked.account_exists
        and ranked.action_count >= 5
        and not (coalesce(ranked.role_level, 0) = 2 or ranked.role = 'super_admin')
        and not ranked.has_term
        and not ranked.excluded
        then 'eligible' else 'skipped' end,
      case
        when not ranked.account_exists then '账号已注销'
        when ranked.action_count < 5 then '上月有效行为不足 5 次'
        when coalesce(ranked.role_level, 0) = 2 or ranked.role = 'super_admin' then '超级管理员不参与轮换'
        when ranked.has_term then '已有有效管理员任期'
        when ranked.excluded then '命中有效候选排除'
        else null
      end
    from ranked;

    get diagnostics v_captured = row_count;
  end if;

  v_granted := private_db2.fill_monthly_admin_vacancies(v_service_month);
  return pg_catalog.jsonb_build_object(
    'status', 'completed', 'service_month', v_service_month,
    'captured', v_captured, 'granted', v_granted
  );
end;
$$;

create function private_db2.low_risk_clothes_candidates(p_reviewer uuid)
returns table (
  candidate_key text,
  representative_pending_id bigint,
  name text,
  category text,
  game_id text,
  stars integer,
  scores jsonb,
  tags text,
  supporter_count integer,
  minority_count integer,
  adopted_pending_ids bigint[],
  all_source_pending_ids bigint[]
)
language sql
stable
security definer
set search_path = ''
as $$
  with pending as (
    select item.*,
      pg_catalog.btrim(item.category) as cluster_category,
      pg_catalog.btrim(item.game_id) as cluster_game_id,
      pg_catalog.md5(pg_catalog.concat_ws('|',
        pg_catalog.btrim(item.category), pg_catalog.btrim(item.game_id),
        pg_catalog.btrim(item.name), item.stars::text, item.scores::text,
        coalesce(pg_catalog.btrim(item.tags), '')
      )) as variant_key
    from public.pending_clothes as item
    where item.status = 'pending'
      and item.submitted_by is not null
      and nullif(pg_catalog.btrim(item.name), '') is not null
      and nullif(pg_catalog.btrim(item.category), '') is not null
      and nullif(pg_catalog.btrim(item.game_id), '') is not null
      and pg_catalog.btrim(item.game_id) ~ '^[0-9]+$'
      and item.stars is not null
      and item.scores is not null
      and item.suit_id is null
      and nullif(pg_catalog.btrim(coalesce(item.temp_suit_name, '')), '') is null
      and item.needs_suit_review = false
  ),
  variants as (
    select
      cluster_category, cluster_game_id, variant_key,
      min(id) as representative_pending_id,
      min(name) as name,
      min(category) as category,
      min(game_id) as game_id,
      min(stars) as stars,
      (pg_catalog.array_agg(scores order by id))[1] as scores,
      min(tags) as tags,
      count(distinct submitted_by)::integer as supporter_count,
      pg_catalog.array_agg(id order by id) as adopted_pending_ids
    from pending
    group by cluster_category, cluster_game_id, variant_key
  ),
  ranked as (
    select variants.*,
      dense_rank() over (
        partition by cluster_category, cluster_game_id
        order by supporter_count desc
      ) as support_rank,
      count(*) over (
        partition by cluster_category, cluster_game_id, supporter_count
      ) as tied_variant_count
    from variants
  ),
  clusters as (
    select
      pending.cluster_category,
      pending.cluster_game_id,
      count(*)::integer as all_count,
      pg_catalog.array_agg(pending.id order by pending.id) as all_source_pending_ids,
      bool_or(pending.submitted_by = p_reviewer) as reviewer_participated
    from pending
    group by pending.cluster_category, pending.cluster_game_id
  )
  select
    top.variant_key,
    top.representative_pending_id,
    top.name, top.category, top.game_id, top.stars, top.scores, top.tags,
    top.supporter_count,
    clusters.all_count - pg_catalog.cardinality(top.adopted_pending_ids) as minority_count,
    top.adopted_pending_ids,
    clusters.all_source_pending_ids
  from ranked as top
  join clusters using (cluster_category, cluster_game_id)
  where top.support_rank = 1
    and top.tied_variant_count = 1
    and top.supporter_count >= 5
    and not clusters.reviewer_participated
    and not exists (
      select 1 from public.clothes as formal
      where pg_catalog.btrim(formal.category) = top.cluster_category
        and (
          pg_catalog.btrim(coalesce(formal.game_id, '')) = top.cluster_game_id
          or pg_catalog.btrim(coalesce(formal.name, '')) = pg_catalog.btrim(top.name)
        )
    )
  order by top.representative_pending_id;
$$;

create function public.list_low_risk_clothes_review_candidates()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_allowed boolean;
  v_result jsonb;
begin
  select public.is_super_admin() or private_db2.is_effective_ordinary_admin(v_user_id)
  into v_allowed;
  if v_user_id is null or not v_allowed then
    raise exception using errcode = '42501', message = '没有低风险新增服装审核权限';
  end if;

  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'candidate_key', candidate.candidate_key,
    'representative_pending_id', candidate.representative_pending_id,
    'name', candidate.name,
    'category', candidate.category,
    'game_id', candidate.game_id,
    'stars', candidate.stars,
    'scores', candidate.scores,
    'tags', candidate.tags,
    'supporter_count', candidate.supporter_count,
    'minority_count', candidate.minority_count
  ) order by candidate.representative_pending_id), '[]'::jsonb)
  into v_result
  from private_db2.low_risk_clothes_candidates(v_user_id) as candidate;
  return v_result;
end;
$$;

create function public.review_low_risk_clothes_candidate(
  p_representative_pending_id bigint,
  p_action text,
  p_reason text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_term public.admin_terms%rowtype;
  v_candidate record;
  v_decision_id uuid;
  v_result jsonb;
  v_updated integer;
begin
  if p_action not in ('approved', 'rejected') then
    raise exception using errcode = '22023', message = '审核决定只能是通过或驳回';
  end if;
  if p_action = 'rejected' and nullif(pg_catalog.btrim(coalesce(p_reason, '')), '') is null then
    raise exception using errcode = '22023', message = '驳回必须填写原因';
  end if;

  select decision.id into v_decision_id
  from public.admin_review_decisions as decision
  join public.admin_review_decision_sources as source on source.decision_id = decision.id
  where source.pending_id = p_representative_pending_id
    and decision.action = p_action
  order by decision.created_at desc
  limit 1;
  if found then
    return pg_catalog.jsonb_build_object('already_completed', true, 'decision_id', v_decision_id);
  end if;

  if v_user_id is null then
    raise exception using errcode = '42501', message = '请先登录';
  end if;

  select * into v_term from private_db2.current_admin_term(v_user_id);
  if v_term.id is null and not public.is_super_admin() then
    raise exception using errcode = '42501', message = '当前管理员任期无效';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('db15:low-risk-review:' || p_representative_pending_id::text, 0)
  );

  select * into v_candidate
  from private_db2.low_risk_clothes_candidates(v_user_id) as candidate
  where candidate.representative_pending_id = p_representative_pending_id;
  if not found then
    raise exception using errcode = '40001', message = '候选状态已变化、人数不足、存在并列、正式库已有或审核者参与过提交';
  end if;

  if p_action = 'approved' then
    if v_term.id is not null then
      insert into private_db2.admin_review_authorizations (transaction_id, user_id, term_id)
      values (pg_catalog.txid_current(), v_user_id, v_term.id)
      on conflict (transaction_id, user_id) do nothing;
    end if;

    v_result := public.approve_pending_clothes_arbitration(
      'custom_admin_' || pg_catalog.substr(v_candidate.candidate_key, 1, 20),
      v_candidate.name, v_candidate.game_id, v_candidate.category,
      v_candidate.stars, v_candidate.scores, null, null,
      v_candidate.tags, v_candidate.adopted_pending_ids, false
    );

    if v_term.id is not null then
      delete from private_db2.admin_review_authorizations
      where transaction_id = pg_catalog.txid_current() and user_id = v_user_id;
    end if;
  else
    update public.pending_clothes
    set status = 'rejected'
    where id = any(v_candidate.adopted_pending_ids) and status = 'pending';
    get diagnostics v_updated = row_count;
    if v_updated <> pg_catalog.cardinality(v_candidate.adopted_pending_ids) then
      raise exception using errcode = '40001', message = '申请状态已变化，本次驳回已整体回滚';
    end if;
    v_result := pg_catalog.jsonb_build_object('rejected_count', v_updated);
  end if;

  insert into public.admin_review_decisions (
    reviewer_user_id, admin_term_id, action, reason, candidate_key,
    adopted_payload, adopted_pending_ids, all_source_pending_ids
  ) values (
    v_user_id, v_term.id, p_action, nullif(pg_catalog.btrim(coalesce(p_reason, '')), ''),
    v_candidate.candidate_key,
    pg_catalog.jsonb_build_object(
      'name', v_candidate.name, 'category', v_candidate.category,
      'game_id', v_candidate.game_id, 'stars', v_candidate.stars,
      'scores', v_candidate.scores, 'tags', v_candidate.tags
    ),
    v_candidate.adopted_pending_ids, v_candidate.all_source_pending_ids
  ) returning id into v_decision_id;

  insert into public.admin_review_decision_sources (decision_id, pending_id, is_adopted)
  select v_decision_id, source.pending_id,
    source.pending_id = any(v_candidate.adopted_pending_ids)
  from pg_catalog.unnest(v_candidate.all_source_pending_ids) as source(pending_id);

  return coalesce(v_result, '{}'::jsonb) || pg_catalog.jsonb_build_object(
    'already_completed', false, 'decision_id', v_decision_id
  );
end;
$$;

create function public.get_my_rejected_clothing_submissions()
returns table (
  pending_id bigint,
  name text,
  category text,
  game_id text,
  rejected_at timestamptz,
  reason text,
  can_resubmit boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    pending.id, pending.name, pending.category, pending.game_id,
    decision.created_at, decision.reason, true
  from public.pending_clothes as pending
  join public.admin_review_decision_sources as source
    on source.pending_id = pending.id and source.is_adopted
  join public.admin_review_decisions as decision
    on decision.id = source.decision_id and decision.action = 'rejected'
  where pending.submitted_by = (select auth.uid())
  order by decision.created_at desc;
$$;

create function public.list_admin_governance()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_result jsonb;
begin
  if not public.is_super_admin() then
    raise exception using errcode = '42501', message = '仅超级管理员可查看任期治理';
  end if;
  select pg_catalog.jsonb_build_object(
    'terms', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', term.id, 'user_id', term.user_id,
        'display_name', coalesce(nullif(pg_catalog.btrim(profile.username), ''), nullif(pg_catalog.btrim(profile.nickname), ''), '未命名用户'),
        'source', term.source, 'service_month', term.service_month,
        'starts_at', term.starts_at, 'scheduled_end_at', term.scheduled_end_at,
        'status', term.status, 'reason', term.reason, 'end_reason', term.end_reason,
        'created_at', term.created_at
      ) order by term.created_at desc)
      from public.admin_terms as term
      left join public.profiles as profile on profile.id = term.user_id
    ), '[]'::jsonb),
    'exclusions', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', exclusion.id, 'user_id', exclusion.user_id,
        'display_name', coalesce(nullif(pg_catalog.btrim(profile.username), ''), nullif(pg_catalog.btrim(profile.nickname), ''), '未命名用户'),
        'reason', exclusion.reason, 'starts_at', exclusion.starts_at,
        'ends_at', exclusion.ends_at, 'revoked_at', exclusion.revoked_at
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
        'eligibility_status', candidate.eligibility_status,
        'skip_reason', candidate.skip_reason,
        'display_name', coalesce(nullif(pg_catalog.btrim(profile.username), ''), nullif(pg_catalog.btrim(profile.nickname), ''), '已注销用户')
      ) order by candidate.service_month desc, candidate.candidate_order)
      from private_db2.admin_rotation_candidates as candidate
      left join public.profiles as profile on profile.id = candidate.user_id
    ), '[]'::jsonb),
    'decisions', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', decision.id, 'action', decision.action, 'reason', decision.reason,
        'adopted_payload', decision.adopted_payload,
        'adopted_count', pg_catalog.cardinality(decision.adopted_pending_ids),
        'source_count', pg_catalog.cardinality(decision.all_source_pending_ids),
        'created_at', decision.created_at
      ) order by decision.created_at desc)
      from public.admin_review_decisions as decision
    ), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

create function public.create_manual_admin_term(
  p_user_id uuid,
  p_reason text,
  p_ends_at timestamptz
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_now timestamptz := pg_catalog.now();
  v_current public.admin_terms%rowtype;
begin
  if not public.is_super_admin() then
    raise exception using errcode = '42501', message = '仅超级管理员可创建手动任期';
  end if;
  if p_user_id is null or nullif(pg_catalog.btrim(coalesce(p_reason, '')), '') is null then
    raise exception using errcode = '22023', message = '用户和原因不能为空';
  end if;
  if p_ends_at <= v_now or p_ends_at > v_now + interval '31 days' then
    raise exception using errcode = '22023', message = '手动任期结束时间必须在未来 31 天内';
  end if;
  if exists (select 1 from public.profiles where id = p_user_id and (role_level = 2 or role = 'super_admin')) then
    raise exception using errcode = '22023', message = '超级管理员不需要普通管理员任期';
  end if;

  select * into v_current from private_db2.current_admin_term(p_user_id, v_now);
  if v_current.source in ('manual', 'legacy_transition') then
    raise exception using errcode = '23505', message = '该用户已有有效手动或过渡任期';
  end if;
  if v_current.source = 'monthly' then
    update public.admin_terms
    set status = 'revoked', ended_at = v_now, ended_by = (select auth.uid()),
      end_reason = '转为独立手动任期'
    where id = v_current.id;
  end if;

  insert into public.admin_terms (user_id, source, reason, starts_at, scheduled_end_at, granted_by)
  values (p_user_id, 'manual', pg_catalog.btrim(p_reason), v_now, p_ends_at, (select auth.uid()))
  returning id into v_id;

  if v_current.source = 'monthly' then
    perform private_db2.fill_monthly_admin_vacancies(v_current.service_month);
  end if;
  return v_id;
end;
$$;

create function public.end_admin_term(p_term_id uuid, p_reason text)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare v_term public.admin_terms%rowtype; v_service_month date;
begin
  if not public.is_super_admin() then
    raise exception using errcode = '42501', message = '仅超级管理员可提前结束任期';
  end if;
  if nullif(pg_catalog.btrim(coalesce(p_reason, '')), '') is null then
    raise exception using errcode = '22023', message = '提前结束任期必须填写原因';
  end if;
  update public.admin_terms set status = 'revoked', ended_at = pg_catalog.now(),
    ended_by = (select auth.uid()), end_reason = pg_catalog.btrim(p_reason)
  where id = p_term_id and status = 'active' and scheduled_end_at > pg_catalog.now()
  returning * into v_term;
  if not found then return false; end if;
  v_service_month := v_term.service_month;
  if v_term.source = 'monthly' then
    perform private_db2.fill_monthly_admin_vacancies(v_service_month);
  end if;
  return true;
end;
$$;

create function public.leave_current_admin_term()
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare v_term public.admin_terms%rowtype;
begin
  select * into v_term from private_db2.current_admin_term((select auth.uid()));
  if v_term.id is null then return false; end if;
  update public.admin_terms set status = 'revoked', ended_at = pg_catalog.now(),
    ended_by = (select auth.uid()), end_reason = '管理员本人主动退出'
  where id = v_term.id;
  if v_term.source = 'monthly' then
    perform private_db2.fill_monthly_admin_vacancies(v_term.service_month);
  end if;
  return true;
end;
$$;

create function public.create_admin_candidate_exclusion(
  p_user_id uuid, p_reason text, p_starts_at timestamptz, p_ends_at timestamptz
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare v_id uuid; v_term public.admin_terms%rowtype;
begin
  if not public.is_super_admin() then
    raise exception using errcode = '42501', message = '仅超级管理员可维护候选排除';
  end if;
  if p_user_id is null or nullif(pg_catalog.btrim(coalesce(p_reason, '')), '') is null
    or p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at then
    raise exception using errcode = '22023', message = '排除用户、原因和有效期必须完整';
  end if;
  insert into public.admin_candidate_exclusions (
    user_id, reason, starts_at, ends_at, created_by
  ) values (
    p_user_id, pg_catalog.btrim(p_reason), p_starts_at, p_ends_at, (select auth.uid())
  ) returning id into v_id;

  select * into v_term from private_db2.current_admin_term(p_user_id);
  if v_term.source = 'monthly' then
    update public.admin_terms set status = 'revoked', ended_at = pg_catalog.now(),
      ended_by = (select auth.uid()), end_reason = '新增候选排除：' || pg_catalog.btrim(p_reason)
    where id = v_term.id;
    perform private_db2.fill_monthly_admin_vacancies(v_term.service_month);
  end if;
  return v_id;
end;
$$;

create function public.revoke_admin_candidate_exclusion(p_exclusion_id uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not public.is_super_admin() then
    raise exception using errcode = '42501', message = '仅超级管理员可撤销候选排除';
  end if;
  update public.admin_candidate_exclusions
  set revoked_at = pg_catalog.now(), revoked_by = (select auth.uid())
  where id = p_exclusion_id and revoked_at is null;
  return found;
end;
$$;

insert into public.admin_terms (
  user_id, source, reason, starts_at, scheduled_end_at, granted_by
)
select
  profile.id, 'legacy_transition', '旧普通管理员迁移为 31 天受限过渡任期',
  pg_catalog.now(), pg_catalog.now() + interval '31 days', null
from public.profiles as profile
where profile.role_level = 1 or profile.role = 'admin';

update public.profiles
set role = 'user', role_level = 0, updated_at = pg_catalog.now()
where role_level = 1 or role = 'admin';

alter table public.profiles
  add constraint profiles_no_ordinary_admin_role_check
  check (role_level <> 1 and role <> 'admin');

drop policy if exists "认证用户可查看自己的申请及管理员可查看全部" on public.pending_clothes;
create policy "认证用户只能查看自己的申请及超级管理员可查看全部"
on public.pending_clothes for select to authenticated
using (
  (select auth.uid()) is not null
  and (submitted_by = (select auth.uid()) or (select public.is_super_admin()))
);

drop policy if exists "管理员可更新申请状态" on public.pending_clothes;
create policy "仅超级管理员可直接更新申请状态"
on public.pending_clothes for update to authenticated
using ((select public.is_super_admin()))
with check ((select public.is_super_admin()));

revoke update on table public.pending_clothes from authenticated;
grant update (status) on table public.pending_clothes to authenticated;

revoke all on function private_db2.current_admin_term(uuid, timestamptz) from public, anon, authenticated, service_role;
revoke all on function private_db2.is_effective_ordinary_admin(uuid, timestamptz) from public, anon, authenticated, service_role;
revoke all on function private_db2.fill_monthly_admin_vacancies(date) from public, anon, authenticated, service_role;
revoke all on function private_db2.rotate_monthly_admins_if_due(timestamptz) from public, anon, authenticated, service_role;
revoke all on function private_db2.low_risk_clothes_candidates(uuid) from public, anon, authenticated, service_role;

revoke all on function public.get_current_admin_capabilities() from public, anon, authenticated, service_role;
grant execute on function public.get_current_admin_capabilities() to authenticated, service_role;
revoke all on function public.list_low_risk_clothes_review_candidates() from public, anon, authenticated, service_role;
grant execute on function public.list_low_risk_clothes_review_candidates() to authenticated, service_role;
revoke all on function public.review_low_risk_clothes_candidate(bigint, text, text) from public, anon, authenticated, service_role;
grant execute on function public.review_low_risk_clothes_candidate(bigint, text, text) to authenticated, service_role;
revoke all on function public.get_my_rejected_clothing_submissions() from public, anon, authenticated, service_role;
grant execute on function public.get_my_rejected_clothing_submissions() to authenticated, service_role;
revoke all on function public.list_admin_governance() from public, anon, authenticated, service_role;
grant execute on function public.list_admin_governance() to authenticated, service_role;
revoke all on function public.create_manual_admin_term(uuid, text, timestamptz) from public, anon, authenticated, service_role;
grant execute on function public.create_manual_admin_term(uuid, text, timestamptz) to authenticated, service_role;
revoke all on function public.end_admin_term(uuid, text) from public, anon, authenticated, service_role;
grant execute on function public.end_admin_term(uuid, text) to authenticated, service_role;
revoke all on function public.leave_current_admin_term() from public, anon, authenticated, service_role;
grant execute on function public.leave_current_admin_term() to authenticated, service_role;
revoke all on function public.create_admin_candidate_exclusion(uuid, text, timestamptz, timestamptz) from public, anon, authenticated, service_role;
grant execute on function public.create_admin_candidate_exclusion(uuid, text, timestamptz, timestamptz) to authenticated, service_role;
revoke all on function public.revoke_admin_candidate_exclusion(uuid) from public, anon, authenticated, service_role;
grant execute on function public.revoke_admin_candidate_exclusion(uuid) to authenticated, service_role;

comment on table public.admin_terms is 'DB-15 普通管理员权限唯一事实；月度、手动和旧管理员过渡任期均按时间生效。';
comment on table private_db2.admin_rotation_candidates is 'DB-15 月初冻结候选顺序及跳过原因；月中不随新积分重排。';
comment on table public.admin_candidate_exclusions is 'DB-15 超级管理员维护的显式候选排除事实。';
comment on table public.admin_review_decisions is 'DB-15 低风险新增服装审核不可变决定与采用资料摘要。';

do $$
begin
  if exists (select 1 from cron.job where jobname = 'db15-rotate-monthly-admins') then
    raise exception 'DB15 migration refuses to overwrite an existing cron job';
  end if;
end;
$$;

select cron.schedule(
  'db15-rotate-monthly-admins',
  '10 16 * * *',
  $command$select private_db2.rotate_monthly_admins_if_due();$command$
);

commit;
