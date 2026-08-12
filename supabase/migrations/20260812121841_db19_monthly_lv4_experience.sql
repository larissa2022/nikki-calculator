begin;

create table private_db2.monthly_lv4_experience_terms (
  id bigint generated always as identity primary key,
  service_month date not null,
  source_month date not null,
  source_snapshot_id bigint not null,
  user_id uuid,
  frozen_points bigint not null,
  leaderboard_rank bigint not null,
  starts_at timestamptz not null,
  scheduled_end_at timestamptz not null,
  granted_at timestamptz not null default pg_catalog.now(),
  reclaimed_at timestamptz,

  constraint monthly_lv4_experience_terms_source_snapshot_fkey
    foreign key (source_snapshot_id)
    references private_db2.points_leaderboard_monthly_snapshots (id)
    on delete restrict,
  constraint monthly_lv4_experience_terms_user_id_fkey
    foreign key (user_id)
    references auth.users (id)
    on delete set null,
  constraint monthly_lv4_experience_terms_service_month_check
    check (
      service_month = pg_catalog.date_trunc('month', service_month::timestamp)::date
      and source_month = (service_month - interval '1 month')::date
    ),
  constraint monthly_lv4_experience_terms_rank_check
    check (leaderboard_rank = 1),
  constraint monthly_lv4_experience_terms_window_check
    check (
      starts_at = service_month::timestamp at time zone 'Asia/Shanghai'
      and scheduled_end_at = (service_month + interval '1 month')::timestamp
        at time zone 'Asia/Shanghai'
      and granted_at >= starts_at
      and (reclaimed_at is null or reclaimed_at >= scheduled_end_at)
    ),
  constraint monthly_lv4_experience_terms_service_snapshot_key
    unique (service_month, source_snapshot_id)
);

create index monthly_lv4_experience_terms_source_snapshot_id_idx
  on private_db2.monthly_lv4_experience_terms (source_snapshot_id);

create index monthly_lv4_experience_terms_user_window_idx
  on private_db2.monthly_lv4_experience_terms (
    user_id,
    starts_at,
    scheduled_end_at
  )
  where user_id is not null;

alter table private_db2.monthly_lv4_experience_terms enable row level security;
alter table private_db2.monthly_lv4_experience_terms force row level security;

revoke all on table private_db2.monthly_lv4_experience_terms
  from public, anon, authenticated, service_role;
revoke all on sequence private_db2.monthly_lv4_experience_terms_id_seq
  from public, anon, authenticated, service_role;

create function private_db2.active_monthly_lv4_experience_id(
  p_user_id uuid,
  p_at timestamptz default pg_catalog.now()
)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select term.id
  from private_db2.monthly_lv4_experience_terms as term
  where term.user_id = p_user_id
    and p_user_id is not null
    and p_at is not null
    and term.starts_at <= p_at
    and term.scheduled_end_at > p_at
  order by term.service_month desc, term.id desc
  limit 1;
$$;

