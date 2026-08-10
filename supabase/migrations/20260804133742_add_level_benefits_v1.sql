begin;

-- 等级计算只依赖权威积分流水。私有状态是可从流水重建的并发辅助缓存，
-- 用于在同一用户并发获得奖励时串行取得“奖励发生前”的准确等级。
create table private_db2.user_points_state (
  user_id uuid primary key references auth.users (id) on delete cascade,
  total_points bigint not null default 0,
  updated_at timestamptz not null default pg_catalog.now()
);

alter table private_db2.user_points_state enable row level security;
alter table private_db2.user_points_state force row level security;

revoke all on table private_db2.user_points_state
  from public, anon, authenticated, service_role;

insert into private_db2.user_points_state (user_id, total_points)
select ledger.user_id, coalesce(pg_catalog.sum(ledger.delta), 0)::bigint
from public.points_ledger as ledger
where ledger.user_id is not null
  and ledger.status = 'awarded'
group by ledger.user_id;

create function private_db2.level_for_points(p_total_points bigint)
returns smallint
language sql
immutable
set search_path = ''
as $$
  select case
    when greatest(coalesce(p_total_points, 0), 0) >= 10000 then 4
    when greatest(coalesce(p_total_points, 0), 0) >= 5000 then 3
    when greatest(coalesce(p_total_points, 0), 0) >= 2000 then 2
    when greatest(coalesce(p_total_points, 0), 0) >= 500 then 1
    else 0
  end::smallint;
$$;

create function private_db2.level_bonus_for_level(p_level smallint)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case p_level
    when 1 then 1
    when 2 then 2
    when 3 then 3
    when 4 then 5
    else 0
  end;
$$;

create function private_db2.vote_weight_for_level(p_level smallint)
returns smallint
language sql
immutable
set search_path = ''
as $$
  select case
    when p_level >= 4 then 3
    when p_level >= 2 then 2
    else 1
  end::smallint;
$$;

revoke all on function private_db2.level_for_points(bigint)
  from public, anon, authenticated, service_role;
revoke all on function private_db2.level_bonus_for_level(smallint)
  from public, anon, authenticated, service_role;
revoke all on function private_db2.vote_weight_for_level(smallint)
  from public, anon, authenticated, service_role;

alter table public.points_ledger
  add column bonus_of uuid,
  add column level_snapshot smallint;

alter table public.points_ledger
  add constraint points_ledger_bonus_of_fkey
    foreign key (bonus_of)
    references public.points_ledger (id)
    on delete restrict,
  add constraint points_ledger_level_snapshot_check
    check (level_snapshot is null or level_snapshot between 0 and 4);

create unique index points_ledger_bonus_of_key
  on public.points_ledger (bonus_of)
  where bonus_of is not null;

alter table public.points_ledger
  drop constraint points_ledger_source_type_check,
  drop constraint points_ledger_entry_shape_check;

alter table public.points_ledger
  add constraint points_ledger_source_type_check
    check (source_type in (
      'clothing_contribution',
      're_review_candidate',
      'jury_vote',
      'correction_request',
      'level_bonus',
      'reversal'
    )),
  add constraint points_ledger_entry_shape_check
    check (
      (
        source_type = 'clothing_contribution'
        and source_id is not null
        and re_review_candidate_id is null
        and jury_vote_id is null
        and correction_request_id is null
        and bonus_of is null
        and reversal_of is null
        and delta > 0
      )
      or (
        source_type = 're_review_candidate'
        and source_id is null
        and re_review_candidate_id is not null
        and jury_vote_id is null
        and correction_request_id is null
        and bonus_of is null
        and reversal_of is null
        and delta > 0
      )
      or (
        source_type = 'jury_vote'
        and source_id is null
        and re_review_candidate_id is null
        and jury_vote_id is not null
        and correction_request_id is null
        and bonus_of is null
        and reversal_of is null
        and delta = 1
      )
      or (
        source_type = 'correction_request'
        and source_id is null
        and re_review_candidate_id is null
        and jury_vote_id is null
        and correction_request_id is not null
        and bonus_of is null
        and reversal_of is null
        and delta = 5
      )
      or (
        source_type = 'level_bonus'
        and source_id is null
        and re_review_candidate_id is null
        and jury_vote_id is null
        and correction_request_id is null
        and bonus_of is not null
        and reversal_of is null
        and level_snapshot between 1 and 4
        and delta = private_db2.level_bonus_for_level(level_snapshot)
      )
      or (
        source_type = 'reversal'
        and source_id is null
        and re_review_candidate_id is null
        and jury_vote_id is null
        and correction_request_id is null
        and bonus_of is null
        and reversal_of is not null
        and delta < 0
      )
    );

