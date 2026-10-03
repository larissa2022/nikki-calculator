begin;

-- DB-21 V2.1 收口补丁：手动任期只允许站长处理；普通管理员继续参与候选排除。
-- 同时修复普通管理员在陪审页面始终无法发起永久驳回的问题。

create or replace function private_db2.enforce_super_only_manual_term_signature()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_action_type text;
begin
  select action.action_type
  into v_action_type
  from public.community_admin_actions as action
  where action.id = new.action_id;

  if v_action_type in ('manual_term_create', 'term_end')
    and new.signature_source <> 'super_admin' then
    raise exception using
      errcode = '42501',
      message = '手动任期只能由站长处理';
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_super_only_manual_term_signature
  on public.community_admin_action_signatures;

create trigger enforce_super_only_manual_term_signature
before insert or update on public.community_admin_action_signatures
for each row execute function private_db2.enforce_super_only_manual_term_signature();

revoke all on function private_db2.enforce_super_only_manual_term_signature()
  from public, anon, authenticated, service_role;

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
    'can_manage_admin_terms', v_super,
    'can_manage_candidate_exclusions', v_super or v_term.id is not null,
    'can_review_high_risk', v_super or v_term.id is not null,
    'term_id', v_term.id,
    'term_source', v_term.source,
    'term_ends_at', v_term.scheduled_end_at,
    'show_grant_notice', v_term.id is not null and v_term.created_at >= pg_catalog.now() - interval '7 days'
  );
end;
$$;

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
  v_is_super_admin boolean := false;
  v_is_ordinary_admin boolean := false;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception '需要登录后才能查看陪审团';
  end if;

  v_is_super_admin := public.is_super_admin();
  v_is_ordinary_admin := private_db2.is_effective_ordinary_admin(v_user_id, pg_catalog.now());

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
        'current_user_level', v_user_level,
        'can_admin_reject',
          nullif(queue.item->>'candidate_id', '') is not null
          and (
            v_is_super_admin
            or (
              v_is_ordinary_admin
              and nullif(queue.item->>'my_vote', '') is null
            )
          ),
        'admin_reject_block_reason', case
          when nullif(queue.item->>'candidate_id', '') is null then 'no_candidate'
          when v_is_super_admin then null
          when not v_is_ordinary_admin then 'not_admin'
          when nullif(queue.item->>'my_vote', '') is not null then 'already_voted'
          else null
        end
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

revoke all on function public.get_current_admin_capabilities()
  from public, anon, authenticated, service_role;
grant execute on function public.get_current_admin_capabilities()
  to authenticated, service_role;

revoke all on function public.get_jury_review_queue_with_evidence()
  from public, anon, authenticated, service_role;
grant execute on function public.get_jury_review_queue_with_evidence()
  to authenticated, service_role;

comment on function public.get_current_admin_capabilities() is
  'DB-21 V2.1 管理员能力：手动任期仅站长可管理；普通管理员继续参与审核和候选排除。';
comment on function public.get_jury_review_queue_with_evidence() is
  'DB-21 V2.1 陪审队列：普通管理员未参与本轮投票时可发起永久驳回；站长保留独立终审。';
comment on function public.submit_admin_governance_action(text, uuid, uuid, text, timestamptz, timestamptz) is
  'DB-21 V2.1 管理员治理：手动任期仅站长可执行；候选排除由普通管理员 3 人共同确认或站长单独执行。';

commit;