create function private_db2.refresh_monthly_lv4_experiences(
  p_run_at timestamptz default pg_catalog.now()
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_local_date date;
  v_service_month date;
  v_source_month date;
  v_inserted_count integer := 0;
  v_reclaimed_count integer := 0;
begin
  if p_run_at is null then
    raise exception using errcode = '22023', message = '体验资格刷新时间不能为空';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('db19:monthly_lv4_experiences', 0)
  );

  update private_db2.monthly_lv4_experience_terms as term
  set reclaimed_at = p_run_at
  where term.reclaimed_at is null
    and term.scheduled_end_at <= p_run_at;
  get diagnostics v_reclaimed_count = row_count;

  v_local_date := pg_catalog.timezone('Asia/Shanghai', p_run_at)::date;
  v_service_month := pg_catalog.date_trunc('month', v_local_date::timestamp)::date;
  v_source_month := (v_service_month - interval '1 month')::date;

  if not exists (
    select 1
    from private_db2.points_leaderboard_months as frozen_month
    where frozen_month.month_start = v_source_month
  ) then
    return pg_catalog.jsonb_build_object(
      'status', 'source_not_frozen',
      'service_month', v_service_month,
      'source_month', v_source_month,
      'granted_count', 0,
      'reclaimed_count', v_reclaimed_count
    );
  end if;

  insert into private_db2.monthly_lv4_experience_terms (
    service_month,
    source_month,
    source_snapshot_id,
    user_id,
    frozen_points,
    leaderboard_rank,
    starts_at,
    scheduled_end_at,
    granted_at
  )
  select
    v_service_month,
    v_source_month,
    snapshot.id,
    snapshot.user_id,
    snapshot.points,
    snapshot.leaderboard_rank,
    v_service_month::timestamp at time zone 'Asia/Shanghai',
    (v_service_month + interval '1 month')::timestamp at time zone 'Asia/Shanghai',
    p_run_at
  from private_db2.points_leaderboard_monthly_snapshots as snapshot
  where snapshot.month_start = v_source_month
    and snapshot.leaderboard_rank = 1
    and snapshot.user_id is not null
    and exists (
      select 1 from auth.users as account where account.id = snapshot.user_id
    )
  order by snapshot.id
  on conflict (service_month, source_snapshot_id) do nothing;
  get diagnostics v_inserted_count = row_count;

  return pg_catalog.jsonb_build_object(
    'status', case when v_inserted_count > 0 then 'granted' else 'already_granted' end,
    'service_month', v_service_month,
    'source_month', v_source_month,
    'granted_count', v_inserted_count,
    'reclaimed_count', v_reclaimed_count,
    'active_count', (
      select pg_catalog.count(*)
      from private_db2.monthly_lv4_experience_terms as term
      where term.service_month = v_service_month
        and term.user_id is not null
        and term.starts_at <= p_run_at
        and term.scheduled_end_at > p_run_at
    )
  );
end;
$$;