create function private_db2.prepare_points_ledger_entry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_total_after bigint;
  v_total_before bigint;
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

  -- BEFORE trigger 必须先识别业务幂等重试；否则 INSERT ... ON CONFLICT DO NOTHING
  -- 虽然不会新增流水，却会把并发缓存重复加分。
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
    new.level_snapshot := private_db2.level_for_points(v_total_before);
  elsif new.source_type <> 'level_bonus' then
    new.level_snapshot := null;
  end if;

  return new;
end;
$$;

create function private_db2.append_level_bonus_or_reversal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bonus public.points_ledger%rowtype;
  v_bonus_delta integer;
begin
  if new.source_type in ('clothing_contribution', 're_review_candidate', 'correction_request') then
    v_bonus_delta := private_db2.level_bonus_for_level(new.level_snapshot);
    if v_bonus_delta > 0 then
      insert into public.points_ledger (
        user_id, delta, status, source_type, bonus_of, level_snapshot, occurred_at
      ) values (
        new.user_id, v_bonus_delta, 'awarded', 'level_bonus', new.id,
        new.level_snapshot, new.occurred_at
      )
      on conflict (bonus_of) where bonus_of is not null do nothing;
    end if;
  elsif new.source_type = 'reversal' then
    select bonus.* into v_bonus
    from public.points_ledger as bonus
    where bonus.bonus_of = new.reversal_of
      and bonus.source_type = 'level_bonus';

    if found then
      insert into public.points_ledger (
        user_id, delta, status, source_type, reversal_of, occurred_at
      ) values (
        v_bonus.user_id, -v_bonus.delta, 'awarded', 'reversal', v_bonus.id,
        new.occurred_at
      )
      on conflict (reversal_of) where reversal_of is not null do nothing;
    end if;
  end if;

  return null;
end;
$$;

revoke all on function private_db2.prepare_points_ledger_entry()
  from public, anon, authenticated, service_role;
revoke all on function private_db2.append_level_bonus_or_reversal()
  from public, anon, authenticated, service_role;

create trigger points_ledger_prepare_level_snapshot
before insert on public.points_ledger
for each row execute function private_db2.prepare_points_ledger_entry();

create trigger points_ledger_append_level_bonus
after insert on public.points_ledger
for each row execute function private_db2.append_level_bonus_or_reversal();

alter table public.jury_votes
  add column voter_level smallint not null default 0,
  add column vote_weight smallint not null default 1,
  add column review_note varchar(200);

alter table public.jury_votes
  add constraint jury_votes_voter_level_check check (voter_level between 0 and 4),
  add constraint jury_votes_vote_weight_check check (vote_weight between 1 and 3),
  add constraint jury_votes_review_note_check check (
    review_note is null
    or (
      voter_level >= 2
      and nullif(pg_catalog.btrim(review_note), '') is not null
      and pg_catalog.char_length(review_note) <= 200
    )
  );

drop function public.cast_jury_vote(uuid, text);

