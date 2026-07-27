begin;

alter table public.re_review_candidates
  add column status text not null default 'voting',
  add column resolved_at timestamptz;

alter table public.re_review_candidates
  add constraint re_review_candidates_status_check
  check (status in ('voting', 'approved', 'returned', 'rejected'));

drop index public.re_review_candidates_item_key;

create unique index re_review_candidates_active_item_key
  on public.re_review_candidates (re_review_item_id)
  where status = 'voting';

create index re_review_candidates_item_created_at_idx
  on public.re_review_candidates (re_review_item_id, created_at desc);

update public.re_review_items as item
set
  status = 'voting',
  updated_at = pg_catalog.now(),
  resolved_by = null,
  resolved_at = null
where item.status in ('pending', 'failed')
  and exists (
    select 1
    from public.re_review_candidates as candidate
    where candidate.re_review_item_id = item.id
      and candidate.status = 'voting'
  );

drop policy "登录用户可为未参与重审项提交候选修正版"
  on public.re_review_candidates;

revoke insert (re_review_item_id, payload, submitted_by)
  on table public.re_review_candidates
  from authenticated;

create table public.jury_votes (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null,
  user_id uuid,
  vote text not null,
  created_at timestamptz not null default now(),

  constraint jury_votes_candidate_id_fkey
    foreign key (candidate_id)
    references public.re_review_candidates (id)
    on delete restrict,
  constraint jury_votes_user_id_fkey
    foreign key (user_id)
    references auth.users (id)
    on delete set null,
  constraint jury_votes_vote_check
    check (vote in ('approve', 'reject')),
  constraint jury_votes_candidate_user_key
    unique (candidate_id, user_id)
);

create index jury_votes_user_created_at_idx
  on public.jury_votes (user_id, created_at desc)
  where user_id is not null;

create table public.jury_admin_decisions (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null,
  re_review_item_id uuid not null,
  admin_user_id uuid,
  decision text not null,
  reason text not null,
  created_at timestamptz not null default now(),

  constraint jury_admin_decisions_candidate_id_fkey
    foreign key (candidate_id)
    references public.re_review_candidates (id)
    on delete restrict,
  constraint jury_admin_decisions_item_id_fkey
    foreign key (re_review_item_id)
    references public.re_review_items (id)
    on delete restrict,
  constraint jury_admin_decisions_admin_user_id_fkey
    foreign key (admin_user_id)
    references auth.users (id)
    on delete set null,
  constraint jury_admin_decisions_candidate_key
    unique (candidate_id),
  constraint jury_admin_decisions_decision_check
    check (decision = 'rejected'),
  constraint jury_admin_decisions_reason_check
    check (nullif(pg_catalog.btrim(reason), '') is not null)
);

create index jury_admin_decisions_item_created_at_idx
  on public.jury_admin_decisions (re_review_item_id, created_at desc);

alter table public.jury_votes enable row level security;
alter table public.jury_admin_decisions enable row level security;

revoke all on table public.jury_votes
  from public, anon, authenticated, service_role;
revoke all on table public.jury_admin_decisions
  from public, anon, authenticated, service_role;

grant select, insert on table public.jury_votes to service_role;
grant select, insert on table public.jury_admin_decisions to service_role;

alter table public.points_ledger
  add column re_review_candidate_id uuid;

alter table public.points_ledger
  add constraint points_ledger_re_review_candidate_id_fkey
  foreign key (re_review_candidate_id)
  references public.re_review_candidates (id)
  on delete restrict;

alter table public.points_ledger
  drop constraint points_ledger_source_type_check,
  drop constraint points_ledger_entry_shape_check;

alter table public.points_ledger
  add constraint points_ledger_source_type_check
    check (source_type in ('clothing_contribution', 're_review_candidate', 'reversal')),
  add constraint points_ledger_entry_shape_check
    check (
      (
        source_type = 'clothing_contribution'
        and source_id is not null
        and re_review_candidate_id is null
        and reversal_of is null
        and delta > 0
      )
      or
      (
        source_type = 're_review_candidate'
        and source_id is null
        and re_review_candidate_id is not null
        and reversal_of is null
        and delta > 0
      )
      or
      (
        source_type = 'reversal'
        and source_id is null
        and re_review_candidate_id is null
        and reversal_of is not null
        and delta < 0
      )
    );