revoke all on function private_db2.active_monthly_lv4_experience_id(uuid, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function private_db2.refresh_monthly_lv4_experiences(timestamptz)
  from public, anon, authenticated, service_role;

-- 月榜冻结成功后立即授予当月体验资格；沿用 DB-14 北京时间 00:05 的唯一 cron，
-- 并继续由 DB-15 在 00:10 独立计算累计等级候选，不共享体验资格。
create or replace function private_db2.freeze_previous_month_if_due(
  p_run_at timestamptz default pg_catalog.now()
)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_local_date date;
  v_target_month date;
  v_frozen_count bigint;
begin
  v_local_date := pg_catalog.timezone('Asia/Shanghai', p_run_at)::date;

  if extract(day from v_local_date) <> 1 then
    return 0;
  end if;

  v_target_month := (
    pg_catalog.date_trunc('month', v_local_date::timestamp) - interval '1 month'
  )::date;

  v_frozen_count := private_db2.freeze_points_leaderboard_month(v_target_month);
  perform private_db2.refresh_monthly_lv4_experiences(p_run_at);
  return v_frozen_count;
end;
$$;

revoke all on function private_db2.freeze_previous_month_if_due(timestamptz)
  from public, anon, authenticated, service_role;

create or replace function private_db2.prepare_points_ledger_entry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_total_after bigint;
  v_total_before bigint;
  v_cumulative_level smallint;
begin
  if new.user_id is null then
    new.level_snapshot := null;
    return new;
  end if;

  insert into private_db2.user_points_state (user_id, total_points, updated_at)
  values (new.user_id, 0, pg_catalog.now())
  on conflict (user_id) do nothing;

  select state.total_points into v_total_before
  from private_db2.user_points_state as state
  where state.user_id = new.user_id
  for update;

  if exists (
    select 1
    from public.points_ledger as existing
    where existing.id = new.id
      or (new.source_id is not null and existing.source_id = new.source_id)
      or (
        new.re_review_candidate_id is not null
        and existing.re_review_candidate_id = new.re_review_candidate_id
      )
      or (new.jury_vote_id is not null and existing.jury_vote_id = new.jury_vote_id)
      or (
        new.correction_request_id is not null
        and existing.correction_request_id = new.correction_request_id
      )
      or (new.bonus_of is not null and existing.bonus_of = new.bonus_of)
      or (new.reversal_of is not null and existing.reversal_of = new.reversal_of)
  ) then
    return null;
  end if;

  update private_db2.user_points_state as state
  set total_points = state.total_points + new.delta,
      updated_at = pg_catalog.now()
  where state.user_id = new.user_id
  returning state.total_points into v_total_after;

  if new.source_type in ('clothing_contribution', 're_review_candidate', 'correction_request') then
    v_cumulative_level := private_db2.level_for_points(v_total_before);
    new.level_snapshot := case
      when private_db2.active_monthly_lv4_experience_id(new.user_id, new.occurred_at) is not null
        then 4
      else v_cumulative_level
    end;
  elsif new.source_type <> 'level_bonus' then
    new.level_snapshot := null;
  end if;

  return new;
end;
$$;

revoke all on function private_db2.prepare_points_ledger_entry()
  from public, anon, authenticated, service_role;

-- 保留累计等级作为复核意见门槛，只让当月体验改变本次投票的等级与票权快照。
create or replace function public.cast_jury_vote(
  p_candidate_id uuid,
  p_vote text,
  p_review_note text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_candidate public.re_review_candidates%rowtype;
  v_item public.re_review_items%rowtype;
  v_vote_id uuid;
  v_existing_vote text;
  v_existing_note text;
  v_existing_weight smallint;
  v_existing_level smallint;
  v_cumulative_level smallint;
  v_vote_level smallint;
  v_vote_weight smallint;
  v_review_note text := nullif(pg_catalog.btrim(coalesce(p_review_note, '')), '');
  v_approve_count integer := 0;
  v_reject_count integer := 0;
  v_approve_weight integer := 0;
  v_reject_weight integer := 0;
  v_result_status text := 'voting';
  v_points_awarded integer := 0;
  v_apply_result jsonb := '{}'::jsonb;
begin
  if v_user_id is null then
    raise exception '需要登录后才能参与陪审团投票';
  end if;
  if p_vote is null or p_vote not in ('approve', 'reject') then
    raise exception '投票只允许 approve 或 reject';
  end if;
  if pg_catalog.char_length(v_review_note) > 200 then
    raise exception using errcode = '22023', message = '复核意见不能超过 200 字';
  end if;

  select candidate.* into v_candidate
  from public.re_review_candidates as candidate
  where candidate.id = p_candidate_id
  for update;
  if not found then raise exception '待审核内容不存在'; end if;

  select vote.id, vote.vote, vote.review_note, vote.vote_weight, vote.voter_level
  into v_vote_id, v_existing_vote, v_existing_note, v_existing_weight, v_existing_level
  from public.jury_votes as vote
  where vote.candidate_id = v_candidate.id
    and vote.user_id = v_user_id;

  if found and (
    v_existing_vote is distinct from p_vote
    or v_existing_note is distinct from v_review_note
  ) then
    raise exception '投票和复核意见提交后不能修改';
  end if;

  select private_db2.level_for_points(coalesce(pg_catalog.sum(ledger.delta), 0))
  into v_cumulative_level
  from public.points_ledger as ledger
  where ledger.user_id = v_user_id
    and ledger.status = 'awarded';

  v_vote_level := case
    when private_db2.active_monthly_lv4_experience_id(v_user_id, pg_catalog.now()) is not null
      then 4
    else v_cumulative_level
  end;
  v_vote_weight := private_db2.vote_weight_for_level(v_vote_level);

  if v_review_note is not null and v_cumulative_level < 2 then
    raise exception using errcode = '42501', message = '累计 Lv2 及以上才能提交复核意见';
  end if;

  if v_candidate.status <> 'voting' then
    if v_vote_id is null then raise exception '该内容当前不可投票'; end if;
    select
      pg_catalog.count(*) filter (where vote.vote = 'approve')::integer,
      pg_catalog.count(*) filter (where vote.vote = 'reject')::integer,
      coalesce(pg_catalog.sum(vote.vote_weight) filter (where vote.vote = 'approve'), 0)::integer,
      coalesce(pg_catalog.sum(vote.vote_weight) filter (where vote.vote = 'reject'), 0)::integer
    into v_approve_count, v_reject_count, v_approve_weight, v_reject_weight
    from public.jury_votes as vote
    where vote.candidate_id = v_candidate.id;

    return pg_catalog.jsonb_build_object(
      'candidate_id', v_candidate.id,
      're_review_item_id', v_candidate.re_review_item_id,
      'approve_count', v_approve_count,
      'reject_count', v_reject_count,
      'approve_weight', v_approve_weight,
      'reject_weight', v_reject_weight,
      'my_vote', v_existing_vote,
      'my_vote_weight', v_existing_weight,
      'my_voter_level', v_existing_level,
      'my_review_note', v_existing_note,
      'points_awarded', 0,
      'status', v_candidate.status
    );
  end if;

  select item.* into v_item
  from public.re_review_items as item
  where item.id = v_candidate.re_review_item_id
  for update;
  if not found or v_item.status <> 'voting' then
    raise exception '审核事项当前不在投票状态';
  end if;

  if v_candidate.submitted_by is not distinct from v_user_id
    or v_item.submitted_by is not distinct from v_user_id
    or exists (
      select 1 from public.pending_clothes as primary_source
      where primary_source.id = v_item.source_pending_id
        and primary_source.submitted_by = v_user_id
    )
    or exists (
      select 1 from public.re_review_item_sources as source
      where source.re_review_item_id = v_item.id
        and source.source_user_id = v_user_id
    ) then
    raise exception using errcode = '42501',
      message = '不能投票审核自己提交或参与过的数据';
  end if;

  if v_vote_id is null then
    insert into public.jury_votes (
      candidate_id, user_id, vote, voter_level, vote_weight, review_note
    ) values (
      v_candidate.id, v_user_id, p_vote, v_vote_level, v_vote_weight, v_review_note
    ) returning id into v_vote_id;

    insert into public.points_ledger (
      user_id, delta, status, source_type, source_id,
      re_review_candidate_id, jury_vote_id, correction_request_id,
      bonus_of, reversal_of
    ) values (
      v_user_id, 1, 'awarded', 'jury_vote', null,
      null, v_vote_id, null, null, null
    ) on conflict (jury_vote_id) where jury_vote_id is not null do nothing;

    get diagnostics v_points_awarded = row_count;
    v_existing_vote := p_vote;
    v_existing_note := v_review_note;
    v_existing_weight := v_vote_weight;
    v_existing_level := v_vote_level;
  end if;

  select
    pg_catalog.count(*) filter (where vote.vote = 'approve')::integer,
    pg_catalog.count(*) filter (where vote.vote = 'reject')::integer,
    coalesce(pg_catalog.sum(vote.vote_weight) filter (where vote.vote = 'approve'), 0)::integer,
    coalesce(pg_catalog.sum(vote.vote_weight) filter (where vote.vote = 'reject'), 0)::integer
  into v_approve_count, v_reject_count, v_approve_weight, v_reject_weight
  from public.jury_votes as vote
  where vote.candidate_id = v_candidate.id;

  if v_approve_count >= 5 and v_approve_weight > v_reject_weight then
    v_apply_result := public.apply_approved_jury_candidate(
      v_item.id, v_candidate.id, v_user_id
    );
    v_result_status := 'approved';
  elsif v_reject_count >= 3 and v_reject_weight - v_approve_weight >= 3 then
    update public.re_review_candidates
    set status = 'returned', resolved_at = pg_catalog.now()
    where id = v_candidate.id;

    update public.re_review_items
    set status = 'pending', resolved_by = null, resolved_at = null,
        updated_at = pg_catalog.now()
    where id = v_item.id;
    v_result_status := 'returned';
  end if;

  return pg_catalog.jsonb_build_object(
    'candidate_id', v_candidate.id,
    're_review_item_id', v_item.id,
    'approve_count', v_approve_count,
    'reject_count', v_reject_count,
    'approve_weight', v_approve_weight,
    'reject_weight', v_reject_weight,
    'my_vote', v_existing_vote,
    'my_vote_weight', v_existing_weight,
    'my_voter_level', v_existing_level,
    'my_review_note', v_existing_note,
    'points_awarded', case when v_points_awarded > 0 then 1 else 0 end,
    'status', v_result_status
  ) || v_apply_result;
end;
$$;

revoke all on function public.cast_jury_vote(uuid, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.cast_jury_vote(uuid, text, text)
  to authenticated, service_role;

alter function public.get_my_level_benefits() set schema private_db2;
alter function private_db2.get_my_level_benefits() rename to cumulative_level_benefits;
revoke all on function private_db2.cumulative_level_benefits()
  from public, anon, authenticated, service_role;

create function private_db2.lv4_governance_stats(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'terms', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'service_month', terms.service_month,
        'status', terms.status,
        'term_count', terms.term_count
      ) order by terms.service_month desc, terms.status)
      from (
        select term.service_month, term.status, pg_catalog.count(*)::integer as term_count
        from public.admin_terms as term
        where term.service_month is not null
          and term.service_month >= (
            pg_catalog.timezone('Asia/Shanghai', pg_catalog.now())::date - interval '11 months'
          )::date
        group by term.service_month, term.status
      ) as terms
    ), '[]'::jsonb),
    'decisions', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'month_start', decisions.month_start,
        'action', decisions.action,
        'decision_count', decisions.decision_count
      ) order by decisions.month_start desc, decisions.action)
      from (
        select pg_catalog.date_trunc('month', decision.created_at)::date as month_start,
          decision.action, pg_catalog.count(*)::integer as decision_count
        from public.admin_review_decisions as decision
        where decision.created_at >= pg_catalog.date_trunc('month', pg_catalog.now()) - interval '11 months'
        group by 1, decision.action
      ) as decisions
    ), '[]'::jsonb),
    'eligible_backlog_count', (
      select pg_catalog.count(*)::integer
      from private_db2.low_risk_clothes_candidates(p_user_id)
    )
  );