create function public.cast_jury_vote(
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
  v_user_level smallint;
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
  into v_user_level
  from public.points_ledger as ledger
  where ledger.user_id = v_user_id
    and ledger.status = 'awarded';
  v_vote_weight := private_db2.vote_weight_for_level(v_user_level);

  if v_review_note is not null and v_user_level < 2 then
    raise exception using errcode = '42501', message = 'Lv2 及以上才能提交复核意见';
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
      v_candidate.id, v_user_id, p_vote, v_user_level, v_vote_weight, v_review_note
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
    v_existing_level := v_user_level;
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

-- 保留旧的二参数 RPC 签名，现有客户端和既有验收脚本无需同步切换；
-- 新客户端只有在提交复核意见时才调用三参数签名。
create function public.cast_jury_vote(
  p_candidate_id uuid,
  p_vote text
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select public.cast_jury_vote(p_candidate_id, p_vote, null);
$$;

revoke all on function public.cast_jury_vote(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.cast_jury_vote(uuid, text)
  to authenticated, service_role;

create or replace function public.get_jury_review_queue_with_evidence()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_user_level smallint;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception '需要登录后才能查看陪审团';
  end if;

  select private_db2.level_for_points(coalesce(pg_catalog.sum(ledger.delta), 0))
  into v_user_level
  from public.points_ledger as ledger
  where ledger.user_id = v_user_id
    and ledger.status = 'awarded';

  select coalesce(
    pg_catalog.jsonb_agg(
      queue.item || pg_catalog.jsonb_build_object(
        'correction_evidence', coalesce(evidence.items, '[]'::jsonb),
        'approve_weight', coalesce(vote_stats.approve_weight, 0),
        'reject_weight', coalesce(vote_stats.reject_weight, 0),
        'review_opinions', coalesce(vote_stats.review_opinions, '[]'::jsonb),
        'can_submit_review_note',
          v_user_level >= 2 and coalesce((queue.item->>'can_vote')::boolean, false),
        'current_user_level', v_user_level
      )
      order by queue.ordinality
    ),
    '[]'::jsonb
  ) into v_result
  from pg_catalog.jsonb_array_elements(public.get_jury_review_queue())
    with ordinality as queue(item, ordinality)
  left join lateral (
    select pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'request_id', request.id,
        'field_key', request.field_key,
        'evidence_image_path', request.evidence_image_path
      ) order by request.created_at, request.id
    ) as items
    from public.correction_requests as request
    where request.re_review_item_id = (queue.item->>'re_review_item_id')::uuid
      and request.evidence_image_path is not null
  ) as evidence on true
  left join lateral (
    select
      coalesce(pg_catalog.sum(vote.vote_weight) filter (where vote.vote = 'approve'), 0)::integer as approve_weight,
      coalesce(pg_catalog.sum(vote.vote_weight) filter (where vote.vote = 'reject'), 0)::integer as reject_weight,
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'voter_level', vote.voter_level,
          'vote', vote.vote,
          'review_note', vote.review_note
        ) order by vote.created_at, vote.id
      ) filter (where vote.review_note is not null) as review_opinions
    from public.jury_votes as vote
    where vote.candidate_id = nullif(queue.item->>'candidate_id', '')::uuid
  ) as vote_stats on true;

  return v_result;
end;
$$;

revoke all on function public.get_jury_review_queue_with_evidence()
  from public, anon, authenticated, service_role;
grant execute on function public.get_jury_review_queue_with_evidence()
  to authenticated, service_role;

-- 公开贡献者继续按既有时间规则排序，只增加等级快照供前端做署名和视觉强调。
drop view public.clothing_contributors_public;
drop function private_db2.public_initial_contributors();