create unique index points_ledger_re_review_candidate_id_key
  on public.points_ledger (re_review_candidate_id)
  where re_review_candidate_id is not null;

create or replace function public.submit_jury_candidate(
  p_re_review_item_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_item public.re_review_items%rowtype;
  v_candidate public.re_review_candidates%rowtype;
  v_suit_id uuid;
begin
  if v_user_id is null then
    raise exception '需要登录后才能提交陪审团候选';
  end if;

  if p_payload is null
    or pg_catalog.jsonb_typeof(p_payload) <> 'object'
    or p_payload = '{}'::jsonb then
    raise exception '候选快照必须是非空 JSON 对象';
  end if;

  select item.*
    into v_item
  from public.re_review_items as item
  where item.id = p_re_review_item_id
  for update;

  if not found then
    raise exception '重审项不存在';
  end if;

  if v_item.status not in ('pending', 'failed') then
    raise exception '当前重审项不能提交新候选';
  end if;

  if v_item.submitted_by is not distinct from v_user_id
    or exists (
      select 1
      from public.pending_clothes as primary_source
      where primary_source.id = v_item.source_pending_id
        and primary_source.submitted_by = v_user_id
    )
    or exists (
      select 1
      from public.re_review_item_sources as source
      where source.re_review_item_id = v_item.id
        and source.source_user_id = v_user_id
    ) then
    raise exception using
      errcode = '42501',
      message = '不能参与自己提交或参与过的数据重审';
  end if;

  if exists (
    select 1
    from public.re_review_candidates as candidate
    where candidate.re_review_item_id = v_item.id
      and candidate.status = 'voting'
  ) then
    raise exception '该重审项已有正在投票的候选快照';
  end if;

  if v_item.reason <> 'missing_suit' then
    raise exception '当前第一版只支持“所属套装待确认”重审项进入陪审团';
  end if;

  if (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(p_payload)) <> 1
    or not (p_payload ? 'suit_id')
    or pg_catalog.jsonb_typeof(p_payload->'suit_id') <> 'string' then
    raise exception '所属套装候选只能包含 suit_id';
  end if;

  begin
    v_suit_id := (p_payload->>'suit_id')::uuid;
  exception when invalid_text_representation then
    raise exception '候选 suit_id 格式无效';
  end;

  if not exists (
    select 1
    from public.suits as suit
    where suit.id = v_suit_id
  ) then
    raise exception '候选套装不存在';
  end if;

  if not exists (
    select 1
    from public.clothes as clothes
    where clothes.id = v_item.clothes_id
      and clothes.suit_id is null
      and nullif(pg_catalog.btrim(coalesce(clothes.temp_suit_name, '')), '') is null
  ) then
    raise exception '正式服装已经有关联套装，或目标服装不存在';
  end if;

  insert into public.re_review_candidates (
    re_review_item_id,
    payload,
    submitted_by,
    status
  )
  values (
    v_item.id,
    pg_catalog.jsonb_build_object('suit_id', v_suit_id::text),
    v_user_id,
    'voting'
  )
  returning * into v_candidate;

  update public.re_review_items
  set
    status = 'voting',
    updated_at = pg_catalog.now(),
    resolved_by = null,
    resolved_at = null
  where id = v_item.id;

  return pg_catalog.jsonb_build_object(
    're_review_item_id', v_item.id,
    'candidate_id', v_candidate.id,
    'candidate_status', v_candidate.status,
    'item_status', 'voting'
  );
end;
$$;

create or replace function public.get_jury_review_queue()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception '需要登录后才能查看陪审团';
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        're_review_item_id', item.id,
        'reason', item.reason,
        'item_status', item.status,
        'clothes_id', item.clothes_id,
        'clothes_name', coalesce(item.payload->>'name', clothes.name, '未命名服装'),
        'category', coalesce(item.payload->>'category', clothes.category, ''),
        'game_id', coalesce(item.payload->>'game_id', clothes.game_id, ''),
        'candidate_id', candidate.id,
        'candidate_payload', candidate.payload,
        'candidate_status', candidate.status,
        'candidate_created_at', candidate.created_at,
        'approve_count', coalesce(vote_count.approve_count, 0),
        'reject_count', coalesce(vote_count.reject_count, 0),
        'my_vote', my_vote.vote,
        'can_submit_candidate', candidate.id is null and item.status in ('pending', 'failed'),
        'can_vote', candidate.id is not null
          and candidate.submitted_by is distinct from v_user_id
          and my_vote.vote is null,
        'is_candidate_author', candidate.submitted_by is not distinct from v_user_id
      )
      order by item.created_at, item.id
    ),
    '[]'::jsonb
  )
    into v_result
  from public.re_review_items as item
  left join public.clothes as clothes
    on clothes.id = item.clothes_id
  left join lateral (
    select current_candidate.*
    from public.re_review_candidates as current_candidate
    where current_candidate.re_review_item_id = item.id
      and current_candidate.status = 'voting'
    order by current_candidate.created_at desc, current_candidate.id
    limit 1
  ) as candidate on true
  left join lateral (
    select
      pg_catalog.count(*) filter (where vote.vote = 'approve')::integer as approve_count,
      pg_catalog.count(*) filter (where vote.vote = 'reject')::integer as reject_count
    from public.jury_votes as vote
    where vote.candidate_id = candidate.id
  ) as vote_count on true
  left join lateral (
    select vote.vote
    from public.jury_votes as vote
    where vote.candidate_id = candidate.id
      and vote.user_id = v_user_id
    limit 1
  ) as my_vote on true
  where item.reason = 'missing_suit'
    and item.status in ('pending', 'voting', 'failed')
    and item.submitted_by is distinct from v_user_id
    and not exists (
      select 1
      from public.pending_clothes as primary_source
      where primary_source.id = item.source_pending_id
        and primary_source.submitted_by = v_user_id
    )
    and not exists (
      select 1
      from public.re_review_item_sources as source
      where source.re_review_item_id = item.id
        and source.source_user_id = v_user_id
    );

  return v_result;