$$;

revoke all on function private_db2.lv4_governance_stats(uuid)
  from public, anon, authenticated, service_role;

create function public.get_my_level_benefits()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_result jsonb;
  v_term private_db2.monthly_lv4_experience_terms%rowtype;
  v_cumulative_level smallint;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = '需要登录后才能查看等级权益';
  end if;

  v_result := private_db2.cumulative_level_benefits();
  v_cumulative_level := (v_result->>'level')::smallint;

  select term.* into v_term
  from private_db2.monthly_lv4_experience_terms as term
  where term.id = private_db2.active_monthly_lv4_experience_id(
    v_user_id,
    pg_catalog.now()
  );

  if found then
    v_result := v_result || pg_catalog.jsonb_build_object(
      'bonus_per_event', 5,
      'vote_weight', 3,
      'governance_stats', case
        when v_result->'governance_stats' = 'null'::jsonb
          then private_db2.lv4_governance_stats(v_user_id)
        else v_result->'governance_stats'
      end,
      'monthly_lv4_experience', pg_catalog.jsonb_build_object(
        'source_month', v_term.source_month,
        'service_month', v_term.service_month,
        'starts_at', v_term.starts_at,
        'scheduled_end_at', v_term.scheduled_end_at,
        'temporarily_applied', v_cumulative_level < 4
      )
    );
  else
    v_result := v_result || pg_catalog.jsonb_build_object(
      'monthly_lv4_experience', null
    );
  end if;

  return v_result;