create function private_db2.public_initial_contributors()
returns table (
  clothes_id character varying,
  contribution_rank smallint,
  display_name text,
  contributed_at timestamptz,
  contributor_level smallint
)
language sql
stable
security definer
set search_path = ''
as $$
  with points_by_user as (
    select ledger.user_id, coalesce(pg_catalog.sum(ledger.delta), 0)::bigint as total_points
    from public.points_ledger as ledger
    where ledger.user_id is not null and ledger.status = 'awarded'
    group by ledger.user_id
  ), ranked_contributors as (
    select
      contribution.clothes_id,
      pg_catalog.row_number() over (
        partition by contribution.clothes_id
        order by contribution.source_created_at, contribution.contribution_rank,
          contribution.created_at, contribution.id
      ) as stable_rank,
      case
        when contribution.user_id is null then '已注销用户'
        when nullif(pg_catalog.btrim(profile.username), '') is not null
          then pg_catalog.btrim(profile.username)
        else '匿名贡献者-' || pg_catalog.substr(pg_catalog.md5(contribution.user_id::text), 1, 8)
      end as display_name,
      contribution.source_created_at as contributed_at,
      case when contribution.user_id is null then 0::smallint
        else private_db2.level_for_points(coalesce(points.total_points, 0))
      end as contributor_level
    from public.clothing_contributions as contribution
    left join public.profiles as profile on profile.id = contribution.user_id
    left join points_by_user as points on points.user_id = contribution.user_id
    where contribution.contribution_type in ('auto_entry', 'admin_arbitration')
  )
  select ranked.clothes_id, ranked.stable_rank::smallint,
    ranked.display_name, ranked.contributed_at, ranked.contributor_level
  from ranked_contributors as ranked
  where ranked.stable_rank <= 3;
$$;

revoke all on function private_db2.public_initial_contributors()
  from public, anon, authenticated, service_role;
grant execute on function private_db2.public_initial_contributors()
  to anon, authenticated;

create view public.clothing_contributors_public
with (security_invoker = true, security_barrier = true)
as
select result.clothes_id, result.contribution_rank, result.display_name,
  result.contributed_at, result.contributor_level
from private_db2.public_initial_contributors() as result;

revoke all on table public.clothing_contributors_public
  from public, anon, authenticated, service_role;
grant select on table public.clothing_contributors_public
  to anon, authenticated;

-- 排行榜分数仍按各自周期排序，等级始终来自当前累计积分。
drop view public.points_leaderboard_total;
drop view public.points_leaderboard_current_month;
drop view public.points_leaderboard_last_month;
drop function private_db2.total_points_leaderboard();
drop function private_db2.current_month_points_leaderboard();
drop function private_db2.last_month_points_leaderboard();