end;
$$;

create or replace function public.cast_jury_vote(
  p_candidate_id uuid,
  p_vote text
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
  v_existing_vote text;
  v_approve_count integer := 0;
  v_reject_count integer := 0;
  v_result_status text := 'voting';
  v_suit_id uuid;
begin
  if v_user_id is null then
    raise exception '需要登录后才能参与陪审团投票';
  end if;

  if p_vote is null or p_vote not in ('approve', 'reject') then
    raise exception '投票只允许 approve 或 reject';
  end if;

  select candidate.*
    into v_candidate
  from public.re_review_candidates as candidate
  where candidate.id = p_candidate_id
  for update;

  if not found then
    raise exception '候选快照不存在';
  end if;

  if v_candidate.status <> 'voting' then
    select vote.vote
      into v_existing_vote
    from public.jury_votes as vote
    where vote.candidate_id = v_candidate.id
      and vote.user_id = v_user_id;

    if found and v_existing_vote is distinct from p_vote then
      raise exception '陪审团投票一票定稿，不允许改票';
    elsif not found then
      raise exception '候选快照当前不可投票';
    end if;

    select
      pg_catalog.count(*) filter (where vote.vote = 'approve')::integer,
      pg_catalog.count(*) filter (where vote.vote = 'reject')::integer
      into v_approve_count, v_reject_count
    from public.jury_votes as vote
    where vote.candidate_id = v_candidate.id;

    return pg_catalog.jsonb_build_object(
      'candidate_id', v_candidate.id,
      're_review_item_id', v_candidate.re_review_item_id,
      'approve_count', v_approve_count,
      'reject_count', v_reject_count,
      'status', v_candidate.status
    );
  end if;

  select item.*
    into v_item
  from public.re_review_items as item
  where item.id = v_candidate.re_review_item_id
  for update;

  if not found or v_item.status <> 'voting' then
    raise exception '重审项当前不在投票状态';
  end if;

  if v_candidate.submitted_by is not distinct from v_user_id
    or v_item.submitted_by is not distinct from v_user_id
    or exists (
      select 1
      from public.pending_clothes as primary_source
      where primary_source.id = v_item.source_pending_id
        and primary_source.submitted_by = v_user_id
    )
    or exists (
      select 1
      from public.re_review_item_sources as source
      where source.re_review_item_id = v_item.id
        and source.source_user_id = v_user_id
    ) then
    raise exception using
      errcode = '42501',
      message = '不能投票审核自己提交或参与过的数据';
  end if;

  select vote.vote
    into v_existing_vote
  from public.jury_votes as vote
  where vote.candidate_id = v_candidate.id
    and vote.user_id = v_user_id;

  if found and v_existing_vote is distinct from p_vote then
    raise exception '陪审团投票一票定稿，不允许改票';
  elsif not found then
    insert into public.jury_votes (candidate_id, user_id, vote)
    values (v_candidate.id, v_user_id, p_vote);
  end if;

  select
    pg_catalog.count(*) filter (where vote.vote = 'approve')::integer,
    pg_catalog.count(*) filter (where vote.vote = 'reject')::integer
    into v_approve_count, v_reject_count
  from public.jury_votes as vote
  where vote.candidate_id = v_candidate.id;

  if v_approve_count >= 5 and v_approve_count > v_reject_count then
    if v_item.reason <> 'missing_suit'
      or (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(v_candidate.payload)) <> 1
      or not (v_candidate.payload ? 'suit_id') then
      raise exception '候选快照不符合当前可自动处理的重审类型';
    end if;

    begin
      v_suit_id := (v_candidate.payload->>'suit_id')::uuid;
    exception when invalid_text_representation then
      raise exception '候选 suit_id 格式无效';
    end;

    if not exists (select 1 from public.suits as suit where suit.id = v_suit_id) then
      raise exception '候选套装不存在';
    end if;

    update public.clothes
    set
      suit_id = v_suit_id,
      temp_suit_name = null
    where id = v_item.clothes_id
      and suit_id is null
      and nullif(pg_catalog.btrim(coalesce(temp_suit_name, '')), '') is null;

    if not found then
      raise exception '正式服装已变化，不能按旧候选快照自动修改';
    end if;

    update public.re_review_candidates
    set
      status = 'approved',
      resolved_at = pg_catalog.now()
    where id = v_candidate.id;

    update public.re_review_items
    set
      status = 'approved',
      resolved_by = v_user_id,
      resolved_at = pg_catalog.now(),
      updated_at = pg_catalog.now()
    where id = v_item.id;

    insert into public.points_ledger (
      user_id,
      delta,
      status,
      source_type,
      source_id,
      re_review_candidate_id,
      reversal_of
    )
    values (
      v_candidate.submitted_by,
      8,
      'awarded',
      're_review_candidate',
      null,
      v_candidate.id,
      null
    );

    v_result_status := 'approved';
  elsif v_reject_count - v_approve_count >= 3 then
    update public.re_review_candidates
    set
      status = 'returned',
      resolved_at = pg_catalog.now()
    where id = v_candidate.id;

    update public.re_review_items
    set
      status = 'pending',
      resolved_by = null,
      resolved_at = null,
      updated_at = pg_catalog.now()
    where id = v_item.id;

    v_result_status := 'returned';
  end if;

  return pg_catalog.jsonb_build_object(
    'candidate_id', v_candidate.id,
    're_review_item_id', v_item.id,
    'approve_count', v_approve_count,
    'reject_count', v_reject_count,
    'status', v_result_status
  );
end;
$$;

create or replace function public.admin_reject_jury_candidate(
  p_candidate_id uuid,
  p_reason text
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
  v_reason text := nullif(pg_catalog.btrim(coalesce(p_reason, '')), '');
begin
  if v_user_id is null then
    raise exception '需要登录后才能执行管理员终审';
  end if;

  if not public.is_super_admin() then
    raise exception '只有超级管理员可以执行永久驳回终审';
  end if;

  if v_reason is null then
    raise exception '永久驳回必须填写终审理由';
  end if;

  select candidate.*
    into v_candidate
  from public.re_review_candidates as candidate
  where candidate.id = p_candidate_id
  for update;

  if not found or v_candidate.status not in ('voting', 'returned') then
    raise exception '候选快照不存在或当前不能终审驳回';
  end if;

  select item.*
    into v_item
  from public.re_review_items as item
  where item.id = v_candidate.re_review_item_id
  for update;

  if not found or v_item.status not in ('pending', 'voting', 'failed') then
    raise exception '重审项当前不能终审驳回';
  end if;

  if (v_candidate.status = 'voting' and v_item.status <> 'voting')
    or (v_candidate.status = 'returned' and v_item.status not in ('pending', 'failed'))
    or exists (
      select 1
      from public.re_review_candidates as active_candidate
      where active_candidate.re_review_item_id = v_item.id
        and active_candidate.status = 'voting'
        and active_candidate.id <> v_candidate.id
    ) then
    raise exception '该候选已不是当前可终审轮次';
  end if;

  if v_candidate.submitted_by is not distinct from v_user_id
    or v_item.submitted_by is not distinct from v_user_id
    or exists (
      select 1
      from public.pending_clothes as primary_source
      where primary_source.id = v_item.source_pending_id
        and primary_source.submitted_by = v_user_id
    )
    or exists (
      select 1
      from public.re_review_item_sources as source
      where source.re_review_item_id = v_item.id
        and source.source_user_id = v_user_id
    ) then
    raise exception using
      errcode = '42501',
      message = '管理员不能终审自己提交或参与过的数据';
  end if;

  if exists (
    select 1
    from public.jury_votes as vote
    where vote.candidate_id = v_candidate.id
      and vote.user_id = v_user_id
  ) then
    raise exception using
      errcode = '42501',
      message = '已参与该候选投票的管理员不能再执行终审';
  end if;

  insert into public.jury_admin_decisions (
    candidate_id,
    re_review_item_id,
    admin_user_id,
    decision,
    reason
  )
  values (
    v_candidate.id,
    v_item.id,
    v_user_id,
    'rejected',
    v_reason
  );

  update public.re_review_candidates
  set
    status = 'rejected',
    resolved_at = pg_catalog.now()
  where id = v_candidate.id;

  update public.re_review_items
  set
    status = 'rejected',
    resolved_by = v_user_id,
    resolved_at = pg_catalog.now(),
    updated_at = pg_catalog.now()
  where id = v_item.id;

  return pg_catalog.jsonb_build_object(
    'candidate_id', v_candidate.id,
    're_review_item_id', v_item.id,
    'status', 'rejected'
  );
end;
$$;

revoke all on function public.submit_jury_candidate(uuid, jsonb)
  from public, anon;
grant execute on function public.submit_jury_candidate(uuid, jsonb)
  to authenticated, service_role;

revoke all on function public.get_jury_review_queue()
  from public, anon;
grant execute on function public.get_jury_review_queue()
  to authenticated, service_role;

revoke all on function public.cast_jury_vote(uuid, text)
  from public, anon;
grant execute on function public.cast_jury_vote(uuid, text)
  to authenticated, service_role;

revoke all on function public.admin_reject_jury_candidate(uuid, text)
  from public, anon;
grant execute on function public.admin_reject_jury_candidate(uuid, text)
  to authenticated, service_role;

comment on table public.jury_votes is
  'DB-7 陪审团不可变投票事实；同一用户对同一冻结候选只能投一票。';

comment on table public.jury_admin_decisions is
  'DB-7 管理员独立终审事实；第一版只记录超级管理员的永久驳回。';

comment on column public.re_review_candidates.status is
  '候选轮次状态：voting 投票中、approved 通过、returned 退回重审、rejected 管理员永久驳回。';

comment on column public.points_ledger.re_review_candidate_id is
  '重审候选通过产生的积分来源；与 clothing_contribution 来源互斥。';

comment on function public.submit_jury_candidate(uuid, jsonb) is
  'DB-7 提交单一冻结候选；第一版只支持 missing_suit 候选并在同事务进入 voting。';

comment on function public.get_jury_review_queue() is
  'DB-7 返回当前登录用户可参与的重审项、冻结候选、票数和自己的投票状态。';

comment on function public.cast_jury_vote(uuid, text) is
  'DB-7 一人一票：同意达到 5 且领先则通过，反对领先至少 3 则退回重审，其他情况继续投票。';

comment on function public.admin_reject_jury_candidate(uuid, text) is
  'DB-7 超级管理员独立永久驳回；已参与该候选投票的管理员不得终审。';

commit;