end;
$$;

revoke all on function public.get_my_level_benefits()
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_level_benefits()
  to authenticated, service_role;

-- 首次启用时，若上月榜已冻结，则为当前这个“次月”立即建立剩余有效期资格；
-- 不追补部署前已经发生的积分或投票事件。
select private_db2.refresh_monthly_lv4_experiences(pg_catalog.now());

comment on table private_db2.monthly_lv4_experience_terms is
  '上月冻结榜 dense-rank 第一名在次月获得的独立、可审计 Lv4 三项体验资格；不承载累计等级或管理员权限。';
comment on column private_db2.monthly_lv4_experience_terms.scheduled_end_at is
  '北京时间次月月初即自然失效；reclaimed_at 只补记回收审计，不参与权限判断。';
comment on function private_db2.refresh_monthly_lv4_experiences(timestamptz) is
  '月榜冻结后的幂等授予与到期审计；并列第一全部授予，注销账号跳过。';
comment on function private_db2.active_monthly_lv4_experience_id(uuid, timestamptz) is
  '只按独立资格窗口判断三项 Lv4 体验，不读取或修改累计等级、管理员任期和候选资格。';
comment on function public.get_my_level_benefits() is
  '返回累计等级分级数据，并单独叠加有效月榜首 Lv4 奖励、票权和治理统计体验；管理员候选仍只按累计等级。';
comment on column public.points_ledger.level_snapshot is
  '积分事件发生前的权益快照；通常为累计等级，有效月榜首体验期间三类业务事件冻结为 Lv4。';
comment on column public.jury_votes.vote_weight is
  '首次投票时冻结累计等级或有效月榜首体验对应的票权；历史投票不追改。';

commit;