create function private_db2.total_points_leaderboard()
returns table (
  leaderboard_rank bigint,
  display_name text,
  points bigint,
  current_level smallint,
  is_current_user boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with scored as (
    select ledger.user_id, pg_catalog.sum(ledger.delta)::bigint as points
    from public.points_ledger as ledger
    where ledger.status = 'awarded' and ledger.user_id is not null
      and (select auth.uid()) is not null
    group by ledger.user_id
  ), ranked as (
    select scored.user_id, scored.points,
      pg_catalog.dense_rank() over (order by scored.points desc) as leaderboard_rank
    from scored
  )
  select ranked.leaderboard_rank,
    case
      when nullif(pg_catalog.btrim(profile.username), '') is not null
        then pg_catalog.btrim(profile.username)
      else '匿名搭配师-' || pg_catalog.upper(
        pg_catalog.substr(pg_catalog.md5(ranked.user_id::text), 1, 8)
      )
    end,
    ranked.points,
    private_db2.level_for_points(ranked.points),
    ranked.user_id = (select auth.uid())
  from ranked
  left join public.profiles as profile on profile.id = ranked.user_id
  order by ranked.leaderboard_rank, ranked.user_id;
$$;

create function private_db2.current_month_points_leaderboard()
returns table (
  leaderboard_rank bigint,
  display_name text,
  points bigint,
  current_level smallint,
  is_current_user boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with month_boundary as (
    select
      (pg_catalog.date_trunc(
      'month', pg_catalog.timezone('Asia/Shanghai', pg_catalog.now())
      ) at time zone 'Asia/Shanghai') as starts_at,
      ((pg_catalog.date_trunc(
        'month', pg_catalog.timezone('Asia/Shanghai', pg_catalog.now())
      ) + interval '1 month') at time zone 'Asia/Shanghai') as ends_at
  ), totals as (
    select ledger.user_id, pg_catalog.sum(ledger.delta)::bigint as total_points
    from public.points_ledger as ledger
    where ledger.status = 'awarded' and ledger.user_id is not null
    group by ledger.user_id
  ), scored as (
    select ledger.user_id, pg_catalog.sum(ledger.delta)::bigint as points
    from public.points_ledger as ledger cross join month_boundary
    where ledger.status = 'awarded' and ledger.user_id is not null
      and ledger.occurred_at >= month_boundary.starts_at
      and ledger.occurred_at < month_boundary.ends_at
      and (select auth.uid()) is not null
    group by ledger.user_id
  ), ranked as (
    select scored.user_id, scored.points,
      pg_catalog.dense_rank() over (order by scored.points desc) as leaderboard_rank
    from scored
  )
  select ranked.leaderboard_rank,
    case
      when nullif(pg_catalog.btrim(profile.username), '') is not null
        then pg_catalog.btrim(profile.username)
      else '匿名搭配师-' || pg_catalog.upper(
        pg_catalog.substr(pg_catalog.md5(ranked.user_id::text), 1, 8)
      )
    end,
    ranked.points,
    private_db2.level_for_points(coalesce(totals.total_points, 0)),
    ranked.user_id = (select auth.uid())
  from ranked
  left join totals on totals.user_id = ranked.user_id
  left join public.profiles as profile on profile.id = ranked.user_id
  order by ranked.leaderboard_rank, ranked.user_id;
$$;

create function private_db2.last_month_points_leaderboard()
returns table (
  leaderboard_rank bigint,
  display_name text,
  points bigint,
  current_level smallint,
  is_current_user boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with target_month as (
    select (pg_catalog.date_trunc(
      'month', pg_catalog.timezone('Asia/Shanghai', pg_catalog.now())
    ) - interval '1 month')::date as month_start
  ), totals as (
    select ledger.user_id, pg_catalog.sum(ledger.delta)::bigint as total_points
    from public.points_ledger as ledger
    where ledger.status = 'awarded' and ledger.user_id is not null
    group by ledger.user_id
  )
  select snapshot.leaderboard_rank,
    case
      when snapshot.user_id is null then '已注销用户'
      when nullif(pg_catalog.btrim(profile.username), '') is not null
        then pg_catalog.btrim(profile.username)
      else '匿名搭配师-' || pg_catalog.upper(
        pg_catalog.substr(pg_catalog.md5(snapshot.user_id::text), 1, 8)
      )
    end,
    snapshot.points,
    private_db2.level_for_points(coalesce(totals.total_points, 0)),
    snapshot.user_id = (select auth.uid())
  from private_db2.points_leaderboard_monthly_snapshots as snapshot
  cross join target_month
  left join totals on totals.user_id = snapshot.user_id
  left join public.profiles as profile on profile.id = snapshot.user_id
  where snapshot.month_start = target_month.month_start
    and (select auth.uid()) is not null
  order by snapshot.leaderboard_rank, snapshot.id;
$$;

revoke all on function private_db2.total_points_leaderboard()
  from public, anon, authenticated, service_role;
revoke all on function private_db2.current_month_points_leaderboard()
  from public, anon, authenticated, service_role;
revoke all on function private_db2.last_month_points_leaderboard()
  from public, anon, authenticated, service_role;
grant execute on function private_db2.total_points_leaderboard() to authenticated;
grant execute on function private_db2.current_month_points_leaderboard() to authenticated;
grant execute on function private_db2.last_month_points_leaderboard() to authenticated;

create view public.points_leaderboard_total
with (security_invoker = true, security_barrier = true)
as select result.leaderboard_rank, result.display_name, result.points,
  result.current_level, result.is_current_user
from private_db2.total_points_leaderboard() as result;

create view public.points_leaderboard_current_month
with (security_invoker = true, security_barrier = true)
as select result.leaderboard_rank, result.display_name, result.points,
  result.current_level, result.is_current_user
from private_db2.current_month_points_leaderboard() as result;

create view public.points_leaderboard_last_month
with (security_invoker = true, security_barrier = true)
as select result.leaderboard_rank, result.display_name, result.points,
  result.current_level, result.is_current_user
from private_db2.last_month_points_leaderboard() as result;

revoke all on table public.points_leaderboard_total
  from public, anon, authenticated, service_role;
revoke all on table public.points_leaderboard_current_month
  from public, anon, authenticated, service_role;
revoke all on table public.points_leaderboard_last_month
  from public, anon, authenticated, service_role;
grant select on table public.points_leaderboard_total to authenticated;
grant select on table public.points_leaderboard_current_month to authenticated;
grant select on table public.points_leaderboard_last_month to authenticated;

alter table private_db2.admin_rotation_candidates
  add column level_at_snapshot smallint;

alter table private_db2.admin_rotation_candidates
  add constraint admin_rotation_candidates_level_check
    check (level_at_snapshot is null or level_at_snapshot between 0 and 4);

create or replace function private_db2.fill_monthly_admin_vacancies(p_service_month date)
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

  select greatest(5 - pg_catalog.count(*)::integer, 0)
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
      and candidate.level_at_snapshot >= 2
      and candidate.qualifying_action_count >= 5
      and not (coalesce(profile.role_level, 0) = 2 or profile.role = 'super_admin')
      and not exists (
        select 1 from public.admin_terms as prior
        where prior.source = 'monthly' and prior.service_month = p_service_month
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
  select available.user_id, 'monthly', available.service_month, available.source_month,
    available.candidate_order, available.frozen_points,
    available.qualifying_action_count, v_starts_at, v_ends_at
  from available
  on conflict (service_month, user_id) where source = 'monthly' do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$$;

create or replace function private_db2.rotate_monthly_admins_if_due(
  p_run_at timestamptz default pg_catalog.now()
)
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
      select v_source_month::timestamp at time zone 'Asia/Shanghai' as starts_at,
        v_service_month::timestamp at time zone 'Asia/Shanghai' as ends_at
    ), actions as (
      select ledger.user_id, pg_catalog.count(*)::integer as action_count,
        pg_catalog.max(ledger.occurred_at) as last_action_at
      from public.points_ledger as ledger cross join boundary
      where ledger.status = 'awarded' and ledger.delta > 0
        and ledger.source_type <> 'level_bonus'
        and ledger.user_id is not null
        and ledger.occurred_at >= boundary.starts_at
        and ledger.occurred_at < boundary.ends_at
      group by ledger.user_id
    ), cumulative as (
      select ledger.user_id, coalesce(pg_catalog.sum(ledger.delta), 0)::bigint as total_points
      from public.points_ledger as ledger cross join boundary
      where ledger.status = 'awarded' and ledger.user_id is not null
        and ledger.occurred_at < boundary.ends_at
      group by ledger.user_id
    ), source as (
      select snapshot.user_id, snapshot.points,
        coalesce(actions.action_count, 0) as action_count,
        coalesce(actions.last_action_at, snapshot.frozen_at) as last_action_at,
        private_db2.level_for_points(coalesce(cumulative.total_points, 0)) as level_at_snapshot,
        profile.role, profile.role_level, account.id is not null as account_exists,
        exists (
          select 1 from public.admin_terms as term
          where term.user_id = snapshot.user_id and term.status = 'active'
            and term.starts_at < (v_service_month + interval '1 month')::timestamp at time zone 'Asia/Shanghai'
            and term.scheduled_end_at > v_service_month::timestamp at time zone 'Asia/Shanghai'
        ) as has_term,
        exists (
          select 1 from public.admin_candidate_exclusions as exclusion
          where exclusion.user_id = snapshot.user_id and exclusion.revoked_at is null
            and exclusion.starts_at < (v_service_month + interval '1 month')::timestamp at time zone 'Asia/Shanghai'
            and exclusion.ends_at > v_service_month::timestamp at time zone 'Asia/Shanghai'
        ) as excluded
      from private_db2.points_leaderboard_monthly_snapshots as snapshot
      left join actions on actions.user_id = snapshot.user_id
      left join cumulative on cumulative.user_id = snapshot.user_id
      left join auth.users as account on account.id = snapshot.user_id
      left join public.profiles as profile on profile.id = snapshot.user_id
      where snapshot.month_start = v_source_month and snapshot.user_id is not null
    ), ranked as (
      select source.*, pg_catalog.row_number() over (
        order by source.points desc, source.action_count desc,
          source.last_action_at asc, source.user_id asc
      )::integer as candidate_order
      from source
    )
    insert into private_db2.admin_rotation_candidates (
      service_month, source_month, user_id, frozen_points,
      qualifying_action_count, tie_break_at, candidate_order,
      eligibility_status, skip_reason, level_at_snapshot
    )
    select v_service_month, v_source_month, ranked.user_id, ranked.points,
      ranked.action_count, ranked.last_action_at, ranked.candidate_order,
      case when ranked.account_exists and ranked.level_at_snapshot >= 2
        and ranked.action_count >= 5
        and not (coalesce(ranked.role_level, 0) = 2 or ranked.role = 'super_admin')
        and not ranked.has_term and not ranked.excluded
        then 'eligible' else 'skipped' end,
      case
        when not ranked.account_exists then '账号已注销'
        when ranked.level_at_snapshot < 2 then '冻结时等级低于 Lv2'
        when ranked.action_count < 5 then '上月有效行为不足 5 次'
        when coalesce(ranked.role_level, 0) = 2 or ranked.role = 'super_admin' then '超级管理员不参与轮换'
        when ranked.has_term then '已有有效管理员任期'
        when ranked.excluded then '命中有效候选排除'
        else null
      end,
      ranked.level_at_snapshot
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

revoke all on function private_db2.fill_monthly_admin_vacancies(date)
  from public, anon, authenticated, service_role;
revoke all on function private_db2.rotate_monthly_admins_if_due(timestamptz)
  from public, anon, authenticated, service_role;

create or replace function public.list_admin_governance()
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
        'reviewer_display_name', coalesce(
          nullif(pg_catalog.btrim(reviewer.username), ''),
          nullif(pg_catalog.btrim(reviewer.nickname), ''),
          '已注销管理员'
        ),
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
    ), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

comment on function public.list_admin_governance() is
  '超级管理员治理读模型，候选包含冻结等级，不暴露邮箱。';

create function public.get_my_level_benefits()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_total_points bigint;
  v_level smallint;
  v_since timestamptz;
  v_points_entries jsonb := null;
  v_contributions jsonb := null;
  v_votes jsonb := null;
  v_community_stats jsonb := null;
  v_governance_stats jsonb := null;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = '需要登录后才能查看等级权益';
  end if;

  select coalesce(pg_catalog.sum(ledger.delta), 0)::bigint into v_total_points
  from public.points_ledger as ledger
  where ledger.user_id = v_user_id and ledger.status = 'awarded';
  v_level := private_db2.level_for_points(v_total_points);

  if v_level >= 1 then
    select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'occurred_at', entry.occurred_at,
      'delta', entry.delta,
      'source_type', entry.source_type,
      'level_snapshot', entry.level_snapshot,
      'is_level_bonus', entry.source_type = 'level_bonus',
      'is_reversal', entry.source_type = 'reversal'
    ) order by entry.occurred_at desc, entry.created_at desc), '[]'::jsonb)
    into v_points_entries
    from (
      select ledger.occurred_at, ledger.created_at, ledger.delta,
        ledger.source_type, ledger.level_snapshot
      from public.points_ledger as ledger
      where ledger.user_id = v_user_id and ledger.status = 'awarded'
      order by ledger.occurred_at desc, ledger.created_at desc, ledger.id desc
      limit 100
    ) as entry;
  end if;

  if v_level >= 2 then
    select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'clothes_name', entry.clothes_name,
      'category', entry.category,
      'contribution_type', entry.contribution_type,
      'contribution_rank', entry.contribution_rank,
      'contributed_at', entry.contributed_at
    ) order by entry.contributed_at desc), '[]'::jsonb)
    into v_contributions
    from (
      select coalesce(clothes.name, '已删除服装') as clothes_name,
        coalesce(clothes.category, '') as category,
        contribution.contribution_type, contribution.contribution_rank,
        contribution.source_created_at as contributed_at
      from public.clothing_contributions as contribution
      left join public.clothes as clothes on clothes.id = contribution.clothes_id
      where contribution.user_id = v_user_id
      order by contribution.source_created_at desc, contribution.id desc
      limit 100
    ) as entry;

    select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'clothes_name', entry.clothes_name,
      'vote', entry.vote,
      'vote_weight', entry.vote_weight,
      'voter_level', entry.voter_level,
      'review_note', entry.review_note,
      'candidate_status', entry.candidate_status,
      'created_at', entry.created_at
    ) order by entry.created_at desc), '[]'::jsonb)
    into v_votes
    from (
      select coalesce(clothes.name, '已删除服装') as clothes_name,
        vote.vote, vote.vote_weight, vote.voter_level, vote.review_note,
        candidate.status as candidate_status, vote.created_at
      from public.jury_votes as vote
      join public.re_review_candidates as candidate on candidate.id = vote.candidate_id
      join public.re_review_items as item on item.id = candidate.re_review_item_id
      left join public.clothes as clothes on clothes.id = item.clothes_id
      where vote.user_id = v_user_id
      order by vote.created_at desc, vote.id desc
      limit 100
    ) as entry;

    v_since := case when v_level >= 3
      then pg_catalog.date_trunc('month', pg_catalog.now()) - interval '11 months'
      else pg_catalog.date_trunc('month', pg_catalog.now())
    end;

    select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'month_start', stats.month_start,
      'reason', stats.reason,
      'outcome', stats.outcome,
      'item_count', stats.item_count
    ) order by stats.month_start desc, stats.reason, stats.outcome), '[]'::jsonb)
    into v_community_stats
    from (
      select pg_catalog.date_trunc('month', candidate.resolved_at)::date as month_start,
        item.reason, candidate.status as outcome, pg_catalog.count(*)::integer as item_count
      from public.re_review_candidates as candidate
      join public.re_review_items as item on item.id = candidate.re_review_item_id
      where candidate.resolved_at >= v_since
        and candidate.status in ('approved', 'returned', 'rejected')
      group by 1, item.reason, candidate.status
    ) as stats;
  end if;

  if v_level >= 4 then
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
            and term.service_month >= (current_date - interval '11 months')::date
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
        from private_db2.low_risk_clothes_candidates(v_user_id)
      )
    ) into v_governance_stats;
  end if;

  return pg_catalog.jsonb_build_object(
    'level', v_level,
    'total_points', v_total_points,
    'bonus_per_event', private_db2.level_bonus_for_level(v_level),
    'vote_weight', private_db2.vote_weight_for_level(v_level),
    'can_submit_review_note', v_level >= 2,
    'admin_candidate_eligible', v_level >= 2,
    'points_entries', v_points_entries,
    'contributions', v_contributions,
    'votes', v_votes,
    'community_stats', v_community_stats,
    'governance_stats', v_governance_stats
  );
end;
$$;

revoke all on function public.get_my_level_benefits()
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_level_benefits()
  to authenticated, service_role;

comment on table private_db2.user_points_state is
  '等级奖励并发辅助缓存；可从 points_ledger 重建，不是积分权威来源。';
comment on column public.points_ledger.bonus_of is
  '等级奖励流水关联的唯一基础正向积分流水；历史积分不追补。';
comment on column public.points_ledger.level_snapshot is
  '积分事件发生前的等级快照；等级奖励按该快照计算。';
comment on column public.jury_votes.vote_weight is
  '首次投票时按奖励前累计积分冻结的票权；历史投票保持 1。';
comment on column public.jury_votes.review_note is
  'Lv2 及以上首次投票时可提交、不可修改的匿名复核意见，最多 200 字。';
comment on function public.get_my_level_benefits() is
  '按当前等级返回本人可见积分、贡献、投票及匿名统计；不返回其他用户身份或私密证据。';

commit;
